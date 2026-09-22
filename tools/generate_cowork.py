"""Reproducible fictional source observations; no customer data or network access."""

import argparse
import csv
import hashlib
import json
import random
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path


RELEASE = "restaurant-recovery-v3-seed-417"
START = date(2024, 9, 16)
AS_OF = date(2026, 9, 14)
CHANGE = date(2026, 7, 20)
DAYPARTS = ("Breakfast", "Lunch", "Dinner", "Late night")
CHANNELS = ("Dine-in", "Takeaway", "Delivery")
FIELDS = {
    "ROSTER": ["RELEASE_ID", "RESTAURANT_ID", "RESTAURANT_NAME", "MARKET", "FORMAT", "OPEN_DATE", "CLOSE_DATE"],
    "CALENDAR": ["RELEASE_ID", "BUSINESS_DATE", "BASELINE_DATE", "WEEK_START", "COMPLETE"],
    "PERFORMANCE": ["RELEASE_ID", "RESTAURANT_ID", "BUSINESS_DATE", "DAYPART", "CHANNEL", "GUESTS", "CHECKS", "NET_SALES", "COMPLETE"],
    "OPERATIONS": ["RELEASE_ID", "RESTAURANT_ID", "BUSINESS_DATE", "DAYPART", "OPEN_HOURS", "LABOR_HOURS", "SERVICE_MINUTES", "SERVICE_OBSERVATIONS", "COMPLETE"],
    "EVENTS": ["RELEASE_ID", "EVENT_ID", "RESTAURANT_ID", "EFFECTIVE_DATE", "DAYPART", "EVENT_TYPE", "SOURCE"],
    "RELEASE_METADATA": ["RELEASE_ID", "AS_OF_DATE", "CONTRACT_VERSION", "ANALYSIS_VERSION", "SYNTHETIC", "SEED"],
}
GRAINS = {
    "ROSTER": ["RESTAURANT_ID"], "CALENDAR": ["BUSINESS_DATE"],
    "PERFORMANCE": ["RESTAURANT_ID", "BUSINESS_DATE", "DAYPART", "CHANNEL"],
    "OPERATIONS": ["RESTAURANT_ID", "BUSINESS_DATE", "DAYPART"],
    "EVENTS": ["EVENT_ID"], "RELEASE_METADATA": ["RELEASE_ID"],
}


def observations(seed=417):
    rng = random.Random(seed)
    tables = {name: [] for name in FIELDS}
    release = f"restaurant-recovery-v3-seed-{seed}"

    def append(table, *values):
        tables[table].append(dict(zip(FIELDS[table], (release, *values), strict=True)))

    append("RELEASE_METADATA", AS_OF.isoformat(), "3.0", "pre26-v3", True, seed)
    for offset in range((AS_OF - START).days):
        business_date = START + timedelta(days=offset)
        append("CALENDAR", business_date.isoformat(),
               (business_date - timedelta(days=364)).isoformat() if offset >= 364 else None,
               (business_date - timedelta(days=business_date.weekday())).isoformat(), True)
    for market_index, market in enumerate(("Mesa Vale", "Juniper Coast", "Cedar Basin")):
        for restaurant_index in range(12):
            restaurant_id = f"R{market_index + 1}{restaurant_index + 1:02d}"
            open_date = date(2023, 1, 1)
            close_date = None
            if restaurant_id == "R110":
                close_date = date(2026, 8, 17)
            if restaurant_id == "R111":
                open_date = date(2026, 8, 3)
            format_name = "Roadside" if restaurant_id == "R312" else "Family dining"
            append("ROSTER", restaurant_id, f"{market} Diner {restaurant_index + 1:02d}", market,
                   format_name, open_date.isoformat(), close_date.isoformat() if close_date else None)
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
                weekday_factor = (1.0, 0.96, 0.99, 1.04, 1.12, 1.32, 1.22)[business_date.weekday()]
                seasonal = 1 + 0.03 * ((offset % 364) // 28 - 6) / 6
                for daypart_index, daypart in enumerate(DAYPARTS):
                    open_hours = (6.0, 5.0, 6.0, 7.0)[daypart_index] if active else 0.0
                    if restaurant_id == "R102" and changed and daypart == "Late night":
                        open_hours = 3.5
                    labor_hours = open_hours * (2.8, 2.5, 2.2, 1.7)[daypart_index]
                    if restaurant_id in ("R101", "R103") and business_date >= date(2026, 7, 13) and daypart == "Breakfast":
                        labor_hours *= 0.80
                    service_minutes = 12.0 + daypart_index + rng.randrange(0, 5) / 2
                    if restaurant_id == "R101" and changed and daypart == "Breakfast":
                        service_minutes += 4
                    append("OPERATIONS", restaurant_id, business_date.isoformat(), daypart,
                           open_hours, round(labor_hours, 2), service_minutes if active else None,
                           12 if active else 0, True)
                    for channel_index, channel in enumerate(CHANNELS):
                        base = (100, 90, 66, 34)[daypart_index] * (0.72, 0.16, 0.12)[channel_index]
                        base *= (1 + restaurant_index * 0.012) * weekday_factor * seasonal
                        factor = 1.0
                        if changed:
                            factor = (0.98, 0.92, 1.015)[market_index]
                            if restaurant_id == "R101" and daypart == "Breakfast":
                                factor *= 0.65
                            if restaurant_id == "R102" and daypart == "Late night":
                                factor *= 0.50
                            if restaurant_id == "R103":
                                factor = 1.06
                            if restaurant_id == "R104" and channel == "Delivery":
                                factor *= 0.62
                        guests = max(0, round(base * factor + rng.randrange(-2, 3))) if active else 0
                        checks = round(guests / (1.8 if channel == "Dine-in" else 1.3))
                        spend = (11.5, 13.0, 14.0, 12.0)[daypart_index] * (1.03 if changed else 1)
                        sales = round(guests * spend, 2)
                        complete = not (restaurant_id == "R109" and business_date == date(2026, 8, 24) and daypart == "Breakfast")
                        append("PERFORMANCE", restaurant_id, business_date.isoformat(), daypart, channel,
                               guests if complete else None, checks if complete else None,
                               sales if complete else None, complete)
    return tables


def validate(tables):
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
            key = tuple(row[column] for column in GRAINS[table])
            if key in seen:
                raise ValueError(f"{table}: duplicate grain {key}")
            seen.add(key)
            if "RESTAURANT_ID" in row and row["RESTAURANT_ID"] not in roster:
                raise ValueError(f"{table}: unknown restaurant")
            if "BUSINESS_DATE" in row and row["BUSINESS_DATE"] not in calendar:
                raise ValueError(f"{table}: unknown date")
            if "DAYPART" in row and row["DAYPART"] not in DAYPARTS:
                raise ValueError(f"{table}: invalid daypart")
    dates = sorted(calendar)
    for index, day in enumerate(dates):
        if date.fromisoformat(day) != START + timedelta(days=index):
            raise ValueError("Calendar gap")
        expected = (date.fromisoformat(day) - timedelta(days=364)).isoformat() if index >= 364 else None
        if calendar[day]["BASELINE_DATE"] != expected:
            raise ValueError("Invalid baseline mapping")
    for row in tables["PERFORMANCE"]:
        if row["CHANNEL"] not in CHANNELS:
            raise ValueError("Invalid channel")
        values = [row[column] for column in ("GUESTS", "CHECKS", "NET_SALES")]
        if row["COMPLETE"] != all(value is not None for value in values):
            raise ValueError("Completeness mismatch")
        for column in ("GUESTS", "CHECKS"):
            value = row[column]
            if value is not None and (type(value) is not int or value < 0):
                raise ValueError("Invalid count")
        restaurant = roster[row["RESTAURANT_ID"]]
        active = restaurant["OPEN_DATE"] <= row["BUSINESS_DATE"] and (restaurant["CLOSE_DATE"] is None or row["BUSINESS_DATE"] < restaurant["CLOSE_DATE"])
        if not active and any(value not in (0, None) for value in values):
            raise ValueError("Observations outside lifecycle")
    expected_cells = len(roster) * len(calendar) * len(DAYPARTS)
    if len(tables["PERFORMANCE"]) != expected_cells * len(CHANNELS) or len(tables["OPERATIONS"]) != expected_cells:
        raise ValueError("Incomplete expected grid")
    for row in tables["OPERATIONS"]:
        if not 0 <= row["OPEN_HOURS"] <= 24 or row["LABOR_HOURS"] < 0:
            raise ValueError("Invalid operations hours")
        if row["SERVICE_OBSERVATIONS"] == 0 and row["SERVICE_MINUTES"] is not None:
            raise ValueError("Service average without observations")


def expected_answers(tables, start="2026-07-20", end="2026-09-14"):
    index = {(row["RESTAURANT_ID"], row["BUSINESS_DATE"], row["DAYPART"], row["CHANNEL"]): row for row in tables["PERFORMANCE"]}
    calendar = {row["BUSINESS_DATE"]: row["BASELINE_DATE"] for row in tables["CALENDAR"]}
    totals = defaultdict(lambda: {"current": 0, "baseline": 0, "excluded_pairs": 0})
    for row in tables["PERFORMANCE"]:
        if not start <= row["BUSINESS_DATE"] < end:
            continue
        prior = index.get((row["RESTAURANT_ID"], calendar[row["BUSINESS_DATE"]], row["DAYPART"], row["CHANNEL"]))
        result = totals[row["RESTAURANT_ID"]]
        if prior is None or not row["COMPLETE"] or not prior["COMPLETE"]:
            result["excluded_pairs"] += 1
        else:
            result["current"] += row["GUESTS"]
            result["baseline"] += prior["GUESTS"]
    for value in totals.values():
        value["change"] = value["current"] - value["baseline"]
    return {"start": start, "end_exclusive": end, "restaurants": dict(totals),
            "net_change": sum(row["change"] for row in totals.values()),
            "gross_losses": sum(max(-row["change"], 0) for row in totals.values()),
            "offsetting_gains": sum(max(row["change"], 0) for row in totals.values())}


def write_release(directory, seed=417):
    tables = observations(seed)
    validate(tables)
    directory.mkdir(parents=True, exist_ok=True)
    inventory = {}
    for table, rows in tables.items():
        path = directory / f"{table}.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS[table], lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        inventory[path.name] = {"rows": len(rows), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    manifest = {"release": tables["RELEASE_METADATA"][0], "files": inventory, "grains": GRAINS, "fields": FIELDS}
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (directory / "expected_answers.json").write_text(json.dumps(expected_answers(tables), indent=2) + "\n")
    print(json.dumps({"release": manifest["release"], "files": inventory}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=417)
    arguments = parser.parse_args()
    write_release(arguments.output, arguments.seed)