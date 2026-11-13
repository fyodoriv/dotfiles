#!/bin/bash
# Doctor checks for the local-AI stack module. Ollama (:11434) is the one
# local engine. Apps reserve the models they need in .agents/local-models;
# bin/local-models installs those on demand and removes the rest. A second
# engine (LM Studio) only duplicates models on disk, so the doctor flags it.
#
# Auto-discovered by ~/bin/dotfiles-doctor when this file exists. To skip:
# `dotfiles doctor --skip local-ai.<id>`.

# local_ai_agents=false (chezmoi data): the stack is off on this Mac, so skip
# the module. Its fixes would otherwise download opencode (curl | bash) and load
# the opencode-serve, Ollama and warmup LaunchAgents. Unset means on.
if [ "${LOCAL_AI_AGENTS:-true}" = "false" ] && [ "${LIST_MODE:-false}" != true ]; then
  return 0 2>/dev/null || exit 0
fi

# ── Detect which engines are installed (informational; no fail) ─────
_lmstudio_installed() { [ -d "/Applications/LM Studio.app" ] && [ -x "$HOME/.lmstudio/bin/lms" ]; }
_ollama_installed()   { command -v ollama >/dev/null 2>&1; }

_lmstudio_up() { curl -sf -m 2 http://127.0.0.1:1234/v1/models >/dev/null 2>&1; }
_ollama_up()   { curl -sf -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; }

# Ollama must be installed (local-models ensure installs it and the
# reserved models only when some app reserves one).
check "local-ai.engine_installed" "Ollama installed" \
  "_ollama_installed" \
  "local-models ensure"

# One engine only: LM Studio keeps its own copy of every model.
check_advisory "local-ai.single_engine" "only one local engine (no LM Studio next to Ollama)" \
  "! _lmstudio_installed" \
  "brew uninstall --cask lm-studio && rm -rf ~/.lmstudio"

# ── opencode binary ─────────────────────────────────────────────────
check "local-ai.opencode_installed" "opencode binary present" \
  "command -v opencode || [ -x \"\$HOME/.opencode/bin/opencode\" ]" \
  "curl -fsSL https://opencode.ai/install | bash"

# macOS kills a binary whose signature no longer matches its contents
# (launchd: OS_REASON_CODESIGNING), so opencode-serve never answers.
# The fix re-signs it ad hoc, like the other user-dir binaries here.
# shellcheck source=/dev/null
[ -f "${DOTFILES_DIR:-}/lib/opencode-version.sh" ] && source "$DOTFILES_DIR/lib/opencode-version.sh"
_opencode_bin() {
  if declare -F opencode_resolve_binary >/dev/null; then
    opencode_resolve_binary 2>/dev/null || printf '%s' "$HOME/.opencode/bin/opencode"
  else
    command -v opencode 2>/dev/null || printf '%s' "$HOME/.opencode/bin/opencode"
  fi
}
_local_ai_doctor_opencode_major="$(opencode_major_version "$(_opencode_bin)" 2>/dev/null || true)"
check "local-ai.opencode_signature_valid" "opencode binary code signature is valid" \
  "[ ! -x \"\$(_opencode_bin)\" ] || ! command -v codesign >/dev/null || codesign --verify \"\$(_opencode_bin)\"" \
  "codesign --force --sign - \"\$(_opencode_bin)\""

# ── LaunchAgents ─────────────────────────────────────────────────────
_launchagent_loaded() { launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1; }

check "local-ai.warmup_agent_loaded" "com.dotfiles.local-ai-warmup LaunchAgent registered" \
  "_launchagent_loaded com.dotfiles.local-ai-warmup" \
  "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.dotfiles.local-ai-warmup.plist"

if [ "$_local_ai_doctor_opencode_major" = 2 ]; then
  check "local-ai.opencode_serve_agent_loaded" "OpenCode shared service running" \
    "opencode_managed_service_healthy \"\$(_opencode_bin)\"" \
    "\"\$(_opencode_bin)\" service start >/dev/null 2>&1"
elif [ "$_local_ai_doctor_opencode_major" = 1 ]; then
  check "local-ai.opencode_serve_agent_loaded" "com.dotfiles.opencode-serve LaunchAgent registered" \
    "_launchagent_loaded com.dotfiles.opencode-serve" \
    "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.dotfiles.opencode-serve.plist"
else
  check "local-ai.opencode_serve_agent_loaded" "OpenCode version is supported" "false" ""
fi

# Ollama supervised LaunchAgent — only relevant when Ollama is installed.
# When LM Studio is the chosen engine, this check is skipped (Ollama agent
# is harmless to leave loaded but not required).
if [ "${LIST_MODE:-false}" = true ] || _ollama_installed; then
  check "local-ai.ollama_agent_loaded" "Collision-safe com.dotfiles.ollama LaunchAgent registered" \
    "_launchagent_loaded com.dotfiles.ollama" \
    "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.dotfiles.ollama.plist"
fi

# ── At least one inference engine should be reachable right now ─────
check "local-ai.inference_api_responding" "Ollama API responding on :11434" \
  "_ollama_up" \
  "\$HOME/bin/local-ai-warmup (or check ~/.local/share/dotfiles/logs/local-ai-warmup.log)"

# ── opencode-serve daemon ───────────────────────────────────────────
if [ "$_local_ai_doctor_opencode_major" = 2 ]; then
  check "local-ai.opencode_serve_api" "OpenCode shared service API responds" \
    "opencode_managed_service_healthy \"\$(_opencode_bin)\"" \
    "\"\$(_opencode_bin)\" service start >/dev/null 2>&1"
elif [ "$_local_ai_doctor_opencode_major" = 1 ]; then
  check "local-ai.opencode_serve_api" "opencode-serve responding on :4096" \
    "curl -sf -m 2 http://127.0.0.1:4096/ >/dev/null" \
    "launchctl kickstart -k gui/\$(id -u)/com.dotfiles.opencode-serve"
else
  check "local-ai.opencode_serve_api" "OpenCode version is supported" "false" ""
fi
unset _local_ai_doctor_opencode_major

# ── Models on disk: exactly what apps reserve ──────────────────────
_local_models() {
  if [ -x "${DOTFILES_DIR:-}/bin/local-models" ]; then printf '%s' "$DOTFILES_DIR/bin/local-models"
  else command -v local-models 2>/dev/null || printf 'local-models'; fi
}
if [ "${LIST_MODE:-false}" = true ] || _ollama_up; then
  check "local-ai.reserved_models_present" "every model an app reserves is on disk (local-models check)" \
    "\"\$(_local_models)\" check >/dev/null" \
    "\"\$(_local_models)\" ensure"
  check_advisory "local-ai.no_unreserved_models" "no Ollama model sits on disk unreserved (local-models status)" \
    "! \"\$(_local_models)\" prune 2>/dev/null | grep -q '^would remove'" \
    "\"\$(_local_models)\" prune --yes"
fi

# ── Shell wiring ────────────────────────────────────────────────────
_opencode_oc_available() {
  local resolved file root="${DOTFILES_LINK_DIR:-$DOTFILES_DIR}"
  for file in "$HOME/.zshrc.ai-tools" "$HOME/.zshrc.local" "$HOME/.zshrc"; do
    grep -Eq '^[[:space:]]*alias[[:space:]]+oc=.*opencode[[:space:]]+attach[[:space:]]+http://(127[.]0[.]0[.]1|localhost):4096' "$file" 2>/dev/null && return 1
  done
  resolved="$(command -v oc 2>/dev/null || true)"
  [ "$resolved" = "$root/bin/oc" ] && [ -x "$resolved" ] && return 0
  resolved="$(command -v dotfiles-opencode 2>/dev/null || true)"
  [ "$resolved" = "$root/bin/dotfiles-opencode" ] && [ -x "$resolved" ] || return 1
  for file in "$HOME/.zshrc.ai-tools" "$HOME/.zshrc.local" "$HOME/.zshrc"; do
    grep -Fxq "alias oc='dotfiles-opencode'" "$file" 2>/dev/null && return 0
  done
  return 1
}
check "local-ai.oc_alias" "Managed 'oc' launcher available" \
  "_opencode_oc_available" \
  "Remove a stale oc attach alias from shell overrides, or re-apply dotfiles to deploy the managed launcher"

# ── opencode.json tool-call wiring ──────────────────────────────────
# `~/.config/opencode/` is owned by agentbrew per the dotfiles/agentbrew
# boundary, so this is a verification-only check (no fix-mode that
# rewrites user state). What we guard: every Ollama-backed entry must
# declare `tools: true` so opencode's @ai-sdk/openai-compatible adapter
# actually parses Ollama's tool_calls field. Without the flag the model
# emits XML-style <function=...> tags as plain text and opencode silently
# fails every agent loop. Surfaced after several hours of debugging in
# the 2026-05-11 session.
_opencode_config_has_tools() {
  local cfg="$HOME/.config/opencode/opencode.json"
  [ -f "$cfg" ] || return 0  # skip when opencode isn't configured at all
  # If the file declares an Ollama provider, at least one model under it
  # must have `tools: true`.
  python3 - "$cfg" <<'PY' || return 1
import json, sys
cfg = json.load(open(sys.argv[1]))
ollama = cfg.get("provider", {}).get("ollama")
if not ollama:
    sys.exit(0)  # no ollama provider — nothing to check
models = ollama.get("models", {})
if not any(m.get("tools") is True for m in models.values()):
    sys.exit(1)
PY
}
check "local-ai.opencode_tools_enabled" "opencode.json: at least one Ollama model declares tools: true" \
  "_opencode_config_has_tools" \
  "Add \"tools\": true to the qwen3-coder:30b entry under provider.ollama.models in ~/.config/opencode/opencode.json"

# ── opencode.json MCP format (opencode 1.14+ schema) ─────────────────
# Detects the OLD MCP stdio format that opencode 1.14+ rejects with
# `Expected { type: "local", ... } | { type: "remote", ... }, got
# {"command":"npx","args":[...]}`. agentbrew sync's JsonAdapter.toEntry
# (src/mcp/adapters.ts:100-101 in the agentbrew repo) was writing the old
# format on every sync, silently re-breaking opencode-serve until the user
# manually edited the file — only to have the next `agentbrew sync` undo
# the manual fix.
#
# Cross-repo coordination: this check is detection-only because the
# durable fix is `fix-opencode-adapter-format` in agentbrew (see agentbrew
# TASKS.md). Once that lands, `agentbrew sync` will write the correct
# format and this check will stay green naturally. No --fix command-fix
# here because rewriting `~/.config/opencode/` is owned by agentbrew per
# the dotfiles/agentbrew boundary in the file header above.
#
# The new schema per opencode 1.14+:
#   { "type": "local" | "remote",
#     "command": ["bin", "arg1", ...],  // ARRAY, not string. args is merged in.
#     "environment": { ... } }          // key is "environment", not "env"
_opencode_mcp_format_ok() {
  local cfg="$HOME/.config/opencode/opencode.json"
  [ -f "$cfg" ] || return 0  # skip when opencode isn't configured
  python3 -c "$(cat <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
mcp = cfg.get("mcp", {})
if not mcp:
    sys.exit(0)
errors = []
for name, entry in mcp.items():
    if not isinstance(entry, dict):
        errors.append(f"{name}: not an object")
        continue
    if "type" not in entry:
        errors.append(f"{name}: missing 'type' key (old stdio format)")
        continue
    if entry["type"] not in ("local", "remote"):
        errors.append(f"{name}: type must be 'local' or 'remote', got {entry['type']!r}")
        continue
    if entry["type"] == "local":
        if not isinstance(entry.get("command"), list):
            errors.append(f"{name}: type=local but command is not an array - old stdio format")
        if "args" in entry:
            errors.append(f"{name}: stray 'args' key - args must be merged into command array")
        if "env" in entry:
            errors.append(f"{name}: 'env' key - opencode 1.14+ uses 'environment'")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
)" "$cfg"
}
check "local-ai.opencode_mcp_format" "opencode.json: MCP entries use new schema (type+command-array)" \
  "_opencode_mcp_format_ok" \
  ""  # no --fix: agentbrew owns ~/.config/opencode/, see header comment + agentbrew P0 fix-opencode-adapter-format

# ── Kimi Code plan for OpenCode (bin/kimi-goal) ─────────────────────
# Advisory: the key is a human step (buy the plan, create a Kimi Code key).
check_advisory "local-ai.kimi_key" "Kimi Code key for OpenCode (kimi-goal --check)" \
  "\"\$HOME/bin/kimi-goal\" --check >/dev/null 2>&1 || kimi-goal --check >/dev/null 2>&1" \
  "opencode auth login (pick Kimi Code Plan), or: security add-generic-password -a \"\$USER\" -s kimi-code-api-key -w"
