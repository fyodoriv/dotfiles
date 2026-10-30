#!/usr/bin/env bats
# dotfiles-doctor runs each fix in a new process (`bash -c "$cmd"`), so a fix
# that calls a function defined in its module, or in a lib/ file the module
# sources, must `export -f` it. The jetbrains plugin fix and the workflow
# duplicate-agent fix missed this and failed on every Mac.

load test_helper

@test "every fix that calls a module or lib function exports that function" {
  cd "$BATS_TEST_DIRNAME/.."
  local f fn line libs missing=""
  for f in modules/*/doctor.sh; do
    libs="$(grep -oE 'source "\$DOTFILES_DIR/lib/[A-Za-z0-9_.-]+\.sh"' "$f" | sed -E 's|.*/lib/|lib/|; s|"$||')"
    for fn in $(cat "$f" $libs | grep -oE '^[[:space:]]*_?[A-Za-z_][A-Za-z0-9_]*\(\)' | tr -d ' ()' | sort -u); do
      # A fix is the last argument of check: a line holding only one quoted
      # string that starts with the function name.
      line="^[[:space:]]+\"$fn( [^\"]*)?\"[[:space:]]*\$"
      grep -qE "$line" "$f" || continue
      # check_advisory has no fix; its last argument is a test, run in-process.
      grep -B3 -E "$line" "$f" | grep -q '^[[:space:]]*check_advisory' && continue
      grep -qE "export -f .*\b$fn\b" "$f" || missing="$missing $f:$fn"
    done
  done
  [ -z "$missing" ] || { echo "not exported:$missing"; false; }
}

@test "dotfiles-doctor still runs fixes in a new bash process" {
  grep -q 'bash -c "$cmd"' "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  # Lib functions that fixes call read DOTFILES_DIR at run time.
  grep -q "^export DOTFILES_DIR$" "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
}

@test "workflow duplicate-agent fix runs in a new bash process" {
  local tmp; tmp="$(mktemp -d)"
  ( source "$BATS_TEST_DIRNAME/../lib/launchagent-duplicates.sh"
    export -f launchagent_argv launchagent_duplicates launchagent_remove_duplicates
    bash -c "launchagent_remove_duplicates '$tmp' '$tmp'" )
  rm -rf "$tmp"
}
