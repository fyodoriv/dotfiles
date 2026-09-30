#!/bin/bash
# Doctor checks for devin subsystem

# ── Executables ───────────────────────────────────────────────────────
check "devin.network_watchdog_exec" "network-watchdog is executable" \
  "[ -x '$DOTFILES_DIR/bin/network-watchdog' ]" \
  "chmod +x '$DOTFILES_DIR/bin/network-watchdog'"

# ── Devin binary ─────────────────────────────────────────────────────
check "devin.binary_exists" "devin CLI binary exists" \
  "[ -x \"\$HOME/.local/share/devin/cli/_versions/current/bin/devin\" ]" \
  "echo 'Install Devin CLI: https://cli.devin.ai/docs'"

# ── Stub binary guard ─────────────────────────────────────────────────
# Devin updates occasionally ship a stub shell script instead of a real binary.
# Detect this by checking the ELF/Mach-O magic bytes; if missing, roll back to
# the most recent version that has a real binary.
_devin_binary_is_real() {
  local bin="$HOME/.local/share/devin/cli/_versions/current/bin/devin"
  [ -f "$bin" ] || return 1
  # Real Mach-O binary starts with 0xcffaedfe (little-endian) or 0xcefaedfe
  local magic
  magic=$(xxd -l 4 "$bin" 2>/dev/null | awk '{print $2$3}' | head -1)
  [[ "$magic" == "cffaedfe" || "$magic" == "cefaedfe" ]]
}
_devin_rollback_stub() {
  local versions_dir="$HOME/.local/share/devin/cli/_versions"
  local good_ver=""
  # shellcheck disable=SC2012,SC2045 # need newest-first ordering; ls -t is portable on macOS
  for ver in $(ls -t "$versions_dir" 2>/dev/null); do
    case "$ver" in _*|current) continue;; esac
    local bin="$versions_dir/$ver/bin/devin"
    if [ -f "$bin" ]; then
      local magic
      magic=$(xxd -l 4 "$bin" 2>/dev/null | awk '{print $2$3}' | head -1)
      if [[ "$magic" == "cffaedfe" || "$magic" == "cefaedfe" ]]; then
        good_ver="$ver"
        break
      fi
    fi
  done
  if [ -n "$good_ver" ]; then
    ln -sfn "$versions_dir/$good_ver" "$versions_dir/current"
    echo "✓ Rolled back devin current → $good_ver (stub binary detected in newer release)"
  else
    echo "✗ No working devin binary found — reinstall from https://cli.devin.ai/docs"
    return 1
  fi
}
check "devin.binary_not_stub" "devin current binary is a real executable (not a stub)" \
  "_devin_binary_is_real" \
  "_devin_rollback_stub"



# ── Config file hygiene ──────────────────────────────────────────────
#
# Devin pins to GPT-5.5 XHigh Thinking Fast per the operator's
# cross-agent model policy (see dotfiles AGENTS.md § Model Configuration).
# The live Devin config selector is gpt-5-5-xhigh-priority.
_devin_model_is_default() {
  grep -q '"model"[[:space:]]*:[[:space:]]*"gpt-5-5-xhigh-priority"' "$HOME/.config/devin/config.json" 2>/dev/null
}
_devin_set_default_model() {
  python3 - <<'PY'
import json
from pathlib import Path

path = Path.home() / ".config/devin/config.json"
data = json.loads(path.read_text()) if path.exists() else {}
data.setdefault("agent", {})["model"] = "gpt-5-5-xhigh-priority"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}
check "devin.model_default" "devin config defaults to GPT-5.5 XHigh Thinking Fast" \
  "_devin_model_is_default" \
  "_devin_set_default_model"


