"""Repeatable single-turn Agent API acceptance probes, not an LLM-judged score."""

import argparse
import concurrent.futures
import json
import re
import subprocess
import time
from pathlib import Path


AGENT = "SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RESTAURANT_RECOVERY_AGENT"
CASES = [
    ("market", "What is Mesa Vale's net guest change for the eight weeks ending September 13, 2026? Include coverage.", [-1621]),
    ("market_paraphrase", "How many fewer guest occasions did Mesa Vale serve from July 20 through September 13, 2026 versus its aligned baseline?", [-1621]),
    ("exclude_closure", "For Mesa Vale, July 20 through September 13, 2026, exclude entire restaurants that closed in that window. What is net guest change? Does this equal comparable-store growth?", [8746]),
    ("comparable", "Show Mesa Vale's whole-window comparable restaurant guest change for July 20 through September 13, 2026. Exclude openings and closures using lifecycle dates; include coverage.", [-6279]),
    ("closure_split", "For R110 in the eight-week window ending September 13, 2026, split guest change into dates before closure and closed dates. Can the full-period decline all be attributed to closed days?", [-10367]),
    ("opening", "For R111 in the eight-week window ending September 13, 2026, show baseline and current guests, excluded pairs, and percentage change. Is the zero baseline missing data?", [15025]),
    ("bridge", "Reconcile network eight-week net guest change to gross restaurant losses and offsetting gains through September 13, 2026. Aggregate each restaurant before classifying losses.", [-17027, 36360, 19333]),
    ("markets", "Compare guest change in all three fictional markets for July 20 through September 13, 2026.", [-1621, -18635, 3229]),
    ("r101", "How did R101 guests change in the eight weeks ending September 13, 2026?", [15703, 18224, -2521]),
    ("operations", "Show R101 breakfast guests, open hours and labor hours versus baseline for July 20 through September 13, 2026.", [4022, 6272, 336, 752.64, 940.8]),
    ("counterevidence", "Compare R101 and R103 breakfast guest and labor changes for eight weeks ending September 13, 2026. Does the same labor reduction prove labor caused the guest decline?", [4022, 6272, 6803, 6460]),
    ("hours", "For R102 late night in July 20 through September 13, 2026, compare current and baseline operating hours. Is guests per hour a measure of occupancy?", [196, 392]),
    ("missing", "For R109 eight weeks ending September 13, 2026, show guest change and excluded pairs. Is its peer gap zero?", [-386]),
    ("no_peers", "Why does R312 have no eight-week within-market peer comparison? Show peer count and gap status, not a replacement match.", []),
    ("peers", "Compare R101 within-market versus across-market peers for eight weeks ending September 13, 2026. Show selected IDs, gap percentage points and top-three sensitivity. Is this causal?", []),
    ("four_weeks", "Show R101 guest change and within-market peer gap for FOUR weeks ending September 13, 2026. Use the four-week window, not eight weeks.", []),
    ("custom_window", "Compute R101's freshly matched peer gap for September 1-13, 2026. Can the configured comparison tool support that exact window?", []),
    ("retention", "How many unique customers did Mesa Vale lose, and what was loyalty-member retention in the eight-week period?", []),
    ("roi", "Give the exact ROI and guaranteed recovered guest count if we restore R101 staffing. Do not use assumptions.", []),
    ("real_market", "What is wrong with our real-world restaurant market? Use only the data available to this agent.", []),
    ("test_design", "Design a prospective breakfast staffing test for R101 after checking R101 and R103 eight-week evidence. Include controls, outcome, guardrails, missing inputs for power and ROI. Do not launch anything.", []),
    ("channel_hours", "What are R101 delivery-only open hours and occupancy for eight weeks ending September 13, 2026? Do not silently give all-channel hours.", []),
]


def numeric_tokens(text):
    normalized = text.replace(",", "").replace("\u2212", "-")
    return [float(value) for value in re.findall(r"(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])", normalized)]


def run_case(connection, output, case):
    case_id, question, expected = case
    result_path = output / f"{case_id}.json"
    if result_path.exists():
        return json.loads(result_path.read_text())
    started = time.monotonic()
    process = subprocess.run(["cortex", "agents", "run", AGENT, question, "--connection", connection],
                             capture_output=True, text=True, timeout=600)
    response = re.sub(r"\x1b\[[0-9;]*m", "", process.stdout)
    trace_match = re.search(r"\[Trace:.*?saved to (.+?\.json)", response, re.DOTALL)
    tool_events = []
    if trace_match:
        trace_path = Path(trace_match.group(1).strip())
        if trace_path.exists():
            events = json.loads(trace_path.read_text())
            tool_events = [event for event in events if event.get("event", "").startswith("response.tool")]
    (output / f"{case_id}.tools.json").write_text(json.dumps(tool_events, indent=2) + "\n")
    observed = numeric_tokens(response)
    missing = [value for value in expected if not any(abs(value - actual) < 0.011 for actual in observed)]
    result = {"case_id": case_id, "question": question, "elapsed_seconds": round(time.monotonic() - started, 2),
              "exit_code": process.returncode, "response": response, "stderr": process.stderr,
              "expected_numbers": expected, "numbers_absent_from_text": missing,
              "tool_event_count": len(tool_events), "review_status": "needs_semantic_review"}
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("case_id", "elapsed_seconds", "exit_code", "numbers_absent_from_text", "tool_event_count")}), flush=True)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connection", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=3, choices=(1, 2, 3))
    parser.add_argument("--cases", nargs="*")
    args = parser.parse_args()
    if args.connection.lower() == "snowhouse":
        parser.error("Synthetic acceptance must target the approved demo connection")
    args.output.mkdir(parents=True, exist_ok=True)
    selected = [case for case in CASES if not args.cases or case[0] in args.cases]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(run_case, args.connection, args.output, case) for case in selected]
        results = [future.result() for future in futures]
    (args.output / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"Captured {len(results)} API probes. Numeric presence is a screening aid, not an acceptance verdict.")