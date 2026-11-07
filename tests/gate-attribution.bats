#!/usr/bin/env bats

@test "valid_success" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_success
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "valid_failure" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_failure
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "valid_overlap_a" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_overlap_a
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "valid_overlap_b" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_overlap_b
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "valid_reordered" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_reordered
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "valid_nested" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_nested
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_missing" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_missing
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_truncated" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_truncated
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_duplicate_completion" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_duplicate_completion
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_duplicate_invocation" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_duplicate_invocation
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_missing_step" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_missing_step
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_status" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_status
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_replay" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_replay
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}

@test "unknown_malformed" {
  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" unknown_malformed
  if [ "$status" -ne 0 ]; then
    if [ "$output" = 'synthetic join rejected: unimplemented' ]; then
      echo 'synthetic join rejected: unimplemented' >&3
    else
      echo 'synthetic control rejected' >&3
    fi
    return 1
  fi
  [ "$output" = 'synthetic control passed' ] || { echo 'synthetic control rejected' >&3; return 1; }
}
