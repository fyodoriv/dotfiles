#!/bin/bash
# Doctor module shipped by the fixture plugin. Verifies a sentinel exists
# so the test can assert the doctor pipeline ran the plugin's contribution.

check "test-plugin.installed" "fixture plugin doctor module loaded" \
  "true" \
  ""
