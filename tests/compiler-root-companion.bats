#!/usr/bin/env bats

@test "compiler root join preserves synthetic evidence and refuses invalid packets" {
    run python3 -B "$BATS_TEST_DIRNAME/fixtures/compiler-root-companion/control.py"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'synthetic projections: 12/12\ninvalid controls refused: 10/10')" ]
}
