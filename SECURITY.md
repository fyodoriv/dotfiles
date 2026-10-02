# Security Policy

This document covers two distinct topics:

1. **Vulnerability reporting** — how to report a security issue you find in
   this repo.
2. **Public-repo privacy contract** — how this repo guarantees that
   `github.com/fyodoriv/dotfiles` (the only canonical home) never receives configured private identifiers,
   `@company.example` author emails, or hardcoded secrets.

## Reporting a Vulnerability

If you discover a security issue in this dotfiles repo (e.g., a leaked secret
in a template, a permission escalation, an unsafe default, or a leak that
slipped past the privacy gates documented below), please report it
**privately**:

1. **Do not open a public issue.** Security issues should not be disclosed
   publicly until a fix is available — especially on
   `github.com/fyodoriv/dotfiles`, where a public issue amplifies the leak.
2. Email the repo maintainer (<fyodor@sent.com>) directly, or use GitHub's
   [private vulnerability reporting][gh-private-vuln] if enabled on this
   repository.
3. Include:
   - A description of the issue
   - Steps to reproduce (if applicable)
   - The affected file(s) and line numbers
   - Suggested fix (optional but appreciated)

[gh-private-vuln]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability

## What Counts as a Security Issue

- Secrets (API keys, tokens, passwords) committed to tracked files
- Unsafe file permissions on sensitive files (`~/.ssh/`, `~/.zshenv.secrets`)
- `sudo` commands that could be exploited or are unnecessarily broad
- LaunchAgents that expose attack surfaces (e.g., open CDP ports)
- Unsafe `defaults write` settings that weaken macOS security posture
- Template rendering that could leak secrets into plaintext files
- **Any leak on `github.com/fyodoriv/dotfiles`**: an `@company.example` author or
  committer email in `git log`, a configured private identifier in a tracked file
  outside the configured private-reference gate, a hardcoded secret anywhere. Treat any of these
  as a P0.

## Security Model

For a detailed description of trust boundaries, privilege escalation, secrets
handling, and audit capabilities, see [docs/security-model.md](docs/security-model.md).

## Built-in Security Checks

This repo includes automated security auditing:

```bash
dotfiles audit            # Check security posture (SSH perms, secrets, git config)
dotfiles audit --report   # Markdown report for sharing
dotfiles doctor           # Includes security + git modules in weekly health checks
```

The `security` module checks SSH permissions, secret scanning, credential
storage, and GPG signing. The `git` module additionally checks the
public-repo privacy contract (`user.email`, hook self-tests). See [docs/security-model.md](docs/security-model.md#audit-capability)
for the full list of checks.

---

## Public-repo privacy contract

`github.com/fyodoriv/dotfiles` is the only canonical home of this repo.
Nothing rewrites history. The repo has a strict
**no-leak** contract: nothing about an organization's internal
infrastructure, no hardcoded secrets, and no @company.example identities
ever reach it. Every gate runs before a commit leaves the machine.

### Contract

Three independent leak categories are blocked, in order of how easy they
are to commit by accident:

1. **Content leaks** — configured private identifiers in tracked files (company
   names, internal product names, internal hostnames, ticket
   project codes). Source of truth: the regex in `lib/oss-readiness.sh`
   (`OSS_READINESS_INTERNAL_PATTERN`).

2. **Identity leaks** — git commits authored or committed by an
   `@company.example` email. These appear in `git log` on github.com and identify
   both the company and the individual. Source of truth:
   `OSS_READINESS_PRIVATE_EMAIL_PATTERN`, supplied by the org overlay's
   `oss-readiness.env`. No mapping can make a private email safe, because
   nothing rewrites history.

3. **Secret leaks** — hardcoded API keys, OAuth tokens, AWS keys, private
   keys. Source of truth: `OSS_READINESS_SECRET_PATTERNS` in
   `lib/oss-readiness.sh`, plus the env-var-style patterns in
   `lib/secret-scan.sh` (referenced by `modules/security/doctor.sh`).

### Gates (defense in depth)

The same rule is enforced at more than one layer, so a leak has to slip
past each of them to land on github.com. Each layer is intentionally
redundant — losing one (e.g. a contributor disables a hook) still leaves
the others.

| Layer | Where | What it catches | Bypass |
|-------|-------|-----------------|--------|
| **L1** Pre-commit hook | `git-hooks/pre-commit` | Forbidden files, content, secrets, and private committer email on staged files. In dotfiles it also blocks protected-directory deletions and lints TASKS.md | `git commit --no-verify` |
| **L2** Pre-push hook | `git-hooks/pre-push` | For pushes of dotfiles, agentbrew, and every repo in `config/public-push-remotes.txt` to github.com: blocks commits whose author or committer email matches the private-email pattern, blocks files changed in the push (read at the pushed commit) that match the private-identifier pattern, and blocks pushed commits whose added lines, file names, or message match. The messages list paths or commit ids only. Then delegates to the repo-local `hooks/pre-push` | `git push --no-verify` |
| **L2b** gh leak guard | `bin/gh` | Text that git hooks never see: PR, issue, and release bodies, titles, comments, `gh api` write fields, squash-merge commit messages, and public gist files. For a public github.com repo it blocks matches for the private-identifier and private-email patterns, this machine's `$HOME` path, any enterprise host `gh` is signed in to, and token-shaped secrets. GitHub Enterprise hosts and private repos are not checked | `DOTFILES_GH_ALLOW_PRIVATE_REFS=1` |
| **L3** Local test gate | `make check` | Shellcheck, TASKS.md lint, and affected Bats tests. GitHub Actions is turned off, so this is the last gate before merge to `feat/chezmoi` | skipping the run |

Nothing rewrites history after a push. A private email that passes L1 and
L2 lands on github.com as-is. That is why L2 blocks instead of warning, and
why L0 below guards the hook files themselves.

### Hook integrity (L0 — protects L1 + L2 from silent overwrite)

L1 and L2 only work if the hook files themselves are the canonical ones we
committed. PR #59 (2026-05-20) demonstrated the failure mode: a sister
repo's transitive `pnpm install` ran `lefthook install --force` against
the globally-configured `core.hooksPath` (pointing at this repo's
`git-hooks/`) and silently replaced `pre-commit` + `pre-push` with stubs.
None of this repo's CI, commit hooks, or tests caught it because the
swap happens during a package install in a sibling repo — no commit
involved here. The result: 8 commits with `@company.example` author emails
leaked to `github.com/fyodoriv/dotfiles` over a week.

The `git.hook_integrity.<name>` checks in `modules/git/doctor.sh` close
the gap. On every doctor run they compare each tracked hook's working-tree
blob SHA against its HEAD tree-entry SHA. Any mismatch — lefthook stub,
manual edit-without-commit, husky, you-name-it — produces a loud `fail`.
`--fix` mode restores the canonical file via `git checkout HEAD --
git-hooks/<name>` (scoped to the single file; not `git checkout .`, which
the multi-agent git-safety rules forbid).

This is L0 because it runs BEFORE the commit hooks fire — `dotfiles-doctor`
(weekly launchagent + manual) catches the overwrite before the next push
attempt would silently bypass L1 + L2. If the hook is somehow restored
before doctor runs again, the layers below still hold.

Test coverage: `tests/git-doctor-hook-integrity.bats` — five scenarios
including the exact lefthook stub pattern that triggered the 2026-05-20
leak.

### How to commit safely

By default, every dev should set `user.email` to a public-safe address in
this repo:

```
git -C ~/apps/tooling/dotfiles config user.email <your-public@email>
```

The `git` doctor module verifies this on every `dotfiles doctor` run.
Valid public-safe choices:

- Your personal email (Gmail / Fastmail / sent.com / etc.)
- A GitHub noreply address: `123456+username@users.noreply.github.com`

A new contributor with an @company.example email must set one of these
before their first commit here.

The pre-commit hook blocks a commit under an @company.example identity.
`ALLOW_PRIVATE_EMAIL=1` allows a local-only commit:

```
ALLOW_PRIVATE_EMAIL=1 git commit -m "feat: …"
```

The pre-push hook still blocks that commit from reaching github.com. Fix
the author on the local commit before you push.

### Private-reference scanner configuration

The base repo does not hardcode private identifiers or a permanent allowlist.
Private overlays provide `oss-readiness.env`, which defines:

- `OSS_READINESS_INTERNAL_PATTERN` — content identifiers that must not appear in
  the base repo
- `OSS_READINESS_PRIVATE_EMAIL_PATTERN` — author/committer emails that must
  never reach github.com

`lib/oss-readiness.sh` looks for the file in this order: `OSS_READINESS_ENV_FILE`,
the local-only `${XDG_CONFIG_HOME:-$HOME/.config}/oss-readiness/oss-readiness.env`,
the overlay root, then sibling repos under `~/apps`. Keep the local file out of
every repo.

With no overlay, both patterns are empty and those checks have nothing to
match. Run `tests/no-internal-refs.bats` with that env loaded before you
push. If it finds a match, move the content to the overlay or generalize it
in the base.

### Why this design

- **The hooks are the chokepoint.** Nothing rewrites history after a push,
  so a leak must stop before it leaves the machine.
- **Private patterns live in the org overlay.** The base repo stays free of
  private identifiers. Each org supplies its own patterns through
  `oss-readiness.env`.
- **Two failure modes, both loud.** Either the gates block a leak before
  it lands (red error, no push), or `~/.config/dotfiles/notify.yaml` fires
  a notification telling you a previously-OK commit now leaks. Silent
  failure is the worst outcome and we explicitly avoid it.
