#!/usr/bin/env python3
"""Build SessionStart env JSON for Claude/Cursor agent hooks (PATH + NODE_EXTRA_CA_CERTS)."""

from __future__ import annotations

import json
import os
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


def main() -> None:
    dotfiles = sys.argv[1] if len(sys.argv) > 1 else ""
    home = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("HOME", "")
    path_prefix = sys.argv[3] if len(sys.argv) > 3 else ""

    if not dotfiles:
        print("{}")
        return

    print(json.dumps(build_session_env(dotfiles, home, path_prefix)))


if __name__ == "__main__":
    main()
