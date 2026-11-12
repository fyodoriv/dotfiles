import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_bounded_output as output


class OutputControls(unittest.TestCase):
    def test_interleaved_streams_are_independently_bounded(self):
        capture = output.BoundedOutput()
        capture.append("stdout", b"a" * 3000)
        capture.append("stderr", b"b" * 4096)
        capture.append("stdout", b"c" * 3000)
        self.assertEqual(len(capture.data("stdout")), 4096)
        self.assertEqual(len(capture.data("stderr")), 4096)
        self.assertTrue(capture.overflowed)
        self.assertFalse(capture.empty)
        capture.append("stderr", b"c" * 10)
        capture.append("stdout", b"")
        self.assertTrue(capture.overflowed)
        receipt = json.dumps(capture.receipt())
        self.assertNotIn("aaaa", receipt)
        self.assertNotIn("bbbb", receipt)

    def test_exact_cap_empty_and_invalid_input(self):
        capture = output.BoundedOutput()
        self.assertTrue(capture.empty)
        capture.append("stdout", b"a" * 4096)
        self.assertFalse(capture.overflowed)
        capture.append("stdout", b"")
        self.assertFalse(capture.overflowed)
        capture.append("stderr", b"b" * 4097)
        self.assertTrue(capture.overflowed)
        before = (capture.data("stdout"), capture.data("stderr"), capture.receipt())
        for stream, value in (("other", b"x"), ("stderr", "x"), ("stdout", None)):
            with self.assertRaises(ValueError): capture.append(stream, value)
            self.assertEqual((capture.data("stdout"), capture.data("stderr"), capture.receipt()), before)

if __name__ == "__main__":
    unittest.main()
