#!/bin/bash
# Run the upstream service against scratch state. Never print its credentials.
set -u
binary="${OPENCODE_TRIAL_BINARY:?Set OPENCODE_TRIAL_BINARY to the tested binary}"
control_port="${OPENCODE_TRIAL_CONTROL_PORT:-18765}"
port=49391
case "$binary" in *[!a-zA-Z0-9_./-]*) echo 'FAIL binary path'; exit 1;; esac
case "$control_port" in *[!0-9]*|'') echo 'FAIL control port'; exit 1;; esac
root="$(mktemp -d /tmp/opencode-managed-trial.XXXXXX)" || exit 1
root="$(cd "$root" && pwd -P)"
mkdir -p "$root/home" "$root/config" "$root/data" "$root/cache"
profile="(version 1)(deny default)(allow process*)(allow sysctl-read)(allow file-read* (literal \"/\") (literal \"/private\") (literal \"/private/tmp\") (literal \"$binary\") (subpath \"$root\") (subpath \"/usr\") (subpath \"/bin\") (subpath \"/System\") (subpath \"/dev\"))(allow file-write* (subpath \"$root\") (literal \"/dev/null\"))(allow network-bind (local ip \"localhost:$port\"))(allow network-inbound (local ip \"localhost:$port\"))(allow network-outbound (remote ip \"localhost:$port\"))"
isolated() {
  env -i HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache" TMPDIR="$root" PATH=/usr/bin:/bin /usr/bin/sandbox-exec -p "$profile" "$@" >/dev/null 2>&1
}
cleanup() {
  isolated "$binary" service stop || true
  if /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo 'FAIL scratch listener remains after cleanup' >&2
    return 1
  fi
  rm -rf -- "$root"
}
trap cleanup EXIT
if /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo 'FAIL scratch port occupied'; exit 1
fi
if ! /usr/bin/nc -z -w 1 127.0.0.1 "$control_port" >/dev/null 2>&1; then
  echo 'FAIL network control is not listening'; exit 1
fi
if isolated /usr/bin/nc -z -w 1 127.0.0.1 "$control_port"; then
  echo 'FAIL sandbox reached network control'; exit 1
fi
if ! isolated "$binary" service set port "$port"; then
  echo 'FAIL scratch service configuration'; exit 1
fi
if ! isolated "$binary" service start; then
  echo 'FAIL scratch service start'; exit 1
fi
if ! isolated "$binary" api get /api/info; then
  env -i HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache" TMPDIR="$root" PATH=/usr/bin:/bin /usr/bin/sandbox-exec -p "$profile" "$binary" api get /api/info 2>&1 | /usr/bin/python3 tests/fixtures/opencode-error-category.py || true
  echo 'FAIL scratch authenticated API'; exit 1
fi
if ! isolated "$binary" service stop; then
  echo 'FAIL scratch service stop'; exit 1
fi
if /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo 'FAIL scratch listener remains'; exit 1
fi
echo 'PASS isolated start, authenticated API, stop, and listener cleanup'
