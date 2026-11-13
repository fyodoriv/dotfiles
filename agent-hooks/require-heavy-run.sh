#!/bin/bash
# Blocks full test suites and builds that do not run through heavy-run (#357).
# Receives Claude Code PreToolUse tool input as JSON on stdin.
# Supported single-test runners stay allowed for fast iteration.
# HEAVY_RUN_HOOK=off turns the hook off.

set -euo pipefail
_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=bootstrap-endpoint-path.sh
source "$_hook_dir/bootstrap-endpoint-path.sh"

[ "${HEAVY_RUN_HOOK:-on}" = off ] && exit 0

input=$(cat)
command="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_input.command raw -o - -- - 2>/dev/null || true)"
[ -n "$command" ] || exit 0

# This exact search disables rg configuration and ends option parsing before
# reading the resolved runner file. All other substitutions keep the guard.
_read_only_runner_search=$'^[ \t]*(command[ \t]+-v[ \t]+bats[ \t]*&&[ \t]*)?rg[ \t]+--no-config[ \t]+(-(n|l)[ \t]+)?--[ \t]+\047[A-Za-z0-9_.-]+\047[ \t]+"\\$\\(command[ \t]+-v[ \t]+bats\\)"[ \t]*$'
if [[ "$command" != *$'\n'* && "$command" =~ $_read_only_runner_search ]]; then
  exit 0
fi

# True when the arguments pick one test: a filter (-g, --grep, -t,
# --testNamePattern) with a real value, or an explicit spec path. "." , ".*",
# a folder ("tests/"), and the value of any other flag (--config, --output
# out/res, --outputFile a/b.xml) do not count.
_one_test_args() {
  local a v
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      -g|--grep|-t|--testNamePattern)
        v="${1:-}"
        case "$v" in ""|-*|.|".*") ;; *) return 0 ;; esac
        case "$v" in -*) ;; *) shift || true ;; esac ;;
      -g=*|--grep=*|-t=*|--testNamePattern=*)
        v="${a#*=}"
        case "$v" in ""|.|".*") ;; *) return 0 ;; esac ;;
      --|--headed|--ui|--debug|--list|--quiet|--forbid-only|--fully-parallel|--last-failed|--no-deps|--pass-with-no-tests|--update-snapshots|--coverage|--watch|--run) ;;
      --*=*) ;;
      -c|--*) case "${1:-}" in ""|-*) ;; *) shift ;; esac ;;
      -*|run|test|.|..|./|*/) ;;
      */*|*.*) return 0 ;;
    esac
  done
  return 1
}

# True when the script name is a test or build script.
_heavy_script() {
  case "$1" in test|test:*|test-*|t|build|verify|e2e|e2e:*|e2e-*|ui|ui:*|ui-*) return 0 ;; esac
  return 1
}

# True when the words after an exec-style runner start a Playwright test run.
_playwright_test_run() {
  [ "${1%%@*}" = playwright ] && [ "${2:-}" = test ]
}

# Drop leading flags of a command prefix from the array w. Arguments name the
# flags that take a value, which is dropped too.
_skip_flags() {
  local vf=" $* "
  while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == -* ]]; do
    if [[ "$vf" == *" ${w[0]} "* ]]; then w=("${w[@]:2}"); else w=("${w[@]:1}"); fi
  done
}

# True when the words in w after `command` are a lookup: -v or -V (alone or
# with -p), then only literal names and output redirections. A lookup prints
# where a name resolves and never runs it. Any other word is not proven inert.
_lookup_only() {
  local n names=0
  case "${w[0]:-}" in -v|-V|-pv|-pV|-vp|-Vp) ;; *) return 1 ;; esac
  for n in "${w[@]:1}"; do
    case "$n" in
      '>/dev/null'|'1>/dev/null'|'2>/dev/null'|'&>/dev/null'|'2>&1'|'>&2') ;;
      -*|*[!A-Za-z0-9_.+@/-]*) return 1 ;;
      *) names=$((names + 1)) ;;
    esac
  done
  [ "$names" -gt 0 ]
}

# True when one simple command (no && ; |) is a heavy run.
_is_heavy() {
  local -a w
  read -r -a w <<< "$1" || true
  # Strip VAR=x, control words (if, then, do, ...), and the prefixes time,
  # command, exec, nohup, timeout, env, sudo, nice, caffeinate with their own
  # flags and flag values.
  while [ "${#w[@]}" -gt 0 ]; do
    case "${w[0]}" in
      *=*|if|while|until|then|do|else|elif|'!') w=("${w[@]:1}") ;;
      command)
        w=("${w[@]:1}")
        [ "$_lookup_ok" = 1 ] && _lookup_only && return 1
        _skip_flags ;;
      time|nohup) w=("${w[@]:1}"); _skip_flags ;;
      exec) w=("${w[@]:1}"); _skip_flags -a ;;
      timeout)
        w=("${w[@]:1}"); _skip_flags -s -k --signal --kill-after
        w=("${w[@]:1}") ;;
      env) w=("${w[@]:1}"); _skip_flags -u -S -C ;;
      sudo) w=("${w[@]:1}"); _skip_flags -u -g -h -p -C -D -R -T -U -r -t ;;
      nice) w=("${w[@]:1}"); _skip_flags -n --adjustment ;;
      caffeinate) w=("${w[@]:1}"); _skip_flags -t -w ;;
      *) break ;;
    esac
  done
  [ "${#w[@]}" -gt 0 ] || return 1
  # A path runs the same program: ./node_modules/.bin/playwright, /usr/bin/make.
  w[0]="${w[0]##*/}"
  [ "${w[0]}" = heavy-run ] && return 1
  case "${w[0]}" in npx|bunx) w=("${w[@]:1}"); _skip_flags -p --package -c --call ;; esac
  [ "${#w[@]}" -gt 0 ] || return 1
  local tool="${w[0]##*/}" a
  # npx -y playwright@1 test: a version suffix names the same tool.
  case "$tool" in @*) ;; *) tool="${tool%%@*}" ;; esac
  local -a rest=() raw=("${w[@]:1}")
  local i=0
  # Drop workspace selectors (and their value) so `pnpm --filter web e2e` reads as `pnpm e2e`.
  while [ "$i" -lt "${#raw[@]}" ]; do
    case "${raw[$i]}" in
      --filter|-F|--workspace|-w|--prefix|-C) i=$((i + 2)); continue ;;
    esac
    rest+=("${raw[$i]}"); i=$((i + 1))
  done
  case "$tool" in
    cargo)
      rest=(${raw[@]+"${raw[@]}"})
      # Toolchain selection does not make compilation a light command.
      case "${rest[0]:-}" in
        +stable) rest=("${rest[@]:1}") ;;
        +*) return 0 ;;
      esac
      case "${rest[*]-}" in
        --version|-V|--help|help|"help build"|"build --help"|"test --help"|"metadata --no-deps --format-version 1"|"locate-project --message-format plain") return 1 ;;
      esac
      # Unknown subcommands, variable arguments and response files stay refused.
      return 0 ;;
    rustc)
      rest=(${raw[@]+"${raw[@]}"})
      case "${rest[*]-}" in --version|-V|--help|"--print sysroot") return 1 ;; esac
      return 0 ;;
    npm|yarn|pnpm|bun|turbo)
      # npm exec / pnpm exec / pnpm dlx / bun x / yarn playwright test; turbo run <script>
      case "${rest[0]:-}" in
        exec|dlx|x)
          # Drop flags (-y, --yes, -p pkg, --) between exec and the program, then
          # read the program like a plain command (vitest, jest, turbo run test, ...).
          w=("${rest[@]:1}"); _skip_flags -p --package -c --call
          [ "${#w[@]}" -gt 0 ] || return 1
          _is_heavy "${w[*]}" && return 0
          return 1 ;;
      esac
      if _playwright_test_run "${rest[0]:-}" "${rest[1]:-}"; then
        _one_test_args "${rest[@]:2}" && return 1
        return 0
      fi
      for i in "${!rest[@]}"; do
        a="${rest[$i]}"
        case "$a" in -*|run|run-script) continue ;; esac
        _heavy_script "$a" || return 1
        [ "$a" = verify ] && return 0
        _one_test_args "${rest[@]:$((i + 1))}" && return 1
        return 0
      done
      return 1 ;;
    vitest|jest)
      _one_test_args ${rest[@]+"${rest[@]}"} && return 1
      return 0 ;;
    make|gmake)
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in -n|--dry-run|--just-print|--recon) return 1 ;; esac
      done
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in e2e|test-all|test-force) return 0 ;; esac
      done
      return 1 ;;
    playwright)
      if [ "${rest[0]:-}" = test ]; then
        _one_test_args "${rest[@]:1}" && return 1
        return 0
      fi
      return 1 ;;
    bats)
      rest=(${raw[@]+"${raw[@]}"})
      # A lone version or help flag runs no tests.
      case "${rest[*]-}" in --version|-v|--help|-h) return 1 ;; esac
      local filtered=0
      case "${rest[0]:-}" in
        -f|--filter)
          case "${rest[1]:-}" in
            ""|-*|.|".*") return 0 ;;
          esac
          filtered=1
          rest=("${rest[@]:2}") ;;
      esac
      [ "${#rest[@]}" -gt 0 ] || return 0
      [ "$filtered" -eq 1 ] || [ "${#rest[@]}" -eq 1 ] || return 0
      for a in "${rest[@]}"; do
        case "$a" in
          -*|*[!a-zA-Z0-9_./-]*) return 0 ;;
          *.bats) ;;
          *) return 0 ;;
        esac
      done
      return 1 ;;
  esac
  return 1
}

# Remove heredoc bodies, then replace each quoted string with Q (empty quotes vanish; a lone . or .* stays), so words inside commit messages and PR bodies are never matched.
# Text that runs as a command moves to its own line at the end: $(...) and backticks (quoted or inside a word, so `make -j$(nproc) e2e` keeps its words) and the string after `bash -c` / `sh -c`.
_strip_text() {
  /usr/bin/perl -0777 -pe '
    sub strip {
      my ($s) = @_;
      my @extra;
      $s =~ s/<<-?\s*(["\x27]?)(\w+)\1([^\n]*\n)(?:.*?\n)??[ \t]*\2[ \t]*$/ $3/gms;
      $s =~ s/("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/
        my $q = $1; my $pre = $`; my $in = substr($q, 1, -1);
        my $dq = substr($q, 0, 1) eq "\"";
        my $r = $in =~ m{^\.\*?$} ? $in : length($in) ? "Q" : "";
        if ($dq) {
          while ($in =~ m{\$\(([^)]*)\)|`([^`]*)`}g) { push @extra, defined $1 ? $1 : $2; }
        }
        # Preserve only literal Rust executable identity at command position.
        # Replace its path with the basename so spaces remain one safe token.
        if ($pre =~ m{(?:^|[;&|(){}\n])[ \t]*$}
            && (!$dq || $in !~ m{[\$`\\]})
            && $in =~ m{(?:^|\x2f)(cargo|rustc)$}) {
          $r = $1;
        }
        if ($pre =~ m{(?:^|[;&|(){}\n]|\b(?:then|do|else)\b)[ \t]*(?:[A-Za-z_]\w*=\S*[ \t]+)*(?:(?:sudo|env|time|nohup|exec|command|nice|caffeinate|timeout)[ \t]+(?:-\S+[ \t]+|\d\S*[ \t]+|[A-Z]+[ \t]+)*)*(?:\S*\/)?(?:ba|z|da|k)?sh[ \t]+(?:-\w+[ \t]+(?:[A-Za-z]\w*[ \t]+)?)*-\w*c\w*[ \t]+$}) {
          $in =~ s{\\(["\\$`])}{$1}g if $dq;
          push @extra, strip($in);
        }
        $r/gsex;
      $s =~ s/\$(\((?:[^()]++|(?1))*\))/push @extra, substr($1, 1, -1); "S"/ge;
      $s =~ s/`([^`]*)`/push @extra, $1; "S"/ge;
      # Mark every lifted line with \x01 so its output is known to feed another command.
      return $s . join("", map { my $e = $_; $e =~ s/^(?!\x01)/\x01/mg; "\n$e\n" } @extra);
    }
    $_ = strip($_);
  '
}

stripped="$(printf '%s\n' "$command" | _strip_text)"
# The command -v lookup allowance holds only for a top-level probe whose output
# feeds nothing: no pipe (| or |&) or process substitution anywhere in the
# command, and not a line lifted out of $(...), backticks, sh -c, or eval text.
_piped=0
grep -qE '(^|[^|])\|([^|]|$)|[<>]\(' <<< "$stripped" && _piped=1
while IFS= read -r line; do
  _lookup_ok=1
  [ "$_piped" -eq 0 ] || _lookup_ok=0
  case "$line" in $'\x01'*) _lookup_ok=0; line="${line#$'\x01'}" ;; esac
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    case "$seg" in heavy-run|heavy-run\ *) continue ;; esac
    if _is_heavy "$seg"; then
      echo "BLOCKED: a full test suite or build must queue on the Mac-wide lock. Run this as \`heavy-run <command>\`." >&2
      exit 2
    fi
  done < <(printf '%s\n' "$line" | sed -E 's/(&&|\|\||;|\||[(){}])/\n/g')
done <<< "$stripped"

exit 0
