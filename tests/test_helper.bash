# Shared test helpers for bats tests.
# Loaded via: load test_helper

# The host bash-env.sh re-exports DOTFILES_DIR and PATH in every child bash,
# which would point `bash -c` fixtures at the real checkout.
# Keep the coverage trace hook (bin/dotfiles-coverage sets BASH_ENV to
# lib/coverage-trap.sh); unsetting it would record zero covered lines.
case "${BASH_ENV:-}" in
*/lib/coverage-trap.sh) unset ENV ;;
*) unset BASH_ENV ENV ;;
esac

# Tests never write the real errors or stats logs (lib/errors-log.sh,
# lib/stats.sh); a test that checks a write sets the variable back to 1.
export DOTFILES_ERRORS_LOG=0
export DOTFILES_STATS_LOG=0

# Create isolated temp environment for each test
setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES"

  # Override HOME and DOTFILES_DIR for isolated testing
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Build two physically distinct checkouts for tests that must separate the
# applied chezmoi source from a development checkout or linked worktree.
setup_distinct_dotfiles_checkouts() {
  TEST_DEV_DOTFILES="${1:-$TEST_DOTFILES}"
  TEST_APPLIED_DOTFILES="${2:-$TEST_DIR/applied-dotfiles}"
  mkdir -p "$TEST_DEV_DOTFILES" "$TEST_APPLIED_DOTFILES"
}

# Helper: create a file with content
create_file() {
  local path="$1" content="${2:-}"
  mkdir -p "$(dirname "$path")"
  echo "$content" > "$path"
}

# Helper: assert file is a symlink pointing to expected target
assert_symlink() {
  local path="$1" expected_target="$2"
  [ -L "$path" ] || { echo "Expected $path to be a symlink"; return 1; }
  local actual
  actual="$(readlink "$path")"
  [ "$actual" = "$expected_target" ] || { echo "Expected symlink to $expected_target, got $actual"; return 1; }
}

# Helper: assert file exists and is a regular file
assert_file() {
  local path="$1"
  [ -f "$path" ] || { echo "Expected $path to exist as a regular file"; return 1; }
}

# Helper: assert file does not exist
assert_no_file() {
  local path="$1"
  [ ! -e "$path" ] || { echo "Expected $path to not exist"; return 1; }
}
