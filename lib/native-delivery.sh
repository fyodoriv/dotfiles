#!/bin/bash
# Shared, per-invocation install and rollback for owned native commands.

native_delivery_install() (
  local root="$1" crate="$2" binary="$3" directory="$4" prefix="$5" label="$6"
  local source_file current_target temporary link_temp source_hash copy_hash destination
  [ "$(uname -s)" = Darwin ] || { echo "$label: macOS required" >&2; exit 1; }
  (cd "$root/rust" && "$root/bin/heavy-run" cargo build --locked --offline --release --manifest-path "$crate/Cargo.toml")
  source_file="$root/rust/$crate/target/release/$binary"
  [ -f "$source_file" ] && [ -x "$source_file" ] || { echo "$label: build did not produce an executable" >&2; exit 1; }
  mkdir -p "$directory"
  if [ -e "$directory/current" ] && [ ! -L "$directory/current" ]; then
    echo "$label: refusing to replace an unowned file" >&2
    exit 1
  fi
  if [ -L "$directory/current" ]; then
    current_target="$(readlink "$directory/current")"
    if [[ ! "$current_target" =~ ^${prefix}-[0-9a-f]{64}$ ]] || [ -d "$directory/current" ]; then
      echo "$label: refusing to replace an unowned link" >&2
      exit 1
    fi
  fi
  temporary="$(mktemp "$directory/.binary.XXXXXXXX")"
  link_temp=""
  trap 'rm -f "$temporary" ${link_temp:+"$link_temp"}' EXIT
  cp "$source_file" "$temporary"
  chmod 700 "$temporary"
  source_hash="$(shasum -a 256 "$source_file" | cut -d' ' -f1)"
  copy_hash="$(shasum -a 256 "$temporary" | cut -d' ' -f1)"
  [ "$source_hash" = "$copy_hash" ] || { echo "$label: copy integrity check failed" >&2; exit 1; }
  destination="$prefix-$copy_hash"
  if [ -L "$directory/$destination" ] || { [ -e "$directory/$destination" ] && [ ! -f "$directory/$destination" ]; }; then
    echo "$label: refusing to replace an unowned artifact" >&2
    exit 1
  fi
  mv -f "$temporary" "$directory/$destination"
  link_temp="$(mktemp "$directory/.current.XXXXXXXX")"
  rm -f "$link_temp"
  ln -s "$destination" "$link_temp"
  mv -f "$link_temp" "$directory/current"
)

native_delivery_rollback() {
  local directory="$1" prefix="$2" label="$3" target
  if [ -L "$directory/current" ]; then
    target="$(readlink "$directory/current")"
    if [[ "$target" =~ ^${prefix}-[0-9a-f]{64}$ ]]; then
      rm "$directory/current"
    else
      echo "$label: refusing to remove an unowned link" >&2
      return 1
    fi
  elif [ -e "$directory/current" ]; then
    echo "$label: refusing to remove an unowned file" >&2
    return 1
  fi
}
