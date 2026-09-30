#!/usr/bin/env bash
# Stability-priority gate for dotfiles TASKS.md.
#
# Reuses agentbrew's scripts/lint-tasks-stability.mjs (single implementation,
# GET-don't-IMPLEMENT) located via the shared agentbrew-locate helper, so the
# stability-tag set never drifts between the tooling repos. Stability work
# (observability / regression / data-integrity / ci-gate / …) must live in
# P0/P1 — see ~/.config/devin/AGENTS.md § Task queues. The draining backlog of
# pre-existing stability tasks is grandfathered in .tasks-stability-allowlist.
#
# Skips cleanly (exit 0) when agentbrew isn't checked out, or the located
# checkout predates the lint script (e.g. before the next agentbrew sync) —
# best-effort, like the agentbrew.hooks_enforcing doctor check. Enforces
# (hard-fail) once the script is present.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/agentbrew-locate.sh
source "$REPO_ROOT/lib/agentbrew-locate.sh"

if ! ab="$(agentbrew_locate 2>/dev/null)"; then
  echo "  (skip: no agentbrew checkout found — stability lint is reused from agentbrew)"
  exit 0
fi
script="$ab/scripts/lint-tasks-stability.mjs"
if [ ! -f "$script" ]; then
  echo "  (skip: $script not present yet — pending agentbrew sync)"
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "  (skip: node not on PATH)"
  exit 0
fi

exec node "$script" "$REPO_ROOT/TASKS.md" --allow-file "$REPO_ROOT/.tasks-stability-allowlist"
