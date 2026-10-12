# Plan: Competitive scorecard for dotfiles

- **Task**: self-metrics-competitive-benchmark
- **Repo**: ~/apps/tooling/dotfiles
- **Author**: agent session 2026-10-12
- **Status**: implemented

## Goal

One command prints a JSON scorecard that compares dotfiles with at least four
other dotfile managers on at least five shared metrics. The scorecard is the
main metric. Every new task names the metric it advances.

## Why

dotfiles had no measured comparison with other tools. Without a baseline, no
change can show that it closes a gap.

## Scope (in)

- `scripts/benchmark-run.sh`: synthetic workload, isolated temp HOMEs,
  median timings, blocked rows with reasons, a `north_star` summary.
- Competitors: chezmoi, GNU Stow, yadm (pinned, SHA-256 checked), dotbot
  (pinned, uv venv), home-manager (blocked when nix is absent).
- The dotfiles row runs the real `bin/dotfiles apply --no-fix` and
  `dotfiles diff` code paths on the fixture. It never runs the real apply,
  the doctor, or run_once scripts.
- `docs/competition/scorecard.md`: GQM metric set, corpus, step sources,
  results, where dotfiles is behind, the first-iterations-bootstrap rule.
- `tests/benchmark-run.bats`: JSON shape, at least five metrics, all
  competitor rows with blocked reasons, real HOME unchanged, argument errors.
- `TASKS.md`: policy line that every task names its scorecard metric.

## Scope (out)

- A fresh-VM run. No VM tool is set up on this host. The temp-HOME workload
  is the Pivot: it measures the file layer of each tool on the same machine.
- Templates, secrets, and macOS settings. Not every tool supports them.
- Installing nix. It needs admin rights and a system volume.

## Verify

```bash
scripts/benchmark-run.sh --json | jq '.north_star'
bats tests/benchmark-run.bats
make check
```
