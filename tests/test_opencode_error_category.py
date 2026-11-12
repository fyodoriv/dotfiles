import subprocess
import sys
import unittest
from pathlib import Path


class OpenCodeDiagnosticTest(unittest.TestCase):
    def test_only_fixed_categories_are_emitted(self):
        classifier = Path(__file__).parent / "fixtures/opencode-error-category.py"
        cases = {
            "HTTP 401 placeholder-secret": "http-auth",
            "HTTP 500 placeholder-secret": "http-server",
            "permission denied placeholder-secret": "permission",
            "ECONNREFUSED placeholder-secret": "connection",
            "unclassified placeholder-secret": "unknown",
        }
        for text, category in cases.items():
            with self.subTest(category=category):
                result = subprocess.run(
                    [sys.executable, str(classifier)], input=text, capture_output=True, text=True, check=True
                )
                self.assertEqual(result.stdout.strip(), category)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
