import unittest
from mapping import adapt


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.canonical = {"restaurant": "Diner 1", "date": "2026-08-01", "daypart": "Breakfast", "channel": "Dine-in", "guests": 20, "checks": 11, "sales": 250}
        self.columns = {key: key for key in self.canonical}
        self.meanings = {"guests": "guest occasions", "sales": "net USD excluding tax and tips"}

    def test_alternate_schema_parity(self):
        columns = dict(zip(self.canonical, ("store_key", "trading_day", "meal", "fulfillment", "covers", "tickets", "net_amount")))
        source = {columns[key]: value for key, value in self.canonical.items()}
        source["store_key"] = 11
        actual = adapt([source], columns, self.meanings, [{"id": 11, "name": "Diner 1"}])
        self.assertEqual(actual, adapt([self.canonical], self.columns, self.meanings))

    def test_ambiguous_guest_definition_stops(self):
        with self.assertRaisesRegex(ValueError, "definitions"):
            adapt([self.canonical], self.columns, {**self.meanings, "guests": "transactions?"})

    def test_fanout_stops(self):
        with self.assertRaisesRegex(ValueError, "fanout"):
            adapt([], self.columns, self.meanings, [{"id": 11, "name": "A"}, {"id": 11, "name": "B"}])

    def test_drift_stops(self):
        with self.assertRaisesRegex(ValueError, "drift"):
            adapt([{}], self.columns, self.meanings)

    def test_duplicate_stops(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            adapt([self.canonical, self.canonical], self.columns, self.meanings)


if __name__ == "__main__":
    unittest.main()