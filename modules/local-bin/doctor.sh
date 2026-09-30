#!/bin/bash
# Doctor checks for ~/.local/bin (XDG user-binary directory)
#
# Why: shim-style tools (minsky, future minsky/tasks.md shims) install
# themselves by symlinking into ~/.local/bin. If the directory is missing
# or not on PATH, `command -v <shim>` fails first-try and the operator
# has to debug a "command not found" before anything else works.
check "local_bin.dir_exists" ".local/bin exists" \
  "[ -d \"\$HOME/.local/bin\" ]" \
  "mkdir -p \"\$HOME/.local/bin\""

check "local_bin.on_path" ".local/bin on \$PATH (fix: chezmoi apply, then open a new shell)" \
  "case \":\$PATH:\" in *:\"\$HOME/.local/bin\":*) true ;; *) false ;; esac" \
  ""
