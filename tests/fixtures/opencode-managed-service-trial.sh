#!/bin/bash
# Run the upstream service against scratch state. Never print its credentials.
set -u
binary="${OPENCODE_TRIAL_BINARY:?Set OPENCODE_TRIAL_BINARY to the tested binary}"
control_port="${OPENCODE_TRIAL_CONTROL_PORT:-18765}"
port=49391
if [ "${1:-}" = '--inside' ]; then
  classifier="${OPENCODE_TRIAL_CLASSIFIER:?Set OPENCODE_TRIAL_CLASSIFIER}"
  cd "$HOME" || exit 1
  if kill -0 "$PPID" 2>/dev/null; then
    echo 'FAIL sandbox can signal its outside parent'; exit 1
  fi
  /bin/sleep 10 & child=$!
  if ! kill -0 "$child" 2>/dev/null || ! kill "$child" 2>/dev/null; then
    echo 'FAIL sandbox cannot signal its child'; exit 1
  fi
  wait "$child" 2>/dev/null || true
  if /usr/bin/nc -z -w 1 127.0.0.1 "$control_port" >/dev/null 2>&1; then
    echo 'FAIL sandbox reached network control'; exit 1
  fi
  # shellcheck disable=SC2329 # Called by the EXIT trap.
  cleanup_inside() { "$binary" service stop >/dev/null 2>&1 || true; }
  trap cleanup_inside EXIT
  if ! "$binary" service set port "$port" >/dev/null 2>&1; then
    echo 'FAIL scratch service configuration'; exit 1
  fi
  if ! "$binary" service start >/dev/null 2>&1; then
    echo 'FAIL scratch service start'; exit 1
  fi
  service_url="$("$binary" service status 2>/dev/null)" || { echo 'FAIL scratch service status'; exit 1; }
  case "$service_url" in http://*|https://*) ;; *) echo 'FAIL scratch service discovery'; exit 1 ;; esac
  if ! "$binary" api get /api/info >/dev/null 2>&1; then
    "$binary" api get /api/info 2>&1 | /bin/bash "$classifier" || true
    echo 'FAIL scratch authenticated API'; exit 1
  fi
  if ! "$binary" service stop >/dev/null 2>&1; then
    echo 'FAIL scratch service stop'; exit 1
  fi
  service_url="$("$binary" service status 2>/dev/null)" || { echo 'FAIL stopped service status'; exit 1; }
  [ "$service_url" = stopped ] || { echo 'FAIL stopped service discovery'; exit 1; }
  trap - EXIT
  echo 'PASS isolated service and client'
  exit 0
fi

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
script="$script_dir/opencode-managed-service-trial.sh"
classifier="$script_dir/opencode-error-category.sh"
case "$binary$script$classifier" in *[!a-zA-Z0-9_./-]*) echo 'FAIL trial path'; exit 1;; esac
case "$control_port" in *[!0-9]*|'') echo 'FAIL control port'; exit 1;; esac
if /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo 'FAIL scratch port occupied'; exit 1
fi
if ! /usr/bin/nc -z -w 1 127.0.0.1 "$control_port" >/dev/null 2>&1; then
  echo 'FAIL network control is not listening'; exit 1
fi
root="$(mktemp -d /tmp/opencode-managed-trial.XXXXXX)" || exit 1
root="$(cd "$root" && pwd -P)"
mkdir -p "$root/home" "$root/config" "$root/data" "$root/cache" "$root/state"
profile="(version 1)(deny default)(allow process*)(allow signal (target same-sandbox))(allow sysctl-read)(allow file-read* (literal \"/\") (literal \"/private\") (literal \"/private/tmp\") (literal \"$binary\") (literal \"$script\") (literal \"$classifier\") (subpath \"$root\") (subpath \"/usr\") (subpath \"/bin\") (subpath \"/System\") (subpath \"/dev\"))(allow file-write* (subpath \"$root\") (literal \"/dev/null\"))(allow network-bind (local ip \"localhost:$port\"))(allow network-inbound (local ip \"localhost:$port\"))(allow network-outbound (remote ip \"localhost:$port\"))"
status=0
env -i HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache" XDG_STATE_HOME="$root/state" TMPDIR="$root" PATH=/usr/bin:/bin OPENCODE_TRIAL_BINARY="$binary" OPENCODE_TRIAL_CLASSIFIER="$classifier" OPENCODE_TRIAL_CONTROL_PORT="$control_port" /usr/bin/sandbox-exec -p "$profile" /bin/bash "$script" --inside || status=$?
if /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1 || compgen -G "$root/state/opencode/service*.json" >/dev/null; then
  echo 'FAIL scratch service state remains after cleanup' >&2
  exit 1
fi
rm -rf -- "$root"
exit "$status"
