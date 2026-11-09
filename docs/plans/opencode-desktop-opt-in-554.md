# OpenCode Desktop opt-in (#554)

Registered before implementation.

## Hypothesis

Default and `excludeAgents` applies install zero OpenCode Desktop casks. An explicit `opencode_desktop: true` opt-in attempts one separate cask install. A failed optional install produces a warning and lets later apply steps continue; an unrelated Brew bundle failure remains fatal.

## Measurement

`bats tests/opencode-desktop-cask.bats tests/chezmoiscripts.bats tests/dotfiles-config.bats`, then `make check`.

## Success

All three acceptance controls pass, the optional failure is non-fatal, the unrelated bundle failure remains fatal, and the settings/docs contracts stay green.

## Pivot

If a separate optional install cannot preserve the fatal bundle boundary, remove the cask from automated installation and document a manual opt-in instead. Do not make every cask or bundle failure non-fatal.

## Anchor

Issue #554's managed-machine failure and acceptance criteria; Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.
