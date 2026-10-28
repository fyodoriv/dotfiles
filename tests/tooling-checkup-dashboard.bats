#!/usr/bin/env bats
# Comfort gate for the tooling-checkup dashboard page. It needs playwright, axe-core and d3
# Deps come from DASHBOARD_NODE_PATH, else NODE_PATH, else the pinned cache folder
# ~/.cache/dotfiles/dashboard-gate/node_modules. Without them every test prints a SKIPPED line
# that names the install command.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GATE="$ROOT/skills/tooling-checkup/scripts/dashboard_comfort.cjs"
  PAGE="$ROOT/skills/tooling-checkup/dashboard/index.html"
  command -v node >/dev/null || skip "node not installed"
  CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/dashboard-gate"
  export NODE_PATH="${DASHBOARD_NODE_PATH:-${NODE_PATH:-$CACHE/node_modules}}"
  node -e "require('playwright'); require.resolve.paths('x'); const f=require('fs'),p=require('path'); for (const r of ['axe-core/axe.min.js','d3/dist/d3.min.js']) if (!require.resolve.paths(r).some(d => f.existsSync(p.join(d, r)))) process.exit(1)" 2>/dev/null \
    || skip "SKIPPED dashboard comfort gate: install deps once with: npm i --prefix $CACHE playwright@1.64.1 axe-core@4.14.0 d3@7.9.0"
  export DASH_OUT="$BATS_TEST_TMPDIR"
}

@test "dashboard passes the comfort gate on phone and desktop, light and dark" {
  run node "$GATE" "$PAGE" clean
  [ "$status" -eq 0 ]
}

@test "the gate fails on a planted sideways overflow" {
  DASH_PLANT=overflow run node "$GATE" "$PAGE" overflow
  [ "$status" -eq 1 ]
  [[ "$output" == *"overflow"* ]]
}

@test "the gate fails on a planted break-anywhere rule in table cells" {
  DASH_PLANT=breakall run node "$GATE" "$PAGE" breakall
  [ "$status" -eq 1 ]
  [[ "$output" == *"splitWords"* ]]
}

@test "a missing dataset leaves the other panels drawn" {
  DASH_DROP=load run node "$GATE" "$PAGE" nodata
  [ "$status" -eq 0 ]
}
