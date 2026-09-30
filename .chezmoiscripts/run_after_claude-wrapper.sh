#!/bin/bash
# Install a ~/bin/claude wrapper that strips ANTHROPIC_MODEL before exec.
#
# WHY ~/bin/ instead of ~/.local/bin/:
#   claude update overwrites ~/.local/bin/claude with a new symlink on every update,
#   which would destroy a wrapper placed there. ~/bin/ comes before ~/.local/bin/ in
#   PATH (set by zshrc) so this wrapper takes precedence and survives updates.
#
# The wrapper defensively strips leaked ANTHROPIC_MODEL values so Claude Code
# uses its own configured model selection.
# Runs after every chezmoi apply. Idempotent.
set -euo pipefail

WRAPPER="$HOME/bin/claude"
REAL_CLAUDE="$HOME/.local/bin/claude"

# Skip if claude isn't installed
if [ ! -e "$REAL_CLAUDE" ]; then
  exit 0
fi

# Ensure ~/bin exists
mkdir -p "$HOME/bin"

# Skip if wrapper is already correct
if [ -f "$WRAPPER" ] \
  && grep -q "unset ANTHROPIC_MODEL" "$WRAPPER" 2>/dev/null \
  && grep -q "default-name-from-cwd" "$WRAPPER" 2>/dev/null \
  && grep -q "default-permission-mode-bypass" "$WRAPPER" 2>/dev/null \
  && ! grep -q "inaccessible on Enterprise accounts" "$WRAPPER" 2>/dev/null; then
  exit 0
fi

cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
# claude wrapper — strips ANTHROPIC_MODEL so Claude Code uses its own model
# selection, defaults --permission-mode to bypassPermissions, and defaults
# --name to "[<folder-basename>]" so the cwd shows in the terminal title (per
# `claude --help`: "shown in the prompt box, /resume picker, and terminal title").
#
# Lives in ~/bin/ (before ~/.local/bin in PATH) so claude update cannot
# overwrite it. Managed by dotfiles — do not edit directly.

REAL_CLAUDE="$HOME/.local/bin/claude"

unset ANTHROPIC_MODEL

_has_permission_mode=0
for _arg in "$@"; do
  case "$_arg" in
    --permission-mode|--permission-mode=*|--dangerously-skip-permissions)
      _has_permission_mode=1
      break
      ;;
  esac
done
if [ "$_has_permission_mode" = "0" ]; then
  set -- --permission-mode bypassPermissions "$@"
fi
# Tag: default-permission-mode-bypass

# Inject --name "[<folder>]" by default so the operator can see which folder
# each Ghostty tab is operating in. Skips when the user already provided -n
# or --name. Tag: default-name-from-cwd (used by the dotfiles installer to
# detect when this wrapper needs reinstalling). Source: 2026-05-27 operator
# directive — "shows on top which folder is devin or claude code is executing".
_has_name=0
for _arg in "$@"; do
  case "$_arg" in
    -n|--name) _has_name=1; break ;;
  esac
done
if [ "$_has_name" = "0" ]; then
  _folder="${PWD/#$HOME/~}"
  _basename="${_folder##*/}"
  set -- --name "[$_basename]" "$@"
fi

exec "$REAL_CLAUDE" "$@"
WRAPPER_EOF

chmod +x "$WRAPPER"
echo "✓ Claude wrapper installed at ~/bin/claude (strips ANTHROPIC_MODEL)"
