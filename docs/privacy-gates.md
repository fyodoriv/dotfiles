# Privacy and security gates (full text)

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## Privacy & security gates

This repo enforces a strict no-leak contract on its public history at
`github.com/fyodoriv/dotfiles`. **No @company.example email, no organization
identifier outside the configured private-reference gate, no hardcoded secret ever reaches
github.com.** Nothing rewrites history, so every gate runs before a commit
leaves the machine. The full design lives in [`SECURITY.md`](../SECURITY.md). The
short version every contributor needs:

1. **Set a public-safe `user.email` in this repo:**
   ```
   git -C ~/apps/tooling/dotfiles config user.email <your-public@email>
   ```
   The `git` doctor check verifies this. Never commit under an
   @company.example identity. `ALLOW_PRIVATE_EMAIL=1` skips the pre-commit
   email check for one commit, but the pre-push gate still blocks that
   commit. No mapping can make a private email safe, because nothing
   rewrites history.

2. **The pre-commit hook (`git-hooks/pre-commit`) blocks** any staged
   file mentioning configured private identifiers (`lib/oss-readiness.sh` regex),
   any hardcoded secret pattern (GitHub PAT, AWS key, PEM, …), and any
   @company.example committer email. Bypass with `--no-verify` only as a
   last-resort emergency fix; later gates still fire.

3. **The pre-push hook (`git-hooks/pre-push`) applies a privacy gate** to
   pushes of dotfiles, agentbrew, and every repo in
   `config/public-push-remotes.txt` to github.com. It blocks any commit
   whose author or committer email matches the private-email pattern. It
   also blocks the push when a file changed in the pushed range (read at
   the pushed commit) matches the private-identifier pattern; the message
   lists file paths only. It also blocks a pushed commit whose added lines,
   file names, or message match; that message lists commit ids only. Both patterns come from the local-only `oss-readiness.env`,
   which `lib/oss-readiness.sh` loads. For the owner's public repos the
   hook fails closed: a missing or outdated pattern file (version below
   `config/oss-readiness-min-version`) blocks the push. Generic markers
   (home paths, enterprise hosts, `git@` remotes) run on pushed lines and
   messages with no pattern file. See `SECURITY.md` § "Private pattern
   file". The hook then delegates to the repo-local `hooks/pre-push`.
   Never set `DOTFILES_ALLOW_GH_PRIVATE_REFS=1` as an agent; only a human
   who read the text may.

4. **`bats tests/no-internal-refs.bats`** + **`bats tests/oss-readiness-lib.bats`**
   lock the private-reference scanner and secret patterns in place.
   Adding a configured private identifier to the base repo fails the
   build.

5. **Adding tasks from any machine.** Two valid paths:
   (a) edit TASKS.md via the github.com web UI on a feature branch and
   open a PR — zero setup, works from a phone; (b) use `bin/add-task`
   from a local clone — it generates a properly-formatted entry, runs
   `make lint-tasks`, and prints the git commands for you.

The regex source of truth is `lib/oss-readiness.sh::OSS_READINESS_INTERNAL_PATTERN`.
Adding a new identifier to scrub requires updating that file, running
`bats tests/no-internal-refs.bats`, and either moving matches to the
overlay or generalizing the base repo text.

**Public-safe TASKS.md:** Base-repo task entries must pass
`tests/no-internal-refs.bats` before you push.
Use generic project tags like `PROJ-123` — not org ticket prefixes — in
base `TASKS.md`. Org-specific vendor names, ticket keys, and
hostnames belong in the org overlay or in operator-only docs, not in
tracked base-repo queue text. A failure of that gate after merge means
ship-it is incomplete until the gate passes.
