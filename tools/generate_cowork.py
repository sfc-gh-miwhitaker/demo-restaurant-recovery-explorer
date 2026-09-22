"""Reproducible fictional source observations; no customer data or network access.

What this is
    A deterministic generator for a complete, two-year restaurant fixture:
    36 restaurants across 3 markets, every day, daypart and channel. Given a
    seed it always produces byte-identical output, so an answer demonstrated
    today can be reproduced tomorrow and a reviewer can check the arithmetic
    against the source rather than trusting a screenshot.

Why synthesise at all
    The demo needs situations that are awkward on purpose -- a closure
    mid-window, an opening with no prior year, one unobserved cell, a
    restaurant that improved while its market declined. Real data rarely
    contains a clean example of each, and never with permission to publish.

Design rules
    * The grid is complete by construction: every restaurant x date x daypart
      x channel cell exists. Incompleteness is then introduced deliberately,
      in one known place, so "missing" is a decision rather than an accident.
    * Observations outside a restaurant's lifecycle are explicit zeros, never
      absent rows. Closed is a measurement; missing is not.
    * Effects are applied as multiplicative factors on a smooth base, so a
      decline is visible against weekday and seasonal variation but is not
      the only thing moving. An investigator has to separate signal from
      noise, which is the skill the demo is about.
    * Nothing here names a cause. The generator knows why each series bends;
      the runtime deliberately does not. EVENTS records only that something
      was logged on a date, and the scenario structure below never reaches
      the semantic views, the skills or the agent -- otherwise the demo would
      be testing whether a model can read a label rather than whether it can
      investigate evidence.

Outputs
    One CSV per canonical table, a manifest with row counts and SHA-256
    digests, and expected_answers.json for local verification. The expected
    answers are a test fixture for humans, never an input to the runtime.
"""

import argparse
import csv
import hashlib
import json
import random
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path


# Fixture constants. Dates are fixed rather than relative to today: a demo
# whose window moves with the calendar cannot be verified twice.
RELEASE = "restaurant-recovery-v3-seed-417"
START = date(2024, 9, 16)   # first business date; ~2 years of history
AS_OF = date(2026, 9, 14)   # exclusive end -- the fixture's fixed "today"
CHANGE = date(2026, 7, 20)  # the date the injected effects begin
DAYPARTS = ("Breakfast", "Lunch", "Dinner", "Late night")
CHANNELS = ("Dine-in", "Takeaway", "Delivery")
# FIELDS is the canonical column contract, in order. sql/01_setup.sql must
# match it exactly, and tools/native_runtime.py compares the live table
# schema against it before loading, so a rename fails loudly instead of
# shifting values into the wrong columns.
FIELDS = {
    "ROSTER": ["RELEASE_ID", "RESTAURANT_ID", "RESTAURANT_NAME", "MARKET", "FORMAT", "OPEN_DATE", "CLOSE_DATE"],
    "CALENDAR": ["RELEASE_ID", "BUSINESS_DATE", "BASELINE_DATE", "WEEK_START", "COMPLETE"],
    "PERFORMANCE": ["RELEASE_ID", "RESTAURANT_ID", "BUSINESS_DATE", "DAYPART", "CHANNEL", "GUESTS", "CHECKS", "NET_SALES", "COMPLETE"],
    "OPERATIONS": ["RELEASE_ID", "RESTAURANT_ID", "BUSINESS_DATE", "DAYPART", "OPEN_HOURS", "LABOR_HOURS", "SERVICE_MINUTES", "SERVICE_OBSERVATIONS", "COMPLETE"],
    "EVENTS": ["RELEASE_ID", "EVENT_ID", "RESTAURANT_ID", "EFFECTIVE_DATE", "DAYPART", "EVENT_TYPE", "SOURCE"],
    "RELEASE_METADATA": ["RELEASE_ID", "AS_OF_DATE", "CONTRACT_VERSION", "ANALYSIS_VERSION", "SYNTHETIC", "SEED"],
}
# The uniqueness key for each table, excluding RELEASE_ID. validate() uses
# these to prove no duplicate rows exist -- a duplicate at the grain would
# double-count on every join downstream, which is the single most common way
# a pipeline produces confidently wrong totals.
GRAINS = {
    "ROSTER": ["RESTAURANT_ID"], "CALENDAR": ["BUSINESS_DATE"],
    "PERFORMANCE": ["RESTAURANT_ID", "BUSINESS_DATE", "DAYPART", "CHANNEL"],
    "OPERATIONS": ["RESTAURANT_ID", "BUSINESS_DATE", "DAYPART"],
    "EVENTS": ["EVENT_ID"], "RELEASE_METADATA": ["RELEASE_ID"],
}


def observations(seed=417):
    """Build every table in memory and return them keyed by table name.

    Structure: metadata, then the calendar, then a loop over markets and
    restaurants, and within each restaurant a loop over days, dayparts and
    channels. Guests are generated at the finest grain and hours one level
    up, at the daypart, because that is genuinely how a restaurant works --
    one set of doors serving all three channels at once.
    """
    # Seeded PRNG, and the only source of randomness. Same seed, same fixture.
    rng = random.Random(seed)
    tables = {name: [] for name in FIELDS}
    # The seed travels in the release ID, so a loaded fixture can be traced
    # back to the exact invocation that produced it.
    release = f"restaurant-recovery-v3-seed-{seed}"

    def append(table, *values):
        # strict=True makes a positional mistake raise immediately rather than
        # silently truncating a row to the shorter of the two sequences.
        tables[table].append(dict(zip(FIELDS[table], (release, *values), strict=True)))

    append("RELEASE_METADATA", AS_OF.isoformat(), "3.0", "pre26-v3", True, seed)
    # Calendar first: it is the single place the year-ago pairing is defined.
    for offset in range((AS_OF - START).days):
        business_date = START + timedelta(days=offset)
        append("CALENDAR", business_date.isoformat(),
               # 364 days = 52 whole weeks, so Saturday pairs with Saturday.
               # The first 364 days have no baseline and store NULL -- out of
               # scope for pairing, which is different from unobserved.
               (business_date - timedelta(days=364)).isoformat() if offset >= 364 else None,
               # Monday-anchored week start, for weekly roll-ups.
               (business_date - timedelta(days=business_date.weekday())).isoformat(), True)
    # 3 markets x 12 restaurants. IDs encode the market as the first digit,
    # which keeps them readable without making market a derived field.
    for market_index, market in enumerate(("Mesa Vale", "Juniper Coast", "Cedar Basin")):
        for restaurant_index in range(12):
            restaurant_id = f"R{market_index + 1}{restaurant_index + 1:02d}"
            # Most restaurants traded for the whole fixture. Two do not, and
            # they exist so the comparability rules have something to catch:
            # one closes mid-window (its loss is structural, not performance)
            # and one opens mid-window (it has no prior year to compare to).
            open_date = date(2023, 1, 1)
            close_date = None
            if restaurant_id == "R110":
                close_date = date(2026, 8, 17)
            if restaurant_id == "R111":
                open_date = date(2026, 8, 3)
            # One restaurant has a different format, so format-matched peer
            # selection has a case where the eligible pool is genuinely
            # too small -- which surfaces as a withheld comparison.
            format_name = "Roadside" if restaurant_id == "R312" else "Family dining"
            append("ROSTER", restaurant_id, f"{market} Diner {restaurant_index + 1:02d}", market,
                   format_name, open_date.isoformat(), close_date.isoformat() if close_date else None)
            # Dated log entries only. Two restaurants share a same-day
            # staffing entry and then move in opposite directions, so an
            # investigator who treats an adjacent event as a cause is
            # demonstrably wrong. That is the point of including it.
            if restaurant_id in ("R101", "R103"):
                append("EVENTS", f"E-{restaurant_id}", restaurant_id, "2026-07-13", "Breakfast",
                       "Staffing change", "Fictional operating log")
            if restaurant_id == "R102":
                append("EVENTS", f"E-{restaurant_id}", restaurant_id, CHANGE.isoformat(), "Late night",
                       "Hours change", "Fictional operating log")
            for offset in range((AS_OF - START).days):
                business_date = START + timedelta(days=offset)
                active = open_date <= business_date and (close_date is None or business_date < close_date)
                changed = business_date >= CHANGE
                # Baseline variation, applied to every restaurant equally:
                # weekends trade well above midweek, and a gentle seasonal
                # ripple sits on top. Without this, any injected effect would
                # be trivially visible and the demo would teach nothing about
                # separating a real movement from ordinary variation.
                weekday_factor = (1.0, 0.96, 0.99, 1.04, 1.12, 1.32, 1.22)[business_date.weekday()]
                seasonal = 1 + 0.03 * ((offset % 364) // 28 - 6) / 6
                for daypart_index, daypart in enumerate(DAYPARTS):
                    # Hours are per daypart and shared across channels. A
                    # closed restaurant records 0.0 hours, not NULL.
                    open_hours = (6.0, 5.0, 6.0, 7.0)[daypart_index] if active else 0.0
                    # A late-night hours reduction: real lost opportunity, so
                    # guests-per-open-hour barely moves while guests fall.
                    # The capacity explanation and the demand explanation are
                    # distinguishable only if hours are checked.
                    if restaurant_id == "R102" and changed and daypart == "Late night":
                        open_hours = 3.5
                    labor_hours = open_hours * (2.8, 2.5, 2.2, 1.7)[daypart_index]
                    # The same labor reduction at two restaurants, from the
                    # same date. Their guest outcomes diverge, which is what
                    # makes "labor cuts caused this" a hypothesis to test
                    # rather than a conclusion to state.
                    if restaurant_id in ("R101", "R103") and business_date >= date(2026, 7, 13) and daypart == "Breakfast":
                        labor_hours *= 0.80
                    # Service time is a mean over SERVICE_OBSERVATIONS samples;
                    # the count is stored so consumers can re-weight instead
                    # of averaging averages.
                    service_minutes = 12.0 + daypart_index + rng.randrange(0, 5) / 2
                    if restaurant_id == "R101" and changed and daypart == "Breakfast":
                        service_minutes += 4
                    append("OPERATIONS", restaurant_id, business_date.isoformat(), daypart,
                           # Closed days carry no service average, and the
                           # observation count is 0 rather than NULL: there
                           # were genuinely zero samples to average.
                           open_hours, round(labor_hours, 2), service_minutes if active else None,
                           12 if active else 0, True)
                    for channel_index, channel in enumerate(CHANNELS):
                        # Base volume: daypart scale x channel share, tilted
                        # slightly by restaurant so no two are identical, then
                        # moved by weekday and season.
                        base = (100, 90, 66, 34)[daypart_index] * (0.72, 0.16, 0.12)[channel_index]
                        base *= (1 + restaurant_index * 0.012) * weekday_factor * seasonal
                        factor = 1.0
                        if changed:
                            # Market-level movement first, so a restaurant's
                            # own change has to be read net of its market --
                            # which is exactly why peer scope is reported
                            # within market and across markets separately.
                            factor = (0.98, 0.92, 1.015)[market_index]
                            # Restaurant-specific effects, each shaped to make
                            # one reasoning error detectable:
                            # concentrated in a single daypart, so a whole-
                            # restaurant total understates what happened;
                            if restaurant_id == "R101" and daypart == "Breakfast":
                                factor *= 0.65
                            # paired with the hours reduction above, so the
                            # loss has a capacity explanation available;
                            if restaurant_id == "R102" and daypart == "Late night":
                                factor *= 0.50
                            # growing inside a declining market, replacing the
                            # market factor entirely, so gross losses and net
                            # change are different numbers;
                            if restaurant_id == "R103":
                                factor = 1.06
                            # and confined to one channel, so a daypart-only
                            # view misses it completely.
                            if restaurant_id == "R104" and channel == "Delivery":
                                factor *= 0.62
                        # Small integer jitter keeps totals from looking
                        # synthesised. max(0, ...) prevents negative guests;
                        # an inactive restaurant records a true zero.
                        guests = max(0, round(base * factor + rng.randrange(-2, 3))) if active else 0
                        # Party size differs by channel, which is why checks
                        # and guests are separate measures and neither can be
                        # derived from the other by a fixed ratio.
                        checks = round(guests / (1.8 if channel == "Dine-in" else 1.3))
                        # A modest price rise after the change date, so sales
                        # and guests move differently and a sales-only view
                        # understates the guest decline.
                        spend = (11.5, 13.0, 14.0, 12.0)[daypart_index] * (1.03 if changed else 1)
                        sales = round(guests * spend, 2)
                        # Exactly one unobserved cell in the whole fixture.
                        # It exists so the withholding path is exercised by
                        # real data: its pair is excluded on both sides and
                        # every total that touches it reports the exclusion.
                        complete = not (restaurant_id == "R109" and business_date == date(2026, 8, 24) and daypart == "Breakfast")
                        append("PERFORMANCE", restaurant_id, business_date.isoformat(), daypart, channel,
                               # NULL, not 0, when unobserved -- the whole
                               # evidence layer depends on that distinction.
                               guests if complete else None, checks if complete else None,
                               sales if complete else None, complete)
    return tables


def validate(tables):
    """Refuse to publish a fixture that violates its own contract.

    Every check raises rather than warns, and validate() runs both before the
    CSVs are written and again inside Snowflake before the load. A generator
    that can emit a subtly broken fixture is worse than no generator: the
    resulting demo would teach a wrong number confidently.
    """
    # One release, explicitly flagged synthetic. Asserted in data, not just in
    # a filename, so the load path can verify it independently.
    release_ids = {row["RELEASE_ID"] for row in tables["RELEASE_METADATA"]}
    if len(release_ids) != 1 or tables["RELEASE_METADATA"][0]["SYNTHETIC"] is not True:
        raise ValueError("Expected one explicitly synthetic release")
    roster = {row["RESTAURANT_ID"]: row for row in tables["ROSTER"]}
    calendar = {row["BUSINESS_DATE"]: row for row in tables["CALENDAR"]}
    for table, rows in tables.items():
        seen = set()
        for row in rows:
            if set(row) != set(FIELDS[table]) or row["RELEASE_ID"] not in release_ids:
                raise ValueError(f"{table}: field or release mismatch")
            # Grain uniqueness. A duplicate here would fan out on every join
            # downstream and inflate totals invisibly.
            key = tuple(row[column] for column in GRAINS[table])
            if key in seen:
                raise ValueError(f"{table}: duplicate grain {key}")
            seen.add(key)
            # Referential integrity, enforced here because CSVs and Snowflake
            # tables have no foreign keys to enforce it for us.
            if "RESTAURANT_ID" in row and row["RESTAURANT_ID"] not in roster:
                raise ValueError(f"{table}: unknown restaurant")
            if "BUSINESS_DATE" in row and row["BUSINESS_DATE"] not in calendar:
                raise ValueError(f"{table}: unknown date")
            if "DAYPART" in row and row["DAYPART"] not in DAYPARTS:
                raise ValueError(f"{table}: invalid daypart")
    dates = sorted(calendar)
    for index, day in enumerate(dates):
        # No gaps. A missing date would look like an unobserved day to every
        # consumer, quietly turning a generator bug into "missing data".
        if date.fromisoformat(day) != START + timedelta(days=index):
            raise ValueError("Calendar gap")
        # And the 364-day pairing must hold for every row, including the NULLs
        # in the first year.
        expected = (date.fromisoformat(day) - timedelta(days=364)).isoformat() if index >= 364 else None
        if calendar[day]["BASELINE_DATE"] != expected:
            raise ValueError("Invalid baseline mapping")
    for row in tables["PERFORMANCE"]:
        if row["CHANNEL"] not in CHANNELS:
            raise ValueError("Invalid channel")
        values = [row[column] for column in ("GUESTS", "CHECKS", "NET_SALES")]
        # COMPLETE must agree with the measures exactly: all present or all
        # absent. A half-populated "complete" row is the state that lets a
        # zero masquerade as an observation.
        if row["COMPLETE"] != all(value is not None for value in values):
            raise ValueError("Completeness mismatch")
        for column in ("GUESTS", "CHECKS"):
            value = row[column]
            # `type(value) is not int` rather than isinstance: bool is a
            # subclass of int, and True would otherwise pass as a count.
            if value is not None and (type(value) is not int or value < 0):
                raise ValueError("Invalid count")
        restaurant = roster[row["RESTAURANT_ID"]]
        active = restaurant["OPEN_DATE"] <= row["BUSINESS_DATE"] and (restaurant["CLOSE_DATE"] is None or row["BUSINESS_DATE"] < restaurant["CLOSE_DATE"])
        # A restaurant cannot trade outside its own lifecycle. Zero or NULL
        # only; anything else would make lifecycle classification a lie.
        if not active and any(value not in (0, None) for value in values):
            raise ValueError("Observations outside lifecycle")
    # The grid must be complete. This is what lets the evidence layer treat a
    # missing row as an error rather than as a silent absence.
    expected_cells = len(roster) * len(calendar) * len(DAYPARTS)
    if len(tables["PERFORMANCE"]) != expected_cells * len(CHANNELS) or len(tables["OPERATIONS"]) != expected_cells:
        raise ValueError("Incomplete expected grid")
    for row in tables["OPERATIONS"]:
        if not 0 <= row["OPEN_HOURS"] <= 24 or row["LABOR_HOURS"] < 0:
            raise ValueError("Invalid operations hours")
        # An average over zero samples is not a number. Storing one would let
        # a closed daypart contribute to a weighted service time.
        if row["SERVICE_OBSERVATIONS"] == 0 and row["SERVICE_MINUTES"] is not None:
            raise ValueError("Service average without observations")


def expected_answers(tables, start="2026-07-20", end="2026-09-14"):
    """Recompute the headline paired totals in plain Python.

    Deliberately independent of the SQL: this is a second implementation of
    the same pairing rules, so agreement between the two is evidence and not
    a tautology. It answers "is the evidence layer arithmetically right?"

    For human verification only. It is written to local output and must never
    be loaded into Snowflake or exposed to the agent -- an agent that can read
    the answer key is not being tested on investigation.
    """
    # Index the cells so each current cell can find its year-ago counterpart
    # in one lookup, using the same 4-part key as the SQL join.
    index = {(row["RESTAURANT_ID"], row["BUSINESS_DATE"], row["DAYPART"], row["CHANNEL"]): row for row in tables["PERFORMANCE"]}
    calendar = {row["BUSINESS_DATE"]: row["BASELINE_DATE"] for row in tables["CALENDAR"]}
    totals = defaultdict(lambda: {"current": 0, "baseline": 0, "excluded_pairs": 0})
    for row in tables["PERFORMANCE"]:
        # Half-open window, matching ANALYSIS_WINDOWS. ISO date strings sort
        # lexicographically, so string comparison is safe here.
        if not start <= row["BUSINESS_DATE"] < end:
            continue
        prior = index.get((row["RESTAURANT_ID"], calendar[row["BUSINESS_DATE"]], row["DAYPART"], row["CHANNEL"]))
        result = totals[row["RESTAURANT_ID"]]
        # Same withholding rule as the SQL: either side missing excludes the
        # pair entirely, and neither half is counted.
        if prior is None or not row["COMPLETE"] or not prior["COMPLETE"]:
            result["excluded_pairs"] += 1
        else:
            result["current"] += row["GUESTS"]
            result["baseline"] += prior["GUESTS"]
    for value in totals.values():
        value["change"] = value["current"] - value["baseline"]
    # Three different totals, reported separately because they answer three
    # different questions and are routinely confused:
    #   net_change       -- the chain's overall movement, gains and losses
    #                       cancelling.
    #   gross_losses     -- how much was lost by the restaurants that lost,
    #                       netted within each restaurant first. Always larger
    #                       than the net decline, and a share of it is not a
    #                       share of the net decline.
    #   offsetting_gains -- what the growing restaurants added, which is the
    #                       difference between the two numbers above.
    return {"start": start, "end_exclusive": end, "restaurants": dict(totals),
            "net_change": sum(row["change"] for row in totals.values()),
            "gross_losses": sum(max(-row["change"], 0) for row in totals.values()),
            "offsetting_gains": sum(max(row["change"], 0) for row in totals.values())}


def write_release(directory, seed=417):
    """Generate, validate and write one release to disk.

    Validation runs before anything is written, so a failed run leaves no
    partial fixture for someone to pick up by mistake.
    """
    tables = observations(seed)
    validate(tables)
    directory.mkdir(parents=True, exist_ok=True)
    inventory = {}
    for table, rows in tables.items():
        path = directory / f"{table}.csv"
        # newline="" and an explicit "\n" terminator keep the bytes identical
        # on every platform, which is what makes the digests below comparable.
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS[table], lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        # Row count and content digest per file: the cheap way to prove two
        # runs produced the same fixture, and to detect a hand edit.
        inventory[path.name] = {"rows": len(rows), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    # The manifest carries the contract itself -- grains and field order --
    # alongside the provenance, so a consumer can check its assumptions
    # without reading this module.
    manifest = {"release": tables["RELEASE_METADATA"][0], "files": inventory, "grains": GRAINS, "fields": FIELDS}
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (directory / "expected_answers.json").write_text(json.dumps(expected_answers(tables), indent=2) + "\n")
    print(json.dumps({"release": manifest["release"], "files": inventory}, indent=2))


if __name__ == "__main__":
    # CLI entry point for local use only. Inside Snowflake the module is
    # imported by tools/native_runtime.py, which calls observations() and
    # validate() directly and writes to tables instead of CSVs -- so nothing
    # below this line runs during a deployment.
    parser = argparse.ArgumentParser(description=__doc__)
    # --output is required rather than defaulted: writing a fixture should be
    # a place the operator chose, not a surprise directory.
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=417)
    arguments = parser.parse_args()
    write_release(arguments.output, arguments.seed)