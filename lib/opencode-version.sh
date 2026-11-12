#!/bin/bash
# Parse the major version of the executable passed by the caller.
opencode_major_version() {
  local version major
  version="$("$1" --version 2>/dev/null)" || return 1
  version="${version##* }"
  version="${version#v}"
  major="${version%%.*}"
  case "$major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$major"
}

# Unknown versions do not authorize the old server interface.
opencode_legacy_service_required() {
  local major
  major="$(opencode_major_version "$1")" || return 1
  [ "$major" = 1 ]
}

opencode_managed_service_healthy() {
  local service_url
  service_url="$("$1" service status 2>/dev/null)" || return 1
  case "$service_url" in http://*|https://*) return 0 ;; *) return 1 ;; esac
}
