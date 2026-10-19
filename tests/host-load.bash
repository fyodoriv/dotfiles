# shellcheck shell=bash
# Helper: true when the 1-minute load average is above the CPU count. Timing
# tests skip then: under `bats --jobs` or other heavy work, a wall-clock
# budget measures the host, not the code. DOTFILES_TEST_LOAD1 and
# DOTFILES_TEST_NCPU override the readings in tests.
host_is_saturated() {
  local load1 ncpu
  load1="${DOTFILES_TEST_LOAD1:-$(sysctl -n vm.loadavg 2>/dev/null | awk '{print int($2)}')}"
  ncpu="${DOTFILES_TEST_NCPU:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
  [ "${load1:-0}" -gt "$ncpu" ]
}
