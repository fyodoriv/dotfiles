#!/bin/bash
# Fixture doctor module for tests/doctor-notification.bats.
#
# Single check that ALWAYS fails — used to force the notification path
# in dotfiles-doctor and verify the failing-IDs preview is included.
# Lives under tests/fixtures/ so the EXTRA_DOCTOR_DIR hook can pull it
# in for tests without polluting the real module list.

check "notification-fail-module.always_fails" \
  "synthetic failing check for notification-content test" \
  "false" \
  "no manual fix needed — this fixture is for test purposes only"
