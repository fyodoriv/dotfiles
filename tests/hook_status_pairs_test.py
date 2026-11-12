import importlib.util
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
MODULE = Path(__file__).parent / "helpers/hook_status_pairs.py"
spec = importlib.util.spec_from_file_location("hook_status_pairs", MODULE)
pairs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pairs)


def sample(old=100, new=75, case_index=0):
    return [{"order": "old-first" if (i + case_index) % 2 == 0 else "new-first", "old_ns": old, "new_ns": new}
            for i in range(15)]


class PairControls(unittest.TestCase):
    def setUp(self):
        self.data = {name: sample(case_index=i) for i, name in enumerate(pairs.CASES)}
        self.flags = dict.fromkeys(("admission", "source", "tools", "output", "load"), True)

    def test_four_complete_balanced_cases_pass(self):
        result = pairs.summarize(self.data, self.flags)
        self.assertTrue(result["valid"])
        self.assertTrue(result["passed"])
        self.assertEqual(set(result["median_ratios"]), set(pairs.CASES))

    def test_short_unbalanced_or_invalid_samples_fail_closed(self):
        for changed in (sample()[:-1], [{**sample()[0], "order": "new-first"}] + sample()[1:], sample(new=0)):
            values = {**self.data, pairs.CASES[0]: changed}
            self.assertFalse(pairs.summarize(values, self.flags)["valid"])
        self.assertFalse(pairs.summarize({**self.data, "extra": sample()}, self.flags)["valid"])

    def test_threshold_and_evidence_flags_are_independent(self):
        self.assertTrue(pairs.summarize({**self.data, pairs.CASES[0]: sample(new=80)}, self.flags)["passed"])
        values = {**self.data, pairs.CASES[0]: sample(new=81)}
        self.assertTrue(pairs.summarize(values, self.flags)["valid"])
        self.assertFalse(pairs.summarize(values, self.flags)["passed"])
        self.assertFalse(pairs.summarize(self.data, {**self.flags, "source": False})["valid"])
        self.assertFalse(pairs.summarize(self.data, {**self.flags, "source": 1})["valid"])
        self.assertFalse(pairs.summarize(self.data, {k: v for k, v in self.flags.items() if k != "load"})["valid"])

    def test_invalid_timing_types_and_rows_fail_closed(self):
        for field in ("old_ns", "new_ns"):
            for value in (True, 1.5, -1, 2**63):
                changed = sample()
                changed[0] = {**changed[0], field: value}
                self.assertFalse(pairs.summarize({**self.data, pairs.CASES[0]: changed}, self.flags)["valid"])
        self.assertFalse(pairs.summarize({**self.data, pairs.CASES[0]: [None] + sample()[1:]}, self.flags)["valid"])

    def test_receipt_does_not_copy_private_fields(self):
        result = pairs.summarize(self.data, {**self.flags, "extra": "PRIVATE_CANARY"})
        self.assertNotIn("PRIVATE_CANARY", json.dumps(result))
        self.assertFalse(result["valid"])


if __name__ == "__main__":
    unittest.main()
