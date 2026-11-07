# Managed-browser stray-tab guidance

Issue #475 asks failed doctor checks to name who can act and how. The managed
browser stray-tab check currently fails without a next step. A failed check is
not permission to close a page.

## Prediction

Goal: make that failure actionable without closing a page. Question: does the
failure name the agent's read-only review command and preserve the configured
keep-one policy? Predict that **1/1** failing synthetic cases names the agent
and exact dry-run command, **1/1** keep-one cases includes its flag, and **1/1**
passing cases stays passing. The check must make **zero** non-dry-run calls in
normal and fix modes.

The failure message names `Agent:` and supplies the helper's actual absolute
path, shell-quoted with Bash `printf %q`, followed by `--dry-run`. When the
configured keep-one option is true, append `--keep-one`. Tell the agent to
review the result and obtain the necessary authorization before closing a page.
The command itself only inspects; the doctor does not close a page.

After this registration lands, add `tests/agent-browser-stray-guidance.bats`.
All helper calls in these tests use a local test double and a captured argument
log, never a live browser. The failing-guidance control exercises normal and
fix modes and verifies at least one call in each, every one with `--dry-run`.
The named red control must fail for the fixed missing-guidance reason:

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run bats --filter '^failing_guidance$' tests/agent-browser-stray-guidance.bats >"$log" 2>&1
status=$?
[ "$status" -eq 1 ] && grep -Fxq 'not ok 1 failing_guidance' "$log" && grep -Fq 'missing dry-run guidance' "$log"
BASH
```

Implement the failure-only message, then require the three named controls,
the existing module tests, and the full gate:

```sh
bash <<'BASH'
set -o pipefail
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
test -f tests/agent-browser-stray-guidance.bats || exit 2
heavy-run bats tests/agent-browser-stray-guidance.bats 2>&1 | tee "$log" || exit 1
grep -Fxq '1..3' "$log" && grep -Fxq 'ok 1 failing_guidance' "$log" && grep -Fxq 'ok 2 keep_one_guidance' "$log" && grep -Fxq 'ok 3 passing_unchanged' "$log" || exit 2
heavy-run bats tests/module-agent-browser.bats || exit 1
heavy-run make check
BASH
```

Success requires all three controls, zero non-dry-run calls, the existing module
tests and `heavy-run make check` to pass. Any missing owner or command, wrong
keep-one flag, changed passing state, non-dry-run call, or failed gate rejects
the guidance approach. Do not close browser tabs as part of this experiment.

This covers one doctor line on the current Mac and does not establish that all
fresh-Mac failures are actionable. Anchor: issue #475; Basili, Caldiera and
Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.
