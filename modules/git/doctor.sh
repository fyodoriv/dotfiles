#!/bin/bash
# Doctor checks for git module

# ── Managed files & symlinks ──────────────────────────────────────────
check_managed "managed.gitconfig"       "$DOTFILES_DIR/dot_gitconfig.tmpl"      "$HOME/.gitconfig"
check_symlink "symlink.gitignore"      "$DOTFILES_DIR/home/gitignore_global"   "$HOME/.gitignore_global"
check_symlink "symlink.gitcommit"      "$DOTFILES_DIR/home/gitcommit_template" "$HOME/.gitcommit_template"
check_symlink "symlink.git_editor"     "$DOTFILES_DIR/home/git-editor"         "$HOME/.git-editor"

# ── Personal config bootstrap ────────────────────────────────────────
check "git.local_config" "\$HOME/.gitconfig.local exists (name + email)" \
  "[ -f \"\$HOME/.gitconfig.local\" ]"
# no auto-fix — user must set their own name/email; instructions in gitconfig.local.example

check "git.user_name" "git user.name is set" \
  "[ -n \"\$(git -C /tmp config user.name 2>/dev/null)\" ]"
check "git.user_email" "git user.email is set" \
  "[ -n \"\$(git -C /tmp config user.email 2>/dev/null)\" ]"

# ── Split identity (work default + personal for github.com) ─────────
# Driven by the git_personal_enabled chezmoi prompt. When enabled,
# ~/.gitconfig.personal is chezmoi-managed and the includeIf block in
# ~/.gitconfig.local is maintained by run_onchange_after_git-personal-includeif.sh.tmpl.
_git_personal_enabled="$(chezmoi execute-template '{{ dig "git_personal_enabled" false . }}' 2>/dev/null || echo "false")"
if [ "$_git_personal_enabled" = "true" ]; then
  check_managed "managed.gitconfig_personal" "$DOTFILES_DIR/dot_gitconfig.personal.tmpl" "$HOME/.gitconfig.personal"
  check "git.personal_includeif_block" "\$HOME/.gitconfig.local has managed includeIf block for github.com" \
    "grep -qF '# BEGIN git-personal-includeif' \"\$HOME/.gitconfig.local\""
  # Verify git actually picks up the personal identity in a repo that should trigger it.
  check "git.personal_resolves_for_minsky" "personal identity resolves for github.com repos" \
    "[ ! -d \"\$HOME/apps/tooling/minsky/.git\" ] || [ \"\$(git -C \"\$HOME/apps/tooling/minsky\" config user.email 2>/dev/null)\" != \"\$(chezmoi execute-template '{{ .git_work_email }}' 2>/dev/null)\" ]"
elif [ -f "$HOME/.gitconfig.personal" ]; then
  # Personal is disabled but the file lingers — flag it so the user notices drift.
  check "git.personal_disabled_but_file_exists" "\$HOME/.gitconfig.personal removed when git_personal_enabled=false" \
    "[ ! -f \"\$HOME/.gitconfig.personal\" ]"
fi

# ── Git config ───────────────────────────────────────────────────────
git_unsafe_add_aliases() {
  local alias_line alias_name alias_value
  git config --global --get-regexp '^alias\.' 2>/dev/null | while IFS= read -r alias_line; do
    alias_name="${alias_line%% *}"
    alias_value="${alias_line#* }"
    if printf '%s\n' "$alias_value" | grep -Eq '(^|[[:space:];|&])!?[[:space:]]*(git[[:space:]]+)?add[[:space:]]+(--[[:space:]]+)?(-A|--all|\.)([[:space:];|&]|$)'; then
      printf '%s\n' "$alias_name"
    fi
  done
}

check "git.pull_rebase"     "pull.rebase = true"          "[ \"\$(git config --global pull.rebase)\" = 'true' ]"          "git config --global pull.rebase true"
check "git.push_autosetup"  "push.autoSetupRemote = true" "[ \"\$(git config --global push.autoSetupRemote)\" = 'true' ]" "git config --global push.autoSetupRemote true"
check "git.pager_delta"     "core.pager = delta"          "git config --global core.pager | grep -q delta"                "command -v delta &>/dev/null && git config --global core.pager 'delta 2>/dev/null || less'"
check "git.rerere"          "rerere.enabled = true"       "[ \"\$(git config --global rerere.enabled)\" = 'true' ]"       "git config --global rerere.enabled true"
check "git.diff_algorithm"  "diff.algorithm = histogram"  "[ \"\$(git config --global diff.algorithm)\" = 'histogram' ]"  "git config --global diff.algorithm histogram"
check "git.fetch_prune"     "fetch.prune = true"          "[ \"\$(git config --global fetch.prune)\" = 'true' ]"          "git config --global fetch.prune true"
check "git.rebase_autostash" "rebase.autoStash = true"    "[ \"\$(git config --global rebase.autoStash)\" = 'true' ]"     "git config --global rebase.autoStash true"
check "git.fsmonitor_off"   "core.fsmonitor = false"      "[ \"\$(git config --global core.fsmonitor)\" = 'false' ]"      "git config --global core.fsmonitor false"
check "git.splitindex_off"  "core.splitIndex not set"     "[ -z \"\$(git config --global core.splitIndex)\" ]"            "git config --global --unset core.splitIndex 2>/dev/null"
check "git.maintenance_auto" "maintenance.auto = true"    "[ \"\$(git config --global maintenance.auto)\" = 'true' ]"     "git config --global maintenance.auto true"
check "git.safe_aliases"    "global git aliases avoid add-all staging" "[ -z \"\$(git_unsafe_add_aliases)\" ]"

# ── File permissions ─────────────────────────────────────────────────
check "git.safe_guard" "git-safe is executable" "[ -x \"$DOTFILES_DIR/bin/git-safe\" ]" "chmod +x \"$DOTFILES_DIR/bin/git-safe\""

# ── Dynamic checks (require runtime logic) ───────────────────────────
check "git.hooks_path" "git hooksPath points to dotfiles" \
  "[ \"\$(git -C /tmp config core.hooksPath 2>/dev/null)\" = \"${DOTFILES_LINK_DIR:-$DOTFILES_DIR}/git-hooks\" ]" \
  "git config -f ~/.gitconfig.local core.hooksPath \"${DOTFILES_LINK_DIR:-$DOTFILES_DIR}/git-hooks\""

# A LOCAL core.hooksPath in the dotfiles checkout silently overrides the global
# value above — a repo relocation or `lefthook install --force` can leave it
# pointing at a stale/non-existent dir, disabling the commit-msg + pre-commit
# backstops in THIS repo (the check above reads global via /tmp and stays green).
# Unset it so the global git-hooks/ apply. Auto-fixed by `dotfiles-doctor --fix`.
check "git.hooks_path_no_local_override" "dotfiles repo has no stale local core.hooksPath override" \
  "[ -z \"\$(git -C \"$DOTFILES_DIR\" config --local --get core.hooksPath 2>/dev/null)\" ]" \
  "git -C \"$DOTFILES_DIR\" config --local --unset core.hooksPath 2>/dev/null"

# ── Hook integrity (rule-#10 deterministic gate) ─────────────────────
# Defends against transitive `lefthook install` overwriting our git-hooks/*
# from a sister repo's pnpm install (root cause of the 2026-05-20 leak —
# 8 commits with @company.example authors reached personal/main because PR #59
# silently swapped pre-{commit,push} for a /tmp/minsky-gate/.../lefthook
# stub during a sister-repo install, no commit involved).
#
# Approach: compare each canonical hook's working-tree blob SHA against
# its HEAD tree-entry SHA. Mismatch → file was modified outside git
# tracking (or there's an uncommitted intentional edit; commit it first).
# The check uses git's own hash-object so it's identical to what git's
# index would record; no separate SHA registry to drift.
#
# Why this approach (vs `lib/canonical-hook-sha.txt`): a separate SHA file
# would itself need to be kept in sync with the hooks — drift between them
# silently breaks the gate. HEAD's tree entry is the SAME canonical state
# git already tracks; updating a hook via PR updates its tree entry
# automatically. One source of truth.
#
# --fix mode restores via `git checkout HEAD -- git-hooks/<name>`. This
# is scoped to a single file (not `git checkout .`), so it doesn't fall
# under the multi-agent "never reset" rule — but it WILL discard a
# legitimate uncommitted hook edit. If you're intentionally editing a
# hook, commit it first, then re-run doctor.
#
# The canonical list is derived from `git ls-tree HEAD -- git-hooks/`:
# whatever's tracked at HEAD is what we expect on disk. Untracked local
# hooks (e.g. machine-specific post-commit shims) are out of scope — they're per-machine setup, not the
# canonical leak-gate layer.
while IFS= read -r _hook_path; do
  [ -z "$_hook_path" ] && continue
  _hook="${_hook_path#git-hooks/}"
  _head_sha="$(git -C "$DOTFILES_DIR" ls-tree HEAD -- "$_hook_path" 2>/dev/null | awk '{print $3}')"
  _wt_sha=""
  if [ -f "$DOTFILES_DIR/$_hook_path" ]; then
    _wt_sha="$(git -C "$DOTFILES_DIR" hash-object "$DOTFILES_DIR/$_hook_path" 2>/dev/null)"
  fi
  check "git.hook_integrity.$_hook" \
    "git-hooks/$_hook matches HEAD blob (no transitive overwrite)" \
    "[ -n '$_head_sha' ] && [ '$_head_sha' = '$_wt_sha' ]" \
    "git -C '$DOTFILES_DIR' checkout HEAD -- '$_hook_path'"
done < <(git -C "$DOTFILES_DIR" ls-tree --name-only HEAD -- git-hooks/ 2>/dev/null)
unset _hook _hook_path _head_sha _wt_sha
# Scan repos for fsmonitor enabled + worktrees (index corruption risk)
REPOS_DIR="${DOTFILES_REPOS_DIR:-$HOME/apps}"
if [ -d "$REPOS_DIR" ]; then
for repo_dir in "$REPOS_DIR"/*/; do
  [ ! -d "$repo_dir/.git" ] && continue
  repo_name="$(basename "$repo_dir")"
  worktree_count=$(git -C "$repo_dir" worktree list 2>/dev/null | wc -l | tr -d ' ')
  if [ "$worktree_count" -gt 1 ]; then
    fsmon=$(git -C "$repo_dir" config --local core.fsmonitor 2>/dev/null || echo "unset")
    check "git.worktree_fsmon.$repo_name" \
      "$repo_name: fsmonitor off (${worktree_count} worktrees)" \
      "[ \"$fsmon\" = 'false' ]" \
      "git -C \"$repo_dir\" config core.fsmonitor false"
  fi
done
fi

# ── Sister-repo lefthook clobber prevention ───────────────────────────
# A sister repo's `pnpm install` runs lefthook, which installs into git's
# core.hooksPath. dotfiles wires hooksPath GLOBALLY (dot_gitconfig.tmpl),
# so a sister repo's lefthook clobbers the shared privacy hooks — renaming
# pre-{commit,push} to *.old and dropping stubs — silently disabling the
# no-leak contract until repair (git.hook_integrity self-heals, but only
# after the fact). Prevention: any sister repo that bundles its OWN
# lefthook binary should set a LOCAL core.hooksPath so its lefthook
# installs into the repo, not the shared dir. Guarded on a local lefthook
# binary so a repo is never left hook-less; dotfiles is excluded (it owns
# the global path — see git.hooks_path_no_local_override above).
for _lh_repo in "$REPOS_DIR"/*/ "$REPOS_DIR"/tooling/*/; do
  _lh_rp="${_lh_repo%/}"
  [ -d "$_lh_rp/.git" ] || continue
  [ "$_lh_rp" = "$DOTFILES_DIR" ] && continue
  { [ -f "$_lh_rp/lefthook.yml" ] || [ -f "$_lh_rp/lefthook.yaml" ]; } || continue
  [ -x "$_lh_rp/node_modules/.bin/lefthook" ] || continue
  _lh_name="$(basename "$_lh_rp")"
  _lh_local="$(git -C "$_lh_rp" config --local --get core.hooksPath 2>/dev/null || echo "")"
  check "git.lefthook_local_hookspath.$_lh_name" \
    "$_lh_name: lefthook uses a LOCAL core.hooksPath (won't clobber dotfiles' global hooks)" \
    "[ -n \"$_lh_local\" ]" \
    "git -C \"$_lh_rp\" config --local core.hooksPath .git/hooks && ( cd \"$_lh_rp\" && \"$_lh_rp/node_modules/.bin/lefthook\" install >/dev/null 2>&1 )"
done
unset _lh_repo _lh_rp _lh_name _lh_local

if command -v gh &>/dev/null; then
  check "git.gh_protocol"       "gh CLI uses SSH protocol"    "[ \"\$(gh config get git_protocol 2>/dev/null)\" = 'ssh' ]"    "gh config set git_protocol ssh 2>/dev/null"
  check "git.gh_auth" "gh authenticated to github.com" \
    "gh auth status -h github.com &>/dev/null"
  # Required scopes: repo, gist, read:org, workflow, admin:public_key, delete_repo
  # Re-add missing scopes: gh auth refresh -h github.com -s delete_repo
  for _scope in repo gist read:org workflow admin:public_key delete_repo; do
    check "git.gh_scope.$_scope" "gh token has $_scope scope" \
      "gh auth status -h github.com 2>&1 | grep -q '$_scope'"
  done
  unset _scope
fi

# ── Enterprise hooks ─────────────────────────────────────────────────
if [ "$IS_ENTERPRISE" = "true" ]; then
  check "git.hooks_executable" "git hooks are executable" \
    "[ -x \"$DOTFILES_DIR/git-hooks/commit-msg\" ] && [ -x \"$DOTFILES_DIR/git-hooks/pre-commit\" ] && [ -x \"$DOTFILES_DIR/git-hooks/pre-push\" ]" \
    "chmod +x \"$DOTFILES_DIR/git-hooks/commit-msg\" \"$DOTFILES_DIR/git-hooks/pre-commit\" \"$DOTFILES_DIR/git-hooks/pre-push\""
fi

# ── Privacy contract ─────────────────────────────────────────────────
# These checks enforce the SECURITY.md no-leak contract. They run on every
# machine: GitHub.com is canonical, so every push must pass the hooks.
# Self-test the pre-commit + pre-push hooks so we catch breakage
# before it lets a leak through.
check "git.pre_commit_hook_works" \
  "pre-commit hook self-test passes (no-leak contract layer L1)" \
  "[ -x \"$DOTFILES_DIR/git-hooks/pre-commit\" ] && bash \"$DOTFILES_DIR/git-hooks/pre-commit\" --self-test >/dev/null 2>&1" \
  "ls -l \"$DOTFILES_DIR/git-hooks/pre-commit\"  # expect executable, real bash script (not lefthook stub)"

check "git.pre_push_hook_works" \
  "pre-push hook self-test passes (no-leak contract layer L2)" \
  "[ -x \"$DOTFILES_DIR/git-hooks/pre-push\" ] && bash \"$DOTFILES_DIR/git-hooks/pre-push\" --self-test >/dev/null 2>&1" \
  "ls -l \"$DOTFILES_DIR/git-hooks/pre-push\""

if [ -f "$DOTFILES_DIR/lib/oss-readiness.sh" ]; then
  # shellcheck source=../../lib/oss-readiness.sh
  source "$DOTFILES_DIR/lib/oss-readiness.sh"
  oss_readiness_load_private_env dotfiles >/dev/null 2>&1 || true
fi

if [ -n "${OSS_READINESS_PRIVATE_EMAIL_PATTERN:-}" ]; then
  _git_email=$(git -C "$DOTFILES_DIR" config user.email 2>/dev/null || echo "")
  check "git.user_email_is_public_safe" \
    "git user.email does not match the configured private-email pattern" \
    "oss_readiness_email_is_safe \"$_git_email\"" \
    "git -C \"$DOTFILES_DIR\" config user.email <your-public@email>  # see SECURITY.md"
  unset _git_email
fi
