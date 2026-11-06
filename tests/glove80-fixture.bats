#!/usr/bin/env bats

@test "pinned Glove80 factory keymap and license are present" {
  fixture="$BATS_TEST_DIRNAME/fixtures/glove80-factory.keymap"
  [ "$(shasum -a 256 "$fixture" | awk '{print $1}')" = "64a957cf02ba504adb8192e87c09a14fd50d8797df109937e2a1ccb683da7f1b" ]
  grep -q 'Copyright (c) 2022 MoErgo' "$BATS_TEST_DIRNAME/fixtures/glove80-factory.LICENSE"
}
