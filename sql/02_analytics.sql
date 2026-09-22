-- =====================================================================
-- 02_analytics.sql -- deterministic evidence layer
--
-- Purpose  Turn raw synthetic observations into evidence that an agent can
--          cite without arithmetic of its own. Every rule that decides
--          whether a number may be shown lives here, in SQL, not in a
--          prompt: a model can be argued out of a guardrail, a view cannot.
-- Contract docs/04-COWORK-CONTRACT.md defines the grains, units and
--          completeness rules these views implement.
-- Reads    ROSTER, CALENDAR, PERFORMANCE, OPERATIONS, RELEASE_METADATA
-- Builds   PAIRED_PERFORMANCE -> OPERATIONS_EVIDENCE
--          PRE_PERIOD_FEATURES -> PEER_SELECTION -> COMPARISON_EVIDENCE
--                                 WINDOW_OUTCOMES ->
--
-- Three ideas recur, and are worth reading once before the code:
--
--   1. Withhold, never impute. When an observation is missing, the paired
--      measure becomes NULL and an exclusion counter increments. Zero is a
--      measurement ("nobody came"); NULL is the absence of a measurement.
--      Substituting one for the other would quietly bias every total.
--   2. Completeness and comparability are separate tests. A restaurant can
--      be fully observed and still not comparable (it opened mid-period),
--      or comparable and partly unobserved. Each is reported on its own.
--   3. Peers are chosen from pre-period data only. Selecting on the period
--      being measured would let the outcome pick its own control group.
-- =====================================================================

USE WAREHOUSE SFE_RESTAURANT_RECOVERY_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY;

-- ---------------------------------------------------------------------
-- PAIRED_PERFORMANCE
--
-- Grain    release x restaurant x business date x daypart x channel
--          (one row per observed cell, unchanged from PERFORMANCE)
-- Purpose  Attach each current cell to its year-earlier counterpart so a
--          change can be measured at the finest grain, then aggregated.
-- Why 364  CALENDAR.BASELINE_DATE is the business date minus 364 days, not
--          365: 364 is 52 whole weeks, so a Saturday pairs with a Saturday.
--          Restaurant demand swings more by weekday than by calendar date,
--          so a same-weekday pair removes most of the seasonal noise for
--          free. The offset lives in CALENDAR, making it auditable data
--          rather than arithmetic repeated in every query.
-- Caution  This view is per-channel. Operating and labor hours are not
--          per-channel and must never be joined to these rows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW PAIRED_PERFORMANCE COPY GRANTS
COMMENT = 'DEMO: Observed paired cells; nulls stay excluded (Expires: 2026-10-22)' AS
SELECT current_obs.RELEASE_ID, metadata.AS_OF_DATE, current_obs.RESTAURANT_ID,
       roster.RESTAURANT_NAME, roster.MARKET, roster.FORMAT,
       current_obs.BUSINESS_DATE, calendar.BASELINE_DATE, calendar.WEEK_START,
       current_obs.DAYPART, current_obs.CHANNEL,
       roster.OPEN_DATE, roster.CLOSE_DATE,
       -- LIFECYCLE answers "is this pair a like-for-like comparison?" by
       -- testing the restaurant's open/close dates against BOTH ends of the
       -- pair. A restaurant that opened after the baseline date has no real
       -- prior year, so its growth is new capacity, not recovery; one that
       -- closed before the current date contributes structural loss. Mixing
       -- either into a trend produces the classic false headline, so they
       -- are labelled here and filtered by the consumer, never dropped
       -- silently -- the counts themselves are part of the answer.
       CASE WHEN roster.OPEN_DATE > calendar.BASELINE_DATE AND roster.OPEN_DATE <= current_obs.BUSINESS_DATE THEN 'Opening'
            WHEN roster.CLOSE_DATE > calendar.BASELINE_DATE AND roster.CLOSE_DATE <= current_obs.BUSINESS_DATE THEN 'Closure'
            WHEN roster.OPEN_DATE <= calendar.BASELINE_DATE AND (roster.CLOSE_DATE IS NULL OR roster.CLOSE_DATE > current_obs.BUSINESS_DATE) THEN 'Comparable'
            ELSE 'Outside comparison' END AS LIFECYCLE,
       -- A pair is usable only if both sides and the calendar row are
       -- complete. COALESCE(..., FALSE) is deliberate: the LEFT JOIN below
       -- yields NULL when no baseline row exists at all, and three-valued
       -- logic would otherwise leave PAIR_COMPLETE unknown and let the
       -- IFFs downstream fall through. Missing means excluded, explicitly.
       COALESCE(current_obs.COMPLETE AND baseline.COMPLETE AND calendar.COMPLETE, FALSE) AS PAIR_COMPLETE,
       -- Both sides of an incomplete pair are withheld, not just the
       -- missing one. Keeping the observed half would compare a full
       -- current period against a partial baseline and invent a change.
       IFF(PAIR_COMPLETE, current_obs.GUESTS, NULL) AS CURRENT_GUESTS,
       IFF(PAIR_COMPLETE, baseline.GUESTS, NULL) AS BASELINE_GUESTS,
       -- NULL propagates through the subtraction, so an excluded pair
       -- contributes nothing to SUM(GUEST_CHANGE) rather than contributing
       -- a spurious zero.
       CURRENT_GUESTS - BASELINE_GUESTS AS GUEST_CHANGE,
       IFF(PAIR_COMPLETE, current_obs.CHECKS, NULL) AS CURRENT_CHECKS,
       IFF(PAIR_COMPLETE, baseline.CHECKS, NULL) AS BASELINE_CHECKS,
       IFF(PAIR_COMPLETE, current_obs.NET_SALES, NULL) AS CURRENT_SALES,
       IFF(PAIR_COMPLETE, baseline.NET_SALES, NULL) AS BASELINE_SALES,
       -- Coverage travels with the measure: SUM(EXCLUDED_PAIRS) alongside
       -- any total tells the reader how much of the grid the total omits.
       IFF(PAIR_COMPLETE, 0, 1) AS EXCLUDED_PAIRS,
       -- A stable, human-readable handle for one cell. The agent quotes it
       -- so a reviewer can re-fetch the exact row behind a claim.
       current_obs.RELEASE_ID || ':' || current_obs.RESTAURANT_ID || ':' || TO_VARCHAR(current_obs.BUSINESS_DATE) || ':' || current_obs.DAYPART || ':' || current_obs.CHANNEL AS EVIDENCE_ID
FROM PERFORMANCE current_obs
JOIN CALENDAR calendar ON current_obs.RELEASE_ID = calendar.RELEASE_ID AND current_obs.BUSINESS_DATE = calendar.BUSINESS_DATE
JOIN ROSTER roster ON current_obs.RELEASE_ID = roster.RELEASE_ID AND current_obs.RESTAURANT_ID = roster.RESTAURANT_ID
JOIN RELEASE_METADATA metadata ON current_obs.RELEASE_ID = metadata.RELEASE_ID
-- LEFT, not INNER: a current cell with no baseline row must survive as an
-- excluded pair. An INNER JOIN would delete the evidence that something is
-- missing, which is the single easiest way to understate a decline.
-- RELEASE_ID is carried through every join so regenerated fixtures cannot
-- silently blend with each other.
LEFT JOIN PERFORMANCE baseline ON current_obs.RELEASE_ID = baseline.RELEASE_ID
 AND current_obs.RESTAURANT_ID = baseline.RESTAURANT_ID AND calendar.BASELINE_DATE = baseline.BUSINESS_DATE
 AND current_obs.DAYPART = baseline.DAYPART AND current_obs.CHANNEL = baseline.CHANNEL
-- The first 364 days of history have no baseline by construction. They are
-- out of scope for pairing, not incomplete, so they are dropped here rather
-- than inflating the exclusion counts forever.
WHERE calendar.BASELINE_DATE IS NOT NULL;

-- ---------------------------------------------------------------------
-- OPERATIONS_EVIDENCE
--
-- Grain    release x restaurant x business date x daypart (no channel)
-- Purpose  Put guests next to the hours that produced them, so "did we cut
--          hours or lose demand?" can be asked of one row.
-- Why      A restaurant opens its doors once per daypart. Those open and
--          paid labor hours serve dine-in, takeaway and delivery at the
--          same time, so they are a single denominator, not three. Joining
--          hours to the per-channel rows in PAIRED_PERFORMANCE would repeat
--          each hour three times and make productivity look a third of its
--          true value. The all_channels CTE therefore collapses channel
--          away first, and only then are hours attached.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW OPERATIONS_EVIDENCE COPY GRANTS
COMMENT = 'DEMO: All-channel paired operations, one denominator per daypart (Expires: 2026-10-22)' AS
WITH all_channels AS (
 -- Collapse the three channels into one all-channel guest count per
 -- daypart, carrying the channel and exclusion counts forward so the
 -- completeness test below can see whether the roll-up is whole.
 SELECT RELEASE_ID, RESTAURANT_ID, BUSINESS_DATE, BASELINE_DATE, DAYPART,
        COUNT(*) AS CHANNEL_COUNT, SUM(EXCLUDED_PAIRS) AS EXCLUDED_CHANNELS,
        SUM(CURRENT_GUESTS) AS CURRENT_GUESTS, SUM(BASELINE_GUESTS) AS BASELINE_GUESTS
 FROM PAIRED_PERFORMANCE
 GROUP BY RELEASE_ID, RESTAURANT_ID, BUSINESS_DATE, BASELINE_DATE, DAYPART
)
SELECT channels.RELEASE_ID, metadata.AS_OF_DATE, channels.RESTAURANT_ID, roster.RESTAURANT_NAME,
       roster.MARKET, channels.BUSINESS_DATE, channels.BASELINE_DATE, channels.DAYPART,
       -- Stricter than PAIR_COMPLETE, and for a reason: a guests-per-hour
       -- ratio is only honest when the numerator covers exactly the same
       -- trade as the denominator. CHANNEL_COUNT = 3 proves all three
       -- channels are present, EXCLUDED_CHANNELS = 0 proves each was
       -- observed, and both operations rows must be complete as well.
       -- Any shortfall withholds the whole day rather than shrinking the
       -- numerator against an unchanged denominator.
       COALESCE(channels.CHANNEL_COUNT = 3 AND channels.EXCLUDED_CHANNELS = 0 AND current_ops.COMPLETE AND baseline.COMPLETE, FALSE) AS EVIDENCE_COMPLETE,
       IFF(EVIDENCE_COMPLETE, channels.CURRENT_GUESTS, NULL) AS CURRENT_GUESTS,
       IFF(EVIDENCE_COMPLETE, channels.BASELINE_GUESTS, NULL) AS BASELINE_GUESTS,
       IFF(EVIDENCE_COMPLETE, current_ops.OPEN_HOURS, NULL) AS CURRENT_OPEN_HOURS,
       IFF(EVIDENCE_COMPLETE, baseline.OPEN_HOURS, NULL) AS BASELINE_OPEN_HOURS,
       IFF(EVIDENCE_COMPLETE, current_ops.LABOR_HOURS, NULL) AS CURRENT_LABOR_HOURS,
       IFF(EVIDENCE_COMPLETE, baseline.LABOR_HOURS, NULL) AS BASELINE_LABOR_HOURS,
       -- SERVICE_MINUTES is already a per-observation average, and averages
       -- of averages are wrong whenever the observation counts differ. The
       -- total and the count are exposed as separate additive measures so
       -- any roll-up can divide SUM(total) by SUM(count) and get a properly
       -- weighted mean at whatever grain the question asks for.
       IFF(EVIDENCE_COMPLETE, current_ops.SERVICE_MINUTES * current_ops.SERVICE_OBSERVATIONS, NULL) AS CURRENT_SERVICE_TOTAL,
       IFF(EVIDENCE_COMPLETE, current_ops.SERVICE_OBSERVATIONS, NULL) AS CURRENT_SERVICE_COUNT,
       IFF(EVIDENCE_COMPLETE, baseline.SERVICE_MINUTES * baseline.SERVICE_OBSERVATIONS, NULL) AS BASELINE_SERVICE_TOTAL,
       IFF(EVIDENCE_COMPLETE, baseline.SERVICE_OBSERVATIONS, NULL) AS BASELINE_SERVICE_COUNT,
       IFF(EVIDENCE_COMPLETE, 0, 1) AS EXCLUDED_DAYS,
       channels.RELEASE_ID || ':' || channels.RESTAURANT_ID || ':' || TO_VARCHAR(channels.BUSINESS_DATE) || ':' || channels.DAYPART || ':operations' AS EVIDENCE_ID
FROM all_channels channels
JOIN ROSTER roster ON channels.RELEASE_ID = roster.RELEASE_ID AND channels.RESTAURANT_ID = roster.RESTAURANT_ID
JOIN RELEASE_METADATA metadata ON channels.RELEASE_ID = metadata.RELEASE_ID
-- Two LEFT JOINs to the same table at two different dates: one for the
-- current day, one for the year-earlier baseline day. Both are LEFT so a
-- missing hours row is reported as an excluded day instead of vanishing.
LEFT JOIN OPERATIONS current_ops ON channels.RELEASE_ID = current_ops.RELEASE_ID AND channels.RESTAURANT_ID = current_ops.RESTAURANT_ID AND channels.BUSINESS_DATE = current_ops.BUSINESS_DATE AND channels.DAYPART = current_ops.DAYPART
LEFT JOIN OPERATIONS baseline ON channels.RELEASE_ID = baseline.RELEASE_ID AND channels.RESTAURANT_ID = baseline.RESTAURANT_ID AND channels.BASELINE_DATE = baseline.BUSINESS_DATE AND channels.DAYPART = baseline.DAYPART;

-- ---------------------------------------------------------------------
-- ANALYSIS_WINDOWS
--
-- Grain    one row per supported analysis window
-- Purpose  Name the only two windows for which peers have been matched, and
--          pin them to fixed dates.
-- Why      Peer matching is frozen against a specific pre-period. If a
--          window could be typed freely, every new window would silently
--          reuse peers that were never matched for it. Declaring the
--          supported windows as data means an unsupported request fails to
--          find rows -- a visible absence -- instead of returning a
--          plausible number built on the wrong control group.
-- Note     WINDOW_END is exclusive throughout: [start, end). Both windows
--          end 2026-09-14, so the last included business date is
--          2026-09-13. Half-open intervals avoid the off-by-one-day error
--          that BETWEEN invites.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW ANALYSIS_WINDOWS
COMMENT = 'DEMO: Supported frozen peer windows (Expires: 2026-10-22)' AS
SELECT '8 weeks' AS WINDOW_NAME, '2026-07-20'::DATE AS WINDOW_START, '2026-09-14'::DATE AS WINDOW_END
UNION ALL SELECT '4 weeks', '2026-08-17'::DATE, '2026-09-14'::DATE;

-- ---------------------------------------------------------------------
-- PRE_PERIOD_FEATURES
--
-- Grain    release x restaurant x window name
-- Purpose  Describe each restaurant as it looked BEFORE the analysis
--          window, using the 182 days (26 weeks) immediately prior.
-- Why      These are the only features allowed to drive peer selection. A
--          feature computed inside the window would let the outcome choose
--          its own comparison group, which is how "peer benchmarking"
--          turns into circular reasoning.
-- Rule     A restaurant appears only if its pre-period is perfectly
--          observed. Matching on a partly observed profile makes similarity
--          a function of coverage rather than of trade.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW PRE_PERIOD_FEATURES
COMMENT = 'DEMO: Pre-period-only matching features (Expires: 2026-10-22)' AS
WITH perf AS (
 -- Scale-and-shape features. Mixes are computed from guest shares rather
 -- than from sales so a price change cannot masquerade as a mix shift.
 SELECT perf.RELEASE_ID, perf.RESTAURANT_ID, windows.WINDOW_NAME, windows.WINDOW_START, windows.WINDOW_END,
        COUNT(*) AS CELLS, COUNT_IF(perf.COMPLETE) AS COMPLETE_CELLS,
        -- Divided by the 182 pre-period days, not by the row count: a fixed
        -- denominator keeps the mean comparable across restaurants even if
        -- their row counts ever differ.
        SUM(perf.GUESTS) / 182.0 AS MEAN_DAILY_GUESTS,
        -- NULLIF guards the zero-guest case, turning a would-be divide-by-
        -- zero into NULL, which the completeness filter then excludes.
        SUM(IFF(perf.DAYPART = 'Breakfast', perf.GUESTS, 0)) / NULLIF(SUM(perf.GUESTS), 0) AS BREAKFAST_MIX,
        SUM(IFF(perf.CHANNEL = 'Delivery', perf.GUESTS, 0)) / NULLIF(SUM(perf.GUESTS), 0) AS DELIVERY_MIX
 -- CROSS JOIN builds one feature set per supported window, because each
 -- window has its own pre-period and therefore its own frozen profile.
 FROM PERFORMANCE perf CROSS JOIN ANALYSIS_WINDOWS windows
 -- Half-open again: the 182 days ending the day before the window starts.
 -- Strictly < WINDOW_START is what keeps the pre-period clean.
 WHERE perf.BUSINESS_DATE >= DATEADD(day, -182, windows.WINDOW_START) AND perf.BUSINESS_DATE < windows.WINDOW_START
 GROUP BY perf.RELEASE_ID, perf.RESTAURANT_ID, windows.WINDOW_NAME, windows.WINDOW_START, windows.WINDOW_END
), ops AS (
 -- Operating scale, kept separate because hours are per daypart, not per
 -- channel, and must not be counted once per channel.
 SELECT ops.RELEASE_ID, ops.RESTAURANT_ID, windows.WINDOW_NAME,
        COUNT(*) AS DAYS, COUNT_IF(ops.COMPLETE) AS COMPLETE_DAYS, SUM(ops.OPEN_HOURS) / 182.0 AS MEAN_DAILY_OPEN_HOURS
 FROM OPERATIONS ops CROSS JOIN ANALYSIS_WINDOWS windows
 WHERE ops.BUSINESS_DATE >= DATEADD(day, -182, windows.WINDOW_START) AND ops.BUSINESS_DATE < windows.WINDOW_START
 GROUP BY ops.RELEASE_ID, ops.RESTAURANT_ID, windows.WINDOW_NAME
)
SELECT perf.RELEASE_ID, perf.RESTAURANT_ID, roster.RESTAURANT_NAME, roster.MARKET, roster.FORMAT,
       perf.WINDOW_NAME, perf.WINDOW_START, perf.WINDOW_END,
       perf.MEAN_DAILY_GUESTS, perf.BREAKFAST_MIX, perf.DELIVERY_MIX, ops.MEAN_DAILY_OPEN_HOURS
FROM perf JOIN ops ON perf.RELEASE_ID = ops.RELEASE_ID AND perf.RESTAURANT_ID = ops.RESTAURANT_ID AND perf.WINDOW_NAME = ops.WINDOW_NAME
JOIN ROSTER roster ON perf.RELEASE_ID = roster.RELEASE_ID AND perf.RESTAURANT_ID = roster.RESTAURANT_ID
-- Eligibility, deliberately strict. The two constants are the complete
-- expected grid for a 182-day pre-period:
--   2184 = 182 days x 4 dayparts x 3 channels  (PERFORMANCE cells)
--    728 = 182 days x 4 dayparts               (OPERATIONS rows)
-- Requiring CELLS = COMPLETE_CELLS = 2184 asserts both that the grid is
-- whole and that every cell was observed. A restaurant that fails is not
-- "slightly worse matched", it is unmatchable, and is withheld rather than
-- matched on a shorter history.
WHERE perf.CELLS = 2184 AND perf.COMPLETE_CELLS = 2184 AND ops.DAYS = 728 AND ops.COMPLETE_DAYS = 728
 -- It must also have traded for the whole pre-period and still be open at
 -- the window start, so lifecycle change cannot enter through the peer set.
 AND roster.OPEN_DATE <= DATEADD(day, -182, perf.WINDOW_START)
 AND (roster.CLOSE_DATE IS NULL OR roster.CLOSE_DATE >= perf.WINDOW_START);

-- ---------------------------------------------------------------------
-- PEER_SELECTION
--
-- Grain    release x focal restaurant x window x peer scope x peer
-- Purpose  Rank up to five similar restaurants per focal restaurant, twice:
--          once within its own market and once across markets.
-- Why two  Within-market peers share local demand, so a gap points at the
--   scopes restaurant. Across-market peers do not, so a gap conflates the
--          restaurant with its market. Reporting them separately keeps the
--          two readings from being blended into one misleading number.
-- Caution  Similarity is descriptive. These peers are candidates for an
--          experimental control, never a control by themselves, and the
--          resulting gap is not a causal effect.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW PEER_SELECTION COPY GRANTS
COMMENT = 'DEMO: Frozen pre-period peers, not causal controls (Expires: 2026-10-22)' AS
SELECT focal.RELEASE_ID, focal.RESTAURANT_ID, focal.WINDOW_NAME, focal.WINDOW_START, focal.WINDOW_END,
       peer.RESTAURANT_ID AS PEER_ID, peer.MARKET AS PEER_MARKET,
       IFF(focal.MARKET = peer.MARKET, 'Within market', 'Across markets') AS PEER_SCOPE,
       -- Weighted distance on pre-period features only. Each term is scaled
       -- by a tolerance -- the difference considered "one unit of
       -- dissimilarity" -- so that unlike units can be added at all:
       --   50 guests/day, 5 mix points, 3 open hours/day.
       -- Scale carries 0.4 because size dominates restaurant behaviour;
       -- mix and hours carry 0.2 each. The weights and tolerances are a
       -- stated policy, versioned as PEER_POLICY below, not a tuned result.
       0.4 * ABS(focal.MEAN_DAILY_GUESTS - peer.MEAN_DAILY_GUESTS) / 50.0
       + 0.2 * ABS(focal.BREAKFAST_MIX - peer.BREAKFAST_MIX) / 0.05
       + 0.2 * ABS(focal.DELIVERY_MIX - peer.DELIVERY_MIX) / 0.05
       + 0.2 * ABS(focal.MEAN_DAILY_OPEN_HOURS - peer.MEAN_DAILY_OPEN_HOURS) / 3.0 AS DISTANCE,
       -- Ranked within each scope so the two scopes stay independent.
       -- RESTAURANT_ID breaks distance ties, which makes the peer set
       -- deterministic: the same release always yields the same peers, and
       -- an answer can be reproduced tomorrow.
       ROW_NUMBER() OVER (PARTITION BY focal.RELEASE_ID, focal.RESTAURANT_ID, focal.WINDOW_NAME, PEER_SCOPE ORDER BY DISTANCE, peer.RESTAURANT_ID) AS PEER_RANK
-- Self-join of the eligible population. Same format only: a roadside site
-- and a family dining site are different businesses, and matching across
-- them would compare trade patterns, not performance. <> excludes the
-- restaurant from its own peer set.
FROM PRE_PERIOD_FEATURES focal JOIN PRE_PERIOD_FEATURES peer
 ON focal.RELEASE_ID = peer.RELEASE_ID AND focal.WINDOW_NAME = peer.WINDOW_NAME AND focal.FORMAT = peer.FORMAT AND focal.RESTAURANT_ID <> peer.RESTAURANT_ID
-- An absolute similarity floor applied BEFORE ranking. Without it, the
-- five nearest restaurants would always be returned, however dissimilar --
-- "nearest" is not "similar". A focal restaurant with no close peers ends
-- up with too few, which COMPARISON_EVIDENCE reports as a withheld gap.
WHERE DISTANCE <= 1.0
-- QUALIFY filters the window function result without wrapping the query in
-- a subquery; it runs after ROW_NUMBER is assigned.
QUALIFY PEER_RANK <= 5;

-- ---------------------------------------------------------------------
-- WINDOW_OUTCOMES
--
-- Grain    release x restaurant x window
-- Purpose  Roll the paired cells up to one outcome per restaurant per
--          window, keeping the coverage and comparability counts attached.
-- Why      Restaurant-level totals must exist before any comparison. Gross
--          losses, in particular, are only meaningful once each restaurant
--          has been netted internally -- summing negative cells instead
--          would count a quiet Tuesday inside a growing restaurant as loss.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW WINDOW_OUTCOMES
COMMENT = 'DEMO: Paired restaurant outcomes, whole-window lifecycle (Expires: 2026-10-22)' AS
SELECT perf.RELEASE_ID, perf.RESTAURANT_ID, perf.RESTAURANT_NAME, perf.MARKET,
       windows.WINDOW_NAME, windows.WINDOW_START, windows.WINDOW_END,
       SUM(perf.CURRENT_GUESTS) AS CURRENT_GUESTS, SUM(perf.BASELINE_GUESTS) AS BASELINE_GUESTS,
       SUM(perf.GUEST_CHANGE) AS GUEST_CHANGE, SUM(perf.EXCLUDED_PAIRS) AS EXCLUDED_PAIRS,
       -- Two different denominators, kept apart on purpose:
       --   EXPECTED_PAIRS -- how many cells the window should contain, so
       --     EXCLUDED_PAIRS can be read as a share rather than a raw count.
       --   NONCOMP_PAIRS -- how many cells were not like-for-like. Non-zero
       --     means this restaurant opened or closed mid-window, and its
       --     change is structural, not performance.
       COUNT(*) AS EXPECTED_PAIRS, COUNT_IF(perf.LIFECYCLE <> 'Comparable') AS NONCOMP_PAIRS,
       -- Rate of the sums, never the average of per-cell rates: a correct
       -- percentage change weights each cell by its own baseline volume.
       -- NULLIF turns a zero baseline into NULL instead of an error.
       100.0 * SUM(perf.GUEST_CHANGE) / NULLIF(SUM(perf.BASELINE_GUESTS), 0) AS CHANGE_PCT
FROM PAIRED_PERFORMANCE perf CROSS JOIN ANALYSIS_WINDOWS windows
WHERE perf.BUSINESS_DATE >= windows.WINDOW_START AND perf.BUSINESS_DATE < windows.WINDOW_END
GROUP BY perf.RELEASE_ID, perf.RESTAURANT_ID, perf.RESTAURANT_NAME, perf.MARKET, windows.WINDOW_NAME, windows.WINDOW_START, windows.WINDOW_END;

-- ---------------------------------------------------------------------
-- COMPARISON_EVIDENCE
--
-- Grain    release x restaurant x window x peer scope
-- Purpose  Compare a restaurant's change against its frozen peers, or state
--          precisely why no comparison may be published.
-- Design   GAP_STATUS is the point of this view. Every row exists in both
--          peer scopes whether or not a gap is available, so the absence of
--          a comparison is itself visible and reasoned, rather than being a
--          missing row that a reader might interpret as "no problem".
-- Caution  GAP_PP is descriptive: percentage points of difference versus
--          similar restaurants over the same dates. It is not an effect
--          size, and closing it is not a forecast of recoverable demand.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW COMPARISON_EVIDENCE COPY GRANTS
COMMENT = 'DEMO: Descriptive gaps withheld for incomplete selected peers (Expires: 2026-10-22)' AS
WITH peers AS (
 -- Summarise the peers that were selected pre-period, and -- separately --
 -- how many of them turned out to be valid over the window. The two counts
 -- must be compared, not reconciled: dropping an invalid peer and averaging
 -- the rest would be re-matching after the fact, which quietly reintroduces
 -- outcome-driven selection.
 SELECT selection.RELEASE_ID, selection.RESTAURANT_ID, selection.WINDOW_NAME, selection.PEER_SCOPE,
        COUNT(*) AS PEER_COUNT,
        COUNT_IF(outcome.EXCLUDED_PAIRS = 0 AND outcome.NONCOMP_PAIRS = 0 AND outcome.BASELINE_GUESTS > 0) AS VALID_PEER_COUNT,
        AVG(outcome.CHANGE_PCT) AS PEER_CHANGE_PCT,
        -- Sensitivity check: the same comparison against the three closest
        -- peers only. If the five-peer and three-peer gaps disagree, the
        -- finding depends on the peer set and should be reported as fragile.
        AVG(IFF(selection.PEER_RANK <= 3, outcome.CHANGE_PCT, NULL)) AS TOP3_CHANGE_PCT,
        -- Peers are named, in rank order, so the comparison is auditable
        -- rather than an anonymous benchmark.
        LISTAGG(selection.PEER_ID, ', ') WITHIN GROUP (ORDER BY selection.PEER_RANK) AS PEER_IDS,
        MAX(selection.DISTANCE) AS MAX_DISTANCE
 -- LEFT JOIN so a selected peer with no outcome row still counts toward
 -- PEER_COUNT while failing VALID_PEER_COUNT -- exactly the mismatch the
 -- status ladder below is looking for.
 FROM PEER_SELECTION selection LEFT JOIN WINDOW_OUTCOMES outcome
  ON selection.RELEASE_ID = outcome.RELEASE_ID AND selection.PEER_ID = outcome.RESTAURANT_ID AND selection.WINDOW_NAME = outcome.WINDOW_NAME
 GROUP BY selection.RELEASE_ID, selection.RESTAURANT_ID, selection.WINDOW_NAME, selection.PEER_SCOPE
), scopes AS (SELECT 'Within market' AS PEER_SCOPE UNION ALL SELECT 'Across markets')
SELECT outcome.RELEASE_ID, outcome.RESTAURANT_ID, outcome.RESTAURANT_NAME, outcome.MARKET,
       outcome.WINDOW_NAME, outcome.WINDOW_START, outcome.WINDOW_END, scopes.PEER_SCOPE,
       outcome.CURRENT_GUESTS, outcome.BASELINE_GUESTS, outcome.GUEST_CHANGE, outcome.EXCLUDED_PAIRS,
       outcome.CHANGE_PCT AS FOCAL_CHANGE_PCT, COALESCE(peers.PEER_COUNT, 0) AS PEER_COUNT,
       peers.PEER_IDS, peers.MAX_DISTANCE,
       -- The withholding ladder, ordered most to least fundamental. The
       -- first failing condition wins, so the reported reason is the root
       -- cause rather than whichever check happened to run last:
       --   focal data missing -> focal not comparable -> too few peers ->
       --   a selected peer is unusable -> nothing to divide by.
       -- Each branch names a specific, actionable defect. "No data" would
       -- be true but useless; these tell the reader what to fix.
       CASE WHEN outcome.EXCLUDED_PAIRS > 0 THEN 'Incomplete focal observations'
            WHEN outcome.NONCOMP_PAIRS > 0 THEN 'Focal lifecycle change'
            WHEN COALESCE(peers.PEER_COUNT, 0) < 3 THEN 'Insufficient pre-period peers'
            WHEN peers.VALID_PEER_COUNT <> peers.PEER_COUNT THEN 'Selected peer incomplete or lifecycle-changing'
            WHEN outcome.BASELINE_GUESTS = 0 THEN 'Zero focal baseline'
            ELSE 'Available' END AS GAP_STATUS,
       -- Gated on the ladder, so a withheld comparison is NULL rather than
       -- a number with a caveat attached. A NULL gap means "not measured
       -- here" and must never be read, or reported, as zero difference.
       IFF(GAP_STATUS = 'Available', peers.PEER_CHANGE_PCT, NULL) AS PEER_CHANGE_PCT,
       -- Percentage points: the difference of two percentages, not a
       -- percentage of a percentage.
       IFF(GAP_STATUS = 'Available', outcome.CHANGE_PCT - peers.PEER_CHANGE_PCT, NULL) AS GAP_PP,
       IFF(GAP_STATUS = 'Available', outcome.CHANGE_PCT - peers.TOP3_CHANGE_PCT, NULL) AS TOP3_GAP_PP,
       -- Stamping the matching policy on every row means a gap quoted today
       -- can be told apart from one produced under different weights.
       'pre26-v3' AS PEER_POLICY,
       outcome.RELEASE_ID || ':' || outcome.RESTAURANT_ID || ':' || outcome.WINDOW_NAME || ':' || scopes.PEER_SCOPE AS EVIDENCE_ID
-- CROSS JOIN to scopes guarantees both peer scopes are always present for
-- every restaurant and window, so "we did not compare, and here is why"
-- is a row the agent can retrieve and cite.
FROM WINDOW_OUTCOMES outcome CROSS JOIN scopes
LEFT JOIN peers ON outcome.RELEASE_ID = peers.RELEASE_ID AND outcome.RESTAURANT_ID = peers.RESTAURANT_ID AND outcome.WINDOW_NAME = peers.WINDOW_NAME AND scopes.PEER_SCOPE = peers.PEER_SCOPE;
