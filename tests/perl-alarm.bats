#!/usr/bin/env bats
# GNU parallel (bats --jobs) starts each job with SIGALRM ignored. An ignored
# signal stays ignored across exec, so `perl -e 'alarm N; exec @ARGV'` never
# times out unless it resets the handler first. See issue #370.

# Run a command with SIGALRM ignored, like a bats --jobs worker.
_with_alarm_ignored() {
  perl -e '$SIG{ALRM} = "IGNORE"; exec @ARGV' "$@"
}

_alarm_violations() {
  python3 - "$@" <<'PY'
import os
from pathlib import Path
import re
import sys

# Read complete literal snippets; shell/Perl comment lines cannot arm a timer.
snippet = re.compile(r"\bperl\b(?:\\\n|[^\n])*?\s-e\s*(['\"])((?:\\.|(?!\1).)*?)\1", re.S)
handler = re.compile(r"\\?\$SIG\s*\{\s*['\"]?ALRM['\"]?\s*\}\s*=\s*(?:['\"]DEFAULT['\"]|sub\b)")
self_test = Path(os.environ["BATS_TEST_FILENAME"]).resolve()
violations = []
for root in map(Path, sys.argv[1:]):
    for path in ([root] if root.is_file() else root.rglob("*")):
        if not path.is_file() or path.is_symlink() or path.resolve() == self_test:
            continue
        text = path.read_text(errors="ignore")
        text = re.sub(r"(?m)^[ \t]*#.*$", "", text)
        for match in snippet.finditer(text):
            body = match.group(2)
            for alarm in re.finditer(r"\balarm(?:\s|\()", body):
                assignments = list(re.finditer(r"\\?\$SIG\s*\{\s*['\"]?ALRM['\"]?\s*\}\s*=", body[:alarm.start()]))
                reset = handler.match(body, assignments[-1].start()) if assignments else None
                if not reset:
                    line = text.count("\n", 0, match.start()) + 1
                    violations.append(f"{path}:{line}: alarm lacks an active preceding handler")
                    break
print("\n".join(violations), end="\n" if violations else "")
sys.exit(bool(violations))
PY
}

@test "every literal Perl alarm wrapper resets SIGALRM before arming it" {
  run _alarm_violations bin lib tests
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "alarm guard rejects an unsafe multiline wrapper" {
  local dir="$BATS_TEST_TMPDIR/multiline"
  mkdir -p "$dir"
  printf "perl -e '\n  alarm 30;\n  exec @ARGV;\n'\n" > "$dir/runner.sh"
  run _alarm_violations "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *runner.sh* ]]
}

@test "alarm guard rejects line-continued Perl commands" {
  local dir="$BATS_TEST_TMPDIR/continued"
  mkdir -p "$dir"
  cat > "$dir/runner.sh" <<'SH'
perl \
  -e '
    alarm 30;
    exec @ARGV;
  '
SH
  run _alarm_violations "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *runner.sh* ]]
}

@test "alarm guard keeps safe multiline handlers" {
  local dir="$BATS_TEST_TMPDIR/safe"
  mkdir -p "$dir"
  cat > "$dir/runner.sh" <<'SH'
perl -e '
  $SIG{ALRM} = "DEFAULT";
  alarm 30;
  exec @ARGV;
'
SH
  run _alarm_violations "$dir"
  [ "$status" -eq 0 ]
}

@test "alarm guard skips a morning stub comment but checks other morning code" {
  local dir="$BATS_TEST_TMPDIR/morning"
  mkdir -p "$dir"
  printf "# Strip the alarm wrapper: perl -e 'alarm 30; exec @ARGV' <cmd> <args>\n" > "$dir/morning.bats"
  run _alarm_violations "$dir"
  [ "$status" -eq 0 ]
  printf "perl -e 'alarm 30; exec @ARGV'\n" >> "$dir/morning.bats"
  run _alarm_violations "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *morning.bats* ]]
}

@test "alarm guard rejects ignored or late signal handlers" {
  local dir="$BATS_TEST_TMPDIR/order"
  mkdir -p "$dir"
  cat > "$dir/runner.sh" <<'SH'
perl -e '$SIG{ALRM} = "IGNORE"; alarm 30; exec @ARGV'
perl -e 'alarm 30; $SIG{ALRM} = "DEFAULT"; exec @ARGV'
perl -e '$SIG{ALRM} = "DEFAULT"; $SIG{ALRM} = "IGNORE"; alarm 30; exec @ARGV'
perl -e '$SIG{ALRM} = "DEFAULT"; alarm 1; $SIG{ALRM} = "IGNORE"; alarm 2; exec @ARGV'
SH
  run _alarm_violations "$dir"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 4 ]
}

@test "bin/morning _timeout still times out when SIGALRM is ignored" {
  # Source only the _timeout helper; hide gtimeout/timeout so the perl path runs.
  local fn
  fn="$(sed -n '/^_timeout()/,/^}/p' bin/morning)"
  [ -n "$fn" ]
  local nopath="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$nopath"
  ln -s "$(command -v perl)" "$nopath/perl"
  ln -s "$(command -v sleep)" "$nopath/sleep"
  SECONDS=0
  run _with_alarm_ignored env PATH="$nopath" /bin/bash -c "$fn"$'\n'"_timeout 1 sleep 30"
  [ "$SECONDS" -lt 10 ]
  [ "$status" -ne 0 ]
}

@test "bin/dotfiles-doctor _timeout still times out when SIGALRM is ignored" {
  local fn
  fn="$(sed -n '/^_timeout()/,/^}/p' bin/dotfiles-doctor)"
  [ -n "$fn" ]
  local nopath="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$nopath"
  ln -s "$(command -v perl)" "$nopath/perl"
  ln -s "$(command -v sleep)" "$nopath/sleep"
  SECONDS=0
  run _with_alarm_ignored env PATH="$nopath" /bin/bash -c "$fn"$'\n'"_timeout 1 sleep 30"
  [ "$SECONDS" -lt 10 ]
  [ "$status" -ne 0 ]
}
