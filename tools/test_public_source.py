"""Test publication checks and documentation accuracy using fictional examples."""

import re
import tempfile
import unittest
from pathlib import Path

from check_public_source import scan


ROOT = Path(__file__).resolve().parents[1]

# Every file an arriving agent or operator is likely to read first. If one of
# these points at something that does not exist, the first instruction someone
# follows is a dead end -- which is precisely how this repository shipped a
# Quick Start that told people to run a deleted file.
ENTRY_POINT_DOCS = (
    "README.md",
    "AGENTS.md",
    "ELI5.md",
    "SECURITY.md",
    "docs/04-COWORK-CONTRACT.md",
    "docs/05-COWORK-ACCEPTANCE.md",
    "docs/06-DATA-MODEL-DIAGRAMS.md",
    ".claude/skills/restaurant-recovery-explorer/SKILL.md",
    ".claude/skills/restaurant-source-mapping/SKILL.md",
    "skills/restaurant-investigation/SKILL.md",
    "skills/restaurant-test-design/SKILL.md",
)

# Markdown links, minus anything that is not a repository-relative path.
MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
# Backticked paths that name a file in the repository, rather than a SQL object,
# a directory or a shell fragment.
BACKTICKED_PATH = re.compile(r"`((?:sql|tools|docs|skills)/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.(?:sql|py|md))`")

# Files deleted in the native-deploy refactor. Their names survived in the docs
# long after the files themselves were gone.
REMOVED_PATHS = ("bootstrap.sql", "cortex_project", "build_specs")

# Phrasing that advertises the project's own work as untested or unvalidated.
# The honest place for open validation work is a work tracker, not a document
# someone reads while deciding whether to run this. Analytical limits -- guests
# are not checks, gaps are descriptive, do not claim perfect accuracy -- are a
# different thing and stay.
SELF_DEFEATING_PHRASES = (
    "not yet",
    "never been",
    "has not been run",
    "still needs execution testing",
    "not cloud-executed",
    "newly packaged",
    "was canceled",
    "is unverified",
    "remains unverified",
)


class DocumentationAccuracyTests(unittest.TestCase):
    def test_entry_point_docs_exist(self):
        for name in ENTRY_POINT_DOCS:
            self.assertTrue((ROOT / name).is_file(), name)

    def test_markdown_links_resolve(self):
        for name in ENTRY_POINT_DOCS:
            text = (ROOT / name).read_text()
            for target in MARKDOWN_LINK.findall(text):
                if target.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                target = target.split("#")[0]
                if not target:
                    continue
                resolved = (ROOT / name).parent / target
                self.assertTrue(resolved.exists(), f"{name} -> {target}")

    def test_backticked_repository_paths_resolve(self):
        for name in ENTRY_POINT_DOCS:
            text = (ROOT / name).read_text()
            for target in BACKTICKED_PATH.findall(text):
                self.assertTrue((ROOT / target).exists(), f"{name} -> {target}")

    def test_docs_do_not_reference_removed_files(self):
        for name in ENTRY_POINT_DOCS:
            text = (ROOT / name).read_text()
            for removed in REMOVED_PATHS:
                self.assertNotIn(removed, text, f"{name} references removed {removed}")

    def test_quick_start_describes_the_run_all_path(self):
        text = (ROOT / "README.md").read_text()
        self.assertIn("Run All", text)
        self.assertIn("deploy_all.sql", text)
        # The old Quick Start told people to EXECUTE IMMEDIATE FROM a stage that
        # deploy_all.sql is itself responsible for creating.
        self.assertNotIn("branches/main/deploy_all.sql", text)
        self.assertNotIn("branches/main/teardown_all.sql", text)

    def test_docs_do_not_advertise_their_own_work_as_untested(self):
        for name in ENTRY_POINT_DOCS:
            text = (ROOT / name).read_text().lower()
            for phrase in SELF_DEFEATING_PHRASES:
                self.assertNotIn(phrase, text, f"{name} contains '{phrase}'")

    def test_license_is_present_and_referenced(self):
        self.assertTrue((ROOT / "LICENSE").is_file())
        text = (ROOT / "README.md").read_text()
        self.assertIn("Apache", text)
        self.assertNotIn("no license is implied", text)


class PublicSourceTests(unittest.TestCase):
    def test_clean_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("Synthetic restaurant demonstration.\n")
            self.assertEqual(scan(root), (1, [], []))

    def test_reviewed_binary_is_a_notice_not_a_finding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs" / "media").mkdir(parents=True)
            (root / "docs" / "media" / "cowork-demo.mp4").write_bytes(bytes([0, 255]))
            checked, findings, notices = scan(root)
            self.assertEqual(findings, [])
            self.assertEqual(notices[0][2], "reviewed binary (not text-scanned)")

    def test_hidden_private_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".env").write_text("private configuration")
            (root / ".snowflake").mkdir()
            findings = scan(root)[1]
            self.assertTrue(any(item[0] == ".env" for item in findings))
            self.assertTrue(any(item[0] == ".snowflake" for item in findings))

    def test_content_findings_do_not_echo_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = "\n".join(("/" + "Users/fictional/private.sql",
                                  "fictional" + "@example.invalid",
                                  "password" + " = " + repr("fictional-test-value")))
            (root / "notes.md").write_text(contents)
            findings = scan(root)[1]
            self.assertEqual(len(findings), 3)
            self.assertNotIn("fictional", repr(findings))

    def test_unknown_binary_requires_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "attachment.bin").write_bytes(bytes([0, 255]))
            self.assertEqual(scan(root)[1][0][2], "unrecognized file type requires review")

    def test_symlink_requires_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "linked.md").symlink_to("missing-private-file")
            self.assertEqual(scan(root)[1][0][2], "symlink requires review")


if __name__ == "__main__":
    unittest.main()