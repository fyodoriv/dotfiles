import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

sys.dont_write_bytecode = True
MODULE = Path(__file__).parent / "helpers/hook_status_pairs.py"
spec = importlib.util.spec_from_file_location("hook_status_pairs", MODULE)
pairs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pairs)


def sample(old=100, new=75, case_index=0):
    return [{"order": "old-first" if (i + case_index) % 2 == 0 else "new-first", "old_ns": old, "new_ns": new}
            for i in range(15)]


def acknowledge(_row):
    return True


class PairControls(unittest.TestCase):
    def setUp(self):
        self.data = {name: sample(case_index=i) for i, name in enumerate(pairs.CASES)}
        self.flags = dict.fromkeys(("admission", "source", "tools", "output", "load"), True)

    def test_registered_cases_use_fixed_gate_payloads(self):
        expected = {"plain": "git status", "short": "git status --short",
                    "short_branch": "git status -s -b", "porcelain_v1": "git status --porcelain=v1"}
        for name, command in expected.items():
            self.assertEqual(pairs.payload(name), json.dumps({"tool_input": {"command": command}, "cwd": "/tmp"},
                                                             separators=(",", ":")).encode())
        self.assertEqual(pairs.payload("plain"), b'{"tool_input":{"command":"git status"},"cwd":"/tmp"}')
        for invalid in ("unknown", None, True):
            with self.assertRaises(ValueError): pairs.payload(invalid)

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

    def test_capture_never_runs_when_preflight_fails(self):
        runner = Mock(side_effect=AssertionError("unexpected sample"))
        result = pairs.capture(runner, lambda: False, lambda: True, acknowledge)
        self.assertFalse(result["valid"])
        runner.assert_not_called()

    def test_capture_stops_on_nonzero_or_different_output(self):
        for bad in ((100, 2, b"", b""), (100, 0, b"private output", b"")):
            runner = Mock(side_effect=[(100, 0, b"", b""), bad])
            result = pairs.capture(runner, lambda: True, lambda: True, acknowledge)
            self.assertFalse(result["valid"])
            self.assertEqual(runner.call_count, 2)
            self.assertNotIn("private output", json.dumps(result))

    def test_postflight_change_invalidates_complete_capture(self):
        runner = Mock(return_value=(100, 0, b"", b""))
        result = pairs.capture(runner, lambda: True, lambda: False, acknowledge)
        self.assertEqual(runner.call_count, 120)
        self.assertFalse(result["valid"])

    def test_complete_capture_preserves_order_and_samples(self):
        runner = Mock(return_value=(100, 0, b"", b""))
        result = pairs.capture(runner, lambda: True, lambda: True, acknowledge)
        self.assertTrue(result["valid"])
        self.assertFalse(result["passed"])
        self.assertEqual(runner.call_count, 120)
        self.assertEqual(len(result["attempts"]), 120)
        self.assertEqual(runner.call_args_list[0].args, (pairs.CASES[0], "old"))
        self.assertEqual(runner.call_args_list[30].args, (pairs.CASES[1], "new"))

    def test_partial_pair_and_first_failure_are_retained(self):
        runner = Mock(side_effect=[(100, 0, b"", b""), (80, 2, b"private", b"")])
        post = Mock(return_value=False)
        result = pairs.capture(runner, lambda: True, post, acknowledge)
        self.assertFalse(result["valid"])
        self.assertEqual(len(result["attempts"]), 2)
        self.assertEqual(result["attempts"][0]["elapsed_ns"], 100)
        self.assertEqual(result["failure"], {"phase": "sample", "case": pairs.CASES[0], "index": 0, "side": "new"})
        self.assertFalse(result["postflight_ok"])
        self.assertNotIn("private", json.dumps(result))
        post.assert_called_once()

    def test_callback_exceptions_are_bounded_and_preserve_attempts(self):
        def fail():
            raise RuntimeError("PRIVATE_CANARY")
        for phase in ("preflight", "sample", "postflight"):
            runner = Mock(side_effect=[(100, 0, b"", b""), RuntimeError("PRIVATE_CANARY")]) if phase == "sample" else Mock(return_value=(100, 0, b"", b""))
            result = pairs.capture(runner, fail if phase == "preflight" else lambda: True,
                                   fail if phase == "postflight" else lambda: True, acknowledge)
            self.assertFalse(result["valid"])
            self.assertNotIn("PRIVATE_CANARY", json.dumps(result))
            self.assertEqual(result["failure"]["phase"], phase)
            if phase == "sample":
                self.assertEqual(result["attempts"][0]["elapsed_ns"], 100)

    def test_non_bytes_output_is_invalid(self):
        runner = Mock(return_value=(100, 0, bytearray(), b""))
        self.assertFalse(pairs.capture(runner, lambda: True, lambda: True, acknowledge)["valid"])

    def test_interruption_runs_postflight_and_propagates(self):
        runner = Mock(side_effect=[(100, 0, b"", b""), KeyboardInterrupt()])
        post = Mock(return_value=True)
        saved = []
        def save(row):
            saved.append(row)
            return True
        with self.assertRaises(KeyboardInterrupt):
            pairs.capture(runner, lambda: True, post, save)
        post.assert_called_once()
        self.assertEqual([row["outcome"] for row in saved], ["ok", "interrupted"])
        self.assertEqual(saved[0]["elapsed_ns"], 100)

    def test_persistence_failure_stops_and_does_not_leak(self):
        runner = Mock(return_value=(100, 0, b"", b""))
        sink = Mock(side_effect=RuntimeError("PRIVATE_CANARY"))
        post = Mock(return_value=True)
        result = pairs.capture(runner, lambda: True, post, sink)
        self.assertFalse(result["valid"])
        self.assertEqual(result["failure"]["phase"], "persistence")
        self.assertEqual(runner.call_count, 1)
        self.assertNotIn("PRIVATE_CANARY", json.dumps(result))
        post.assert_called_once()

    def test_no_sink_or_false_acknowledgment_never_qualifies(self):
        runner = Mock(return_value=(100, 0, b"", b""))
        self.assertFalse(pairs.capture(runner, lambda: True, lambda: True)["valid"])
        runner.assert_not_called()
        result = pairs.capture(runner, lambda: True, lambda: True, lambda _row: False)
        self.assertFalse(result["valid"])
        self.assertEqual(result["failure"]["phase"], "persistence")
        self.assertEqual(runner.call_count, 1)

    def test_interruption_with_failing_sink_propagates_after_postflight(self):
        runner = Mock(side_effect=KeyboardInterrupt())
        sink = Mock(side_effect=RuntimeError("PRIVATE_CANARY"))
        post = Mock(return_value=True)
        with self.assertRaises(KeyboardInterrupt):
            pairs.capture(runner, lambda: True, post, sink)
        post.assert_called_once()
        sink.assert_called_once()


if __name__ == "__main__":
    unittest.main()
