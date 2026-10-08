#!/bin/bash
# Doctor checks for the local-AI stack module. Engine-agnostic: detects
# whichever inference server is in use (LM Studio :1234 preferred for raw
# perf; Ollama :11434 as the universally-allowed fallback).
#
# Auto-discovered by ~/bin/dotfiles-doctor when this file exists. To skip:
# `dotfiles doctor --skip local-ai.<id>`.

# ── Detect which engines are installed (informational; no fail) ─────
_lmstudio_installed() { [ -d "/Applications/LM Studio.app" ] && [ -x "$HOME/.lmstudio/bin/lms" ]; }
_ollama_installed()   { command -v ollama >/dev/null 2>&1; }

_lmstudio_up() { curl -sf -m 2 http://127.0.0.1:1234/v1/models >/dev/null 2>&1; }
_ollama_up()   { curl -sf -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; }

# At least one engine must be installed
check "local-ai.engine_installed" "at least one inference engine installed (LM Studio or Ollama)" \
  "_lmstudio_installed || _ollama_installed" \
  "brew install --cask lm-studio   OR   brew install ollama"

# ── opencode binary ─────────────────────────────────────────────────
check "local-ai.opencode_installed" "opencode binary present" \
  "command -v opencode || [ -x \"\$HOME/.opencode/bin/opencode\" ]" \
  "curl -fsSL https://opencode.ai/install | bash"

# macOS kills a binary whose signature no longer matches its contents
# (launchd: OS_REASON_CODESIGNING), so opencode-serve never answers.
# The fix re-signs it ad hoc, like the other user-dir binaries here.
_opencode_bin() { command -v opencode 2>/dev/null || printf '%s' "$HOME/.opencode/bin/opencode"; }
check "local-ai.opencode_signature_valid" "opencode binary code signature is valid" \
  "[ ! -x \"\$(_opencode_bin)\" ] || ! command -v codesign >/dev/null || codesign --verify \"\$(_opencode_bin)\"" \
  "codesign --force --sign - \"\$(_opencode_bin)\""

# ── LaunchAgents ─────────────────────────────────────────────────────
_launchagent_loaded() { launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1; }

check "local-ai.warmup_agent_loaded" "com.dotfiles.local-ai-warmup LaunchAgent registered" \
  "_launchagent_loaded com.dotfiles.local-ai-warmup" \
  "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.dotfiles.local-ai-warmup.plist"

check "local-ai.opencode_serve_agent_loaded" "com.dotfiles.opencode-serve LaunchAgent registered" \
  "_launchagent_loaded com.dotfiles.opencode-serve" \
  "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.dotfiles.opencode-serve.plist"

# Ollama supervised LaunchAgent — only relevant when Ollama is installed.
# When LM Studio is the chosen engine, this check is skipped (Ollama agent
# is harmless to leave loaded but not required).
if _ollama_installed; then
  check "local-ai.ollama_agent_loaded" "Collision-safe com.dotfiles.ollama LaunchAgent registered" \
    "_launchagent_loaded com.dotfiles.ollama" \
    "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.dotfiles.ollama.plist"
fi

# ── At least one inference engine should be reachable right now ─────
check "local-ai.inference_api_responding" "at least one inference API responding (:1234 LM Studio or :11434 Ollama)" \
  "_lmstudio_up || _ollama_up" \
  "\$HOME/bin/local-ai-warmup (or check ~/.local/share/dotfiles/logs/local-ai-warmup.log)"

# ── opencode-serve daemon ───────────────────────────────────────────
check "local-ai.opencode_serve_api" "opencode-serve responding on :4096" \
  "curl -sf -m 2 http://127.0.0.1:4096/ >/dev/null" \
  "launchctl kickstart -k gui/\$(id -u)/com.dotfiles.opencode-serve"

# ── Models on disk (whichever engine is up) ─────────────────────────
_local_ai_size_bucket() {
  local mem_gb
  mem_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  if   [ "$mem_gb" -le 32 ]; then echo "14b"
  elif [ "$mem_gb" -le 64 ]; then echo "coder-30b"
  else                            echo "32b"
  fi
}

LOCAL_AI_BUCKET="${DOTFILES_LOCAL_AI_SIZE:-$(_local_ai_size_bucket)}"

if _lmstudio_up; then
  EXPECTED_PRIMARY="qwen/qwen3-${LOCAL_AI_BUCKET}"
  EXPECTED_SMALL="qwen/qwen3-0.6b"
  check "local-ai.lmstudio_primary" "LM Studio: primary model ($EXPECTED_PRIMARY) on disk" \
    "\"\$HOME/.lmstudio/bin/lms\" ls 2>/dev/null | grep -q \"$EXPECTED_PRIMARY\"" \
    "lms get qwen3-${LOCAL_AI_BUCKET} --mlx -y"
  check "local-ai.lmstudio_small" "LM Studio: small_model ($EXPECTED_SMALL) on disk" \
    "\"\$HOME/.lmstudio/bin/lms\" ls 2>/dev/null | grep -q \"$EXPECTED_SMALL\"" \
    "lms get qwen3-0.6b --mlx -y"
elif _ollama_up; then
  # The Ollama library names qwen3 and qwen3-coder as separate entries —
  # a naive `qwen3:${bucket}` substitution produces invalid tags like
  # `qwen3:coder-30b`. Map the size bucket to the right entry/tag pair.
  case "$LOCAL_AI_BUCKET" in
    coder-30b) EXPECTED_PRIMARY="qwen3-coder:30b" ;;
    *)         EXPECTED_PRIMARY="qwen3:${LOCAL_AI_BUCKET}" ;;
  esac
  EXPECTED_SMALL="qwen3:0.6b"
  check "local-ai.ollama_primary" "Ollama: primary model ($EXPECTED_PRIMARY) on disk" \
    "ollama list 2>/dev/null | grep -q \"^$EXPECTED_PRIMARY\"" \
    "ollama pull $EXPECTED_PRIMARY"
  check "local-ai.ollama_small" "Ollama: small_model ($EXPECTED_SMALL) on disk" \
    "ollama list 2>/dev/null | grep -q \"^$EXPECTED_SMALL\"" \
    "ollama pull $EXPECTED_SMALL"
fi

# ── Shell wiring ────────────────────────────────────────────────────
check "local-ai.oc_alias" "'oc' alias defined for fast attach to opencode-serve" \
  "grep -q \"alias oc=\" \$HOME/.zshrc.ai-tools 2>/dev/null || grep -q \"alias oc=\" \$HOME/.zshrc.local 2>/dev/null || grep -q \"alias oc=\" \$HOME/.zshrc 2>/dev/null" \
  "Re-apply dotfiles to deploy home/zshrc.ai-tools (and use \`oc\` instead of \`opencode\`)"

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
