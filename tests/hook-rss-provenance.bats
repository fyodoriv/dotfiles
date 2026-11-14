#!/usr/bin/env bats

@test "hook memory receipt rejects invalid provenance without running timings" {
  run python3 tests/hook_rss_provenance_test.py -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"test_high_load_stops_before_timed_commands (__main__.ReceiptControls.test_high_load_stops_before_timed_commands) ... ok"* ]]
  [[ "$output" == *"test_unavailable_cpu_count_stops_before_timed_commands (__main__.ReceiptControls.test_unavailable_cpu_count_stops_before_timed_commands) ... ok"* ]]
  [[ "$output" == *"test_post_window_load_preserves_earlier_failure (__main__.ReceiptControls.test_post_window_load_preserves_earlier_failure) ... ok"* ]]
  [[ "$output" == *$'\nOK' ]]
}
