# Agent-browser Spotlight guidance: issue 475

Goal: make a failed browser Spotlight check actionable. Question: when the
marker exists but the synthetic index still contains a browser child, does
the doctor name the person and the exact repair? Predict guidance improves
from 0/1 to 1/1, while the clean-probe and marker-repair controls remain 2/2.

Before the change, add a named Bats control using a scratch HOME, an existing
marker, a synthetic indexed child, and a fake `mdls` command. Require the
failed browser description to name `you:`, `System Settings`, `Spotlight`,
`Search Privacy`, and `$HOME/.agent-browser`. The fake logs its last path and
returns a non-null value only for the created direct child. Assert that child
was sampled and the specific `agent-browser.spotlight_excluded` check failed
before inspecting its description. If guidance is absent, print the fixed
diagnostic `spotlight guidance missing` and fail. Keep the existing probe and
marker repair unchanged.

Before editing the doctor, the named red control must fail for that diagnostic:

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run bats --filter '^agent-browser: indexed Spotlight guidance$' tests/module-agent-browser.bats >"$log" 2>&1
status=$?
[ "$status" -eq 1 ] && grep -Fxq 'not ok 1 agent-browser: indexed Spotlight guidance' "$log" && grep -Fq 'spotlight guidance missing' "$log"
BASH
```

Measurement after the change:

```sh
bash <<'BASH'
set -o pipefail
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run bats --filter 'agent-browser: (indexed Spotlight guidance|passes when profile dir and env vars exist|fix mode creates spotlight exclusion file)' tests/module-agent-browser.bats | tee "$log" || exit 1
grep -Fxq '1..3' "$log" &&
grep -Fxq 'ok 1 agent-browser: passes when profile dir and env vars exist' "$log" &&
grep -Fxq 'ok 2 agent-browser: indexed Spotlight guidance' "$log" &&
grep -Fxq 'ok 3 agent-browser: fix mode creates spotlight exclusion file' "$log"
BASH
heavy-run bats tests/module-agent-browser.bats
heavy-run make check
```

Success: all three named controls pass, the entire module suite and full
gate pass, and independent review confirms the description names the correct
folder. Pivot: any missing guidance, incorrect pass for the indexed fixture,
marker regression or gate failure rejects this approach. This is one slice; it
does not establish that every line in issue 475 is resolved.

Anchor: existing workflow doctor Spotlight guidance; Basili, Caldiera and
Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.
