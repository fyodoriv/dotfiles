#!/usr/bin/env python3
"""Exercise only the pure decoder; no executable is launched."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / "helpers"))
from hook_shebang import MAX_HEADER_BYTES, decode_header


class HeaderTests(unittest.TestCase):
    def test_supported_and_boundary(self):
        self.assertEqual(decode_header(b"#!/bin/bash\n"), ("script", "/bin/bash", None))
        self.assertEqual(decode_header(b"#!/bin/bash -e\n"), ("script", "/bin/bash", "-e"))
        self.assertEqual(decode_header(b"#!/" + b"a" * (MAX_HEADER_BYTES - 4) + b"\n")[0], "script")
        self.assertEqual(decode_header(b"ELF"), ("not_script", None, None))

    def test_invalid_inputs_fail_closed(self):
        invalid = [b"#!bin/bash\n", b"#!/usr/bin/env python3\n", b"#!/bin/bash",
                   b"#!/bin/bash  -e\n", b"#!/bin/bash -e -x\n", b"#!/bin/bash\t-e\n",
                   b"#!/bin/../bash\n", b"#!/bin/bash\0\n", b"#!/bin/bash\r\n",
                   b"#!/" + b"a" * (MAX_HEADER_BYTES - 3) + b"\n"]
        for data in invalid:
            with self.subTest(data=data):
                self.assertEqual(decode_header(data), ("unsupported", None, None))

    def test_tracked_wrapper_header_only(self):
        path = Path(__file__).resolve().parents[1] / "bin/git"
        with path.open("rb") as wrapper:
            header = wrapper.read(MAX_HEADER_BYTES)
        self.assertEqual(decode_header(header), ("script", "/bin/bash", None))


if __name__ == "__main__":
    unittest.main()
