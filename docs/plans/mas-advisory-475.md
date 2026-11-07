# Optional App Store CLI: doctor prediction

Issue #475 asks for human-only doctor results to name the person and steps,
and suggests making some checks advisory. The resilience
setup can install Amphetamine through the App Store without `mas`; `mas` is an
optional command-line route. The current `resilience.mas_installed` check is a
failure and advertises an echo-only auto-fix when `mas` is absent.

Goal: make this optional tool's missing state actionable without a false failure.
Predict the missing synthetic case moves from failure to warning, the installed
case stays passing, and neither case invokes `brew`, `open` or the setup wizard.
Success is 3/3 named cases passing, zero unexpected launch attempts, and the
normal Dotfiles checks passing. Any missing warning/guidance, false failure,
lost installed pass, launch attempt or regression rejects this approach. This
slice does not claim fresh-Mac acceptance for the rest of #475.

Commit this prediction before the test or behavior change. In the task-owned
worktree, add the named Bats cases to `tests/module-resilience.bats`. They must
source the real resilience module with synthetic command availability and
capturing check functions, use `FIX_MODE=true`, and plant canaries for `brew`,
`open` and `dotfiles-resilience-setup`. Missing `mas` must be a warning that
says it is optional, gives `You: brew install mas` for the CLI route and names
the App Store alternative. Installed `mas` must pass. A third test runs the
real doctor in a scratch checkout with `--fix --json`, proves fix mode ran on
a separate harmless control, checks the warning and guidance, and requires zero
launch canaries. Its isolated PATH must prove `mas` absent and prove each
executable launch canary is the command the doctor would resolve, regardless of
what is installed on the host.

First prove the missing-case regression with the exact new test:

```sh
set -e
log=$(mktemp)
set +e
JOBS=1 heavy-run bats --filter '^mas missing is advisory with owner guidance$' tests/module-resilience.bats >"$log" 2>&1
status=$?
set -e
[ "$status" -eq 1 ]
grep -Fq 'not ok 1 mas missing is advisory with owner guidance' "$log"
grep -Fq 'expected advisory for missing mas' "$log"
printf 'Private red log: %s\n' "$log"
```

The test must fail at its fixed `expected advisory for missing mas` assertion,
not during setup. Then change only the check and its documentation. Run:

```sh
set -eu
log=$(mktemp)
JOBS=1 heavy-run bats --filter '^mas (missing is advisory with owner guidance|installed remains passing|real doctor fix is advisory without launches)$' tests/module-resilience.bats >"$log" 2>&1
for name in 'mas missing is advisory with owner guidance' 'mas installed remains passing' 'mas real doctor fix is advisory without launches'; do
  [ "$(grep -Ec "^ok [0-9]+ $name$" "$log")" -eq 1 ]
done
grep -Fxq '1..3' "$log"
! grep -Eiq '(^not ok|# skip)' "$log"
printf 'Private focused log: %s\n' "$log"
JOBS=1 heavy-run bats tests/module-resilience.bats
JOBS=1 heavy-run make check
```

Require all three named cases, the complete module suite and the normal gate to
pass, with no skipped named case. Independently review the final changes.
Anchor: issue #475; Basili, Caldiera and Rombach (1994), Goal Question Metric;
Munafò et al. (2017), preregistration.
