#!/usr/bin/env bats
# Registered queue-caller-coverage decisions. Command text remains JSON data.

setup() {
  local repo
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HOOK="$repo/agent-hooks/require-heavy-run.sh"
  export DOTFILES_DIR="$repo"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CALLER_DISPATCH_MARKER="$BATS_TEST_TMPDIR/dispatched"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work"
  local tool
  for tool in cargo rustc npm bats make; do
    printf '%s\n' '#!/bin/sh' 'printf "x\n" >> "$CALLER_DISPATCH_MARKER"' 'exit 98' > "$BATS_TEST_TMPDIR/bin/$tool"
    chmod 700 "$BATS_TEST_TMPDIR/bin/$tool"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  unset BASH_ENV ENV
  cd "$BATS_TEST_TMPDIR/work"
}

assert_hook_decision() {
  local case_id="$1" expected="$2" command_text="$3" json
  json="$(jq -cn --arg c "$command_text" '{tool_input:{command:$c}}')"
  run /bin/bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$HOOK"
  if [ "$status" -ne "$expected" ]; then
    printf '%s: expected exit %s; received %s\n' "$case_id" "$expected" "$status"
    return 1
  fi
  if [ -e "$CALLER_DISPATCH_MARKER" ]; then
    printf '%s: unexpected payload dispatch\n' "$case_id"
    return 1
  fi
  if [ "$expected" -eq 2 ]; then
    [ "$output" = 'BLOCKED: a full test suite or build must queue on the Mac-wide lock. Run this as `heavy-run <command>`.' ] || {
      printf '%s: fixed refusal diagnostic mismatch\n' "$case_id"
      return 1
    }
  else
    [ -z "$output" ] || {
      printf '%s: unexpected diagnostic\n' "$case_id"
      return 1
    }
  fi
}

@test "queue caller H01: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H01 2 'cargo build'
}

@test "queue caller H02: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H02 2 'cargo test'
}

@test "queue caller H03: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H03 2 'cargo check'
}

@test "queue caller H04: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H04 2 'cargo clippy'
}

@test "queue caller H05: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H05 2 'cargo bench --no-run'
}

@test "queue caller H06: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H06 2 'cargo run --bin fixture'
}

@test "queue caller H07: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H07 2 'cargo rustc -- --emit=metadata'
}

@test "queue caller H08: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H08 2 'rustc --crate-type lib fixture.rs'
}

@test "queue caller H09: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H09 2 'rustc --test fixture.rs'
}

@test "queue caller H10: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H10 2 'npm run verify'
}

@test "queue caller H11: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H11 2 'time cargo test'
}

@test "queue caller H12: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H12 2 'env CARGO_BUILD_JOBS=1 cargo build'
}

@test "queue caller H13: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H13 2 '/fixture/bin/cargo test'
}

@test "queue caller H14: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H14 2 'cargo +stable check'
}

@test "queue caller H15: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H15 2 'bash -c '"'"'cargo build'"'"''
}

@test "queue caller H16: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H16 2 'cd fixture && npm run verify'
}

@test "queue caller H17: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H17 2 'rustc '"'"'fixture source.rs'"'"''
}

@test "queue caller H18: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H18 2 ''"'"'cargo'"'"' build'
}

@test "queue caller H19: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H19 2 '"/fixture path/bin/cargo" test'
}

@test "queue caller H20: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H20 2 'cargo test one_name'
}

@test "queue caller H21: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H21 2 'cargo check --manifest-path '"'"'fixture path/Cargo.toml'"'"''
}

@test "queue caller H22: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H22 2 'npm -w web run verify'
}

@test "queue caller H23: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H23 2 'command cargo test'
}

@test "queue caller H24: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H24 2 'cargo --offline build'
}

@test "queue caller H25: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H25 2 'HEAVY_RUN_HELD=SYNTHETIC_FOREIGN cargo test'
}

@test "queue caller H26: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision H26 2 'rustc --print link-args fixture.rs'
}

@test "queue caller U01: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision U01 2 'cargo custom-action'
}

@test "queue caller U02: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision U02 2 'cargo "$MODE"'
}

@test "queue caller U03: unwrapped compilation or unresolved Rust refuses" {
  assert_hook_decision U03 2 'rustc @arguments.rsp'
}

@test "queue caller P01: inspection, inert text or queue dispatch" {
  assert_hook_decision P01 0 'cargo --version'
}

@test "queue caller P02: inspection, inert text or queue dispatch" {
  assert_hook_decision P02 0 'cargo -V'
}

@test "queue caller P03: inspection, inert text or queue dispatch" {
  assert_hook_decision P03 0 'cargo --help'
}

@test "queue caller P04: inspection, inert text or queue dispatch" {
  assert_hook_decision P04 0 'cargo help build'
}

@test "queue caller P05: inspection, inert text or queue dispatch" {
  assert_hook_decision P05 0 'cargo metadata --no-deps --format-version 1'
}

@test "queue caller P06: inspection, inert text or queue dispatch" {
  assert_hook_decision P06 0 'cargo locate-project --message-format plain'
}

@test "queue caller P07: inspection, inert text or queue dispatch" {
  assert_hook_decision P07 0 'rustc --version'
}

@test "queue caller P08: inspection, inert text or queue dispatch" {
  assert_hook_decision P08 0 'rustc -V'
}

@test "queue caller P09: inspection, inert text or queue dispatch" {
  assert_hook_decision P09 0 'rustc --print sysroot'
}

@test "queue caller P10: inspection, inert text or queue dispatch" {
  assert_hook_decision P10 0 'rustc --help'
}

@test "queue caller P11: inspection, inert text or queue dispatch" {
  assert_hook_decision P11 0 'cargo build --help'
}

@test "queue caller P12: inspection, inert text or queue dispatch" {
  assert_hook_decision P12 0 'cargo test --help'
}

@test "queue caller P13: inspection, inert text or queue dispatch" {
  assert_hook_decision P13 0 'cargo +stable --version'
}

@test "queue caller P14: inspection, inert text or queue dispatch" {
  assert_hook_decision P14 0 'printf '"'"'%s\n'"'"' '"'"'cargo build; rustc fixture.rs'"'"''
}

@test "queue caller P15: inspection, inert text or queue dispatch" {
  assert_hook_decision P15 0 'echo "npm run verify"'
}

@test "queue caller P16: inspection, inert text or queue dispatch" {
  assert_hook_decision P16 0 'cat <<'"'"'NOTE'"'"'
cargo build
npm run verify
NOTE
'
}

@test "queue caller P17: inspection, inert text or queue dispatch" {
  assert_hook_decision P17 0 'git commit -m '"'"'docs: run cargo test later'"'"''
}

@test "queue caller P18: inspection, inert text or queue dispatch" {
  assert_hook_decision P18 0 'heavy-run cargo build'
}

@test "queue caller P19: inspection, inert text or queue dispatch" {
  assert_hook_decision P19 0 'env JOBS=1 CARGO_BUILD_JOBS=1 heavy-run cargo test'
}

@test "queue caller P20: inspection, inert text or queue dispatch" {
  assert_hook_decision P20 0 '/fixture/bin/heavy-run cargo check'
}

@test "queue caller P21: inspection, inert text or queue dispatch" {
  assert_hook_decision P21 0 'time heavy-run npm run verify'
}

@test "queue caller P22: inspection, inert text or queue dispatch" {
  assert_hook_decision P22 0 'sh -c '"'"'heavy-run cargo test'"'"''
}

@test "queue caller S01: a filename does not filter the full verify script" {
  assert_hook_decision S01 2 "npm run verify tests/fixture.ts"
}

@test "queue caller S02: a variable toolchain cannot authorize inspection" {
  assert_hook_decision S02 2 'cargo +$MODE metadata --no-deps --format-version 1'
}

@test "queue caller D01: a literal availability probe is read-only discovery" {
  assert_hook_decision D01 0 'command -v bats'
}

@test "queue caller D02: a literal availability probe is read-only discovery" {
  assert_hook_decision D02 0 'command -V bats'
}

@test "queue caller D03: a literal availability probe is read-only discovery" {
  assert_hook_decision D03 0 'command -v bats make cargo'
}

@test "queue caller D04: a literal availability probe is read-only discovery" {
  assert_hook_decision D04 0 'command -v bats >/dev/null 2>&1 || echo missing'
}

@test "queue caller D05: a literal availability probe is read-only discovery" {
  assert_hook_decision D05 0 'if command -pv bats >/dev/null; then echo ok; fi'
}

@test "queue caller D06: a literal version probe is read-only discovery" {
  assert_hook_decision D06 0 'bats --version'
}

@test "queue caller D07: a literal version probe is read-only discovery" {
  assert_hook_decision D07 0 'bats -v'
}

@test "queue caller D08: queued suites and one named file keep their allowance" {
  assert_hook_decision D08 0 'command -v bats && heavy-run bats tests/'
}

@test "queue caller D09: queued suites and one named file keep their allowance" {
  assert_hook_decision D09 0 'command -v bats && bats tests/one.bats'
}

@test "queue caller N01: a probe chained to a full suite refuses" {
  assert_hook_decision N01 2 'command -v bats && bats tests/'
}

@test "queue caller N02: a probe chained to a full suite refuses" {
  assert_hook_decision N02 2 'command -v bats; make test-all'
}

@test "queue caller N03: a probe chained to a full suite refuses" {
  assert_hook_decision N03 2 'command -v bats || bats tests/'
}

@test "queue caller N04: a probe chained to a full suite refuses" {
  assert_hook_decision N04 2 'bash -c "command -v bats && bats tests/"'
}

@test "queue caller N05: command without a lookup flag still runs the suite" {
  assert_hook_decision N05 2 'command bats tests/'
}

@test "queue caller N06: command without a lookup flag still runs the suite" {
  assert_hook_decision N06 2 'command -p bats tests/'
}

@test "queue caller N07: an unknown flag cluster is not a lookup" {
  assert_hook_decision N07 2 'command -vx bats tests/'
}

@test "queue caller N08: command substitution in a probe still refuses" {
  assert_hook_decision N08 2 'command -v $(bats tests/)'
}

@test "queue caller N09: command substitution in a probe still refuses" {
  assert_hook_decision N09 2 'command -v "`make test-all`"'
}

@test "queue caller N10: a version flag with a suite path still refuses" {
  assert_hook_decision N10 2 'bats --version tests/'
}

@test "queue caller N11: an option-like name is not a literal probe" {
  assert_hook_decision N11 2 'command -v -- bats tests/'
}

@test "queue caller N12: a probe chained to a globbed suite refuses" {
  assert_hook_decision N12 2 'command -v bats && command bats tests/*.bats'
}

@test "queue caller N13: a probe inside command substitution refuses" {
  assert_hook_decision N13 2 '$(command -v bats) tests/'
}

@test "queue caller N14: a probe inside quoted command substitution refuses" {
  assert_hook_decision N14 2 '"$(command -v bats)" tests/'
}

@test "queue caller N15: a probe inside backticks refuses" {
  assert_hook_decision N15 2 '`command -v bats` tests/'
}

@test "queue caller N16: a probe stored in a variable then run refuses" {
  assert_hook_decision N16 2 'b=$(command -v bats); $b tests/'
}

@test "queue caller N17: a probe inside eval text refuses" {
  assert_hook_decision N17 2 'eval "$(command -v bats) tests/"'
}

@test "queue caller N18: a probe piped into another command refuses" {
  assert_hook_decision N18 2 'command -v cargo | xargs -I{} {} build'
}

@test "queue caller N19: a probe piped with stderr into another command refuses" {
  assert_hook_decision N19 2 'command -v cargo |& xargs -I{} {} build'
}

@test "queue caller N20: a probe feeding process substitution refuses" {
  assert_hook_decision N20 2 'xargs -I{} {} build < <(command -v cargo)'
}
