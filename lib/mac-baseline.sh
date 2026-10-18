#!/bin/bash
# mac-baseline.sh — the numbers a person sees before and after the install:
# zsh start median, free disk, and the dotfiles LaunchAgent count.
# Sourced by bin/dotfiles-install (plan) and bin/dotfiles-metrics (--baseline),
# so both print the same lines. Functions only; no state.

# Median wall time of `zsh -i -c exit` in ms over N runs (default 3, so plan
# stays fast). /usr/bin/time has 10 ms resolution; that is enough here.
baseline_zsh_ms() {
  local runs="${1:-3}" i
  command -v zsh >/dev/null 2>&1 || return 1
  for ((i = 0; i < runs; i++)); do
    /usr/bin/time -p zsh -i -c exit 2>&1 >/dev/null </dev/null | awk '/^real/ { print int($2 * 1000) }'
  done | sort -n | awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)]; else exit 1 }'
}

# Free space on the volume that holds $HOME, in GB with one decimal.
baseline_free_gb() {
  df -k "$HOME" 2>/dev/null | awk 'NR == 2 { printf "%.1f\n", $4 / 1048576 }'
}

baseline_launchagents() {
  local n=0 plist
  for plist in "$HOME/Library/LaunchAgents"/*.plist; do [ -e "$plist" ] && n=$((n + 1)); done
  printf '%s\n' "$n"
}

# Disk a profile adds: Homebrew packages with their dependencies, the apps
# (full only), and the uv Python tools. Measured from installed sizes on one
# Mac (2026-10-18); Homebrew's download cache adds about as much again while
# it installs.
baseline_profile_disk() {
  case "$1" in
    full) printf 'about 3 GB (Homebrew packages, apps, and Python tools)' ;;
    *) printf 'about 1.5 GB (Homebrew packages and Python tools)' ;;
  esac
}

# The shared lines. $1 is the indent.
baseline_report() {
  local pad="${1:-}" ms
  if ms="$(baseline_zsh_ms "${DOTFILES_BASELINE_ZSH_RUNS:-3}")" && [ -n "$ms" ]; then
    printf '%szsh start: median %s ms of %s runs (your shell config now)\n' "$pad" "$ms" "${DOTFILES_BASELINE_ZSH_RUNS:-3}"
  else
    printf '%szsh start: not measured (zsh did not start)\n' "$pad"
  fi
  printf '%sFree disk: %s GB\n' "$pad" "$(baseline_free_gb)"
  printf '%sLaunchAgents: %s in ~/Library/LaunchAgents\n' "$pad" "$(baseline_launchagents)"
}
