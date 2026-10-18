# Suite-wide setup. Bats loads this once per run, before any test file.

setup_suite() {
  # The host bash-env.sh (exported as BASH_ENV) prepends the live dotfiles
  # bin/ to PATH in every child bash. That shadows the stub commands tests
  # put on PATH (curl, jq, sed), so tests depend on this Mac's state.
  # Keep the coverage trace hook: bin/dotfiles-coverage sets BASH_ENV to
  # lib/coverage-trap.sh, and unsetting it would record zero covered lines.
  case "${BASH_ENV:-}" in
  */lib/coverage-trap.sh) unset ENV ;;
  *) unset BASH_ENV ENV ;;
  esac
}
