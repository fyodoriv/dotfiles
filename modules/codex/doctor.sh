#!/bin/bash
# Codex health only. agentbrew owns the agent's config and hook files.
# An explicit AI opt-out does not install or diagnose a never-installed CLI.
# A broken existing link still needs diagnosis, even after the setting changes.
if ! command -v codex >/dev/null 2>&1 \
    && [ ! -e "$HOME/.local/bin/codex" ] && [ ! -L "$HOME/.local/bin/codex" ]; then
  _codex_enabled="$(chezmoi execute-template '{{ .use_ai_tools }}' 2>/dev/null || echo unknown)"
  if { [ "${DOTFILES_PROFILE:-full}" != full ] && [ ! -d "$HOME/.codex" ]; } \
      || [ "$_codex_enabled" = false ]; then
    unset _codex_enabled
    return 0 2>/dev/null || exit 0
  fi
  unset _codex_enabled
fi

_codex_cli_available() {
  local executable
  executable="$(command -v codex)" && [ -f "$executable" ] && [ -x "$executable" ]
}
_codex_cli_works() {
  command -v codex >/dev/null 2>&1 && codex --version >/dev/null 2>&1
}
_codex_login_ok() {
  python3 - <<'PYCODE'
import subprocess
import sys
try:
    result = subprocess.run(["codex", "login", "status"], timeout=2,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sys.exit(result.returncode)
except (OSError, subprocess.TimeoutExpired):
    sys.exit(1)
PYCODE
}
_codex_config_check() {
  python3 - "$HOME/.codex/config.toml" "$1" <<'PY'
import os
import sys
import tomllib

try:
    with open(sys.argv[1], "rb") as config_file:
        config = tomllib.load(config_file)
except (OSError, ValueError):
    sys.exit(1)
if sys.argv[2] == "paths":
    def paths_exist(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "CODEX_CLI_PATH":
                    if not isinstance(item, str):
                        return False
                    executable = os.path.expanduser(item)
                    if not os.path.isfile(executable) or not os.access(executable, os.X_OK):
                        return False
                elif not paths_exist(item):
                    return False
        elif isinstance(value, list):
            return all(paths_exist(item) for item in value)
        return True
    sys.exit(0 if paths_exist(config) else 1)
PY
}

check "codex.installed" "Codex CLI executable found" \
  "_codex_cli_available" "bash '$DOTFILES_DIR/bin/dotfiles-install-codex'"
check "codex.local_bin" "Codex CLI available in ~/.local/bin for GUI apps" \
  "[ -x \"\$HOME/.local/bin/codex\" ]" "bash '$DOTFILES_DIR/bin/dotfiles-install-codex'"
if [ "${DOTFILES_DOCTOR_FULL:-false}" = true ] || [ "${LIST_MODE:-false}" = true ]; then
  check "codex.version" "Codex CLI runs (codex --version)" \
    "_codex_cli_works" "bash '$DOTFILES_DIR/bin/dotfiles-install-codex'"
  check_advisory "codex.login" "Codex CLI signed in (codex login status)" \
    "_codex_login_ok" "codex login"
fi
check "codex.config_valid" "Codex config.toml parses (Python 3.11+ tomllib)" \
  "_codex_config_check parse" ""
check "codex.cli_paths" "CODEX_CLI_PATH entries point to executable files" \
  "_codex_config_check paths" ""
check "codex.hooks_writable" "Codex hooks.json writable, or its parent writable when absent" \
  "if [ -e \"\$HOME/.codex/hooks.json\" ]; then [ -w \"\$HOME/.codex/hooks.json\" ]; else [ -w \"\$HOME/.codex\" ]; fi" ""
check_advisory "codex.app" "ChatGPT.app installed (Codex GUI host)" \
  "[ -d \"\${DOTFILES_CODEX_APP_DIR:-/Applications/ChatGPT.app}\" ] || [ -d \"\$HOME/Applications/ChatGPT.app\" ]" \
  "brew install --cask chatgpt"
