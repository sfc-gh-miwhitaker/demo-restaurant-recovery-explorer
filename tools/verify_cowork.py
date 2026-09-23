"""Read-only SQL parity and verified-query checks in an explicitly named demo account."""

import argparse
import json
import re
import subprocess
from pathlib import Path

from generate_cowork import observations, expected_answers


def query(connection, sql):
    result = subprocess.run(["snow", "sql", "--connection", connection, "--warehouse",
                             "SFE_RESTAURANT_RECOVERY_WH", "--query", sql, "--format", "json"],
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def verify(connection):
    prefix = "SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY"
    tables = observations()
    for window, start in (("8 weeks", "2026-07-20"), ("4 weeks", "2026-08-17")):
        expected = expected_answers(tables, start)["restaurants"]
        rows = query(connection, f"SELECT RESTAURANT_ID, CURRENT_GUESTS, BASELINE_GUESTS, GUEST_CHANGE, EXCLUDED_PAIRS FROM {prefix}.WINDOW_OUTCOMES WHERE WINDOW_NAME='{window}' ORDER BY RESTAURANT_ID")
        assert len(rows) == len(expected), "Restaurant coverage differs"
        for row in rows:
            actual = {"current": row["CURRENT_GUESTS"], "baseline": row["BASELINE_GUESTS"],
                      "change": row["GUEST_CHANGE"], "excluded_pairs": row["EXCLUDED_PAIRS"]}
            assert actual == expected[row["RESTAURANT_ID"]], (window, row)
    invalid = query(connection, f"SELECT COUNT(*) AS FAILURES FROM {prefix}.COMPARISON_EVIDENCE WHERE (GAP_STATUS <> 'Available' AND GAP_PP IS NOT NULL) OR (GAP_STATUS='Available' AND (PEER_COUNT < 3 OR GAP_PP IS NULL))")
    assert invalid[0]["FAILURES"] == 0, invalid
    root = Path(__file__).resolve().parents[1]
    results = []
    definitions = (root / "sql/04_semantics.sql").read_text()
    for content in re.findall(r"\$\$\n(.*?)\n\$\$", definitions, re.DOTALL):
        spec = json.loads(content)
        for verified in spec.get("verified_queries", []):
            rows = query(connection, verified["sql"])
            assert rows, verified["question"]
            results.append({"question": verified["question"], "rows": len(rows), "sample": rows[:2]})
    assert len(results) == 8, "Expected eight verified queries"
    print(json.dumps({"parity_restaurant_windows": 72, "gap_guard": "passed", "verified_queries": results}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connection", required=True)
    args = parser.parse_args()
    verify(args.connection)