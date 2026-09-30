# CI Setup Guide for Team Forks

How to enable and configure CI (continuous integration) on your team's fork of this dotfiles repo.

---

## How CI works in this repo

The workflow (`.github/workflows/ci.yml`) runs on every push and pull request:

| Job | Runner | What it does |
|-----|--------|-------------|
| **lint** | ubuntu-latest | `make lint` + `make lint-tasks` -- shellcheck scripts and validate `TASKS.md` |
| **test** | macos-13, macos-14, macos-15 | `make test-all` -- full bats suite on macOS |
| **doctor** | macos-latest | `chezmoi apply` + `dotfiles doctor --report` + shell startup benchmark |
| **audit** | macos-latest | `dotfiles-audit` -- security and repo-hygiene scan |
| **coverage** | ubuntu-latest | `bin/dotfiles-coverage` + bats -- shell coverage report artifact |

Organization-specific branch-protection / approval workflows belong in your private overlay (see your overlay's `.github/workflows/`).

The bats suite includes `tests/docs-links.bats`, which validates local Markdown
links in `README.md` and `docs/*.md` so onboarding links fail fast in CI.

### Shell coverage harness

The coverage job runs bats through `bin/dotfiles-coverage`, which writes
`coverage/bats/coverage.json` (kcov-compatible shape) and enforces the shell
coverage floor from `.shell-coverage-floor`. Run `make coverage` locally to
see the same floor check. `.shell-coverage-floor` must be a measured ratchet:
set it from the current full `make coverage` percentage with up to a 1.0 point
buffer for runner noise, then raise it only after adding tests that keep CI
green at the new threshold.

**Why not kcov?** Earlier revisions of this repo used `kcov` for coverage,
but kcov 43 fails on macOS Tahoe (26.x) and any later macOS where SIP
restricts `DYLD_INSERT_LIBRARIES`: kcov can't follow the `bash CMD`
subprocesses that bats spawns for `run bash "$CMD"` patterns, so
`coverage/bats/coverage.json` ends up with `"files": []`. Every local
`make coverage` reported 0% regardless of which tests ran, blocking any
agent that tried to raise the floor. The full reproduction + kcov flag
matrix is documented in `git log --grep='shell coverage'`.

The replacement (`bin/dotfiles-coverage` + `lib/coverage-trap.sh` +
`lib/coverage-report.py`) uses bash's built-in `set -x` instrumentation
through `BASH_ENV`. Bash subprocesses with `BASH_XTRACEFD` support source the
trap helper on startup, open an append-only fd to a per-PID trace file, and
write a `COV@<file>@<lineno>@<command>` marker for every executed line. The
harness then walks the trace files, filters paths under `bin/`, `lib/`,
and `modules/`, and emits a kcov-compatible JSON report so
`.github/scripts/check-shell-coverage.sh` and the badge workflow keep working
unchanged. macOS's legacy `/bin/bash` 3.2 does not support `BASH_XTRACEFD`, so
those subprocesses are left uninstrumented instead of leaking xtrace into
stderr and corrupting output-sensitive tests. The same `.shell-coverage-floor`
is enforced locally and in CI; set it from the lower full-suite baseline if
local and runner percentages differ.

**Ratchet policy.** Treat the floor as a one-way ratchet:

1. Run `make coverage` locally and read the reported percentage.
2. Set `.shell-coverage-floor` to a value at most 1.0 percentage point below
   the observed baseline so transient runner noise doesn't flap CI. Do not
   commit a placeholder value.
3. When new tests land that lift the percentage by >= 2 points, raise the
   floor in the same PR — the goal is to never let it slip back.
4. Never raise the floor in a PR that doesn't add or strengthen tests; the
   floor should track *measured* coverage, not aspiration.

### Monthly Homebrew audit

The separate `.github/workflows/brew-audit.yml` workflow runs on the first day
of each month and can be triggered manually:

```bash
gh workflow run brew-audit.yml
gh run list --workflow brew-audit.yml --limit 1
```

The audit parses every `brew` and `cask` entry from
`.chezmoiscripts/run_onchange_brew.sh.tmpl`, refreshes Homebrew metadata once in
the workflow setup, and checks Homebrew metadata and livecheck via
`brew info --json=v2 --formula/--cask`.

Packages do not need to be installed on the runner. Missing formulae/casks,
disabled entries, deprecated entries, renamed tokens, and upstream livecheck
update signals are reported instead of being skipped. If manifest problems are
found, the workflow creates or updates the `brew-audit` issue with the
actionable entries.

Run the same audit locally when editing the Brew manifest:

```bash
.github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl
BREW_AUDIT_METADATA_TIMEOUT=10 .github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl
BREW_AUDIT_LIVECHECK_TIMEOUT=10 .github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl
BREW_AUDIT_SKIP_LIVECHECK=1 .github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl
```

Each `brew info` metadata lookup is bounded by
`BREW_AUDIT_METADATA_TIMEOUT` seconds (default: 20) and runs with
`HOMEBREW_NO_AUTO_UPDATE=1`, so Homebrew cannot unexpectedly auto-update once
the per-entry audit starts. Metadata timeouts are reported against the affected
formula or cask without blocking the rest of the manifest.

Each `brew livecheck` call is bounded by `BREW_AUDIT_LIVECHECK_TIMEOUT`
seconds (default: 20) and also runs with `HOMEBREW_NO_AUTO_UPDATE=1`. A
livecheck timeout is reported against the affected formula or cask without
suppressing missing, disabled, deprecated, or renamed metadata findings from
the same run. Use `BREW_AUDIT_SKIP_LIVECHECK=1` for a metadata-only audit when
VPN or Homebrew network issues make livecheck unreliable, then retry the full
audit when the network is healthy.

### tasks-lint pin freshness

The `lint` job also runs `make lint-tasks-freshness`, which compares the
pinned `@tasks-md/lint` version in `.tasks-lint-version` with the latest
release published to npm. The audit is intentionally **advisory**:
`continue-on-error: true` lets it warn without breaking CI, and the script
itself returns 0 even when the pin is behind so commit hooks stay
unblocked on offline machines.

Run it locally before bumping the pin:

```bash
make lint-tasks-freshness
```

Possible outcomes:

- `✓ tasks-lint pin X.Y.Z is current` — nothing to do
- `⚠ tasks-lint pin X.Y.Z is behind registry latest A.B.C` — update with the
  printed remediation (`echo A.B.C > .tasks-lint-version` + `make lint-tasks`)
- `↷ tasks-lint freshness check skipped: …` — registry, curl, or jq was
  unavailable; rerun later

The script reads from environment-variable stubs in tests
(`TASKS_LINT_LATEST` / `TASKS_LINT_LATEST_FAIL`) so the audit can be
verified without the network — see `tests/tasks-lint.bats`.

---

## Enabling CI on a fork

### GitHub.com (public)

1. **Fork the repo** on GitHub.com
2. **Enable Actions**: Go to your fork > Settings > Actions > General > Allow all actions
3. **Push a commit** -- the workflow runs automatically

### GitHub Enterprise (GHE)

1. **Fork or import** the repo on your GHE instance
2. **Enable Actions**: Settings > Actions > General > Allow all actions (or restrict to specific actions)
3. **Configure runners**: GHE needs self-hosted macOS runners for the `test` and `doctor` jobs. If your org doesn't have macOS runners, change the `runs-on` to your available runner labels.

---

## Required secrets and environment variables

**None required.** The CI workflow uses no secrets or environment variables beyond what's on the runner. All dependencies are installed via `brew install` during the workflow.

If you add team-specific secrets (e.g., for enterprise tool testing), add them in Settings > Secrets and variables > Actions.

---

## Adding team-specific validation

Add new jobs or steps to the workflow for your team's needs:

```yaml
  # Example: check that no team-specific secrets are committed
  secrets-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Scan for secrets
        run: ./bin/dotfiles-audit
```

Common additions:
- **Custom doctor modules**: The `doctor` job already runs all modules. Add your module to `modules/<name>/doctor.sh` and it's automatically included.
- **Additional linters**: Add a step to the `lint` job (e.g., `shfmt -d` for format checking).
- **Branch protection**: Settings > Branches > Add rule > Require status checks > Select `lint`, `test`, `doctor`.

---

## GHE Actions vs github.com differences

| Feature | github.com | GHE |
|---------|-----------|-----|
| macOS runners | `macos-14`, `macos-15` available | Need self-hosted macOS runners |
| `actions/checkout@v4` | Works out of the box | May need to mirror actions to your GHE |
| Org-specific approval actions | Not available on public GitHub | Available per your overlay's workflows |
| Runner brew cache | Pre-installed (fast) | Depends on runner setup |
| Concurrency | GitHub-hosted limits apply | Depends on runner pool |

### Adapting runner labels for GHE

If your GHE has custom runner labels:

```yaml
# Change this:
runs-on: macos-14
# To your label:
runs-on: [self-hosted, macOS]
```

---

## Troubleshooting CI failures

**`lint` job fails**: Run `make lint` for shellcheck errors and `make lint-tasks` for `TASKS.md` queue format errors. Fix and push.

**`test` job fails**: Run `make test-all` locally. If tests pass locally but fail in CI, check for differences in brew package versions between your machine and the runner.

**`doctor` job fails**: The doctor job runs `chezmoi apply` first, then `dotfiles doctor --report`. Failures usually mean a module check assumes something about the environment that CI runners don't have. The `DOTFILES_CI=1` env var is set so modules can skip CI-incompatible checks.

**Shell startup exceeds 200ms**: The doctor job measures shell startup time. CI runners are slower than local machines. If this fails, check for slow tool inits in `home/zshrc`.
