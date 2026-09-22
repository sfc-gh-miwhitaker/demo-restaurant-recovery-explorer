"""Test real server-side conversation continuity under a scoped reader role."""

import argparse
import json
import re
import subprocess
import time
from pathlib import Path


AGENT = "SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RESTAURANT_RECOVERY_AGENT"
ROLE = "SFE_RESTAURANT_RECOVERY_READER"
QUESTIONS = [
    "What is Mesa Vale's net guest change for the eight weeks ending September 13, 2026? Include excluded pairs.",
    "Now exclude entire restaurants that closed during that window. Keep everything else the same. Is this comparable-store growth?",
    "Now exclude openings as well, using whole-window lifecycle dates. Keep that market and period. Include excluded pairs.",
]


def run_thread(connection, output, repeat):
    thread_id = None
    parent_message_id = 0
    for index, question in enumerate(QUESTIONS):
        request = {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}], "stream": False}
        if thread_id is not None:
            request.update(thread_id=thread_id, parent_message_id=parent_message_id)
        body = json.dumps(request).replace("'", "''")
        sql = (
            "USE SECONDARY ROLES NONE; "
            "SELECT CURRENT_ROLE() AS ROLE_NAME, CURRENT_SECONDARY_ROLES() AS SECONDARY_ROLES; "
            f"SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{AGENT}', '{body}', TRUE)) AS RESPONSE"
        )
        started = time.monotonic()
        process = subprocess.run(["snow", "sql", "--connection", connection, "--role", ROLE,
                                  "--warehouse", "SFE_RESTAURANT_RECOVERY_WH", "--query", sql, "--format", "json"],
                                 capture_output=True, text=True, timeout=600)
        if process.returncode:
            raise RuntimeError(process.stderr)
        batches = json.loads(process.stdout)
        identity = batches[-2][0]
        assert identity["ROLE_NAME"] == ROLE
        assert json.loads(identity["SECONDARY_ROLES"])["roles"] == ""
        response = batches[-1][0]["RESPONSE"]
        if isinstance(response, str):
            response = json.loads(response)
        sanitized = {key: value for key, value in response.items() if key != "content"}
        sanitized["content"] = [part for part in response.get("content", []) if part.get("type") != "thinking"]
        answer = "\n".join(part.get("text", "") for part in sanitized["content"] if part.get("type") == "text")
        expected = (-1621, 8746, -6279)[index]
        numbers = [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", answer.replace(",", "").replace("\u2212", "-"))]
        next_thread_id = response.get("metadata", {}).get("thread_id")
        checks = {
            "expected_net_change_in_answer": expected in numbers,
            "same_thread": thread_id is None or thread_id == next_thread_id,
            "completed": response.get("status") == "completed",
            "no_warnings": not response.get("warnings"),
            "fresh_sql": any(part.get("tool_use", {}).get("type") == "system_execute_sql" for part in sanitized["content"]),
        }
        record = {"question": question, "identity": identity, "elapsed_seconds": round(time.monotonic() - started, 2),
                  "request_thread_id": thread_id, "request_parent_message_id": parent_message_id, "checks": checks, "response": sanitized}
        (output / f"thread-{repeat}-turn-{index + 1}.json").write_text(json.dumps(record, indent=2) + "\n")
        print(json.dumps({"repeat": repeat, "turn": index + 1, "elapsed_seconds": record["elapsed_seconds"],
                          "response_keys": list(response), "warnings": response.get("warnings", [])}), flush=True)
        thread_id = response.get("thread_id") or response.get("metadata", {}).get("thread_id") or thread_id
        parent_message_id = response.get("message_id") or response.get("metadata", {}).get("assistant_message_id")
        if not thread_id or not parent_message_id:
            raise ValueError("Inspect saved response for actual thread/message IDs before continuing")
        if not all(checks.values()):
            raise AssertionError(checks)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connection", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.connection.lower() == "snowhouse":
        parser.error("Use the approved demo account, never Snowhouse")
    args.output.mkdir(parents=True, exist_ok=True)
    for repeat in (1, 2):
        run_thread(args.connection, args.output, repeat)