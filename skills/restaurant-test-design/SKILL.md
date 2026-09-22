---
name: restaurant-test-design
description: Design a prospective restaurant recovery experiment from an evidence-backed hypothesis. Use for what should we test, staffing or hours pilots, promotion evaluation, success criteria, and how to measure recovery.
---

# Restaurant Test Design

## Purpose

Make an actionable measurement proposal without claiming an unrun intervention works.

## Architecture

Verified investigation -> candidate intervention -> eligibility and control design ->
outcomes and guardrails -> explicit missing inputs -> human approval.

## Key Files

This instruction-only SKILL.md uses evidence from the configured analytical tools.
No scripts, external actions or automated experiment assignments are included.

## Workflow

1. Retrieve or confirm the investigation's scope, evidence, competing explanations
   and missing inputs. If evidence is unavailable, propose data collection first.
2. Define one intervention and a mechanism it is intended to test. Do not prescribe
   optimal labor levels or promise guest recovery from a descriptive peer gap.
3. Define eligible restaurants, pre-period, treatment and control, observation window,
   implementation checks, spillover risks and seasonal/calendar adjustments.
4. Prefer randomized assignment where feasible. Otherwise describe a matched-control
   design and its assumptions, including comparable pre-trends. Existing similarity
   peers are candidates for review, not automatically valid experimental controls.
5. Specify one primary outcome such as incremental dine-in guest occasions, and
   guardrails for margin, service and labor. Keep total sales and dine-in objectives distinct.
6. Identify baseline variance, minimum meaningful effect and available units needed
   to determine sample size/duration. Do not invent statistical power from aggregate totals.
7. Request cost and contribution data before profit/ROI calculations. Account for
   discounts, incremental labor and delivery fees where applicable, without double counting.
8. Return a prospective plan for human review. Stop before assigning units, changing
   staffing, publishing offers, sending messages or creating tasks.

## Output

Hypothesis; evidence and counterevidence; proposed intervention; eligible population;
comparison design; primary measure; service/economic guardrails; missing inputs;
success/stop criteria to agree before launch. Label all illustrative numbers synthetic.

## Extension Playbook

For measured experiment results, first add approved assignment, exposure, dates,
outcomes and cost data. Validate estimator assumptions independently. Do not turn
this prospective workflow into retrospective causal claims by changing wording alone.

## Snowflake Objects

Read-only Performance, Operations and Comparisons tools. No experiment execution objects.

## Gotchas

Before/after is not a causal estimate by itself. Member/nonmember loyalty differences
can reflect selection. Faster service is not universally better hospitality.
An industry cost median is not an operating target. Reviews do not prove a sales effect.