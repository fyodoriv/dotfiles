#!/bin/bash
set -euo pipefail

# Feed the hook a synthetic change preflight. The Git commands are data.
root="$(cd "$(dirname "$0")/../.." && pwd)"
jq -Rsc '{tool_input:{command:.},cwd:"/tmp"}' <<'COMMAND' | "$root/agent-hooks/block-dangerous-git.sh"
set -eo pipefail
repo="/tmp/example-tooling"
base=old-revision
candidate=new-revision
git -C "$repo" fetch origin main
[ "$(git -C "$repo" rev-parse origin/main)" = "$candidate" ]
left="$(git -C "$repo" diff --name-only "$base" "$candidate" | sort)"
git -C "$repo" diff --exit-code "$base" "$candidate"
[ "$(git -C "$repo" branch --show-current)" = main ]
git -C "$repo" diff --quiet
git -C "$repo" merge --ff-only "$candidate"
COMMAND
