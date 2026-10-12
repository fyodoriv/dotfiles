# Competitive scorecard

This scorecard is the main metric for dotfiles. It answers one question: on a
shared workload, does dotfiles beat the best other dotfile manager?

Run it with one command:

```bash
scripts/benchmark-run.sh          # table
scripts/benchmark-run.sh --json   # one JSON scorecard
```

The JSON has `dotfiles`, `competitors`, `blocked`, `north_star`,
`generatedAt`, `host`, and `workload`. `north_star.metrics_beaten` counts the
metrics where dotfiles beats the best competitor that ran.

## Goal, questions, metrics (GQM)

Goal: a new or drifted machine gets to the correct state with the least time
and the fewest human steps. The metric set follows Goal-Question-Metric
(Basili, Caldiera, Rombach 1994). The metrics are outcomes, not activity
counts (Forsgren, Humble, Kim 2018, *Accelerate*).

| Question | Metric | Better |
|---|---|---|
| How fast does a fresh home get the files? | `cold_apply_ms` | lower |
| How much does a no-change re-apply cost? | `noop_reapply_ms` | lower |
| How fast does the tool report a hand edit? | `drift_detect_ms` (null when the tool misses the edit) | lower |
| Does the tool see the hand edit at all? | `drift_detected` | true |
| Do two fresh homes get identical files? | `reproducibility_pct` | higher |
| How many commands does a person type on a fresh Mac? | `manual_bootstrap_steps` | lower |

Times are the median of `BENCH_REPS` runs (default 3). Each run uses a new
temporary HOME.

## Workload

- `BENCH_FILES` plain config files (default 120), 24 lines each.
- 12 directories with one nested level, deployed under `~/.bench`.
- The drift event replaces one deployed file with a hand-edited regular file.
- Every tool runs in an isolated temporary HOME with isolated XDG dirs and no
  global git config. The real HOME is never a deploy target.

Templates, secrets, and macOS settings are not in the shared workload. Only
some tools support them, so they cannot be compared on equal terms.

## Competitor corpus

| Tool | Version | How the script gets it | Deploy mode | Drift check used |
|---|---|---|---|---|
| dotfiles | this repo | `bin/dotfiles apply --no-fix` and `dotfiles diff` | copy | `chezmoi diff` |
| chezmoi | installed | `chezmoi` on PATH | copy | `chezmoi status` |
| GNU Stow | installed | `stow` on PATH, `--no-folding` | symlink | `stow --no` dry run reports a conflict |
| yadm | 3.3.0 | pinned script, SHA-256 checked, cached | copy (git work tree) | `yadm status` |
| dotbot | 1.21.0 | `uv` venv in the cache | symlink | a re-run refuses to overwrite and exits non-zero |
| home-manager | — | needs nix | symlink | blocked |

The cache is `~/.cache/dotfiles-benchmark` (`BENCH_CACHE_DIR`). Nothing is
installed system-wide. With `BENCH_NO_FETCH=1`, a missing tool is blocked.

A tool that cannot run is listed in `blocked` with a reason. Its measured
metrics stay `null`. Only the doc-sourced step count is kept.

### Manual bootstrap steps (sources)

Count of commands on a fresh Mac that already has Homebrew and git.

| Tool | Steps | Commands | Source |
|---|---|---|---|
| dotfiles | 4 | `brew install chezmoi`, `git clone`, `chezmoi init --apply`, `dotfiles doctor --fix` | [README § Installation](../../README.md#installation) |
| chezmoi | 1 | `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <user>` | <https://www.chezmoi.io/quick-start/> |
| GNU Stow | 3 | `brew install stow`, `git clone`, `stow <packages>` | <https://www.gnu.org/software/stow/manual/stow.html> |
| yadm | 2 | `brew install yadm`, `yadm clone <url>` | <https://yadm.io/docs/getting_started> |
| dotbot | 2 | `git clone --recursive`, `./install` | <https://github.com/anishathalye/dotbot#getting-started> |
| home-manager | 5 | nix installer, `nix-channel --add`, `nix-channel --update`, `nix-shell '<home-manager>' -A install`, `home-manager switch` | <https://nix-community.github.io/home-manager/#sec-install-standalone> |

## Latest results

Host: Darwin-arm64. Workload: 120 files, 3 runs, median. Date: 2026-10-12.

| Tool | Status | Cold apply (ms) | No-op re-apply (ms) | Drift detect (ms) | Reproducible (%) | Manual steps |
|---|---|---|---|---|---|---|
| dotfiles | ok | 2046 | 57 | 46 | 100 | 4 |
| chezmoi | ok | 2180 | 36 | 34 | 100 | 1 |
| GNU Stow | ok | 55 | 53 | 53 | 100 | 3 |
| yadm | ok | 3232 | 350 | 346 | 100 | 2 |
| dotbot | ok | 71 | 63 | 66 | 100 | 2 |
| home-manager | blocked | — | — | — | — | 5 |

Blocked: home-manager. Nix is not installed. Installing it needs admin rights
and a new APFS volume, which is outside the benchmark budget.

North star: dotfiles beats the best competitor on **0 of 5** metrics.

## Where dotfiles is behind

- **Bootstrap steps.** dotfiles needs 4 commands. chezmoi needs 1. A
  one-line `curl | sh` installer that clones and applies would close most of
  the gap.
- **Cold apply.** Copy-mode tools (dotfiles, chezmoi, yadm) are 30–60 times
  slower than symlink tools (stow, dotbot) on a fresh home. dotfiles uses
  chezmoi, so it shares chezmoi's cost.
- **Wrapper overhead.** `dotfiles apply` adds about 20 ms over plain chezmoi
  (lock handling and the wrapper start). Drift checks add about 10 ms.
- **What the workload does not show.** dotfiles adds doctor health checks,
  self-repair, macOS settings, and LaunchAgents. Competitors have no
  equivalent, so those are not in the shared metrics. They do not count as a
  win here.

## Rules

- **First-iterations bootstrap.** The first one or two agent iterations in
  this repo run `scripts/benchmark-run.sh` and refresh the results table
  above before other work. A stale baseline is not a valid baseline.
- **Every task names its metric.** Each new `TASKS.md` task states which
  scorecard metric it advances (see the policy comment in `TASKS.md`).
- **No made-up numbers.** A tool that cannot run is blocked with a reason.
