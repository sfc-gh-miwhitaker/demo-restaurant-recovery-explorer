"""Offline publication hygiene scan. Reports locations, never matched values."""

import argparse
import re
from pathlib import Path


PRIVATE_NAMES = {"local", ".snowflake", ".builddemo-state.json", ".DS_Store",
                 "connections.toml", ".env", ".venv", "__pycache__"}
PRIVATE_SUFFIXES = {".pem", ".key", ".p12", ".pfx", ".pyc", ".pyo"}
TEXT_SUFFIXES = {".md", ".py", ".sql", ".sh", ".json", ".yaml", ".yml", ".toml", ".txt"}
# Binaries a human has viewed in full and cleared for publication. Pinned by exact
# relative path so any other binary still requires its own review.
REVIEWED_BINARIES = {"docs/media/cowork-demo.mp4"}
# Names of Snowflake-internal systems and accounts. A synthetic public demo has
# no reason to reference them, and a reference leaks internal vocabulary even
# when the surrounding code is harmless -- the guard this list replaced was a
# safety check that named an internal telemetry account in a public file. This
# module is the single place the words are allowed to appear, so it is exempt
# from its own scan; tests import the pattern rather than restating the terms.
INTERNAL_TERMS = re.compile(r"\b(?:snowhouse|sfsenorthamerica|snowflake_intelligence_internal)\b", re.I)
SELF_EXEMPT = "tools/check_public_source.py"
PATTERNS = {
    "Snowflake-internal system name": INTERNAL_TERMS,
    "personal filesystem path": re.compile(r"/(?:Users|home)/[a-zA-Z0-9_.-]+/|[A-Z]:\\Users\\[a-zA-Z0-9_.-]+\\"),
    "email address": re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "Snowflake account host": re.compile(r"\b[\w.-]+\.snowflakecomputing\.com\b", re.I),
    "private key material": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "GitHub credential": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "credential assignment": re.compile(r'''(?im)^\s*["']?(?:password|client_secret|api_key|access_token)["']?\s*[:=]\s*["'][^"'\n]{8,}["']'''),
}


def scan(root):
    findings = []
    notices = []
    checked = 0
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if ".git" in relative.parts:
            continue
        if path.is_symlink():
            findings.append((str(relative), 0, "symlink requires review"))
            continue
        if path.name in PRIVATE_NAMES or path.suffix in PRIVATE_SUFFIXES or path.name.startswith(".env."):
            findings.append((str(relative), 0, "private or generated artifact"))
        if path.is_dir() or any(part in PRIVATE_NAMES for part in relative.parts[:-1]):
            continue
        if path.suffix not in TEXT_SUFFIXES and path.name not in {".gitignore", ".gitattributes", "LICENSE"}:
            if relative.as_posix() in REVIEWED_BINARIES:
                notices.append((str(relative), 0, "reviewed binary (not text-scanned)"))
            else:
                findings.append((str(relative), 0, "unrecognized file type requires review"))
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            findings.append((str(relative), 0, "unreadable text requires review"))
            continue
        checked += 1
        if relative.as_posix() == SELF_EXEMPT:
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            for label, pattern in PATTERNS.items():
                if pattern.search(line):
                    findings.append((str(relative), line_number, label))
    return checked, findings, notices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    checked, findings, notices = scan(args.root.resolve())
    for path, line, label in notices + findings:
        print(f"{path}:{line}: {label}")
    print(f"Checked {checked} text files; {len(findings)} findings. No network requests made.")
    raise SystemExit(bool(findings))


if __name__ == "__main__":
    main()