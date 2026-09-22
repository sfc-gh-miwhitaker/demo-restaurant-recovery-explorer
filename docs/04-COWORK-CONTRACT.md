# CoWork Analytical Contract v3

Pair-programmed by SE Community + Cortex Code

## Boundary

Only fictional observations enter the demo. Real source mappings are proposals until
customer definitions and row-level reconciliation are confirmed. Public research
guides methods, not scenario effect sizes. CoWork is the business interface; CoCo
performs engineering and mapping. The superseded local map application is removed.

## Grains and Units

- ROSTER: restaurant ID; fictional market and format; inclusive opening and exclusive closure date.
- CALENDAR: local business date; explicit 364-day baseline; Monday week; complete-day flag.
- PERFORMANCE: restaurant/business date/daypart/channel; integer guest occasions and checks,
  net sales in USD excluding tax/tips, net of refunds; independent completeness flag.
- OPERATIONS: restaurant/business date/daypart; open hours, paid labor hours, service
  minutes and observation count. Hours are never joined at channel grain.
- EVENTS: event ID; restaurant, effective date, affected daypart, observed change type.
- RELEASE: release ID, seed, as-of date, contract and analysis versions, synthetic flag.

The canonical dayparts are Breakfast, Lunch, Dinner, Late night. Channels are Dine-in,
Takeaway, Delivery. Customer adapters must explicitly map their values. Missing is
not zero. Zero outside lifecycle represents documented inactivity. Every expected
cell exists in the fictional fixture; customer missing cells must be marked incomplete.

Default comparison: 2026-07-20 through 2026-09-13 inclusive. Four-week alternative:
2026-08-17 through 2026-09-13. Baseline uses calendar mappings, not calendar-year subtraction.
Fixed comparison windows bound the first peer workflow; arbitrary-window performance
is supported, but an unsupported peer window must be identified rather than fabricated.

## Calculations

Include a paired cell only if both current and baseline observations are complete.
Exclude both sides otherwise. Sum current minus baseline guests. First aggregate
selected cells to restaurants; then compute gross restaurant losses and offsetting
gains. Gains minus losses equals market net change. Daypart and channel breakdowns
are alternative explanations of the same total, never additional losses.

Rates use summed numerators and denominators; zero baselines yield NULL rates.
Sales/guests is spend per guest; sales/checks is average check. Neither identifies
pure price effects. Fleet lifecycle and data coverage are separate dimensions.

Operations normalization requires all channels complete for that daypart/day and
complete operations. A channel filter cannot reduce the open-hours denominator.
Service averages weight by observation count. No occupancy or lost-demand claim
can be derived from guests/open hour.

## Peer Policy v3

Within-market peers: same format, complete active pre-period (26 weeks), up to five
nearest neighbors, minimum three. Features: mean daily guests, breakfast mix,
delivery mix, mean daily open hours. Normalize differences by explicit scale floors;
weights 0.4/0.2/0.2/0.2, maximum distance 1.0. These are demonstration choices, not
calibrated statistical confidence. Stable restaurant ID breaks ties.

Cross-market comparison: same-format restaurants outside the focal market, chosen
by the same pre-period-only rule. This is a matched restaurant comparison across
markets, not a causal DMA effect or licensed industry benchmark. Report whole-market
comps separately and expose composition differences.

Freeze peers before outcomes. Withhold the entire gap if any selected peer has
incomplete paired outcomes or changes lifecycle. Never replace a failed peer based
on outcomes. Equal-weight peer change is the mean of each peer's own change rate;
the focal gap is in percentage points. Show sensitivity using the top three versus
up to five selected peers, without making the sensitivity result another causal claim.

## Evidence Contract

Return release/as-of, period, restaurant/market, daypart/channel, source view,
population, coverage, exclusions and peer policy with answers. Calculate metrics
before narration. Distinguish observed facts, descriptive comparisons, hypotheses,
and prospective tests. Changing a scope parameter invalidates prior evidence.

## Eighteen-Module Coverage

| Module | First release treatment | Additional real-data prerequisites |
|---|---|---|
| Peer DMA selection | Synthetic market context and cross-market restaurant matching | Approved DMA policy and market comparability |
| Comp sales/traffic | Core synthetic measures | Guest definition, sales accounting, comp rules |
| Daypart mix | Core | Explicit time boundaries |
| Channel mix | Core | Destination mapping and availability |
| Labor | Synthetic hours and dated changes | Time-clock/shift facts; roles and wage basis |
| Guest sentiment | Deferred, no fabricated review findings | Authorized reviews, counts and provenance |
| Discounting | Deferred | Discount amounts, incidence and net-sales reconciliation |
| Operating hours | Core synthetic observations | Effective-dated actual hours and exceptions |
| Fleet health | Openings/closures; remodel context deferred | Lifecycle/remodel history |
| Speed of service | Synthetic weighted observations | Definition and measured timestamps |
| Unit-level comps | Core | Stable restaurant identifiers |
| Cross-module comparison | Core descriptive evidence | Time and population alignment |
| Media investment | Prospective test design only | Spend, targeting, control assignment |
| Industry benchmark | Methodology context only | Licensed aligned benchmark series |
| Brand audits | Deferred | Audit history and scoring definitions |
| External context | Research context only | Dated/geographically aligned licensed/public series |
| Competitive density | Deferred | Valid trade areas, establishments, methodology |
| Food cost/inventory | Deferred | Costs, waste, recipes and accounting grain |

Loyalty and training remain explicit extensions, not implied capabilities. No
retention, elasticity, ROI, recovered-guest promise, or measured intervention effect
is included without the corresponding data and design.