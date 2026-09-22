-- =====================================================================
-- 04_semantics.sql -- the three semantic views the agent queries
--
-- Purpose  Give Cortex Analyst a governed vocabulary over the evidence
--          views: named dimensions, facts and metrics, with the business
--          meaning and the traps written down next to each one.
-- Runs     After 02_analytics.sql, because each view has a base_table that
--          must already exist.
-- Reads    PAIRED_PERFORMANCE, OPERATIONS_EVIDENCE, COMPARISON_EVIDENCE
--          (the evidence layer only -- never the raw tables, so the
--          withholding rules cannot be bypassed from above).
--
-- Each view is created from a JSON payload, so the teaching notes live in
-- the payload's own "description" fields rather than in SQL comments. Read
-- those descriptions as the contract: they are what the model sees.
--
-- Three payload sections are worth knowing by name:
--   * dimensions / facts / metrics -- the vocabulary. Facts are additive
--     columns; metrics are the aggregations that are safe to ask for. A
--     rate exposed as a metric is computed from summed numerator and summed
--     denominator, which is why asking for it cannot produce an average of
--     averages.
--   * module_custom_instructions -- per-view guidance applied when SQL is
--     generated. This is where rules that are easy to state and easy to get
--     wrong live: sum rates using summed denominators, never join hours to
--     channel rows, report excluded pairs alongside totals.
--   * verified_queries -- question/SQL pairs reviewed by a human. Those
--     flagged use_as_onboarding_question also seed suggestions in Cortex
--     Analyst, and they are the raw material for the curated
--     instructions.sample_questions set on the agent in 05_agent.sql.
--
-- Why three views instead of one: a single wide model would let the planner
-- join per-channel performance to all-channel hours, and the most common
-- error in this domain -- counting one open hour once per channel -- would
-- become reachable by accident. Splitting the model makes it unreachable.
-- The agent's orchestration instructions then decide which view answers
-- which question.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1/3 Performance -- guest occasions, checks and net sales at
--     restaurant x date x daypart x channel. The demand view: where losses
--     sit, how they concentrate, what coverage backs the total.
-- ---------------------------------------------------------------------
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS',
$$
{
  "name": "SV_RESTAURANT_RECOVERY_PERFORMANCE",
  "description": "Synthetic restaurant recovery. Guest occasions are not unique people. Descriptive analysis, never causal attribution. Expires: 2026-10-22.",
  "tables": [
    {
      "name": "evidence",
      "description": "Restaurant/day/date/channel paired cells. Default eight-week window 2026-07-20 through 2026-09-13. Sum rates using summed denominators. Gross losses require aggregating to restaurant first, then summing negative restaurant changes. Daypart and channel breakdowns are alternatives. Whole-window exclusion of closures removes the entire restaurant, including its pre-closure observations. Report excluded pairs with totals. Never join operations to channel rows. Guest occasions count guests served on each occasion, NOT transactions or checks and NOT unique people. Do not call guest occasions transactions, orders, or check counts. An incomplete-cell count alone cannot bound the missing volume; never assert excluded data is negligible or cannot change the conclusion. A gap present in the first observed week does not prove it began before that window; retrieve earlier evidence or leave onset unknown.  A restaurant closing during the window has both pre-closure performance and closed-day contributions; do not attribute its entire period change to closed days. Query by BUSINESS_DATE relative to CLOSE_DATE to separate them. An opening has explicit complete zero baseline observations outside its lifecycle, not missing pairs. For whole-window comparable restaurants require OPEN_DATE <= DATEADD(day,-364,window_start) and (CLOSE_DATE IS NULL OR CLOSE_DATE >= window_end_exclusive); do not hardcode restaurant IDs or names. Comparability and observation completeness are separate: always report excluded pairs. Excluding closures alone still includes openings and must not be called comparable-store growth.",
      "base_table": {
        "database": "SNOWFLAKE_EXAMPLE",
        "schema": "RESTAURANT_RECOVERY",
        "table": "PAIRED_PERFORMANCE"
      },
      "dimensions": [
        {
          "name": "release_id",
          "expr": "RELEASE_ID",
          "data_type": "VARCHAR",
          "description": "Immutable fictional release."
        },
        {
          "name": "restaurant_id",
          "expr": "RESTAURANT_ID",
          "data_type": "VARCHAR",
          "description": "Stable fictional restaurant ID."
        },
        {
          "name": "restaurant_name",
          "expr": "RESTAURANT_NAME",
          "data_type": "VARCHAR",
          "description": "Fictional restaurant name."
        },
        {
          "name": "market",
          "expr": "MARKET",
          "data_type": "VARCHAR",
          "description": "Fictional market, not actual customer DMA."
        },
        {
          "name": "business_date",
          "expr": "BUSINESS_DATE",
          "data_type": "DATE",
          "description": "Local business date. Default 2026-07-20 inclusive to 2026-09-14 exclusive."
        },
        {
          "name": "baseline_date",
          "expr": "BASELINE_DATE",
          "data_type": "DATE",
          "description": "Explicit 364-day aligned baseline date."
        },
        {
          "name": "as_of_date",
          "expr": "AS_OF_DATE",
          "data_type": "DATE",
          "description": "Fixed synthetic as-of date, not today."
        },
        {
          "name": "daypart",
          "expr": "DAYPART",
          "data_type": "VARCHAR",
          "description": "Breakfast, Lunch, Dinner, Late night."
        },
        {
          "name": "evidence_id",
          "expr": "EVIDENCE_ID",
          "data_type": "VARCHAR",
          "description": "Cell evidence identity; aggregate answers must also state filters and population."
        },
        {
          "name": "channel",
          "expr": "CHANNEL",
          "data_type": "VARCHAR",
          "description": "Dine-in, Takeaway, Delivery."
        },
        {
          "name": "lifecycle",
          "expr": "LIFECYCLE",
          "data_type": "VARCHAR",
          "description": "Cell lifecycle; for whole-window comp eligibility use open/close dates."
        },
        {
          "name": "open_date",
          "expr": "OPEN_DATE",
          "data_type": "DATE",
          "description": "Inclusive opening date."
        },
        {
          "name": "close_date",
          "expr": "CLOSE_DATE",
          "data_type": "DATE",
          "description": "Exclusive closure date, nullable."
        },
        {
          "name": "pair_complete",
          "expr": "PAIR_COMPLETE",
          "data_type": "BOOLEAN",
          "description": "Both aligned observations complete."
        }
      ],
      "metrics": [
        {
          "name": "m_current_guests",
          "expr": "SUM(CURRENT_GUESTS)",
          "description": "Current paired guest occasions."
        },
        {
          "name": "m_baseline_guests",
          "expr": "SUM(BASELINE_GUESTS)",
          "description": "Same paired population in baseline."
        },
        {
          "name": "m_guest_change",
          "expr": "SUM(GUEST_CHANGE)",
          "description": "Signed change, not gross loss."
        },
        {
          "name": "m_guest_change_pct",
          "expr": "100.0 * SUM(GUEST_CHANGE) / NULLIF(SUM(BASELINE_GUESTS),0)",
          "description": "Weighted change percentage; null for zero baseline."
        },
        {
          "name": "m_current_sales",
          "expr": "SUM(CURRENT_SALES)",
          "description": "Net USD sales excluding tax/tips."
        },
        {
          "name": "m_baseline_sales",
          "expr": "SUM(BASELINE_SALES)",
          "description": "Baseline net USD sales."
        },
        {
          "name": "m_current_checks",
          "expr": "SUM(CURRENT_CHECKS)",
          "description": "Transactions, not guests."
        },
        {
          "name": "m_spend_per_guest",
          "expr": "SUM(CURRENT_SALES) / NULLIF(SUM(CURRENT_GUESTS),0)",
          "description": "Spend per guest, not pure price."
        },
        {
          "name": "m_average_check",
          "expr": "SUM(CURRENT_SALES) / NULLIF(SUM(CURRENT_CHECKS),0)",
          "description": "Net sales per transaction."
        },
        {
          "name": "m_excluded_pairs",
          "expr": "SUM(EXCLUDED_PAIRS)",
          "description": "Missing pair count. Never convert missing observations to zero."
        }
      ]
    }
  ],
  "module_custom_instructions": {
    "sql_generation": "Restaurant/day/date/channel paired cells. Default eight-week window 2026-07-20 through 2026-09-13. Sum rates using summed denominators. Gross losses require aggregating to restaurant first, then summing negative restaurant changes. Daypart and channel breakdowns are alternatives. Whole-window exclusion of closures removes the entire restaurant, including its pre-closure observations. Report excluded pairs with totals. Never join operations to channel rows. Guest occasions count guests served on each occasion, NOT transactions or checks and NOT unique people. Do not call guest occasions transactions, orders, or check counts. An incomplete-cell count alone cannot bound the missing volume; never assert excluded data is negligible or cannot change the conclusion. A gap present in the first observed week does not prove it began before that window; retrieve earlier evidence or leave onset unknown.  A restaurant closing during the window has both pre-closure performance and closed-day contributions; do not attribute its entire period change to closed days. Query by BUSINESS_DATE relative to CLOSE_DATE to separate them. An opening has explicit complete zero baseline observations outside its lifecycle, not missing pairs. For whole-window comparable restaurants require OPEN_DATE <= DATEADD(day,-364,window_start) and (CLOSE_DATE IS NULL OR CLOSE_DATE >= window_end_exclusive); do not hardcode restaurant IDs or names. Comparability and observation completeness are separate: always report excluded pairs. Excluding closures alone still includes openings and must not be called comparable-store growth.",
    "question_categorization": "Do not infer retention, profit, elasticity, causation or actual customer performance from fictional observations."
  },
  "verified_queries": [
    {
      "name": "example_1",
      "question": "Which Mesa Vale restaurants lost the most guests in the eight-week window?",
      "sql": "SELECT RESTAURANT_ID, RESTAURANT_NAME, SUM(GUEST_CHANGE) AS GUEST_CHANGE, SUM(EXCLUDED_PAIRS) AS EXCLUDED_PAIRS FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PAIRED_PERFORMANCE WHERE MARKET = 'Mesa Vale' AND BUSINESS_DATE >= '2026-07-20' AND BUSINESS_DATE < '2026-09-14' GROUP BY RESTAURANT_ID, RESTAURANT_NAME ORDER BY GUEST_CHANGE LIMIT 12",
      "use_as_onboarding_question": true
    },
    {
      "name": "example_2",
      "question": "What is the net guest change by market in the eight-week window?",
      "sql": "SELECT MARKET, SUM(GUEST_CHANGE) AS GUEST_CHANGE, SUM(CURRENT_GUESTS) AS CURRENT_GUESTS, SUM(BASELINE_GUESTS) AS BASELINE_GUESTS, SUM(EXCLUDED_PAIRS) AS EXCLUDED_PAIRS FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PAIRED_PERFORMANCE WHERE BUSINESS_DATE >= '2026-07-20' AND BUSINESS_DATE < '2026-09-14' GROUP BY MARKET ORDER BY MARKET",
      "use_as_onboarding_question": true
    },
    {
      "name": "example_3",
      "question": "Show the eight-week Mesa Vale guest change excluding restaurants that closed during the window.",
      "sql": "SELECT SUM(GUEST_CHANGE) AS GUEST_CHANGE, SUM(EXCLUDED_PAIRS) AS EXCLUDED_PAIRS FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PAIRED_PERFORMANCE WHERE MARKET = 'Mesa Vale' AND BUSINESS_DATE >= '2026-07-20' AND BUSINESS_DATE < '2026-09-14' AND (CLOSE_DATE IS NULL OR CLOSE_DATE < '2026-07-20' OR CLOSE_DATE >= '2026-09-14')",
      "use_as_onboarding_question": true
    }
  ]
}
$$
);

-- ---------------------------------------------------------------------
-- 2/3 Operations -- open hours, paid labor hours and weighted service times
--     at restaurant x date x daypart. No channel dimension exists here, by
--     design: the grain itself prevents allocating shared hours to a single
--     channel. This is the capacity-side counterweight to Performance --
--     it answers "did we reduce the opportunity?" before anyone concludes
--     "demand fell".
-- ---------------------------------------------------------------------
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS',
$$
{
  "name": "SV_RESTAURANT_RECOVERY_OPERATIONS",
  "description": "Synthetic restaurant recovery. Guest occasions are not unique people. Descriptive analysis, never causal attribution. Expires: 2026-10-22.",
  "tables": [
    {
      "name": "evidence",
      "description": "One row per restaurant/date/daypart. All channels only: do not filter or allocate operational hours to a channel. Default 2026-07-20 inclusive to 2026-09-14 exclusive. Weighted service times, never mean of means. Incomplete observations withheld. Staffing changes are descriptive, not proof of cause. Opposite guest outcomes under the same labor change challenge a universal explanation but neither prove nor disprove a labor effect at either location: heterogeneous effects and confounding remain possible. Never say the other restaurant must decline if labor had any causal effect. A contrasting restaurant is not automatically an experimental control; require pre-trend comparability, confounder and spillover review. Scheduled hours and actual paid hours are different; these are paid hours. Guest occasions are not transactions or checks. Prospective switchback designs require carryover/washout and serial-correlation review. Any interim stopping rule needs a pre-specified sequential-analysis design, not repeated unadjusted significance tests.",
      "base_table": {
        "database": "SNOWFLAKE_EXAMPLE",
        "schema": "RESTAURANT_RECOVERY",
        "table": "OPERATIONS_EVIDENCE"
      },
      "dimensions": [
        {
          "name": "release_id",
          "expr": "RELEASE_ID",
          "data_type": "VARCHAR",
          "description": "Immutable fictional release."
        },
        {
          "name": "restaurant_id",
          "expr": "RESTAURANT_ID",
          "data_type": "VARCHAR",
          "description": "Stable fictional restaurant ID."
        },
        {
          "name": "restaurant_name",
          "expr": "RESTAURANT_NAME",
          "data_type": "VARCHAR",
          "description": "Fictional restaurant name."
        },
        {
          "name": "market",
          "expr": "MARKET",
          "data_type": "VARCHAR",
          "description": "Fictional market, not actual customer DMA."
        },
        {
          "name": "business_date",
          "expr": "BUSINESS_DATE",
          "data_type": "DATE",
          "description": "Local business date. Default 2026-07-20 inclusive to 2026-09-14 exclusive."
        },
        {
          "name": "baseline_date",
          "expr": "BASELINE_DATE",
          "data_type": "DATE",
          "description": "Explicit 364-day aligned baseline date."
        },
        {
          "name": "as_of_date",
          "expr": "AS_OF_DATE",
          "data_type": "DATE",
          "description": "Fixed synthetic as-of date, not today."
        },
        {
          "name": "daypart",
          "expr": "DAYPART",
          "data_type": "VARCHAR",
          "description": "Breakfast, Lunch, Dinner, Late night."
        },
        {
          "name": "evidence_id",
          "expr": "EVIDENCE_ID",
          "data_type": "VARCHAR",
          "description": "Cell evidence identity; aggregate answers must also state filters and population."
        }
      ],
      "metrics": [
        {
          "name": "m_current_open_hours",
          "expr": "SUM(CURRENT_OPEN_HOURS)",
          "description": "All-channel operating hours, once per daypart."
        },
        {
          "name": "m_baseline_open_hours",
          "expr": "SUM(BASELINE_OPEN_HOURS)",
          "description": "Paired baseline hours."
        },
        {
          "name": "m_current_labor_hours",
          "expr": "SUM(CURRENT_LABOR_HOURS)",
          "description": "Paid hours, not employee count."
        },
        {
          "name": "m_baseline_labor_hours",
          "expr": "SUM(BASELINE_LABOR_HOURS)",
          "description": "Baseline paid hours."
        },
        {
          "name": "m_current_guests",
          "expr": "SUM(CURRENT_GUESTS)",
          "description": "All-channel guests with complete operational evidence."
        },
        {
          "name": "m_baseline_guests",
          "expr": "SUM(BASELINE_GUESTS)",
          "description": "Paired all-channel baseline guests."
        },
        {
          "name": "m_guests_per_open_hour",
          "expr": "SUM(CURRENT_GUESTS)/NULLIF(SUM(CURRENT_OPEN_HOURS),0)",
          "description": "Not occupancy or unmet demand."
        },
        {
          "name": "m_baseline_guests_per_open_hour",
          "expr": "SUM(BASELINE_GUESTS)/NULLIF(SUM(BASELINE_OPEN_HOURS),0)",
          "description": "Baseline productivity."
        },
        {
          "name": "m_service_minutes",
          "expr": "SUM(CURRENT_SERVICE_TOTAL)/NULLIF(SUM(CURRENT_SERVICE_COUNT),0)",
          "description": "Observation-weighted service time."
        },
        {
          "name": "m_excluded_days",
          "expr": "SUM(EXCLUDED_DAYS)",
          "description": "Excluded daypart observations."
        }
      ]
    }
  ],
  "module_custom_instructions": {
    "sql_generation": "One row per restaurant/date/daypart. All channels only: do not filter or allocate operational hours to a channel. Default 2026-07-20 inclusive to 2026-09-14 exclusive. Weighted service times, never mean of means. Incomplete observations withheld. Staffing changes are descriptive, not proof of cause. Opposite guest outcomes under the same labor change challenge a universal explanation but neither prove nor disprove a labor effect at either location: heterogeneous effects and confounding remain possible. Never say the other restaurant must decline if labor had any causal effect. A contrasting restaurant is not automatically an experimental control; require pre-trend comparability, confounder and spillover review. Scheduled hours and actual paid hours are different; these are paid hours. Guest occasions are not transactions or checks. Prospective switchback designs require carryover/washout and serial-correlation review. Any interim stopping rule needs a pre-specified sequential-analysis design, not repeated unadjusted significance tests.",
    "question_categorization": "Do not infer retention, profit, elasticity, causation or actual customer performance from fictional observations."
  },
  "verified_queries": [
    {
      "name": "example_1",
      "question": "What happened to R101 breakfast hours, staffing, and guests per open hour?",
      "sql": "SELECT DAYPART, SUM(CURRENT_OPEN_HOURS) AS OPEN_HOURS, SUM(BASELINE_OPEN_HOURS) AS BASELINE_OPEN_HOURS, SUM(CURRENT_LABOR_HOURS) AS LABOR_HOURS, SUM(BASELINE_LABOR_HOURS) AS BASELINE_LABOR_HOURS, SUM(CURRENT_GUESTS)/NULLIF(SUM(CURRENT_OPEN_HOURS),0) AS GUESTS_PER_OPEN_HOUR, SUM(BASELINE_GUESTS)/NULLIF(SUM(BASELINE_OPEN_HOURS),0) AS BASELINE_GUESTS_PER_OPEN_HOUR, SUM(EXCLUDED_DAYS) AS EXCLUDED_DAYS FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.OPERATIONS_EVIDENCE WHERE RESTAURANT_ID='R101' AND DAYPART='Breakfast' AND BUSINESS_DATE >= '2026-07-20' AND BUSINESS_DATE < '2026-09-14' GROUP BY DAYPART",
      "use_as_onboarding_question": true
    },
    {
      "name": "example_2",
      "question": "Compare R101 and R103 breakfast labor changes in the eight-week window.",
      "sql": "SELECT RESTAURANT_ID, SUM(CURRENT_LABOR_HOURS) AS CURRENT_LABOR_HOURS, SUM(BASELINE_LABOR_HOURS) AS BASELINE_LABOR_HOURS, SUM(CURRENT_GUESTS) AS CURRENT_GUESTS, SUM(BASELINE_GUESTS) AS BASELINE_GUESTS FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.OPERATIONS_EVIDENCE WHERE RESTAURANT_ID IN ('R101','R103') AND DAYPART='Breakfast' AND BUSINESS_DATE >= '2026-07-20' AND BUSINESS_DATE < '2026-09-14' GROUP BY RESTAURANT_ID",
      "use_as_onboarding_question": true
    }
  ]
}
$$
);

-- ---------------------------------------------------------------------
-- 3/3 Comparisons -- frozen pre-period peers, descriptive gaps, the
--     sensitivity check and the reason a gap was withheld. GAP_STATUS is
--     exposed as a first-class dimension so "why is there no comparison?"
--     is a question with a retrievable answer, and a NULL gap can never be
--     rendered as zero difference.
-- ---------------------------------------------------------------------
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS',
$$
{
  "name": "SV_RESTAURANT_RECOVERY_COMPARISONS",
  "description": "Synthetic restaurant recovery. Guest occasions are not unique people. Descriptive analysis, never causal attribution. Expires: 2026-10-22.",
  "tables": [
    {
      "name": "evidence",
      "description": "One row per restaurant/window/peer scope. Always filter a single WINDOW_NAME. Do not sum rates or guest counts across scopes/windows. Default 8 weeks. Matching uses preceding 26 weeks only; selected-peer missingness or lifecycle change withholds the entire gap without rematching. Null gap is unavailable, never zero. Across markets is a restaurant-level descriptive comparison, not causal DMA effect. No custom peer-window recomputation is supported. Similar top-three and top-five gaps show stability only to that subset choice; they do not prove robustness to any single peer or to confounding. Guest occasions are not transactions, checks, or unique people. Similarity-selected peers are not automatically valid experiment controls; require pre-trend, confounding, and spillover review. When an exact requested window is unsupported, do not silently substitute another or claim eight weeks is closest to a thirteen-day window. Guest change requests should include the signed occasion count as well as percentage when available; use Performance for counts.",
      "base_table": {
        "database": "SNOWFLAKE_EXAMPLE",
        "schema": "RESTAURANT_RECOVERY",
        "table": "COMPARISON_EVIDENCE"
      },
      "dimensions": [
        {
          "name": "release_id",
          "expr": "RELEASE_ID",
          "data_type": "VARCHAR",
          "description": "Immutable fictional release."
        },
        {
          "name": "restaurant_id",
          "expr": "RESTAURANT_ID",
          "data_type": "VARCHAR",
          "description": "Stable fictional restaurant ID."
        },
        {
          "name": "restaurant_name",
          "expr": "RESTAURANT_NAME",
          "data_type": "VARCHAR",
          "description": "Fictional restaurant name."
        },
        {
          "name": "market",
          "expr": "MARKET",
          "data_type": "VARCHAR",
          "description": "Fictional market, not actual customer DMA."
        },
        {
          "name": "window_name",
          "expr": "WINDOW_NAME",
          "data_type": "VARCHAR",
          "description": "Exactly 8 weeks or 4 weeks. Filter exactly one."
        },
        {
          "name": "window_start",
          "expr": "WINDOW_START",
          "data_type": "DATE",
          "description": "Inclusive window start."
        },
        {
          "name": "window_end",
          "expr": "WINDOW_END",
          "data_type": "DATE",
          "description": "Exclusive window end."
        },
        {
          "name": "peer_scope",
          "expr": "PEER_SCOPE",
          "data_type": "VARCHAR",
          "description": "Within market or Across markets. Filter exactly one for aggregates."
        },
        {
          "name": "gap_status",
          "expr": "GAP_STATUS",
          "data_type": "VARCHAR",
          "description": "Available or reason comparison is withheld."
        },
        {
          "name": "peer_ids",
          "expr": "PEER_IDS",
          "data_type": "VARCHAR",
          "description": "Frozen pre-period-selected restaurant IDs."
        },
        {
          "name": "peer_count",
          "expr": "PEER_COUNT",
          "data_type": "NUMBER",
          "description": "Number selected, minimum three."
        },
        {
          "name": "focal_change_pct",
          "expr": "FOCAL_CHANGE_PCT",
          "data_type": "FLOAT",
          "description": "Focal percentage, not additive."
        },
        {
          "name": "peer_change_pct",
          "expr": "PEER_CHANGE_PCT",
          "data_type": "FLOAT",
          "description": "Equal-weight peer percentage, null when withheld."
        },
        {
          "name": "gap_pp",
          "expr": "GAP_PP",
          "data_type": "FLOAT",
          "description": "Descriptive percentage-point gap; never recoverable guests."
        },
        {
          "name": "top3_gap_pp",
          "expr": "TOP3_GAP_PP",
          "data_type": "FLOAT",
          "description": "Sensitivity using first three of same selected peers."
        },
        {
          "name": "evidence_id",
          "expr": "EVIDENCE_ID",
          "data_type": "VARCHAR",
          "description": "Release/restaurant/window/peer-scope identity."
        }
      ],
      "metrics": [
        {
          "name": "m_comparison_count",
          "expr": "COUNT(*)",
          "description": "Number of comparison records, not restaurants unless scope/window fixed."
        }
      ]
    }
  ],
  "module_custom_instructions": {
    "sql_generation": "One row per restaurant/window/peer scope. Always filter a single WINDOW_NAME. Do not sum rates or guest counts across scopes/windows. Default 8 weeks. Matching uses preceding 26 weeks only; selected-peer missingness or lifecycle change withholds the entire gap without rematching. Null gap is unavailable, never zero. Across markets is a restaurant-level descriptive comparison, not causal DMA effect. No custom peer-window recomputation is supported. Similar top-three and top-five gaps show stability only to that subset choice; they do not prove robustness to any single peer or to confounding. Guest occasions are not transactions, checks, or unique people. Similarity-selected peers are not automatically valid experiment controls; require pre-trend, confounding, and spillover review. When an exact requested window is unsupported, do not silently substitute another or claim eight weeks is closest to a thirteen-day window. Guest change requests should include the signed occasion count as well as percentage when available; use Performance for counts.",
    "question_categorization": "Do not infer retention, profit, elasticity, causation or actual customer performance from fictional observations."
  },
  "verified_queries": [
    {
      "name": "example_1",
      "question": "Compare R101 with its within-market and cross-market peers for eight weeks.",
      "sql": "SELECT RESTAURANT_ID, PEER_SCOPE, GAP_STATUS, PEER_COUNT, PEER_IDS, FOCAL_CHANGE_PCT, PEER_CHANGE_PCT, GAP_PP, TOP3_GAP_PP FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.COMPARISON_EVIDENCE WHERE RESTAURANT_ID='R101' AND WINDOW_NAME='8 weeks' ORDER BY PEER_SCOPE",
      "use_as_onboarding_question": true
    },
    {
      "name": "example_2",
      "question": "Why is R312 missing a peer comparison?",
      "sql": "SELECT RESTAURANT_ID, PEER_SCOPE, GAP_STATUS, PEER_COUNT FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.COMPARISON_EVIDENCE WHERE RESTAURANT_ID='R312' AND WINDOW_NAME='8 weeks' ORDER BY PEER_SCOPE",
      "use_as_onboarding_question": true
    },
    {
      "name": "example_3",
      "question": "Which eight-week comparisons are withheld?",
      "sql": "SELECT RESTAURANT_ID, PEER_SCOPE, GAP_STATUS, PEER_IDS FROM SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.COMPARISON_EVIDENCE WHERE WINDOW_NAME='8 weeks' AND GAP_STATUS <> 'Available' ORDER BY RESTAURANT_ID, PEER_SCOPE",
      "use_as_onboarding_question": true
    }
  ]
}
$$
);
