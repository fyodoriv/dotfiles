#!/bin/bash
# One-shot leak-gate bypass that needs a person (issue #145, step 9).
# Replaces the DOTFILES_ALLOW_GH_PRIVATE_REFS environment variable, which an
# agent or a LaunchAgent could set.
#
#   dotfiles leak allow --once [<commit sha>]
#
# asks for a typed confirmation at a terminal and writes one grant to
# ${XDG_STATE_HOME:-~/.local/state}/dotfiles/leak-allow-once:
#   <sha or "any">  <expiry epoch>
# A grant lasts 10 minutes and is used once. With a sha, only a push whose
# commits include that sha may use it; without a sha, only the next blocked
# gh write. The leak gates call leak_allow_consume.
#
# State scope: one file per user; deleted when used or expired.

leak_allow_file() {
  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/leak-allow-once"
}

# leak_allow_grant <sha|any>: needs a terminal on stdin and stderr.
leak_allow_grant() {
  local target="${1:-any}" answer file
  if [ "$target" != any ] && ! [[ "$target" =~ ^[0-9a-f]{7,40}$ ]]; then
    echo "dotfiles leak allow: give a commit sha (7 to 40 hex characters)" >&2
    return 1
  fi
  if [ ! -t 0 ] || [ ! -t 2 ]; then
    echo "dotfiles leak allow: refused without a terminal. A person must run it." >&2
    return 1
  fi
  printf 'Allow ONE %s past the leak gate (10 minutes). Type "allow" to confirm: ' \
    "$([ "$target" = any ] && echo 'gh write' || echo "push of $target")" >&2
  read -r answer
  [ "$answer" = allow ] || { echo "not allowed" >&2; return 1; }
  file="$(leak_allow_file)"
  mkdir -p "$(dirname "$file")"
  (umask 077; printf '%s %s\n' "$target" "$(( $(date +%s) + 600 ))" > "$file")
  echo "✓ One bypass granted for 10 minutes." >&2
}

# leak_allow_consume <any|sha...>: succeeds (and deletes the grant) when an
# unexpired grant matches one of the arguments.
leak_allow_consume() {
  local file target expiry want
  file="$(leak_allow_file)"
  [ -f "$file" ] || return 1
  read -r target expiry < "$file" || { rm -f "$file"; return 1; }
  if [ -z "$expiry" ] || [ "$(date +%s)" -gt "$expiry" ]; then
    rm -f "$file"
    return 1
  fi
  for want in "$@"; do
    case "$want" in
      "$target" | "$target"*) rm -f "$file"; return 0 ;;
    esac
  done
  return 1
}
