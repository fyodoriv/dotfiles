#!/usr/bin/env bash
# Compare the pinned `@tasks-md/lint` version (.tasks-lint-version) with
# the latest release published to npm and emit an actionable warning when
# the pin is behind. Designed to be non-fatal: network/parsing failures
# print a "skipped" notice and exit 0 so this never blocks a commit or CI
# run on offline runners. See docs/ci-setup.md for the rationale.
#
# Tests stub the lookup via two env vars (no curl/jq calls):
#   TASKS_LINT_LATEST          — the latest version to report
#   TASKS_LINT_LATEST_FAIL=1   — simulate an unavailable lookup
#
# Configurable knobs:
#   TASKS_LINT_LATEST_URL      — override the npm registry URL
#   TASKS_LINT_LATEST_TIMEOUT  — curl timeout in seconds (default 10)
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN_FILE="${TASKS_LINT_VERSION_FILE:-$DOTFILES_DIR/.tasks-lint-version}"
URL="${TASKS_LINT_LATEST_URL:-https://registry.npmjs.org/@tasks-md/lint/latest}"
TIMEOUT="${TASKS_LINT_LATEST_TIMEOUT:-10}"

if [ ! -f "$PIN_FILE" ]; then
  echo "↷ tasks-lint freshness check skipped: $PIN_FILE not found" >&2
  exit 0
fi

pinned="$(sed -n '1p' "$PIN_FILE")"
case "$pinned" in
  '' | *[!0-9.]*)
    echo "↷ tasks-lint freshness check skipped: invalid pin '$pinned' in $PIN_FILE" >&2
    exit 0
    ;;
esac

# Stubbed unavailable case lets tests prove the non-fatal contract
# without simulating real network failures.
if [ "${TASKS_LINT_LATEST_FAIL:-0}" = "1" ]; then
  echo "↷ tasks-lint freshness check skipped: latest version lookup unavailable (stubbed)" >&2
  exit 0
fi

# The env-var stub is checked before falling back to curl so unit tests
# never reach for the network. This keeps the audit deterministic and
# prevents flaky CI on registry hiccups.
if [ -n "${TASKS_LINT_LATEST:-}" ]; then
  latest="$TASKS_LINT_LATEST"
else
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "↷ tasks-lint freshness check skipped: curl or jq missing" >&2
    exit 0
  fi
  payload="$(curl --silent --show-error --max-time "$TIMEOUT" "$URL" 2>/dev/null || true)"
  if [ -z "$payload" ]; then
    echo "↷ tasks-lint freshness check skipped: registry lookup at $URL returned no data" >&2
    exit 0
  fi
  latest="$(printf '%s' "$payload" | jq -r '.version // empty' 2>/dev/null || true)"
  if [ -z "$latest" ]; then
    echo "↷ tasks-lint freshness check skipped: could not parse .version from $URL" >&2
    exit 0
  fi
fi

case "$latest" in
  *[!0-9.]*)
    echo "↷ tasks-lint freshness check skipped: bad latest value '$latest'" >&2
    exit 0
    ;;
esac

if [ "$pinned" = "$latest" ]; then
  echo "✓ tasks-lint pin $pinned is current"
  exit 0
fi

# `sort -V` resolves semantic ordering (1.10.0 > 1.9.0) without bringing
# in extra deps. If the pinned version is somehow ahead of "latest"
# (mirror lag, pre-release pin), still report — the operator can decide.
newest="$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)"
if [ "$newest" = "$pinned" ]; then
  echo "✓ tasks-lint pin $pinned is at or ahead of registry ($latest)"
  exit 0
fi

cat <<MSG
⚠  tasks-lint pin $pinned is behind registry latest $latest
   Update with:
     echo $latest > .tasks-lint-version
     make lint-tasks
MSG
exit 0
