#!/bin/bash
# Install the dotfiles-managed devin wrapper. The wrapper keeps the cwd visible
# in the terminal title and repairs broken Devin current-version symlinks. It
# intentionally does not use caffeinate, so macOS updates can restart normally.
# Runs after every chezmoi apply. Idempotent.
set -euo pipefail

WRAPPER="$HOME/.local/bin/devin"
REAL_DEVIN="$HOME/.local/share/devin/cli/_versions/current/bin/devin"

# Skip if devin isn't installed
if [ ! -f "$REAL_DEVIN" ]; then
  exit 0
fi

# Guard: if the current binary is a stub shell script instead of a real Mach-O
# binary (can happen with broken Devin update releases), roll back to the most
# recent version that has a real binary before installing the wrapper.
_devin_magic=$(xxd -l 4 "$REAL_DEVIN" 2>/dev/null | awk '{print $2$3}' | head -1)
if [[ "$_devin_magic" != "cffaedfe" && "$_devin_magic" != "cefaedfe" ]]; then
  echo "⚠ Devin current binary is a stub — rolling back to last real version…"
  _versions_dir="$HOME/.local/share/devin/cli/_versions"
  _rolled_back=""
  # shellcheck disable=SC2012,SC2045 # need newest-first ordering; ls -t is portable on macOS
  for _ver in $(ls -t "$_versions_dir" 2>/dev/null); do
    case "$_ver" in _*|current) continue;; esac
    _bin="$_versions_dir/$_ver/bin/devin"
    if [ -f "$_bin" ]; then
      _magic=$(xxd -l 4 "$_bin" 2>/dev/null | awk '{print $2$3}' | head -1)
      if [[ "$_magic" == "cffaedfe" || "$_magic" == "cefaedfe" ]]; then
        ln -sfn "$_versions_dir/$_ver" "$_versions_dir/current"
        echo "✓ Rolled back devin current → $_ver"
        _rolled_back="$_ver"
        break
      fi
    fi
  done
  if [ -z "$_rolled_back" ]; then
    echo "✗ No working devin binary found — skipping wrapper install"
    exit 0
  fi
fi

# Skip if wrapper is already correct (not a symlink, carries the
# title-watchdog block, delegates directly to Devin, and does not export stale
# model overrides or hold macOS sleep-prevention assertions).
if [ -f "$WRAPPER" ] && [ ! -L "$WRAPPER" ] \
  && grep -q "title-watchdog-from-cwd" "$WRAPPER" 2>/dev/null \
  && grep -q 'exec "$REAL_DEVIN" "$@"' "$WRAPPER" 2>/dev/null \
  && ! grep -q "caffeinate" "$WRAPPER" 2>/dev/null \
  && ! grep -q "ANTHROPIC_MODEL" "$WRAPPER" 2>/dev/null; then
  exit 0
fi

# Remove symlink or stale file
mkdir -p "$(dirname "$WRAPPER")"
rm -f "$WRAPPER"

cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
# devin wrapper — keeps the cwd visible in the Ghostty tab title without
# blocking macOS update restarts.
#
# Title watchdog (tag: title-watchdog-from-cwd): Devin sets the terminal
# title to its current task (e.g. "devin: Update Documentation and Tests"),
# which hides which folder the operator is in. The watchdog re-emits an OSC
# 2 sequence with "[<folder-basename>] devin" once per second to override
# Devin's title. Tradeoff: Devin's task name briefly appears between
# watchdog ticks (<1s flash). Source: 2026-05-27 operator directive — "shows
# on top which folder is devin or claude code is executing", chose
# "Replace fully" over "Watchdog 1s" (the watchdog IS how Replace Fully is
# implemented — Devin offers no --name flag so this is the only path
# without a PTY filter).
#
# Managed by dotfiles — do not edit directly.
REAL_DEVIN="$HOME/.local/share/devin/cli/_versions/current/bin/devin"

# Single-turn mode bypasses the title watchdog.
for _arg in "$@"; do
  case "$_arg" in
    -p|--print) exec "$REAL_DEVIN" "$@" ;;
    --) break ;;
  esac
done

# Compute the cwd-derived title prefix used by the watchdog below.
_folder="${PWD/#$HOME/~}"
_basename="${_folder##*/}"
_title="[$_basename] devin"

# Set the title once so it's correct from the first frame, before Devin
# starts emitting its own OSC 2 sequences.
printf '\e]2;%s\a' "$_title" 2>/dev/null || true

# Background watchdog: re-emit the title once per second. Stops automatically
# when this parent shell exits (its stdout pipe closes).
(
  while sleep 1; do
    printf '\e]2;%s\a' "$_title" >/dev/tty 2>/dev/null || break
  done
) &
_watchdog_pid=$!

# Reap the watchdog on every exit path and reset the title to the bare
# folder name so a subsequent prompt isn't stuck saying "devin".
_cleanup() {
  kill "$_watchdog_pid" 2>/dev/null || true
  printf '\e]2;[%s]\a' "$_basename" 2>/dev/null || true
}
trap _cleanup EXIT INT TERM HUP

exec "$REAL_DEVIN" "$@"
WRAPPER_EOF

chmod +x "$WRAPPER"
echo "✓ Devin wrapper installed"
