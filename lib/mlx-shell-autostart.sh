#!/bin/bash

dotfiles_shell_mlx_autostart_allowed() {
  [ "${DOTFILES_SHELL_MLX_AUTOSTART:-1}" = 1 ] || return 1
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
  local launcher package_file
  launcher="$(command -v mlx_lm.server)" || return 1
  case "$launcher" in
    /*) ;;
    *) return 1 ;;
  esac
  launcher="$(realpath "$launcher" 2>/dev/null)" || return 1
  [ -f "$launcher" ] && [ -x "$launcher" ] || return 1
  if [ -n "${ZSH_VERSION:-}" ]; then setopt local_options nonomatch; fi
  for package_file in "${launcher%/*}"/../lib/python*/site-packages/mlx_lm/server.py; do
    if [ -r "$package_file" ]; then
      printf '%s\n' "$launcher"
      return 0
    fi
  done
  return 1
}
