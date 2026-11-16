#!/bin/bash
# Blocks local test runs inside a dotfiles checkout. Tests run on hosted CI
# only (owner decision 2026-11-16: "Lint local, tests on CI").
# Receives Claude Code PreToolUse tool input as JSON on stdin.
# Blocked there: bats, bin/bats-affected, make check, make test*, make e2e,
# also when started by xargs, find -exec, npx, bunx, npm exec or eval.
# Allowed: make lint*, shellcheck, rg bats, and any command outside a dotfiles
# checkout. A checkout is a folder (or a parent of it) that holds both
# agent-hooks/require-heavy-run.sh and bin/dotfiles-doctor.
# DOTFILES_ALLOW_LOCAL_TESTS=1 turns the hook off. It works only when exported
# before Claude Code or Codex starts. Setting it inside an agent command has no
# effect: the hook reads its own environment, not the command text.

set -euo pipefail

[ "${DOTFILES_ALLOW_LOCAL_TESTS:-}" = 1 ] && exit 0

input=$(cat)
command="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_input.command raw -o - -- - 2>/dev/null || true)"
[ -n "$command" ] || exit 0

# Fast exit: most commands hold no word that can start a test run.
case "$command" in
  *bats*|*make*) ;;
  *) exit 0 ;;
esac

# Load the shared PATH setup only past the fast exit: the steps above use
# absolute paths, and the bootstrap doubles the hook's time.
_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=bootstrap-endpoint-path.sh
source "$_hook_dir/bootstrap-endpoint-path.sh"

cwd="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract cwd raw -o - -- - 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

# Quoted text is data, not a command: drop heredoc bodies and replace each
# quoted string with Q. The string after `bash -c`, `sh -c`, `eval` or
# `npx -c`/`npm exec -c` runs as a command,
# so it moves to its own line at the end. Quoted words that look like a path
# stay, so `cd "~/apps/dotfiles"` still names its folder.
_strip_text() {
  /usr/bin/perl -0777 -pe '
    my @extra;
    s/<<-?\s*(["\x27]?)(\w+)\1([^\n]*\n)(?:.*?\n)??[ \t]*\2[ \t]*$/ $3/gms;
    s/\b(?:ba|z|da)?sh[ \t]+(?:-\w+[ \t]+)*-\w*c\w*[ \t]+("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/
      my $q = $1; push @extra, substr($q, 1, -1); "sh -c Q"/gse;
    s/\b((?:npx|bunx|(?:npm|pnpm)(?:[ \t]+(?:--prefix|-w|--workspace|-C|--dir|--filter|-F|--loglevel)[ \t]+[^\s;&|]+|[ \t]+-[^\s;&|]+)*[ \t]+(?:exec|x|dlx))(?:[ \t]+-[^\s;&|]+)*?[ \t])(?:-c|--call)[ \t=]+("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/
      my ($p, $q) = ($1, $2); push @extra, substr($q, 1, -1); "${p}-c Q"/gse;
    s/\beval[ \t]+("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/
      my $q = $1; push @extra, substr($q, 1, -1); "eval Q"/gse;
    s/("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/
      my $in = substr($1, 1, -1);
      $in =~ m{^[\w.~\x2f\$-]*\x2f[\w.~\x2f\$-]*$} ? $in : length($in) ? "Q" : ""/gse;
    s/\$\(([^()]*)\)/push @extra, $1; "S"/ge;
    s/`([^`]*)`/push @extra, $1; "S"/ge;
    $_ .= join("", map { "\n$_\n" } @extra);
  '
}

# True when dir (or a parent of it) is a dotfiles checkout.
_is_dotfiles_checkout() {
  local d="$1"
  # shellcheck disable=SC2016,SC2088  # the patterns match literal text
  case "$d" in
    "~") d="$HOME" ;;
    "~/"*) d="$HOME/${d#\~/}" ;;
    '$HOME'|'${HOME}') d="$HOME" ;;
    '$HOME/'*) d="$HOME/${d#\$HOME/}" ;;
    '${HOME}/'*) d="$HOME/${d#\$\{HOME\}/}" ;;
  esac
  case "$d" in /*) ;; *) d="$cwd/$d" ;; esac
  while [ -n "$d" ] && [ "$d" != / ]; do
    if [ -f "$d/agent-hooks/require-heavy-run.sh" ] && [ -f "$d/bin/dotfiles-doctor" ]; then
      return 0
    fi
    d="${d%/*}"
  done
  return 1
}

stripped="$(printf '%s\n' "$command" | _strip_text)"

# Folders the command may run in: the session folder plus every `cd X`,
# `make -C X`, `git -C X`, and `--directory X` target it names.
dirs=("$cwd")
while IFS= read -r d; do
  [ -n "$d" ] && dirs+=("$d")
done < <(printf '%s\n' "$stripped" \
  | /usr/bin/perl -ne 'while (/(?:^|[;&|(]\s*|\s)(?:cd|-C|--directory|--directory=)[ \t=]+([^\s;&|()]+)/g) { print "$1\n" }')

# True when one simple command runs a test suite.
_is_test_run() {
  local -a w
  read -r -a w <<< "$1" || true
  while [ "${#w[@]}" -gt 0 ]; do
    case "${w[0]}" in
      *=*|if|while|until|then|do|else|elif|'!'|time|nohup|exec|command|sudo|caffeinate|env|eval|heavy-run|--exclusive)
        w=("${w[@]:1}") ;;
      nice|timeout) w=("${w[@]:1}")
        while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == -* || "${w[0]}" =~ ^[0-9.]+[smhd]?$ ]]; do w=("${w[@]:1}"); done ;;
      -*) w=("${w[@]:1}") ;;
      *) break ;;
    esac
  done
  [ "${#w[@]}" -gt 0 ] || return 1
  local tool="${w[0]##*/}" a
  case "$tool" in
    npm|pnpm)
      # `npm exec X`, `npm x X` and `pnpm dlx X` start X, like npx. Global
      # flags (and the values of the common ones) may come first.
      w=("${w[@]:1}")
      while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == -* ]]; do
        case "${w[0]}" in
          --prefix|-w|--workspace|-C|--dir|--filter|-F|--loglevel) w=("${w[@]:2}") ;;
          *) w=("${w[@]:1}") ;;
        esac
      done
      case "${w[0]:-}" in exec|x|dlx) _is_test_run "npx ${w[*]:1}"; return ;; esac
      return 1 ;;
    xargs|npx|bunx)
      # A launcher: skip its own flags (and their values), then judge the
      # command it starts.
      w=("${w[@]:1}")
      while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == -* ]]; do
        case "$tool:${w[0]}" in
          xargs:-[adEIJLnPRSs]|xargs:--arg-file|xargs:--delimiter|xargs:--max-args|xargs:--max-chars|xargs:--max-procs) w=("${w[@]:2}") ;;
          # GNU `--replace` takes no separate value (`--replace=R` is one word).
          *) w=("${w[@]:1}") ;;
        esac
      done
      [ "${#w[@]}" -gt 0 ] || return 1
      _is_test_run "${w[*]}"
      return ;;
    find)
      # `find ... -exec CMD ...` starts CMD.
      local i
      for i in "${!w[@]}"; do
        case "${w[$i]}" in -exec|-execdir|-ok|-okdir)
          _is_test_run "${w[*]:$((i + 1))}" && return 0 ;;
        esac
      done
      return 1 ;;
    bats|bats-affected|bats-affected.sh)
      # A lone version or help flag runs no tests.
      case "${w[*]:1}" in --version|-v|--help|-h) return 1 ;; esac
      return 0 ;;
    make|gmake)
      for a in "${w[@]:1}"; do
        case "$a" in -n|--dry-run|--just-print|--recon) return 1 ;; esac
      done
      for a in "${w[@]:1}"; do
        case "$a" in check|test|test-*|test_*|e2e|e2e-*) return 0 ;; esac
      done
      return 1 ;;
  esac
  return 1
}

hit=""
while IFS= read -r line; do
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [ -n "$seg" ] || continue
    if _is_test_run "$seg"; then hit="$seg"; break 2; fi
  # An empty {} is an xargs or find placeholder, not a brace group.
  done < <(printf '%s\n' "$line" | sed -E 's/\{\}/ARG/g; s/(&&|\|\||;|\||[(){}])/\n/g')
done <<< "$stripped"
[ -n "$hit" ] || exit 0

for d in "${dirs[@]}"; do
  if _is_dotfiles_checkout "$d"; then
    cat >&2 <<'MSG'
BLOCKED: dotfiles tests run on CI only, not on this Mac.
Run `make lint` (or `shellcheck <file>`) locally. Then push the branch and read CI:
  gh pr checks <number> --repo fyodoriv/dotfiles --watch
  gh run view <run-id> --log-failed
See docs/ci-setup.md ("Lint local, tests on CI").
MSG
    exit 2
  fi
done
exit 0
