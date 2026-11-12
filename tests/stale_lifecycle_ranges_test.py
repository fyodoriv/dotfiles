import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
plan_dir = Path(__file__).parents[1] / "docs/plans"
sys.path.insert(0, str(plan_dir))
spec = importlib.util.spec_from_file_location("ranges", plan_dir / "stale-lifecycle-ranges.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StrictReceipt(unittest.TestCase):
    def test_boolean_is_not_a_line_number(self):
        self.assertTrue(module.same_json({"line": 1}, {"line": 1}))
        self.assertFalse(module.same_json({"line": 1}, {"line": True}))

    def test_duplicate_keys_are_rejected(self):
        self.assertEqual(module.strict_json('{"a": 1}'), {"a": 1})
        with self.assertRaises(ValueError):
            module.strict_json('{"a": 1, "a": 2}')


if __name__ == "__main__":
    unittest.main()
