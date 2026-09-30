# User Story: Stay Safe from Accidental Damage

> Multiple agents and automated scripts touch this repo. Safety nets prevent accidental deletions, secrets leaking, and destructive git operations.

## Deletion Protection

### Auto-sync never commits deletions

`dotfiles-sync` (runs every 30 min) detects staged deletions after `git add -u` and unstages them automatically. Deletions require an explicit manual commit.

### Pre-commit blocks protected directory deletions

The `pre-commit` hook blocks any commit that deletes files in critical directories:

- `bin/` — scripts
- `tests/` — test suite
- `lib/` — shared libraries
- `modules/` — doctor health checks
- `skills/` — agent skill plugins

Intentional deletions bypass with `git commit --no-verify`.

### Excessive deletion guard

If more than 50 files are staged for deletion (usually from worktree index corruption), the commit is blocked.

## Multi-Agent Safety

`git-safe` guards against destructive git commands in repos shared by multiple AI agents:

```bash
git-safe status        # safe — passes through
git-safe reset --hard  # blocked — wipes uncommitted changes from all agents
git-safe checkout .    # blocked — reverts all working-tree edits
git-safe clean -fd     # blocked — deletes untracked files
```

Detects active worktrees and `.orchestrator` / `.worktrees` directories to determine protection level. Bypass with `GIT_SAFE_BYPASS=1 git <command>` when you really mean it.

## Secret Scanning

The `pre-commit` hook automatically:

- **Blocks forbidden files** — SSH keys (`id_rsa`, `id_ed25519`, `id_dsa`), certificates (`.pem`, `.key`, `.p12`, `.pfx`, `.keystore`, `.jks`), and `.env.local` / `.env.production` cannot be committed (full list: `git-hooks/pre-commit:FORBIDDEN_PATTERNS`)
- **Scans for**: `API_KEY`, `SECRET_KEY`, `PRIVATE_KEY`, `ACCESS_TOKEN`, `AUTH_TOKEN`, `PASSWORD`, `CLIENT_SECRET` assignments (value of 8+ characters)

## Security Audit

```bash
dotfiles audit              # full security audit
dotfiles audit --report     # markdown report (for sharing)
```

Checks SSH permissions, git signing, secret exposure, and file permissions. Integrated into the doctor module system as the `security` module.

## Files Involved

| File | Purpose |
|------|---------|
| `bin/dotfiles-sync` | Auto-sync with deletion protection |
| `git-hooks/pre-commit` | Deletion guard, secret scanning, file type blocking |
| `git-hooks/commit-msg` | Conventional commit format enforcement |
| `bin/git-safe` | Multi-agent destructive command guard |
| `bin/dotfiles-audit` | Security audit CLI |
| `modules/security/doctor.sh` | Security health checks |
| `.sync-protect` | Files protected from auto-sync |
