#!/usr/bin/env bats
# Functional tests for modules/cursor/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  CURSOR_LOCAL="$TEST_DIR/cursor-local"
  CURSOR_USER_DIR="$TEST_HOME/Library/Application Support/Cursor/User"
  CURSOR_STATE_DB="$TEST_HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
  CURSOR_APP="$TEST_HOME/Applications/Cursor.app"
  CURSOR_BIN="$TEST_HOME/.local/bin/cursor"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/cursor" "$TEST_DOTFILES/modules/cursor" "$TEST_DOTFILES/.chezmoiscripts" "$TEST_DOTFILES/lib" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/launchagents" "$CURSOR_LOCAL"
  cp "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh" "$TEST_DOTFILES/lib/agentbrew-locate.sh"
  cp "$BATS_TEST_DIRNAME/../lib/agentbrew-memory-readiness.sh" \
    "$TEST_DOTFILES/lib/agentbrew-memory-readiness.sh"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-arch.sh" "$TEST_DOTFILES/lib/dotfiles-arch.sh"
  cp "$BATS_TEST_DIRNAME/../lib/heal-stuck-agents.sh" "$TEST_DOTFILES/lib/heal-stuck-agents.sh"
  cp "$BATS_TEST_DIRNAME/../bin/cursor-at-login" "$TEST_DOTFILES/bin/cursor-at-login"
  cp "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.cursor-at-login.plist.tmpl" \
    "$TEST_DOTFILES/launchagents/com.dotfiles.cursor-at-login.plist.tmpl"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export CURSOR_LOCAL_DIR="$CURSOR_LOCAL"
  export PATH="$(dirname "$CURSOR_BIN"):$PATH"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  cat >> "$OVERRIDES_FILE" <<'EOF'
cursor.terminal_path_dotfiles
cursor.agent_hooks_installed
EOF
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$dst"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$dst"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      ln -s "$src" "$dst"
      fixed "$dst"
    else
      fail "$dst"
    fi
  }

  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"; else pass "$desc"; fi
  }

  security() { return 1; }
  export -f security

  _copy_cursor_doctor
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_cursor-agent-parity.sh" \
     "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-agent-parity.sh"
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_cursor-model-parity.sh" \
     "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-model-parity.sh"
  chmod +x "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-agent-parity.sh" \
            "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-model-parity.sh"

  # The parity script intentionally skips publisher-unapproved Python on a
  # real managed endpoint. Test the parity implementation with an explicit
  # fixture opt-in and a local dotfiles Python shim instead.
  export DOTFILES_ALLOW_PUBLISHER_NA_PYTHON=1
  ln -s "$(command -v python3)" "$TEST_DOTFILES/bin/python3"
}

teardown() {
  rm -rf "$TEST_DIR"
}

_copy_cursor_doctor() {
  sed -e "s|/Applications/Cursor.app|$CURSOR_APP|" \
      -e "s|\$HOME/Library/Application Support/Cursor/User|$CURSOR_USER_DIR|" \
      "$BATS_TEST_DIRNAME/../modules/cursor/doctor.sh" \
      > "$TEST_DOTFILES/modules/cursor/doctor.sh"
}

_setup_cursor_installed() {
  mkdir -p "$CURSOR_APP" "$CURSOR_USER_DIR" "$(dirname "$CURSOR_BIN")"
  printf '#!/usr/bin/env bash\n[ "$1" = "--list-extensions" ] && exit 0\nexit 0\n' > "$CURSOR_BIN"
  chmod +x "$CURSOR_BIN"
  printf '{"editor.fontSize": 15, "mcpServers": {"base": {"command": "base"}}}\n' > "$TEST_DOTFILES/cursor/settings.json"
  printf '[]\n' > "$TEST_DOTFILES/cursor/keybindings.json"
  printf '{"version":"2.0.0","tasks":[]}\n' > "$TEST_DOTFILES/cursor/tasks.json"
  printf '' > "$TEST_DOTFILES/cursor/extensions.txt"
}

_setup_cursor_model_state() {
  mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.cursor" "$(dirname "$CURSOR_STATE_DB")"
  printf '{"model":"claude-opus-4-8","effortLevel":"xhigh"}\n' > "$TEST_HOME/.claude/settings.json"
  cat > "$TEST_HOME/.cursor/cli-config.json" <<'JSON'
{
  "version": 1,
  "model": {
    "modelId": "composer-2-fast",
    "displayModelId": "composer-2-fast",
    "displayName": "Composer 2 Fast",
    "displayNameShort": "Composer 2 Fast",
    "aliases": ["composer"],
    "maxMode": false
  },
  "hasChangedDefaultModel": false,
  "authInfo": {
    "email": "user@example.com"
  }
}
JSON
  python3 - "$CURSOR_STATE_DB" <<'PY'
import json
import sqlite3
import sys

db = sys.argv[1]
key = "src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser"
state = {
    "availableDefaultModels2": [{"serverModelName": "claude-opus-4-8-xhigh"}],
    "aiSettings": {
        "modelConfig": {
            "composer": {"modelName": "default", "maxMode": False, "selectedModels": None},
            "background-composer": {"modelName": "default", "maxMode": True, "selectedModels": None},
            "composer-ensemble": {"modelName": "default", "maxMode": False, "selectedModels": None},
            "plan-execution": {"modelName": "default", "maxMode": False, "selectedModels": None},
            "spec": {"modelName": "default", "maxMode": False, "selectedModels": None},
            "deep-search": {"modelName": "default", "maxMode": False, "selectedModels": None},
            "quick-agent": {"modelName": "default", "maxMode": False, "selectedModels": None},
            "cmd-k": {"modelName": "default", "maxMode": False, "selectedModels": None},
        }
    },
}
conn = sqlite3.connect(db)
subagent_key = "cursor/subagentModelOverrides"
subagent_overrides = {
    "explore": {
        "mode": "model",
        "modelConfig": {
            "modelName": "claude-4.6-sonnet-medium-thinking",
            "maxMode": True,
            "selectedModels": [
                {"modelId": "claude-4.6-sonnet-medium-thinking", "parameters": []}
            ],
        },
    }
}
conn.execute("create table ItemTable (key text primary key, value text)")
conn.execute("insert into ItemTable (key, value) values (?, ?)", (key, json.dumps(state)))
conn.execute(
    "insert into ItemTable (key, value) values (?, ?)",
    (subagent_key, json.dumps(subagent_overrides)),
)
conn.commit()
conn.close()
PY
}

@test "cursor: passes when settings.json exists" {
  _setup_cursor_installed
  FIX_MODE=true
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "cursor: fails when settings.json missing" {
  _setup_cursor_installed
  rm -f "$TEST_DOTFILES/cursor/settings.json"
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "cursor: overrides skip check" {
  _setup_cursor_installed
  echo "cursor.symlink.settings" >> "$OVERRIDES_FILE"
  echo "cursor.symlink.keybindings" >> "$OVERRIDES_FILE"
  echo "cursor.symlink.tasks" >> "$OVERRIDES_FILE"
  echo "cursor.installed" >> "$OVERRIDES_FILE"
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$skip_count" -ge 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "cursor: fails when cursor directory missing entirely" {
  rm -rf "$TEST_DOTFILES/cursor"
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "cursor: passes with empty settings.json file" {
  _setup_cursor_installed
  touch "$TEST_DOTFILES/cursor/settings.json"
  FIX_MODE=true
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "cursor: LIST_MODE suppresses all checks" {
  LIST_MODE=true
  rm -f "$TEST_DOTFILES/cursor/settings.json"
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
  [ "$skip_count" -eq 0 ]
}

@test "cursor: overlay settings merge with base settings" {
  _setup_cursor_installed
  export EXTRA_OVERLAY_ROOT="$TEST_DIR/overlay"
  mkdir -p "$EXTRA_OVERLAY_ROOT/cursor"
  printf '{"mcpServers": {"overlay": {"command": "overlay"}}}\n' > "$EXTRA_OVERLAY_ROOT/cursor/settings.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  [ -f "$CURSOR_LOCAL/settings.generated.json" ]
  grep -q '"base"' "$CURSOR_LOCAL/settings.generated.json"
  grep -q '"overlay"' "$CURSOR_LOCAL/settings.generated.json"
  [ "$(readlink "$CURSOR_USER_DIR/settings.json")" = "$CURSOR_LOCAL/settings.generated.json" ]
}

@test "cursor: base settings materialize generated settings without overlay" {
  mkdir -p "$CURSOR_USER_DIR" "$TEST_DOTFILES/cursor"
  printf '{"editor.fontSize": 15, "mcpServers": {"base": {"command": "base"}}}\n' > "$TEST_DOTFILES/cursor/settings.json"
  printf '[]\n' > "$TEST_DOTFILES/cursor/keybindings.json"
  printf '{"version":"2.0.0","tasks":[]}\n' > "$TEST_DOTFILES/cursor/tasks.json"
  printf '\n' > "$TEST_DOTFILES/cursor/extensions.txt"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  [ -f "$CURSOR_LOCAL/settings.generated.json" ]
  grep -q '"base"' "$CURSOR_LOCAL/settings.generated.json"
  [ "$(readlink "$CURSOR_USER_DIR/settings.json")" = "$CURSOR_LOCAL/settings.generated.json" ]
  [ "$(readlink "$CURSOR_USER_DIR/tasks.json")" = "$TEST_DOTFILES/cursor/tasks.json" ]
}

@test "cursor: native_arch check is declared for Apple Silicon" {
  grep -q 'cursor.native_arch' "$BATS_TEST_DIRNAME/../modules/cursor/doctor.sh"
  grep -q 'dotfiles_app_binary_includes_arm64' "$BATS_TEST_DIRNAME/../modules/cursor/doctor.sh"
}

@test "cursor: memory doctor delegates readiness to the full AgentBrew discovery gate" {
  _setup_cursor_installed
  mkdir -p "$TEST_HOME/.config/agentbrew"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" <<'YAML'
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
YAML
  cat > "$TEST_HOME/.local/bin/agentbrew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/agentbrew-memory.log"
[ "$*" = "memory doctor --ready" ]
EOF
  chmod +x "$TEST_HOME/.local/bin/agentbrew"

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  grep -qx 'memory doctor --ready' "$TEST_HOME/agentbrew-memory.log"
}

@test "cursor: model parity fails when Cursor differs from Claude Code" {
  _setup_cursor_installed
  _setup_cursor_model_state

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  [ "$fail_count" -ge 1 ]
}

@test "cursor: model parity fix pins Cursor CLI and IDE state to Claude Code" {
  _setup_cursor_installed
  _setup_cursor_model_state
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  [ "$fix_count" -ge 1 ]
  python3 - "$TEST_HOME/.cursor/cli-config.json" "$CURSOR_STATE_DB" <<'PY'
import json
import sqlite3
import sys

cli_path, db_path = sys.argv[1:]
target = "claude-opus-4-8-xhigh"
selection = [{"modelId": target, "parameters": []}]
features = (
    "composer",
    "background-composer",
    "composer-ensemble",
    "plan-execution",
    "spec",
    "deep-search",
    "quick-agent",
)

cli = json.load(open(cli_path, encoding="utf-8"))
assert cli["model"]["modelId"] == target
assert cli["model"]["displayModelId"] == target
assert cli["hasChangedDefaultModel"] is True
assert cli["authInfo"]["email"] == "user@example.com"

key = "src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser"
state = json.loads(sqlite3.connect(db_path).execute("select value from ItemTable where key = ?", (key,)).fetchone()[0])
for feature in features:
    model_config = state["aiSettings"]["modelConfig"][feature]
    assert model_config["modelName"] == target
    assert model_config["maxMode"] is False
    assert model_config["selectedModels"] == selection
assert state["aiSettings"]["modelConfig"]["cmd-k"]["modelName"] == "default"
assert state["aiSettings"]["modelDefaultSwitchOnNewChat"] is False

subagent_key = "cursor/subagentModelOverrides"
overrides = json.loads(sqlite3.connect(db_path).execute("select value from ItemTable where key = ?", (subagent_key,)).fetchone()[0])
expected_override = {
    "mode": "model",
    "modelConfig": {
        "modelName": target,
        "maxMode": False,
        "selectedModels": selection,
    },
}
assert overrides["explore"] == expected_override
PY
}

@test "cursor: model parity fix is idempotent on repeat runs" {
  _setup_cursor_installed
  _setup_cursor_model_state
  FIX_MODE=true
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  local first_cli_mtime
  first_cli_mtime=$(stat -f %m "$TEST_HOME/.cursor/cli-config.json")
  sleep 1

  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  local second_cli_mtime
  second_cli_mtime=$(stat -f %m "$TEST_HOME/.cursor/cli-config.json")

  [ "$first_cli_mtime" -eq "$second_cli_mtime" ]
  [ "$fail_count" -eq 0 ]
}

@test "cursor: generated settings preserve live MCP only" {
  _setup_cursor_installed
  mkdir -p "$CURSOR_LOCAL"
  printf '{"editor.fontSize": 99, "workbench.externalBrowser": "${env:HOME}/Applications/ChromeWork.app", "mcpServers": {"live": {"command": "live"}}}\n' \
    > "$CURSOR_LOCAL/settings.generated.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  grep -q '"live"' "$CURSOR_LOCAL/settings.generated.json"
  grep -q '"editor.fontSize": 15' "$CURSOR_LOCAL/settings.generated.json"
  ! grep -q '"editor.fontSize": 99' "$CURSOR_LOCAL/settings.generated.json"
  ! grep -q '"workbench.externalBrowser"' "$CURSOR_LOCAL/settings.generated.json"
}

@test "cursor: external browser leaves system default unconfigured" {
  ! grep -q '"workbench.externalBrowser"' \
    "$BATS_TEST_DIRNAME/../cursor/settings.json"
}

@test "cursor: generated settings parse JSONC comments and trailing commas" {
  _setup_cursor_installed
  cat > "$TEST_DOTFILES/cursor/settings.json" <<'JSONC'
{
  // Cursor settings source is JSONC.
  "editor.fontSize": 15,
  "files.watcherExclude": {
    "**/node_modules/**": true,
  },
}
JSONC
  mkdir -p "$CURSOR_LOCAL"
  printf '{"mcpServers": {"live": {"command": "live"}}}\n' > "$CURSOR_LOCAL/settings.generated.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  grep -q '"editor.fontSize": 15' "$CURSOR_LOCAL/settings.generated.json"
  grep -q '"files.watcherExclude"' "$CURSOR_LOCAL/settings.generated.json"
  grep -q '"live"' "$CURSOR_LOCAL/settings.generated.json"
}

@test "cursor: generated settings exclude logs and lockfiles from search and Cursor global ignore" {
  _setup_cursor_installed
  cp "$BATS_TEST_DIRNAME/../cursor/settings.json" "$TEST_DOTFILES/cursor/settings.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  python3 - "$CURSOR_LOCAL/settings.generated.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))

search_exclude = settings.get("search.exclude", {})
global_ignore = settings.get("cursor.general.globalCursorIgnoreList", [])

assert search_exclude.get("**/*.log") is True
assert search_exclude.get("**/logs/**") is True
assert search_exclude.get("**/yarn.lock") is True
assert search_exclude.get("**/*.tsbuildinfo") is True
assert search_exclude.get("**/*.js.map") is True

for pattern in ("**/.git/**", "**/node_modules/**", "**/dist/**", "**/vendor/**", "**/*.log", "**/logs/**", "**/yarn.lock", "**/*.tsbuildinfo", "**/*.js.map"):
    assert pattern in global_ignore
PY
}

@test "cursor: generated settings match WebStorm visual parity" {
  _setup_cursor_installed
  cp "$BATS_TEST_DIRNAME/../cursor/settings.json" "$TEST_DOTFILES/cursor/settings.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  python3 - "$CURSOR_LOCAL/settings.generated.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))

assert settings["editor.fontFamily"].startswith("'JetBrainsMono Nerd Font'")
assert settings["editor.fontSize"] == 15
assert settings["editor.lineHeight"] == 1.5
assert settings["workbench.colorTheme"] == "IntelliJ IDEA New UI Dark"
assert settings["workbench.iconTheme"] == "material-icon-theme"
assert settings["material-icon-theme.folders.color"] == "#bbbbbb"
assert settings["terminal.integrated.fontFamily"].startswith("'JetBrainsMono Nerd Font'")
assert settings["terminal.integrated.lineHeight"] == 1.4

colors = settings["workbench.colorCustomizations"]
assert colors["focusBorder"] == "#6b9bfa"
assert colors["editor.background"] == "#1e1f22"
assert colors["editor.lineHighlightBackground"] == "#2b2d30"
assert colors["editorLineNumber.foreground"] == "#4e5157"
assert colors["editorLineNumber.activeForeground"] == "#9da0a8"
assert colors["gitDecoration.addedResourceForeground"] == "#c3e887"
assert colors["gitDecoration.deletedResourceForeground"] == "#f77669"
assert colors["gitDecoration.modifiedResourceForeground"] == "#80cbc4"

tokens = settings["editor.tokenColorCustomizations"]
assert tokens["comments"] == "#7a7e85"
assert tokens["keywords"] == "#cf8e6d"
assert tokens["strings"] == "#6aab73"
assert tokens["types"] == "#c77dbb"
assert any("entity.name.type" in rule["scope"] for rule in tokens["textMateRules"])
PY
}

_setup_cursor_agent_settings_state() {
  _setup_cursor_installed
  mkdir -p "$TEST_HOME/.cursor" "$(dirname "$CURSOR_STATE_DB")"
  cp "$BATS_TEST_DIRNAME/../cursor/settings.json" "$TEST_DOTFILES/cursor/settings.json"
  ln -sf "$TEST_DOTFILES/cursor/settings.json" "$CURSOR_USER_DIR/settings.json"
  cat > "$TEST_HOME/.cursor/cli-config.json" <<'JSON'
{
  "version": 1,
  "editor": { "vimMode": false },
  "permissions": { "allow": [], "deny": [] }
}
JSON
  python3 - "$CURSOR_STATE_DB" <<'PY'
import json
import sqlite3
import sys

db = sys.argv[1]
conn = sqlite3.connect(db)
conn.execute("create table ItemTable (key text primary key, value text)")
conn.execute(
    "insert into ItemTable (key, value) values (?, ?)",
    (
        "cursor/glass.editorPreferences",
        json.dumps(
            {
                "lineNumbersVisible": True,
                "wordWrapEnabled": False,
                "keybindings": "default",
            }
        ),
    ),
)
conn.execute(
    "insert into ItemTable (key, value) values (?, ?)",
    (
        "glass.display.settings",
        json.dumps({"uiFontSizePx": 13, "codeFontSizePx": 12}),
    ),
)
conn.commit()
conn.close()
PY
}

@test "cursor: agent settings parity fails when CLI and glass prefs drift from editor" {
  _setup_cursor_agent_settings_state

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  [ "$fail_count" -ge 1 ]
}

@test "cursor: agent settings parity fix mirrors editor vim, fonts, and glass keybindings" {
  _setup_cursor_agent_settings_state
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  [ "$fix_count" -ge 1 ]
  python3 - "$TEST_HOME/.cursor/cli-config.json" "$CURSOR_STATE_DB" <<'PY'
import json
import sqlite3
import sys

cli_path, db_path = sys.argv[1:]
cli = json.load(open(cli_path, encoding="utf-8"))
assert cli["editor"]["vimMode"] is True

conn = sqlite3.connect(db_path)
glass_editor = json.loads(
    conn.execute(
        "select value from ItemTable where key = ?",
        ("cursor/glass.editorPreferences",),
    ).fetchone()[0]
)
glass_display = json.loads(
    conn.execute(
        "select value from ItemTable where key = ?",
        ("glass.display.settings",),
    ).fetchone()[0]
)
conn.close()

assert glass_editor["keybindings"] == "vim"
assert glass_editor["lineNumbersVisible"] is True
assert glass_editor["wordWrapEnabled"] is False
assert glass_display["codeFontSizePx"] == 15
assert glass_display["uiFontSizePx"] == 15
assert "JetBrainsMono Nerd Font" in glass_display["codeFontFamily"]
PY
}

@test "cursor: agent settings parity fix is idempotent on repeat runs" {
  _setup_cursor_agent_settings_state
  FIX_MODE=true
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  local first_cli_mtime
  first_cli_mtime=$(stat -f %m "$TEST_HOME/.cursor/cli-config.json")
  sleep 1

  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  local second_cli_mtime
  second_cli_mtime=$(stat -f %m "$TEST_HOME/.cursor/cli-config.json")

  [ "$first_cli_mtime" -eq "$second_cli_mtime" ]
  [ "$fail_count" -eq 0 ]
}

@test "cursor: model parity wrapper delegates to agent parity script" {
  _setup_cursor_model_state
  FIX_MODE=true
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-model-parity.sh"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-model-parity.sh" --check-model
}

@test "cursor: model parity wrapper resolves dotfiles via CHEZMOI_SOURCE_DIR" {
  _setup_cursor_model_state
  FIX_MODE=true
  CHEZMOI_SOURCE_DIR="$TEST_DOTFILES" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-model-parity.sh"
  CHEZMOI_SOURCE_DIR="$TEST_DOTFILES" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cursor-model-parity.sh" --check-model
}

@test "cursor: generated settings guard Vitest config discovery in large workspaces" {
  _setup_cursor_installed
  cp "$BATS_TEST_DIRNAME/../cursor/settings.json" "$TEST_DOTFILES/cursor/settings.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/cursor/doctor.sh"

  python3 - "$CURSOR_LOCAL/settings.generated.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))
exclude = settings["vitest.configSearchPatternExclude"]
for marker in (
    "docs",
    "worktrees",
    "scrub-tmp",
    "_inventory",
    "caliber-research",
    "internal-doc-repos",
):
    assert marker in exclude, marker
assert settings["vitest.logLevel"] == "info"
assert settings["vitest.disableWorkspaceWarning"] is True
assert settings["vitest.watchOnStartup"] is False
PY
}

@test "cursor: use_cursor=false runs no checks" {
  _setup_cursor_installed
  USE_CURSOR=false
  source "$TEST_DOTFILES/modules/cursor/doctor.sh"
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
  [ "$fix_count" -eq 0 ]
}
