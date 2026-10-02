#!/bin/bash
set -euo pipefail

# use_cursor=false (chezmoi data, or DOTFILES_USE_CURSOR=false) means no Cursor.
if [ "${DOTFILES_USE_CURSOR:-$(chezmoi execute-template '{{ dig "use_cursor" true . }}' 2>/dev/null || echo true)}" = "false" ]; then
  echo "○ Cursor disabled (use_cursor=false) — skipping $(basename "$0")"
  exit 0
fi

MODE="${1:---fix}"

# uv/python-build-standalone carries only an ad-hoc signature. Current endpoint
# policy reports that as unsigned on every spawn, so apply/doctor must not
# execute it automatically. Keep the implementation available after a
# machine-scoped publisher exception by setting the explicit opt-in.
_python_candidate="$(command -v python3 2>/dev/null || true)"
_python_signature="publisher-check-unavailable"
if [ -n "$_python_candidate" ] && [ -x "$_python_candidate" ] \
    && command -v codesign >/dev/null 2>&1; then
  _python_signature="$(codesign -dvv "$_python_candidate" 2>&1 || true)"
fi
if command -v codesign >/dev/null 2>&1 \
    && ! grep -q '^Authority=' <<<"$_python_signature" \
    && [ "${DOTFILES_ALLOW_PUBLISHER_NA_PYTHON:-0}" != "1" ]; then
  echo "○ Cursor agent parity skipped: python3 has no publisher authority (endpoint-policy safe mode)"
  exit 0
fi
unset _python_candidate _python_signature

_resolve_dotfiles_bin_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null || true)"
  if [ -x "$script_dir/bin/python3" ]; then
    printf '%s/bin\n' "$script_dir"
    return 0
  fi
  # chezmoi runs this from a temp copy; its source dir is the applied checkout.
  for candidate in \
    "${CHEZMOI_SOURCE_DIR:-}" \
    "${DOTFILES_DIR:-}" \
    "$HOME/apps/tooling/dotfiles" \
    "$HOME/apps/dotfiles" \
    "$HOME/dotfiles"; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate/bin/python3" ]; then
      printf '%s/bin\n' "$candidate"
      return 0
    fi
  done
  return 1
}

_dotfiles_bin="$(_resolve_dotfiles_bin_dir || true)"
if [ -z "$_dotfiles_bin" ]; then
  echo "⚠ dotfiles python3 shim not found — skipping cursor-agent-parity" >&2
  exit 0
fi
"$_dotfiles_bin/python3" - "$MODE" <<'PY'
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

mode = sys.argv[1]
home = Path(os.environ["HOME"])
claude_settings = home / ".claude/settings.json"
cursor_settings = home / "Library/Application Support/Cursor/User/settings.json"
cursor_cli_config = home / ".cursor/cli-config.json"
cursor_state_db = home / "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
state_key = "src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser"
subagent_overrides_key = "cursor/subagentModelOverrides"
glass_editor_prefs_key = "cursor/glass.editorPreferences"
glass_display_settings_key = "glass.display.settings"
ide_features = (
    "composer",
    "background-composer",
    "composer-ensemble",
    "plan-execution",
    "spec",
    "deep-search",
    "quick-agent",
)
editor_agent_features = ("quick-agent", "composer")
UI_FONT_SIZES = tuple(range(11, 24))
CODE_FONT_SIZES = tuple(range(10, 23))
check_only = mode.startswith("--check")
fix_mode = mode == "--fix" or (not check_only)
run_model = mode in ("--fix", "--check", "--check-model")
run_settings = mode in ("--fix", "--check", "--check-settings")


def load_json(path):
    if not path.exists() or path.stat().st_size == 0:
        return {}
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def dump_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    tmp.replace(path)


def upsert_state_value(conn, key, value):
    payload = json.dumps(value, separators=(",", ":"))
    conn.execute(
        "insert into ItemTable (key, value) values (?, ?) "
        "on conflict(key) do update set value = excluded.value",
        (key, payload),
    )


def nearest_allowed(value, allowed):
    try:
        numeric = int(value)
    except (TypeError, ValueError):
        return allowed[0]
    return min(allowed, key=lambda item: abs(item - numeric))


def editor_vim_enabled(settings):
    if any(key.startswith("vim.") for key in settings):
        return True
    affinity = settings.get("extensions.experimental.affinity", {})
    return "vscodevim.vim" in affinity


def desired_glass_editor_prefs(settings):
    line_numbers = settings.get("editor.lineNumbers", "on")
    word_wrap = settings.get("editor.wordWrap", "off")
    return {
        "keybindings": "vim" if editor_vim_enabled(settings) else "default",
        "lineNumbersVisible": line_numbers not in ("off", False),
        "wordWrapEnabled": word_wrap in ("on", True, "bounded"),
    }


def desired_glass_display_settings(settings):
    desired = {
        "uiFontSizePx": nearest_allowed(settings.get("editor.fontSize", 13), UI_FONT_SIZES),
        "codeFontSizePx": nearest_allowed(settings.get("editor.fontSize", 12), CODE_FONT_SIZES),
    }
    font_family = settings.get("editor.fontFamily")
    if isinstance(font_family, str) and font_family.strip():
        desired["codeFontFamily"] = font_family.strip()
    return desired


def desired_cli_editor(settings):
    return {"vimMode": editor_vim_enabled(settings)}


def merge_managed_keys(current, desired):
    merged = dict(current) if isinstance(current, dict) else {}
    for key, value in desired.items():
        merged[key] = value
    return merged


def subset_matches(current, desired):
    if not isinstance(current, dict):
        return False
    return all(current.get(key) == value for key, value in desired.items())


def sync_model_parity():
    def desired_model_id():
        settings = load_json(claude_settings)
        model = settings.get("model", "")
        effort = settings.get("effortLevel", "")
        if not model:
            return ""
        if re.fullmatch(r"claude-opus-\d+-\d+", model):
            effort = "xhigh" if effort in ("", "max") else effort
            return f"{model}-{effort}"
        return model

    def display_name(model_id):
        match = re.fullmatch(r"claude-opus-(\d+)-(\d+)-(.+)", model_id)
        if match:
            major, minor, effort = match.groups()
            return f"Claude Opus {major}.{minor} {effort.replace('-', ' ').title()}"
        return model_id

    def selected_model(model_id):
        return {"modelId": model_id, "parameters": []}

    def normalize_model_config(config, fallback_target):
        if not isinstance(config, dict):
            config = {}
        model_name = config.get("modelName") or fallback_target
        if model_name in ("", "default"):
            model_name = fallback_target
        selected_models = config.get("selectedModels")
        if not selected_models:
            selected_models = [selected_model(model_name)]
        return {
            "modelName": model_name,
            "maxMode": bool(config.get("maxMode", False)),
            "selectedModels": selected_models,
        }

    def editor_agent_model_config(state, fallback_target):
        model_config = state.get("aiSettings", {}).get("modelConfig", {})
        for feature in editor_agent_features:
            feature_config = model_config.get(feature)
            if isinstance(feature_config, dict) and feature_config.get("modelName") not in (None, "", "default"):
                return normalize_model_config(feature_config, fallback_target)
        return normalize_model_config({}, fallback_target)

    def subagent_override_entry(agent_config):
        return {
            "mode": "model",
            "modelConfig": {
                "modelName": agent_config["modelName"],
                "maxMode": agent_config["maxMode"],
                "selectedModels": agent_config["selectedModels"],
            },
        }

    def subagent_overrides_match(overrides, agent_config):
        if not overrides:
            return True
        expected = subagent_override_entry(agent_config)
        return all(overrides.get(name) == expected for name in overrides)

    target = desired_model_id()
    if not target:
        return True, None

    cli_ok = True
    ide_ok = True
    subagent_ok = True
    agent_config = normalize_model_config({}, target)

    if cursor_cli_config.exists():
        cli = load_json(cursor_cli_config)
    else:
        cli = {"version": 1} if fix_mode else {}

    if cursor_state_db.exists():
        conn = sqlite3.connect(cursor_state_db, timeout=5)
        try:
            row = conn.execute("select value from ItemTable where key = ?", (state_key,)).fetchone()
            if row:
                state = json.loads(row[0])
                available = {
                    item.get("serverModelName") or item.get("name")
                    for item in state.get("availableDefaultModels2", [])
                    if isinstance(item, dict)
                }
                if not available or target in available:
                    model_config = state.get("aiSettings", {}).get("modelConfig", {})
                    expected_selection = [selected_model(target)]
                    ide_ok = all(
                        isinstance(model_config.get(feature), dict)
                        and model_config[feature].get("modelName") == target
                        and model_config[feature].get("selectedModels") == expected_selection
                        and model_config[feature].get("maxMode") is False
                        for feature in ide_features
                    )
                    if fix_mode and not ide_ok:
                        ai_settings = state.setdefault("aiSettings", {})
                        model_config = ai_settings.setdefault("modelConfig", {})
                        ai_settings["modelDefaultSwitchOnNewChat"] = False
                        for feature in ide_features:
                            current = model_config.setdefault(feature, {})
                            current["modelName"] = target
                            current["maxMode"] = False
                            current["selectedModels"] = expected_selection
                        conn.execute(
                            "update ItemTable set value = ? where key = ?",
                            (json.dumps(state, separators=(",", ":")), state_key),
                        )
                        conn.commit()
                        ide_ok = True

                    agent_config = editor_agent_model_config(state, target)

            subagent_row = conn.execute(
                "select value from ItemTable where key = ?",
                (subagent_overrides_key,),
            ).fetchone()
            overrides = json.loads(subagent_row[0]) if subagent_row else {}
            subagent_ok = subagent_overrides_match(overrides, agent_config)
            if fix_mode and not subagent_ok:
                expected = subagent_override_entry(agent_config)
                for name in list(overrides):
                    overrides[name] = expected
                upsert_state_value(conn, subagent_overrides_key, overrides)
                conn.commit()
                subagent_ok = True
        finally:
            conn.close()

    if cursor_cli_config.exists() or fix_mode:
        cli_ok = (
            cli.get("model", {}).get("modelId") == agent_config["modelName"]
            and cli.get("model", {}).get("displayModelId") == agent_config["modelName"]
            and cli.get("hasChangedDefaultModel") is True
            and cli.get("maxMode") == agent_config["maxMode"]
        )
        if fix_mode and not cli_ok:
            model_id = agent_config["modelName"]
            name = display_name(model_id)
            cli["model"] = {
                "modelId": model_id,
                "displayModelId": model_id,
                "displayName": name,
                "displayNameShort": name,
                "aliases": [],
                "maxMode": agent_config["maxMode"],
            }
            cli["hasChangedDefaultModel"] = True
            cli["maxMode"] = agent_config["maxMode"]
            dump_json(cursor_cli_config, cli)
            cli_ok = True

    ok = cli_ok and ide_ok and subagent_ok
    message = f"✓ Cursor model parity pinned: model={agent_config['modelName']}" if ok and fix_mode else None
    return ok, message


def sync_settings_parity():
    settings = load_json(cursor_settings)
    if not settings:
        return True, None

    desired_editor = desired_cli_editor(settings)
    desired_glass_editor = desired_glass_editor_prefs(settings)
    desired_glass_display = desired_glass_display_settings(settings)

    cli_ok = True
    glass_editor_ok = True
    glass_display_ok = True

    if cursor_cli_config.exists():
        cli = load_json(cursor_cli_config)
        cli_editor = cli.get("editor", {})
        cli_ok = isinstance(cli_editor, dict) and cli_editor.get("vimMode") == desired_editor["vimMode"]
    elif fix_mode:
        cli = {"version": 1}
        cli_ok = False
    else:
        cli = {}
        cli_ok = False

    if fix_mode and not cli_ok:
        cli["version"] = cli.get("version", 1)
        cli["editor"] = merge_managed_keys(cli.get("editor"), desired_editor)
        dump_json(cursor_cli_config, cli)
        cli_ok = True

    if cursor_state_db.exists():
        conn = sqlite3.connect(cursor_state_db, timeout=5)
        try:
            glass_editor_row = conn.execute(
                "select value from ItemTable where key = ?",
                (glass_editor_prefs_key,),
            ).fetchone()
            current_glass_editor = json.loads(glass_editor_row[0]) if glass_editor_row else {}
            glass_editor_ok = subset_matches(current_glass_editor, desired_glass_editor)
            if fix_mode and not glass_editor_ok:
                upsert_state_value(
                    conn,
                    glass_editor_prefs_key,
                    merge_managed_keys(current_glass_editor, desired_glass_editor),
                )
                conn.commit()
                glass_editor_ok = True

            glass_display_row = conn.execute(
                "select value from ItemTable where key = ?",
                (glass_display_settings_key,),
            ).fetchone()
            current_glass_display = json.loads(glass_display_row[0]) if glass_display_row else {}
            glass_display_ok = subset_matches(current_glass_display, desired_glass_display)
            if fix_mode and not glass_display_ok:
                upsert_state_value(
                    conn,
                    glass_display_settings_key,
                    merge_managed_keys(current_glass_display, desired_glass_display),
                )
                conn.commit()
                glass_display_ok = True
        finally:
            conn.close()

    ok = cli_ok and glass_editor_ok and glass_display_ok
    if ok and fix_mode:
        message = (
            "✓ Cursor agent settings parity pinned: "
            f"vimMode={desired_editor['vimMode']}, "
            f"glass.keybindings={desired_glass_editor['keybindings']}, "
            f"codeFontSizePx={desired_glass_display['codeFontSizePx']}"
        )
    else:
        message = None
    return ok, message


ok = True
messages = []

if run_model:
    model_ok, model_message = sync_model_parity()
    ok = ok and model_ok
    if model_message:
        messages.append(model_message)

if run_settings:
    settings_ok, settings_message = sync_settings_parity()
    ok = ok and settings_ok
    if settings_message:
        messages.append(settings_message)

if check_only:
    sys.exit(0 if ok else 1)

for message in messages:
    print(message)
PY
