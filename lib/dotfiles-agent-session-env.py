#!/usr/bin/env python3
"""Set the Claude session PATH and build the SessionStart JSON response."""

from __future__ import annotations

import json
import os
import shlex
import stat
import sys


def build_session_env(dotfiles: str, home: str, path_prefix: str) -> dict[str, object]:
    existing = os.environ.get("PATH", "/opt/homebrew/bin:/usr/bin:/bin")
    if path_prefix:
        path_value = f"{path_prefix}:{existing}"
    else:
        path_value = existing

    env: dict[str, str] = {
        "PATH": path_value,
        "DOTFILES_DIR": dotfiles,
    }

    jq_candidates = [
        os.path.join(dotfiles, "bin", "jq"),
        os.path.join(home, ".local", "bin", "jq"),
        "/opt/homebrew/bin/jq",
        "/usr/local/bin/jq",
    ]
    for jq_path in jq_candidates:
        if jq_path and os.path.isfile(jq_path) and os.access(jq_path, os.X_OK):
            env["DOTFILES_JQ"] = jq_path
            break

    ca = os.environ.get("NODE_EXTRA_CA_CERTS", "").strip()
    if not ca:
        extra = [
            c for c in os.environ.get("DOTFILES_CORPORATE_CA_BUNDLES", "").split(":") if c
        ]
        for candidate in (
            *extra,
            os.path.join(home, ".config", "ssl", "corporate-combined-ca.pem"),
            os.path.join(home, ".config", "ssl", "macos-trust-bundle.pem"),
        ):
            if os.path.isfile(candidate):
                ca = candidate
                break
    if ca:
        env["NODE_EXTRA_CA_CERTS"] = ca

    return {"env": env}


def persist_claude_path(home: str, path_prefix: str) -> None:
    env_file = os.environ.get("CLAUDE_ENV_FILE", "")
    if not os.path.isabs(env_file) or not path_prefix:
        return
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(event, dict) or event.get("hook_event_name") != "SessionStart":
        return

    guard_dir = os.path.join(home, ".claude", "codeassist", "hooks-scripts", "lib")
    guard = shlex.quote(guard_dir)
    git_wrapper = shlex.quote(os.path.join(guard_dir, "git"))
    prefix = shlex.quote(path_prefix)
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
    try:
        with os.fdopen(os.open(env_file, flags, 0o600), "a", encoding="utf-8") as out:
            info = os.fstat(out.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
                raise OSError("Unsafe session environment file")
            out.write(
                f'\ncase "${{PATH:-}}" in\n'
                f"  {guard}:*)\n"
                f'    if [ -x {git_wrapper} ]; then export PATH={guard}:{prefix}:"${{PATH#*:}}";\n'
                f'    else export PATH={prefix}:"${{PATH:-}}"; fi ;;\n'
                f'  *) export PATH={prefix}:"${{PATH:-}}" ;;\n'
                f"esac\n"
            )
    except OSError:
        print("Dotfiles could not update Claude's session PATH file.", file=sys.stderr)


def main() -> None:
    dotfiles = sys.argv[1] if len(sys.argv) > 1 else ""
    home = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("HOME", "")
    path_prefix = sys.argv[3] if len(sys.argv) > 3 else ""

    if not dotfiles:
        print("{}")
        return

    persist_claude_path(home, path_prefix)
    print(json.dumps(build_session_env(dotfiles, home, path_prefix)))


if __name__ == "__main__":
    main()
