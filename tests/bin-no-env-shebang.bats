#!/usr/bin/env bats
# Endpoint agents may block /usr/bin/env, so dotfiles executables must name
# their interpreter directly (AGENTS.md rule 10). The doctor checks the live
# checkout; this test stops a new offender at `make check` time.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no bin/ or git-hooks/ script uses a #!/usr/bin/env shebang" {
  run grep -rl '^#!/usr/bin/env' "$REPO_ROOT/bin" "$REPO_ROOT/git-hooks"
  [ "$status" -eq 1 ] || { echo "env shebang in: $output"; return 1; }
}
