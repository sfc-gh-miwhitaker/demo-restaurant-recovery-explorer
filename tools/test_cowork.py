"""Independent invariants and boundary tests for the CoWork fixture."""

import copy
import unittest

from generate_cowork import observations, validate, expected_answers


class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = observations()

    def test_valid_release(self):
        validate(self.tables)

    def test_reproducible(self):
        self.assertEqual(self.tables, observations())

    def test_seed_changes_observations(self):
        self.assertNotEqual(self.tables["PERFORMANCE"][0]["GUESTS"], observations(418)["PERFORMANCE"][0]["GUESTS"])

    def test_bridge(self):
        result = expected_answers(self.tables)
        self.assertEqual(result["offsetting_gains"] - result["gross_losses"], result["net_change"])
        self.assertEqual(result["restaurants"]["R109"]["excluded_pairs"], 3)
        self.assertLess(result["restaurants"]["R110"]["change"], 0)
        self.assertGreater(result["restaurants"]["R111"]["change"], 0)
        self.assertGreater(result["restaurants"]["R103"]["change"], 0)

    def test_missing_not_zero(self):
        missing = [row for row in self.tables["PERFORMANCE"] if not row["COMPLETE"]]
        self.assertEqual(len(missing), 3)
        self.assertTrue(all(row["GUESTS"] is None for row in missing))

    def test_guests_are_not_checks(self):
        row = self.tables["PERFORMANCE"][0]
        self.assertGreater(row["GUESTS"], row["CHECKS"])

    def test_duplicate_rejected(self):
        tables = dict(self.tables)
        tables["PERFORMANCE"] = self.tables["PERFORMANCE"] + [self.tables["PERFORMANCE"][0]]
        with self.assertRaisesRegex(ValueError, "duplicate grain"):
            validate(tables)

    def test_incomplete_marked_complete_rejected(self):
        tables = dict(self.tables)
        rows = list(self.tables["PERFORMANCE"])
        position = next(index for index, row in enumerate(rows) if not row["COMPLETE"])
        rows[position] = {**rows[position], "COMPLETE": True}
        tables["PERFORMANCE"] = rows
        with self.assertRaisesRegex(ValueError, "Completeness mismatch"):
            validate(tables)

    def test_scenario_labels_absent(self):
        for rows in self.tables.values():
            for row in rows:
                self.assertFalse(any("scenario" in field.lower() for field in row))


if __name__ == "__main__":
    unittest.main()