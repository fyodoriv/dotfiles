#!/bin/bash
# Repair a broken official-installer poetry by moving it to uv.
#
# poetry_repair_to_uv <poetry-bin>
#   Moves <poetry-bin> and ~/Library/Application Support/pypoetry/venv
#   aside to *.bak (never deletes; an existing *.bak gets a time suffix),
#   then runs `uv tool install poetry`. Returns non-zero when uv is
#   missing, the binary is outside $HOME (not the official installer's
#   location), or the install fails.

_poetry_repair_move_aside() {
  local path="$1" dest="$1.bak"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  [ -e "$dest" ] || [ -L "$dest" ] && dest="$path.bak.$(date +%s)"
  mv "$path" "$dest"
}

poetry_repair_to_uv() {
  local bin="$1"
  local venv="$HOME/Library/Application Support/pypoetry/venv"
  command -v uv >/dev/null 2>&1 || return 1
  case "$bin" in
    "$HOME"/*) ;;
    *) return 1 ;;
  esac
  _poetry_repair_move_aside "$bin" || return 1
  _poetry_repair_move_aside "$venv" || return 1
  uv tool install poetry
}
