# Git guard literal-search hardening (#472)

Registered after independent review of the first implementation and before the hardening code change. The original four safe and eight unsafe controls remain frozen.

## Findings

The first implementation accepts an inherited `RIPGREP_CONFIG_PATH`, checks the basename `rg` without resolving and identifying the executable, and misses compact short-option clusters containing `z` next to numeric option values.

## Added unsafe controls

Each must exit 2 after the fix.

1. Exported `RIPGREP_CONFIG_PATH` with `rg 'git reset --hard' .`.
2. An exported Bash function named `rg` with the same command text.
3. A fake executable named `rg` earlier on `PATH`.
4. `rg -zC2 'git reset --hard' .`.
5. `rg -znC2 'git reset --hard' .`.

The original four safe controls must still exit 0 when `RIPGREP_CONFIG_PATH` is unset and the resolved executable identifies itself as ripgrep.

## Hypothesis

The five added unsafe permits fall from 5/5 to 0/5; all 12 original controls and existing Git-guard tests keep their registered outcomes.

## Measurement

`bats tests/block-dangerous-git-literal-search.bats tests/agent-hooks-block-dangerous-git.bats tests/agent-hooks-block-dangerous-git-merged.bats`, then `make check`.

## Success

Zero unsafe permits, zero original-control regressions, and a fresh green repository gate.

## Pivot

Any unsafe permit or inability to establish executable identity rejects this exemption. Remove it rather than broaden the grammar or accept an unresolved command.

## Second independent-review pivot

Registered before the next code change.

The `--hostname-bin` option is another process-execution path. A spoofed `ripgrep` version string also showed that executing an unknown candidate for `--version` neither proves identity nor is safe.

Predicted unsafe permits: two; after the fix: zero. Do not execute the candidate. Qualify only the exact resolved `/opt/homebrew/bin/rg` or `/usr/local/bin/rg` installation selected by the same PATH. Replace the flag denylist with the small frozen allowlist: no option, `-n`, `--line-number`, `-F`, `--fixed-strings`, and the option terminator `--`. All other options, including `--hostname-bin`, keep the conservative refusal.

Add one spoofed-version control and one real `--hostname-bin` control. The original controls and first-review controls must retain their outcomes. The same measurement and pivot apply.

## Post-pattern option controls

Registered before the parser fix.

Predicted unsafe permits: two; after the fix: zero. Ripgrep accepts options after the pattern, so stopping validation at the first positional argument lets `--pre` and `--hostname-bin` through. Continue option validation through all arguments; only explicit `--` ends it. Add both post-pattern execution controls and retain all 19 existing controls.

## Anchor

Issue #472's trusted-resolution and fail-closed requirements; Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.
