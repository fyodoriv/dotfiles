# Standalone Git guard Bats regression

Registered before the fix on 2026-11-15. The hosted standalone Bats invocation
in [run 43690201571](https://github.com/fyodoriv/dotfiles/actions/runs/43690201571)
failed while loading the guard test file with an unmatched quote at generated
line 301. The earlier affected-test invocation passed. The trigger is not yet
proven; nested heredoc fixture text is the first hypothesis.

**Hypothesis:** Moving the three synthetic command bodies into separate fixture
files preserves the same test inputs and lets both standalone and affected
hosted Bats invocations load and execute the complete suite.

**Measurement:** Hosted CI runs `bats tests/agent-hooks-block-dangerous-git.bats`
as a standalone invocation and the normal affected repository gate.

**Success:** Both invocations load and execute 100% of the declared tests; the planted safe
case passes and destructive controls stay blocked. **Pivot:** Any parse error,
missing case, changed test decision or new unsafe allow rejects this fix; read
the new log and reassess the parser trigger.

**Anchor:** Hosted failure above; Basili, Caldiera and Rombach 1994 (GQM).
