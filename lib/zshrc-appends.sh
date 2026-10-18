#!/bin/bash
# Moves lines that an installer appended to the tracked home/zshrc into
# ~/.zshrc.local, so they never reach the public repo.
#
# ~/.zshrc is a symlink to home/zshrc. Installers such as opencode, bun, or
# rustup append `export PATH=...` lines to ~/.zshrc, and those lines then
# change a tracked file. home/zshrc already sources ~/.zshrc.local, so the
# lines keep working after the move.
#
# Only a pure append moves: the committed file must be an exact prefix of the
# working file. Any other edit stays in place for a human to review.

# zshrc_appended_text <repo-dir>
# Prints the text appended after the committed home/zshrc. Returns 1 when
# nothing was appended or the change is not a pure append.
zshrc_appended_text() {
  local repo="$1" file="$1/home/zshrc" head_size
  [ -f "$file" ] || return 1
  head_size="$(git -C "$repo" cat-file -s HEAD:home/zshrc 2>/dev/null)" || return 1
  [ "$(wc -c < "$file" | tr -d ' ')" -gt "$head_size" ] || return 1
  head -c "$head_size" "$file" | cmp -s - <(git -C "$repo" show HEAD:home/zshrc) || return 1
  tail -c "+$((head_size + 1))" "$file"
}

# zshrc_move_appends <repo-dir> [local-file]
# Appends the extra text to the local file (default ~/.zshrc.local) and
# restores home/zshrc to the committed text. Writes in place, so the
# ~/.zshrc symlink stays valid. Prints the number of lines moved.
zshrc_move_appends() {
  local repo="$1" local_file="${2:-$HOME/.zshrc.local}" text lines
  text="$(zshrc_appended_text "$repo")" || return 1
  lines="$(printf '%s\n' "$text" | grep -c . || true)"
  {
    printf '\n# Moved from home/zshrc by dotfiles on %s (an installer appended it).\n' "$(date '+%Y-%m-%d')"
    printf '%s\n' "$text"
  } >> "$local_file" || return 1
  git -C "$repo" show HEAD:home/zshrc > "$repo/home/zshrc" || return 1
  printf '%s\n' "$lines"
}
