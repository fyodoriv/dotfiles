#!/bin/bash
# Doctor checks for the Minsky operator surface.
#
# Minsky is a separate repo (~/apps/tooling/minsky) that ships its own
# CLI, daemon, observer, and 23+ AI-coding skills. dotfiles owns three
# integration points with it:
#
#   1. The repo checkout itself — `git rev-parse HEAD` must succeed at
#      `$MINSKY_REPO` (default: $DOTFILES_REPOS_DIR/tooling/minsky).
#   2. The PATH shim — `~/.local/bin/minsky` symlink to `<repo>/bin/minsky`,
#      because the repo's bin/ isn't on PATH by default.
#   3. Runtime sanity — `minsky --help` exits 0 (catches a broken Node
#      build or missing tsc dist/ output).
#
# Skill sync (~/.claude/skills/*, ~/.cursor/skills/*, etc.) is owned by
# **agentbrew**, not dotfiles (see AGENTS.md rule #8). The right place
# for "is the minsky skill catalog wired up?" checks is
# `modules/agentbrew/` plus the agentbrew sync output — not here.
#
# The observer/iter logs at `<repo>/.minsky/*.log` are runtime artifacts;
# their absence means the loop has never run, but that's normal on a
# fresh checkout. We check advisory-only.
#
# Anchor: dotfiles AGENTS.md rule #6 ("New modules need
# modules/<name>/doctor.sh — auto-discovered by dotfiles-doctor").
# Surfaced by TASKS.md task `minsky-doctor-module`.

_MINSKY_REPOS_DIR="${DOTFILES_REPOS_DIR:-$HOME/apps}"
_MINSKY_REPO="${MINSKY_REPO:-$_MINSKY_REPOS_DIR/tooling/minsky}"
_MINSKY_SHIM="${MINSKY_SHIM:-$HOME/.local/bin/minsky}"
_MINSKY_OBSERVER_LOG="$_MINSKY_REPO/.minsky/observer.log"
_MINSKY_ITER_LOG="$_MINSKY_REPO/.minsky/iter-once.log"

# ── Repo checkout ─────────────────────────────────────────────────────

_minsky_repo_is_git() {
  [ -d "$_MINSKY_REPO" ] || return 1
  git -C "$_MINSKY_REPO" rev-parse HEAD >/dev/null 2>&1
}

check "minsky.repo_exists" \
  "minsky repo present at $_MINSKY_REPO" \
  "[ -d '$_MINSKY_REPO' ]" \
  "git clone https://github.com/fyodoriv/minsky.git '$_MINSKY_REPO' (or set MINSKY_REPO to override the path)"

check "minsky.repo_is_git_checkout" \
  "minsky repo is a valid git checkout (HEAD resolvable)" \
  "_minsky_repo_is_git" \
  "cd '$_MINSKY_REPO' && git status — if HEAD is unborn or .git is corrupt, re-clone"

# ── PATH shim ─────────────────────────────────────────────────────────

_minsky_shim_ok() {
  [ -L "$_MINSKY_SHIM" ] || return 1
  # readlink returns the target; resolve to the canonical repo path.
  local target
  target="$(readlink "$_MINSKY_SHIM" 2>/dev/null || echo "")"
  [ -n "$target" ] || return 1
  # Accept either the canonical bin/minsky or a chezmoi-managed path
  # that resolves to it.
  case "$target" in
    "$_MINSKY_REPO/bin/minsky") return 0 ;;
    */minsky/bin/minsky) return 0 ;;
    *) return 1 ;;
  esac
}

check "minsky.shim_symlinked" \
  "\$HOME/.local/bin/minsky symlinked to <repo>/bin/minsky" \
  "_minsky_shim_ok" \
  "mkdir -p \"\$HOME/.local/bin\" && ln -sf '$_MINSKY_REPO/bin/minsky' '$_MINSKY_SHIM'"

# ── Runtime sanity ────────────────────────────────────────────────────

_minsky_help_runs() {
  # Use the shim if available, else fall back to the repo's bin/.
  # Avoid spawning the daemon — --help exits without side effects.
  local bin
  if [ -x "$_MINSKY_SHIM" ]; then
    bin="$_MINSKY_SHIM"
  elif [ -x "$_MINSKY_REPO/bin/minsky" ]; then
    bin="$_MINSKY_REPO/bin/minsky"
  else
    return 1
  fi
  "$bin" --help >/dev/null 2>&1
}

check "minsky.help_runs" \
  "\`minsky --help\` exits 0 (Node dist/ present, CLI parses)" \
  "_minsky_help_runs" \
  "cd '$_MINSKY_REPO' && pnpm install — the prepare hook runs tsc -b to build all workspace dist/ that the CLI loads at runtime"

# ── Observer artifacts (advisory — absent on a fresh checkout) ────────

if [ -d "$_MINSKY_REPO" ]; then
  check_advisory "minsky.observer_log_present" \
    "observer.log present at <repo>/.minsky/" \
    "[ -f '$_MINSKY_OBSERVER_LOG' ] && [ -s '$_MINSKY_OBSERVER_LOG' ]" \
    "Run \`minsky --once\` to generate one iteration's worth of observer output. Absent log on a fresh clone is expected."

  check_advisory "minsky.iter_log_recent" \
    "iter-once.log present (loop has run at least once)" \
    "[ -f '$_MINSKY_ITER_LOG' ]" \
    "Run \`minsky --once\` (foreground, exits after one iteration) — confirms the daemon, the agent dispatch, and the gate runner all reach their happy path."
fi
