#!/usr/bin/env bats
# Pin `home/zshrc` portability invariants.
#
# `home/zshrc` is symlinked into `~/.zshrc` by chezmoi (via
# `symlink_dot_zshrc.tmpl`). Several shell features rely on the symlink
# resolving back to the dotfiles repo so it can prepend
# `<dotfiles>/bin` onto PATH:
#
#   • Aliases that shell out to `dotfiles-*` scripts.
#   • `morning`, `pr`, `hotfix`, `review`, etc., that must be on PATH.
#
# A previous incarnation of the PATH bootstrap fell back to a
# hardcoded `$HOME/apps/dotfiles/home/zshrc` when `readlink` failed —
# silently breaking PATH for any adopter who picked a non-default
# `dotfiles_dir` (chezmoi prompts allow that). These tests stop that
# class of regression from coming back.
#
# Closes harden-zshrc-readlink-fallback.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
ZSHRC="$REPO_ROOT/home/zshrc"
ZSHRC_AI_TOOLS="$REPO_ROOT/home/zshrc.ai-tools"
ZSHENV="$REPO_ROOT/home/zshenv"

@test "home/zshrc does not hardcode apps/dotfiles" {
  if grep -F 'apps/dotfiles' "$ZSHRC"; then
    echo "home/zshrc reintroduced a hardcoded apps/dotfiles path"
    echo "fix: derive the dotfiles bin from readlink \"\$HOME/.zshrc\" only;"
    echo "     when readlink fails, leave _dotfiles_bin empty so the [ -d ] test skips it"
    return 1
  fi
}

@test "home/zshrc keeps the _dotfiles_bin marker (shell module check)" {
  # `modules/shell/doctor.sh:9` greps `home/zshrc` for `_dotfiles_bin`
  # to verify the dotfiles bin is on PATH. Removing the variable would
  # fail that doctor check silently — this is the upstream pin so the
  # rename of the variable always reaches the doctor side too.
  grep -q '_dotfiles_bin' "$ZSHRC" || {
    echo "home/zshrc no longer mentions _dotfiles_bin"
    echo "the shell.dotfiles_on_path doctor check (modules/shell/doctor.sh) will fail"
    return 1
  }
}

@test "home/zshrc PATH block resolves via readlink when ~/.zshrc is a symlink" {
  # Mock a fresh dotfiles tree, symlink ~/.zshrc to it, and source just
  # the PATH block. The block must put `<repo>/bin` on PATH.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/dotfiles/home" "$tmp/dotfiles/bin" "$tmp/home"
  cp "$ZSHRC" "$tmp/dotfiles/home/zshrc"
  ln -s "$tmp/dotfiles/home/zshrc" "$tmp/home/.zshrc"
  touch "$tmp/dotfiles/bin/morning"
  chmod +x "$tmp/dotfiles/bin/morning"

  # Source just the PATH block (lines 28-37 in the current file).
  HOME="$tmp/home" PATH="/usr/bin:/bin" bash -c '
    set -e
    sed -n "/^# ── PATH/,/^unset _dotfiles_bin/p" "'"$tmp"'/dotfiles/home/zshrc" > "'"$tmp"'/path-block.sh"
    # shellcheck disable=SC1091
    . "'"$tmp"'/path-block.sh"
    case ":$PATH:" in
      *":'"$tmp"'/dotfiles/bin:"*) echo "OK"; exit 0 ;;
      *) echo "MISS: $PATH"; exit 1 ;;
    esac
  '
  rm -rf "$tmp"
}

@test "home/zshrc PATH block falls through when ~/.zshrc is not a symlink" {
  # When `readlink ~/.zshrc` fails (regular file, missing file, …), the
  # block must not crash and must fall back to the dotfiles-less PATH.
  # Previously the fallback hardcoded $HOME/apps/dotfiles/home/zshrc;
  # this test pins the new "fall through cleanly" contract.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/home"
  cp "$ZSHRC" "$tmp/zshrc"
  # Plain file, not a symlink.
  echo '# placeholder' > "$tmp/home/.zshrc"

  HOME="$tmp/home" PATH="/usr/bin:/bin" bash -c '
    set -e
    sed -n "/^# ── PATH/,/^unset _dotfiles_bin/p" "'"$tmp"'/zshrc" > "'"$tmp"'/path-block.sh"
    # shellcheck disable=SC1091
    . "'"$tmp"'/path-block.sh"
    # Must not contain "apps/dotfiles" anywhere — that would mean the
    # hardcoded fallback fired.
    case ":$PATH:" in
      *":"*"apps/dotfiles"*) echo "FALLBACK FIRED: $PATH"; exit 1 ;;
    esac
    # And $HOME/bin should be present.
    case ":$PATH:" in
      *":'"$tmp"'/home/bin:"*) echo "OK" ;;
      *) echo "MISS HOME/bin: $PATH"; exit 1 ;;
    esac
  '
  rm -rf "$tmp"
}

@test "home/zshrc has DOTFILES_IS_AGENT detection for all known agent contexts" {
  for var in WINDSURF_CASCADE_TERMINAL_KIND CURSOR_AGENT CLAUDE_CODE_SSE_PORT \
             DEVIN_SESSION_ID CODEX_AGENT VSCODE_INJECTION; do
    grep -q "$var" "$ZSHRC" || {
      echo "home/zshrc missing DOTFILES_IS_AGENT guard for $var"
      return 1
    }
  done
  grep -q 'export DOTFILES_IS_AGENT' "$ZSHRC" || {
    echo "home/zshrc must export DOTFILES_IS_AGENT for child processes"
    return 1
  }
}

@test "home/zshrc uses the WebStorm terminal fast path" {
  grep -q 'TERMINAL_EMULATOR' "$ZSHRC"
  grep -q 'JetBrains-JediTerm' "$ZSHRC"
  grep -q 'DOTFILES_JETBRAINS_FAST_SHELL' "$ZSHRC"
  grep -q 'dotfiles-full-shell' "$ZSHRC"
}

@test "WebStorm fast shell omits full interactive helpers" {
  local tmp="$BATS_TEST_TMPDIR/webstorm-fast-shell"
  local node_bin="$tmp/home/.local/share/fnm/node-versions/v20.0.0/installation/bin"
  mkdir -p "$tmp/home"
  ln -s "$ZSHRC" "$tmp/home/.zshrc"
  ln -s "$ZSHRC_AI_TOOLS" "$tmp/home/.zshrc.ai-tools"
  ln -s "$ZSHENV" "$tmp/home/.zshenv"
  mkdir -p "$node_bin"
  printf 'v20.0.0\n' > "$tmp/home/.node-version"
  touch "$node_bin/node"
  chmod +x "$node_bin/node"

  run env \
    HOME="$tmp/home" \
    DOTFILES_DIR="$REPO_ROOT" \
    PATH="/usr/bin:/bin" \
    TERM=xterm-256color \
    TERMINAL_EMULATOR=JetBrains-JediTerm \
    /usr/bin/script -q /dev/null /bin/zsh -dfi -c 'source "$1"; source "$2"; whence -w dotfiles-full-shell; whence -w agent-browser; whence -w gclean || true; command -v node' zsh "$ZSHENV" "$ZSHRC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-full-shell: function"* ]]
  [[ "$output" == *"agent-browser: function"* ]]
  [[ "$output" == *"gclean: none"* ]]
  [[ "$output" == *"$node_bin/node"* ]]
}

@test "home/zshenv bypasses fnm in the WebStorm fast path" {
  local tmp="$BATS_TEST_TMPDIR/zshenv-fast"
  local node_bin="$tmp/home/.local/share/fnm/node-versions/v20.0.0/installation/bin"
  mkdir -p "$node_bin" "$tmp/bin"
  printf 'v20.0.0\n' > "$tmp/home/.node-version"
  touch "$node_bin/node"
  chmod +x "$node_bin/node"
  cat > "$tmp/bin/fnm" <<'FNM'
#!/bin/sh
touch "$FNM_MARKER"
printf 'export FNM_FALLBACK=1\n'
FNM
  chmod +x "$tmp/bin/fnm"

  run env \
    HOME="$tmp/home" \
    PATH="$tmp/bin:/usr/bin:/bin" \
    FNM_MARKER="$tmp/fnm-called" \
    TERMINAL_EMULATOR=JetBrains-JediTerm \
    /bin/zsh -dfc 'source "$1"; print -r -- "$PATH"' zsh "$ZSHENV"

  [ "$status" -eq 0 ]
  [[ "$output" == "$node_bin:"* ]]
  [ ! -e "$tmp/fnm-called" ]
}

@test "home/zshenv falls back to fnm when the fast-path Node is unavailable" {
  local tmp="$BATS_TEST_TMPDIR/zshenv-fallback"
  mkdir -p "$tmp/home" "$tmp/bin"
  cat > "$tmp/bin/fnm" <<'FNM'
#!/bin/sh
touch "$FNM_MARKER"
printf 'export FNM_FALLBACK=1\n'
FNM
  chmod +x "$tmp/bin/fnm"

  run env \
    HOME="$tmp/home" \
    PATH="$tmp/bin:/usr/bin:/bin" \
    FNM_MARKER="$tmp/fnm-called" \
    TERMINAL_EMULATOR=JetBrains-JediTerm \
    /bin/zsh -dfc 'source "$1"; print -r -- "$FNM_FALLBACK"' zsh "$ZSHENV"

  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ -e "$tmp/fnm-called" ]
}

@test "AI tooling skips MLX startup in the WebStorm fast path" {
  grep -q 'DOTFILES_JETBRAINS_FAST_SHELL' "$ZSHRC_AI_TOOLS"
  grep -q 'DOTFILES_FORCE_MLX_STARTUP' "$ZSHRC_AI_TOOLS"
  grep -q 'return 0' "$ZSHRC_AI_TOOLS"
}

@test "agentbrew shell hook is sourced once" {
  [ "$(grep -h 'agentbrew/shell-hook.sh' "$ZSHRC" "$ZSHRC_AI_TOOLS" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "home/zshrc agent-safe guards prevent prompt hangs" {
  # Every interactive prompt that can hang an agent terminal must have
  # a fail-fast guard gated behind DOTFILES_IS_AGENT.
  local missing=()
  grep -q 'unsetopt CORRECT' "$ZSHRC"       || missing+=("unsetopt CORRECT")
  grep -q "alias sudo='sudo -n'" "$ZSHRC"   || missing+=("sudo -n alias")
  grep -q 'GIT_TERMINAL_PROMPT=0' "$ZSHRC"  || missing+=("GIT_TERMINAL_PROMPT=0")
  grep -q 'GIT_EDITOR=true' "$ZSHRC"        || missing+=("GIT_EDITOR=true")
  grep -q 'BatchMode=yes' "$ZSHRC"          || missing+=("ssh BatchMode=yes")
  grep -q 'PAGER=cat' "$ZSHRC"              || missing+=("PAGER=cat")
  grep -q 'EDITOR=true' "$ZSHRC"            || missing+=("EDITOR=true")
  grep -q 'PIP_NO_INPUT=1' "$ZSHRC"         || missing+=("PIP_NO_INPUT=1")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "home/zshrc missing agent-safe guards: ${missing[*]}"
    return 1
  fi
}

@test "home/zshenv sources under zsh without errors" {
  local tmp="$BATS_TEST_TMPDIR/zshenv-clean"
  mkdir -p "$tmp/home"

  run env -u NODE_EXTRA_CA_CERTS HOME="$tmp/home" PATH="/usr/bin:/bin" \
    DOTFILES_CORPORATE_CA_BUNDLES="/nonexistent/a.pem:/nonexistent/b.pem" \
    /bin/zsh -dfc 'source "$1"' zsh "$ZSHENV"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "home/zshenv uses the first existing DOTFILES_CORPORATE_CA_BUNDLES entry" {
  local tmp="$BATS_TEST_TMPDIR/zshenv-ca"
  mkdir -p "$tmp/home"
  : > "$tmp/second.pem"
  : > "$tmp/third.pem"

  run env -u NODE_EXTRA_CA_CERTS HOME="$tmp/home" PATH="/usr/bin:/bin" \
    DOTFILES_CORPORATE_CA_BUNDLES="/nonexistent/first.pem:$tmp/second.pem:$tmp/third.pem" \
    /bin/zsh -dfc 'source "$1"; print -r -- "$NODE_EXTRA_CA_CERTS"' zsh "$ZSHENV"

  [ "$status" -eq 0 ]
  [ "$output" = "$tmp/second.pem" ]
}
