# Plan: user-dir-installers-for-aws-gcloud

## Goal

A fresh `dotfiles apply` with `is_enterprise: true` installs AWS CLI v2 and the
Google Cloud SDK under `~/.local/bin`, with no brew Python. A second apply
changes nothing.

## Why

- The arm64 Homebrew migration removed `awscli` and the `gcloud-cli` cask. Both
  pull `python@3.x`, which endpoint agents flag on every spawn (AGENTS.md
  rule #10).
- The tools were then installed by hand. `run_after_uv-tools.sh` cannot cover
  them: AWS CLI v2 is not on PyPI, and gcloud is not a uv tool.

## Scope (in)

- `bin/dotfiles-install-aws-gcloud [--aws|--gcloud] [--dry-run]`:
  1. aws: download `AWSCLIV2.pkg`, require an Amazon signature
     (`pkgutil --check-signature`), `pkgutil --expand-full`, copy the
     `aws-cli` payload to `~/.local/aws-cli`, link `aws` and `aws_completer`.
  2. gcloud: download the macOS SDK tarball for the CPU, unpack it to
     `~/google-cloud-sdk`, run `install.sh --quiet --usage-reporting false
     --path-update false --command-completion false`, link `gcloud`, `gsutil`,
     and `bq`.
  3. Skip a tool that is already installed. Re-link only when a link is wrong.
- `.chezmoiscripts/run_after_aws-gcloud.sh.tmpl` runs the helper on every apply,
  only when `is_enterprise` is true. It renders an empty body otherwise.
- Doctor: `enterprise.aws` fixes with the helper, not `brew install awscli`.
  New checks `enterprise.aws_user_dir` and `enterprise.gcloud_user_dir`.

## Scope (out)

- No `curl | bash` of `sdk.cloud.google.com`. The tarball plus `install.sh`
  with explicit flags keeps `~/.zshrc` (owned by dotfiles) untouched.
- No automatic upgrades. `gcloud components update` and a re-run of the AWS
  pkg stay manual.
- Not run on a live enterprise machine in this change. This Mac is personal.

## Verification

- `bats tests/dotfiles-install-aws-gcloud.bats` (stub curl, pkgutil, tar, uname).
- `bats tests/module-enterprise.bats` and the `aws-gcloud template` cases in
  `tests/chezmoiscripts.bats`.
- On an enterprise machine: `command -v aws gcloud | grep -c "$HOME/.local/bin/"`
  reads 2 after `dotfiles apply`.
