import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
PLAN_DIR = Path(__file__).parents[1] / "docs/plans"
sys.path.insert(0, str(PLAN_DIR))
CHECKERS = {
    "current-bin-boundaries": "RECEIPT",
    "ci-source-inventory": "RECEIPT",
    "workflow-source-inventory": "RECEIPT",
    "tracked-source-candidates": "RECEIPT",
    "source-evidence-join": "OUTPUT",
    "tooling-checkup-callers": "OUTPUT",
    "stale-lifecycle-ranges": "OUTPUT",
    "non-test-source-classification": "OUTPUT",
    "stale-hook-bin-ranges": "OUTPUT",
    "bats-discovery-receipt": "OUTPUT",
}


class ReceiptTypes(unittest.TestCase):
    def check_rejected(self, name, attribute, transform, add_boolean=False):
        spec = importlib.util.spec_from_file_location("checker", PLAN_DIR / (name + ".py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        original = Path(getattr(module, attribute)).read_text()
        expected = json.loads(original)
        if add_boolean:
            expected = {**expected, "synthetic_boolean": True}
            original = json.dumps(expected)
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "receipt.json"
            receipt.write_text(transform(original, expected))
            with patch.object(module, attribute, receipt), patch.object(module, "generate", return_value=expected), \
                    patch.object(sys, "argv", [name, "--check"]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises((ValueError, SystemExit)):
                    module.main()

    def test_boolean_cannot_replace_integer_format(self):
        for name, attribute in CHECKERS.items():
            with self.subTest(checker=name):
                self.check_rejected(name, attribute, lambda _raw, expected: json.dumps({**expected, "format": True}))

    def test_duplicate_json_keys_are_rejected(self):
        for name, attribute in CHECKERS.items():
            with self.subTest(checker=name):
                self.check_rejected(name, attribute, lambda raw, _expected: raw.replace("{", '{"format": 1,', 1))

    def test_integer_cannot_replace_boolean(self):
        for name, attribute in CHECKERS.items():
            with self.subTest(checker=name):
                self.check_rejected(name, attribute,
                                    lambda _raw, expected: json.dumps({**expected, "synthetic_boolean": 1}), True)

    def test_nonfinite_numbers_are_rejected(self):
        for name in CHECKERS:
            with self.subTest(checker=name):
                spec = importlib.util.spec_from_file_location("checker", PLAN_DIR / (name + ".py"))
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                for number in ("NaN", "Infinity", "-Infinity", "1e999"):
                    with self.assertRaises(ValueError):
                        module.strict_json('{"value": ' + number + '}')


if __name__ == "__main__":
    unittest.main()
