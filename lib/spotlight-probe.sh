#!/bin/bash
# Probe the Spotlight index for a directory.
#
# A `.metadata_never_index` marker does not always keep a directory out of
# the index. On macOS 27, ~/apps has the marker and Spotlight still holds
# about 188,000 items under it. So doctor checks probe the index itself.
#
# spotlight_dir_unindexed <dir>
#   0 when no sampled direct child of <dir> is in the Spotlight index.
#   1 when a sampled child is in the index.
#   `mdls -raw -name _kMDItemFileName <path>` prints "(null)" for an item
#   that is not in the index, and the file name for an item that is.
#   It samples up to 3 children, so it costs a few mdls calls per dir.
#   Without mdls (not macOS) there is no index to probe, so it returns 0.

spotlight_dir_unindexed() {
  local dir="$1" mdls_bin="${DOTFILES_MDLS_BIN:-mdls}" child val n=0
  command -v "$mdls_bin" >/dev/null 2>&1 || return 0
  while IFS= read -r child; do
    val="$("$mdls_bin" -raw -name _kMDItemFileName "$child" 2>/dev/null)" || continue
    if [ -n "$val" ] && [ "$val" != "(null)" ]; then
      return 1
    fi
    n=$((n + 1))
    [ "$n" -ge 3 ] && break
  done < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.metadata_never_index' 2>/dev/null)
  return 0
}
