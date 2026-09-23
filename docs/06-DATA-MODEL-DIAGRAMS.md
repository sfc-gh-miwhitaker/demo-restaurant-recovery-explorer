# Data Model and Mapping Diagrams

Pair-programmed by SE Community + Cortex Code

> Diagram companion to [the analytical contract](04-COWORK-CONTRACT.md). The contract
> is authoritative; where a diagram simplifies, the contract wins. Everything shown
> here describes the fictional fixture and the mapping gate — no customer schema,
> identifier or definition appears in this file.

Five views of the same system:

1. [Canonical tables and grains](#1-canonical-tables-and-grains) — what is stored, at what grain.
2. [Evidence lineage](#2-evidence-lineage) — how storage becomes something an agent may cite.
3. [Completeness and withholding](#3-completeness-and-withholding) — the three gates that decide whether a number is shown.
4. [Mapping boundary and status ladder](#4-mapping-boundary-and-status-ladder) — what a customer source must prove before it is trusted.
5. [Capability gating](#5-capability-gating) — which module is live, and which customer fact unblocks the rest.

---

## 1. Canonical tables and grains

```mermaid
erDiagram
    RELEASE_METADATA {
        VARCHAR RELEASE_ID PK
        DATE AS_OF_DATE "fixture's fixed today, never CURRENT_DATE"
        BOOLEAN SYNTHETIC "asserted in data, checked before load"
        NUMBER SEED
    }
    ROSTER {
        VARCHAR RELEASE_ID PK
        VARCHAR RESTAURANT_ID PK
        VARCHAR MARKET "fictional, not a customer DMA"
        VARCHAR FORMAT "peer matching never crosses format"
        DATE OPEN_DATE "inclusive"
        DATE CLOSE_DATE "exclusive; NULL means still trading"
    }
    CALENDAR {
        VARCHAR RELEASE_ID PK
        DATE BUSINESS_DATE PK
        DATE BASELINE_DATE "stored -364d, not computed -1y"
        DATE WEEK_START "Monday"
        BOOLEAN COMPLETE "a whole day can be unobserved"
    }
    PERFORMANCE {
        VARCHAR RELEASE_ID PK
        VARCHAR RESTAURANT_ID PK
        DATE BUSINESS_DATE PK
        VARCHAR DAYPART PK
        VARCHAR CHANNEL PK
        NUMBER GUESTS "guest occasions; NOT checks, NOT unique people"
        NUMBER CHECKS "stored separately, deliberately"
        NUMBER NET_SALES "USD excl tax and tips, net of refunds"
        BOOLEAN COMPLETE "FALSE + NULL measures = unobserved; 0 + TRUE = real zero"
    }
    OPERATIONS {
        VARCHAR RELEASE_ID PK
        VARCHAR RESTAURANT_ID PK
        DATE BUSINESS_DATE PK
        VARCHAR DAYPART PK
        NUMBER OPEN_HOURS "no CHANNEL column, by design"
        NUMBER LABOR_HOURS "paid hours"
        NUMBER SERVICE_MINUTES "a mean, not a total"
        NUMBER SERVICE_OBSERVATIONS "the weight for that mean"
        BOOLEAN COMPLETE
    }
    EVENTS {
        VARCHAR RELEASE_ID PK
        VARCHAR EVENT_ID PK
        VARCHAR RESTAURANT_ID FK
        DATE EFFECTIVE_DATE
        VARCHAR DAYPART
        VARCHAR EVENT_TYPE "a logged change, not a cause"
        VARCHAR SOURCE
    }

    RELEASE_METADATA ||--o{ ROSTER : "stamps"
    RELEASE_METADATA ||--o{ CALENDAR : "stamps"
    ROSTER ||--o{ PERFORMANCE : "one row per daypart x channel per day"
    ROSTER ||--o{ OPERATIONS : "one row per daypart per day"
    ROSTER ||--o{ EVENTS : "dated observations"
    CALENDAR ||--o{ PERFORMANCE : "business date"
    CALENDAR ||--o{ OPERATIONS : "business date"
    CALENDAR ||--o| CALENDAR : "BASELINE_DATE pairs to itself -364d"
    PERFORMANCE }o--|| OPERATIONS : "ONLY after channel is collapsed away"
```

The single most consequential feature of this model is a column that does not exist.

```mermaid
flowchart LR
    subgraph perf["PERFORMANCE — per channel"]
        D["Dine-in<br/>guests, checks, sales"]
        T["Takeaway<br/>guests, checks, sales"]
        L["Delivery<br/>guests, checks, sales"]
    end
    subgraph ops["OPERATIONS — per daypart"]
        H["OPEN_HOURS<br/>LABOR_HOURS<br/>one denominator"]
    end
    D --> S["SUM to all-channel<br/>guests per daypart"]
    T --> S
    L --> S
    S --> R["guests per open hour"]
    H --> R
    D -.->|"WRONG: repeats each hour 3x,<br/>productivity reads 1/3 of truth"| H
    T -.-> H
    L -.-> H
```

A restaurant opens its doors once per daypart and serves all three channels with those
same hours. There is no such thing as delivery open hours, so the column does not
exist to be misused, and a channel filter can never shrink the denominator.

Three ideas that get conflated constantly are kept apart:

| Idea | Where it lives | Note |
|---|---|---|
| Guest occasions | `PERFORMANCE.GUESTS` | People served on a visit |
| Checks | `PERFORMANCE.CHECKS` | Transactions, stored separately |
| Unique customers | **absent** | The data cannot answer retention and must not appear to |

---

## 2. Evidence lineage

```mermaid
flowchart TB
    subgraph gen["Generation — tools/generate_cowork.py"]
        G["seeded fictional observations<br/>RELEASE restaurant-recovery-v3-seed-417"]
    end
    subgraph raw["Canonical tables — sql/01_setup.sql"]
        ROS[ROSTER]
        CAL[CALENDAR]
        PERF[PERFORMANCE]
        OPS[OPERATIONS]
        EV[EVENTS]
        MET[RELEASE_METADATA]
    end
    subgraph ev["Evidence layer — sql/02_analytics.sql"]
        PP["PAIRED_PERFORMANCE<br/>restaurant x date x daypart x channel<br/>PAIR_COMPLETE, GUEST_CHANGE, EXCLUDED_PAIRS"]
        OE["OPERATIONS_EVIDENCE<br/>restaurant x date x daypart<br/>EVIDENCE_COMPLETE, hours, weighted service"]
        AW["ANALYSIS_WINDOWS<br/>the only two matched windows"]
        PF["PRE_PERIOD_FEATURES<br/>182 pre-window days, fully observed only"]
        PS["PEER_SELECTION<br/>frozen peers, 2 scopes, distance <= 1.0"]
        WO["WINDOW_OUTCOMES<br/>restaurant x window totals"]
        CE["COMPARISON_EVIDENCE<br/>GAP_STATUS, GAP_PP, TOP3_GAP_PP"]
    end
    subgraph sem["Semantic layer — sql/04_semantics.sql"]
        SVP["SV_..._PERFORMANCE"]
        SVO["SV_..._OPERATIONS"]
        SVC["SV_..._COMPARISONS"]
    end
    subgraph ag["Agent — sql/05_agent.sql"]
        TP[Performance tool]
        TO[Operations tool]
        TC[Comparisons tool]
        SK["skills/<br/>investigation + test-design"]
    end
    CW([CoWork — the only business interface])

    G --> ROS & CAL & PERF & OPS & EV & MET
    PERF --> PP
    CAL --> PP
    ROS --> PP
    MET --> PP
    PP --> OE
    OPS --> OE
    PERF --> PF
    OPS --> PF
    ROS --> PF
    AW --> PF
    AW --> WO
    PF --> PS
    PP --> WO
    PS --> CE
    WO --> CE
    PP --> SVP
    OE --> SVO
    CE --> SVC
    SVP --> TP
    SVO --> TO
    SVC --> TC
    TP & TO & TC & SK --> CW
    EV -.->|"deliberately NOT exposed:<br/>a date coincidence is a lead, not a finding"| CW
```

Two structural choices are visible here.

**The semantic layer reads the evidence views, never the raw tables.** The withholding
rules are compiled into SQL, so they cannot be bypassed from above — a model can be
argued out of a prompt guardrail, not out of a view definition.

**Three semantic views instead of one.** A single wide model would let the planner join
per-channel performance to all-channel hours. Splitting the model makes the most common
error in this domain unreachable rather than merely discouraged.

---

## 3. Completeness and withholding

Three independent gates. Each withholds; none imputes.

### 3a. Pair completeness — `PAIRED_PERFORMANCE`

```mermaid
flowchart TD
    A["current cell<br/>restaurant x date x daypart x channel"] --> B{"BASELINE_DATE exists?<br/>first 364 days have none"}
    B -->|no| OUT["out of scope for pairing<br/>dropped, not counted as excluded"]
    B -->|yes| C{"baseline row found?<br/>LEFT JOIN, so absence survives"}
    C -->|no| X
    C -->|yes| D{"current.COMPLETE<br/>AND baseline.COMPLETE<br/>AND calendar.COMPLETE"}
    D -->|"any FALSE or NULL"| X["PAIR_COMPLETE = FALSE<br/>both sides NULL<br/>EXCLUDED_PAIRS = 1"]
    D -->|"all TRUE"| Y["PAIR_COMPLETE = TRUE<br/>GUEST_CHANGE = current - baseline<br/>EXCLUDED_PAIRS = 0"]
    Y --> Z["LIFECYCLE label:<br/>Comparable / Opening / Closure / Outside"]
    X --> Z
```

`COALESCE(..., FALSE)` is load-bearing: three-valued logic would otherwise leave
`PAIR_COMPLETE` unknown and let the downstream `IFF`s fall through. **Both** sides of a
broken pair are withheld — keeping the observed half would compare a full current period
against a partial baseline and invent a change.

Completeness and comparability are separate axes, and both are reported:

```mermaid
flowchart LR
    subgraph ax["two independent questions"]
        Q1["Was it observed?<br/>EXCLUDED_PAIRS"]
        Q2["Is it like-for-like?<br/>NONCOMP_PAIRS / LIFECYCLE"]
    end
    Q1 --- N["A restaurant can be fully observed<br/>and not comparable — it opened mid-period.<br/>Or comparable and partly unobserved.<br/>Neither substitutes for the other."]
    Q2 --- N
```

### 3b. Evidence completeness — `OPERATIONS_EVIDENCE`

Stricter than pair completeness, because a ratio is only honest when numerator and
denominator cover exactly the same trade.

```mermaid
flowchart TD
    A["one restaurant x date x daypart"] --> B{"CHANNEL_COUNT = 3?"}
    B -->|no| W["EVIDENCE_COMPLETE = FALSE<br/>withhold the WHOLE day<br/>EXCLUDED_DAYS = 1"]
    B -->|yes| C{"EXCLUDED_CHANNELS = 0?"}
    C -->|no| W
    C -->|yes| D{"current ops COMPLETE<br/>AND baseline ops COMPLETE?"}
    D -->|no| W
    D -->|yes| OK["guests and hours both published<br/>service exposed as total + count,<br/>so roll-ups re-weight instead of<br/>averaging averages"]
```

Withholding the whole day is the point: a shrunken numerator against an unchanged
denominator would look like a productivity collapse that never happened.

### 3c. Gap status — `COMPARISON_EVIDENCE`

Ordered most to least fundamental, so the reported reason is the root cause rather than
whichever check ran last.

```mermaid
flowchart TD
    S["focal restaurant x window x peer scope<br/>(row always exists, both scopes)"] --> A{"EXCLUDED_PAIRS > 0"}
    A -->|yes| R1["Incomplete focal observations"]
    A -->|no| B{"NONCOMP_PAIRS > 0"}
    B -->|yes| R2["Focal lifecycle change"]
    B -->|no| C{"PEER_COUNT < 3"}
    C -->|yes| R3["Insufficient pre-period peers"]
    C -->|no| D{"VALID_PEER_COUNT <> PEER_COUNT"}
    D -->|yes| R4["Selected peer incomplete<br/>or lifecycle-changing"]
    D -->|no| E{"BASELINE_GUESTS = 0"}
    E -->|yes| R5["Zero focal baseline"]
    E -->|no| OK["Available<br/>GAP_PP published<br/>+ TOP3_GAP_PP sensitivity"]
    R1 & R2 & R3 & R4 & R5 --> N["GAP_PP = NULL<br/>'not measured here'<br/>NEVER 'no difference'"]
```

Peer selection runs on pre-period features only, and peers are frozen before outcomes
are seen:

```mermaid
flowchart LR
    P["182 pre-window days<br/>fully observed: 2184 cells, 728 ops rows<br/>traded the whole pre-period"] --> F["features:<br/>mean daily guests 0.4<br/>breakfast mix 0.2<br/>delivery mix 0.2<br/>mean open hours 0.2"]
    F --> M["same format only<br/>distance <= 1.0<br/>top 5, min 3<br/>ID breaks ties"]
    M --> FR["FREEZE"]
    FR --> W["window outcomes observed"]
    W --> V{"every selected peer valid?"}
    V -->|yes| G["publish GAP_PP"]
    V -->|no| H["withhold the ENTIRE gap"]
    H -.->|"forbidden: drop the bad peer<br/>and average the rest =<br/>outcome-driven re-matching"| M
    W -.->|"forbidden: selecting on the period<br/>being measured"| F
```

A matched gap is percentage points of difference versus similar restaurants over the
same dates. It is not an effect size, similarity peers are not automatically
experimental controls, and closing the gap is not a forecast of recoverable demand.

---

## 4. Mapping boundary and status ladder

Everything above runs on fictional observations. This section is what a real source has
to prove before any of it may be pointed at customer data.

### 4a. The gate

```mermaid
flowchart TB
    SRC["customer POS / roster / ops extract<br/>native grain, native identifiers"] --> AD["adapt() — tools/mapping.py<br/>structural gate, not an adapter"]
    AD --> CHK{five refusals}
    CHK --> F1["field set is not exactly<br/>restaurant, date, daypart, channel,<br/>guests, checks, sales"]
    CHK --> F2["measure meanings unconfirmed<br/>guests must be guest occasions<br/>sales must be net USD excl tax and tips"]
    CHK --> F3["duplicate dimension id<br/>would fan out the join"]
    CHK --> F4["mapped column absent<br/>schema drift"]
    CHK --> F5["two source rows on one<br/>canonical key<br/>summing is a human decision"]
    F1 & F2 & F3 & F4 & F5 --> STOP["raise — name the decision a human owes"]
    CHK -->|all pass| CANON["canonical grain<br/>restaurant x date x daypart x channel"]
    CANON --> PARITY["parity against the fictional fixture<br/>tools/test_mapping.py"]
    PARITY --> REC["reconciliation at BOTH grains:<br/>duplicates, keys, fanout, nulls,<br/>calendar, lifecycle, aggregates"]
    REC --> ACT["activate only passed capabilities"]
```

Each refusal exists because tolerating it produces silently wrong analytics. A missing
measure definition conflates guests with checks. A duplicate dimension row doubles
volumes. A duplicate canonical key sums two source rows by accident. None of these
announce themselves in a chart — the numbers simply come out wrong and look plausible.

`adapt()` is a gate, not a pipeline: it does not read from a customer system, does not
aggregate, and does not touch Snowflake.

### 4b. Status ladder

```mermaid
flowchart LR
    P["proposed<br/>column-name similarity only"] --> M["metadata-supported<br/>type, grain, cardinality<br/>seen in approved metadata"]
    M --> C["customer-confirmed<br/>the owner has stated<br/>the definition"]
    C --> V["data-validated<br/>row-level reconciliation<br/>passed at both grains"]
    V --> A(["capability activated"])
    P -.->|"never skip"| C
    M -.->|"metadata access is not<br/>permission to read rows"| V
```

No numerical confidence scores. A name match supports a proposal and nothing more.

### 4c. The decisions a customer must actually make

```mermaid
mindmap
  root((unresolved by<br/>column names alone))
    Measures
      guests = occasions or transactions
      net sales incl or excl tax
      tips, discounts, refunds
      delivery commission treatment
      precomputed averages need weights
    Time
      business date vs timestamp date
      daypart boundaries
      fiscal calendar mapping
      last-year columns do not prove alignment
    Dimensions
      channel and destination values
      stable restaurant identifiers
      format and market definitions
      effective-dated roster uniqueness
    Absence
      missing vs zero
      closed vs unobserved
      no workforce facts is not zero labor hours
      first and last sale do not bound open hours
      seats do not establish available seats
    Cardinality
      one canonical key, many source rows
      dimension duplicates
      join fanout
```

Anything unresolved on this map stops the affected capability. It is not repaired
automatically, and the stopping point is reported rather than worked around.

---

## 5. Capability gating

The eighteen modules, and the customer fact each one waits on. Core modules run on the
fictional fixture today; deferred modules are absent rather than approximated.

```mermaid
flowchart LR
    subgraph core["Core in first release"]
        C1["Comp sales and traffic"]
        C2["Daypart mix"]
        C3["Channel mix"]
        C4["Operating hours"]
        C5["Unit-level comps"]
        C6["Cross-module comparison"]
        C7["Speed of service"]
        C8["Peer DMA selection<br/>synthetic market context"]
        C9["Labor<br/>synthetic hours"]
        C10["Fleet health<br/>openings and closures"]
    end
    subgraph need["Real-data prerequisite"]
        N1["guest definition,<br/>sales accounting, comp rules"]
        N2["explicit time boundaries"]
        N3["destination mapping<br/>and availability"]
        N4["effective-dated actual hours<br/>and exceptions"]
        N5["stable restaurant identifiers"]
        N6["time and population alignment"]
        N7["definition and<br/>measured timestamps"]
        N8["approved DMA policy<br/>and comparability"]
        N9["time-clock and shift facts,<br/>roles, wage basis"]
        N10["lifecycle and remodel history"]
    end
    C1 --> N1
    C2 --> N2
    C3 --> N3
    C4 --> N4
    C5 --> N5
    C6 --> N6
    C7 --> N7
    C8 --> N8
    C9 --> N9
    C10 --> N10
```

```mermaid
flowchart LR
    subgraph def["Deferred — no fabricated findings"]
        D1["Guest sentiment"]
        D2["Discounting"]
        D3["Brand audits"]
        D4["Competitive density"]
        D5["Food cost and inventory"]
    end
    subgraph ctx["Context or design only"]
        X1["Media investment<br/>prospective test design"]
        X2["Industry benchmark<br/>methodology context"]
        X3["External context<br/>research context"]
    end
    subgraph blk["Blocking prerequisite"]
        B1["authorized reviews,<br/>counts, provenance"]
        B2["discount amounts, incidence,<br/>net-sales reconciliation"]
        B3["audit history<br/>and scoring definitions"]
        B4["valid trade areas,<br/>establishments, methodology"]
        B5["costs, waste, recipes,<br/>accounting grain"]
        B6["spend, targeting,<br/>control assignment"]
        B7["licensed aligned<br/>benchmark series"]
        B8["dated, geographically<br/>aligned licensed series"]
    end
    D1 --> B1
    D2 --> B2
    D3 --> B3
    D4 --> B4
    D5 --> B5
    X1 --> B6
    X2 --> B7
    X3 --> B8
```

Loyalty and training are explicit extensions, not implied capabilities. No retention,
elasticity, ROI, recovered-guest promise or measured intervention effect exists without
the corresponding data **and** design.

```mermaid
flowchart TD
    Q["a question arrives"] --> A{"is the required fact<br/>mapped and validated?"}
    A -->|yes| ANS["calculate, then narrate:<br/>release, period, population,<br/>coverage, exclusions, peer policy"]
    A -->|no| SAY["name the missing fact<br/>and the decision owner"]
    ANS --> CLS{"which kind of statement?"}
    CLS --> O["observed fact"]
    CLS --> DE["descriptive comparison"]
    CLS --> HY["hypothesis"]
    CLS --> TE["prospective test"]
    SAY -.->|never| FAB["approximate, infer,<br/>or fill the gap"]
```

---

## Reading order for a newcomer

| To understand | Read |
|---|---|
| What is stored and why | §1, then `sql/01_setup.sql` |
| How a number earns the right to be shown | §3, then `sql/02_analytics.sql` |
| What the agent can see | §2, then `sql/04_semantics.sql` and `sql/05_agent.sql` |
| What adoption actually requires | §4 and §5, then `tools/mapping.py` and the source-mapping skill |
