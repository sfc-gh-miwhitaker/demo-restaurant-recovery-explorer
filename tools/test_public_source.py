"""Test publication checks using disposable, entirely fictional examples."""

import tempfile
import unittest
from pathlib import Path

from check_public_source import scan


class PublicSourceTests(unittest.TestCase):
    def test_clean_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("Synthetic restaurant demonstration.\n")
            self.assertEqual(scan(root), (1, []))

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