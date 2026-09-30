#!/bin/bash
# Fixture: a check that fails AND whose fix command also fails.
# Used by tests/doctor-json-status.bats to verify the --json + --fix
# combo reports "fail" status (not "fixed") when the fix doesn't work.
check "json-fail-fix-module.fix_command_always_fails" \
  "synthetic check whose fix command always fails" \
  "false" \
  "false"
