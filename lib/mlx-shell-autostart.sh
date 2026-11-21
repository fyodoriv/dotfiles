#!/bin/bash

dotfiles_shell_mlx_autostart_allowed() {
  [ "${DOTFILES_SHELL_MLX_AUTOSTART:-0}" = 1 ] || return 1
  [ "${DOTFILES_ALLOW_PUBLISHER_NA_PYTHON:-0}" = 1 ] && return 0
  case "${DOTFILES_ENDPOINT_HARDENING:-0}" in
    0|false) ;;
    *) return 1 ;;
  esac
  case "${DOTFILES_SHELL_MLX_ENDPOINT_HARDENING:-${DOTFILES_ENDPOINT_HARDENING:-1}}" in
    0|false) ;;
    *) return 1 ;;
  esac
  # The shared endpoint detector uses POSIX word splitting for its path list.
  if [ -n "${ZSH_VERSION:-}" ]; then setopt local_options sh_word_split; fi
  ! dotfiles_managed_endpoint
}

dotfiles_shell_mlx_launcher() {
  local launcher launcher_dir shebang interpreter python_version
  launcher="$(command -v mlx_lm.server)" || return 1
  case "$launcher" in
    /*) ;;
    *) return 1 ;;
  esac
  launcher="$(realpath "$launcher" 2>/dev/null)" || return 1
  [ -f "$launcher" ] && [ -x "$launcher" ] || return 1
  launcher_dir="${launcher%/*}"
  IFS= read -r shebang < "$launcher" || return 1
  case "$shebang" in
    '#!'/*) interpreter="${shebang#\#!}" ;;
    *) return 1 ;;
  esac
  [ -f "$interpreter" ] && [ -x "$interpreter" ] || return 1
  [ "$(realpath "${interpreter%/*}" 2>/dev/null)" = "$launcher_dir" ] || return 1
  python_version="$(awk -F'[[:space:]=.]+' '
    ($1 == "version" || $1 == "version_info") && $2 == 3 && $3 ~ /^[0-9]+$/ {
      print $2 "." $3
      exit
    }
  ' "$launcher_dir/../pyvenv.cfg" 2>/dev/null)" || return 1
  [ -n "$python_version" ] || return 1
  case "${interpreter##*/}" in
    python|python3|"python$python_version") ;;
    *) return 1 ;;
  esac
  [ -r "$launcher_dir/../lib/python$python_version/site-packages/mlx_lm/server.py" ] || return 1
  printf '%s\n' "$launcher"
}

dotfiles_shell_mlx_local_model() {
  local model="$1" cache revision index shards shard
  if [ ! -d "$model" ]; then
    case "$model" in
      *[!a-zA-Z0-9._/-]*|/*|*/*/*|*/) return 1 ;;
      */*) ;;
      *) return 1 ;;
    esac
    cache="${HF_HUB_CACHE:-${HF_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/huggingface}/hub}/models--${model%/*}--${model#*/}"
    [ -r "$cache/refs/main" ] || return 1
    IFS= read -r revision < "$cache/refs/main" || [ -n "$revision" ] || return 1
    case "$revision" in *[!a-f0-9]*) return 1 ;; esac
    [ "${#revision}" -eq 40 ] || return 1
    model="$cache/snapshots/$revision"
  fi
  [ -f "$model/config.json" ] && [ -s "$model/config.json" ] || return 1
  case "$model" in
    /*) ;;
    *) model="$(realpath "$model" 2>/dev/null)" || return 1 ;;
  esac
  index="$model/model.safetensors.index.json"
  shards=model.safetensors
  if [ -e "$index" ] || [ -L "$index" ]; then
    [ -f "$index" ] || return 1
    shards="$(jq -er '
      .weight_map | select(type == "object" and length > 0)
      | [.[]] | unique
      | select(all(.[]; type == "string" and test("^model[A-Za-z0-9._-]*\\.safetensors$")))
      | .[]
    ' "$index" 2>/dev/null)" || return 1
  fi
  while IFS= read -r shard; do
    [ -f "$model/$shard" ] && [ -s "$model/$shard" ] || return 1
  done <<< "$shards"
  printf '%s\n' "$model"
}
