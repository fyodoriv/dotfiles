#!/usr/bin/env bats
# Tests for bin/dotfiles-telemetry and its hooks: the consent question, the
# off switches, the privacy allowlist, and the reliable daily send.
# No test sends anything real: a fake curl records the request instead.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
  export DOTFILES_COMMANDS_FILE="$TEST_DIR/commands.jsonl"
  export DOTFILES_TELEMETRY_STATE="$TEST_DIR/telemetry.json"
  export DOTFILES_INSTALL_RECEIPT="$TEST_DIR/install-receipt.json"
  # The gains event (tests/telemetry-gains.bats) would add a request and time
  # a real zsh in every send here: a ship day far away turns it off.
  export DOTFILES_TELEMETRY_TEST_GAINS_SINCE="9999-12-31"
  export DOTFILES_TELEMETRY_URL="http://127.0.0.1:9/fake"
  export DOTFILES_TELEMETRY_KEY_FILE="$TEST_DIR/key"
  export DOTFILES_POSTHOG_KEY="phc_testFakeKey1"
  unset DO_NOT_TRACK CI DOTFILES_TELEMETRY DOTFILES_TELEMETRY_TTY
  : >"$DOTFILES_TELEMETRY_KEY_FILE"
  FAKE="$TEST_DIR/fake-curl"
  cat >"$FAKE" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"${FAKE_LOG:?}.args"
cat >>"$FAKE_LOG"
echo >>"$FAKE_LOG"
printf '%s' "${FAKE_CODE:-200}"
SH
  chmod +x "$FAKE"
  export DOTFILES_TELEMETRY_CURL="$FAKE" FAKE_LOG="$TEST_DIR/requests.log"
  TEL="$REPO/bin/dotfiles-telemetry"
  NOW="$(date -u +%FT%TZ)"
  printf '%s\n' \
    "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"seconds_saved\":3,\"units\":1}" \
    "{\"task\":\"doctor\",\"timestamp\":\"$NOW\",\"seconds_saved\":2,\"units\":1,\"pass\":40,\"fail\":1,\"path\":\"canary-dir/secret.txt\",\"message\":\"canary text\"}" \
    >"$DOTFILES_STATS_FILE"
}

teardown() {
  if [ -f "$TEST_DIR/server.pid" ]; then kill "$(cat "$TEST_DIR/server.pid")" 2>/dev/null || true; fi
  rm -rf "$TEST_DIR"
}

# A yes covers only later events. say_yes also moves both cursors back to the
# start, so the lines a test seeded count as recorded after the yes.
say_yes() {
  bash "$TEL" on >/dev/null
  set_state '.sent = 0 | .sent_commands = 0'
}
# No state file means nobody answered: a run that only reads never creates it.
consent() { if [ -e "$DOTFILES_TELEMETRY_STATE" ]; then jq -r .consent "$DOTFILES_TELEMETRY_STATE"; else echo unset; fi; }
# Fakes for the two tools that install the LaunchAgent. The fake chezmoi
# "renders" the template by copying it; the fake launchctl logs its arguments.
# It keeps a marker file while the job is "loaded": print answers from it,
# bootstrap sets it, bootout clears it. While $TEST_DIR/bootstrap-fail-once
# exists, the next bootstrap fails with exit 5 (as launchd does right after a
# bootout) and removes that file.
refute() { if "$@"; then return 1; fi; }
fake_agent_tools() {
  cat >"$TEST_DIR/fake-launchctl" <<SH
#!/bin/bash
printf '%s\\n' "\$*" >>"$TEST_DIR/launchctl.log"
case "\$1" in
  print) [ -e "$TEST_DIR/agent-loaded" ] ;;
  bootout) rm -f "$TEST_DIR/agent-loaded" ;;
  bootstrap)
    if [ -e "$TEST_DIR/bootstrap-fail-once" ]; then rm -f "$TEST_DIR/bootstrap-fail-once"; exit 5; fi
    [ ! -e "$TEST_DIR/bootstrap-fail-always" ] || exit 5
    : >"$TEST_DIR/agent-loaded" ;;
esac
SH
  printf '#!/bin/bash\n[ "$1" = "execute-template" ] || exit 1\ncat\n' >"$TEST_DIR/fake-chezmoi"
  chmod +x "$TEST_DIR/fake-launchctl" "$TEST_DIR/fake-chezmoi"
  export DOTFILES_TELEMETRY_LAUNCHCTL="$TEST_DIR/fake-launchctl" DOTFILES_TELEMETRY_CHEZMOI="$TEST_DIR/fake-chezmoi"
  PLIST="$HOME/Library/LaunchAgents/com.dotfiles.telemetry.plist"
}
# A jq that fails once (exit 5) when $TEST_DIR/jq-fail exists, then works.
# It fails every time while $TEST_DIR/jq-fail-always exists.
fail_once_jq() {
  mkdir -p "$TEST_DIR/jqshim"
  printf '#!/bin/bash\n[ ! -e "%s/jq-fail-always" ] || exit 5\nif [ -e "%s/jq-fail" ]; then rm -f "%s/jq-fail"; exit 5; fi\nexec "%s" "$@"\n' \
    "$TEST_DIR" "$TEST_DIR" "$TEST_DIR" "$(command -v jq)" >"$TEST_DIR/jqshim/jq"
  chmod +x "$TEST_DIR/jqshim/jq"
}
requests() { if [ -f "$FAKE_LOG" ]; then jq -s 'length' "$FAKE_LOG"; else echo 0; fi; }
set_state() { jq -c "$1" "$DOTFILES_TELEMETRY_STATE" >"$TEST_DIR/state.new" && mv "$TEST_DIR/state.new" "$DOTFILES_TELEMETRY_STATE"; }
# Print only bounded counts and fixed completion labels, never transport data.
assert_request_count() {
  local expected="$1" actual="$2" returned="$3" command_status="$4"
  [[ "$expected" =~ ^[0-9]{1,4}$ ]] || expected=unknown
  [[ "$actual" =~ ^[0-9]{1,4}$ ]] || actual=unknown
  case "$returned" in yes|no) ;; *) returned=unknown ;; esac
  [[ "$command_status" =~ ^[0-9]{1,3}$ ]] || command_status=unknown
  if [ "$expected" != unknown ] && [ "$actual" = "$expected" ] && [ "$returned" = yes ] && [ "$command_status" = 0 ]; then return 0; fi
  printf 'expected=%s observed=%s foreground_returned=%s status=%s\n' "$expected" "$actual" "$returned" "$command_status" >&2
  return 1
}
# bin/dotfiles writes its timing line in the background: wait for line $1.
wait_for_command_lines() {
  local tries=0
  until [ -f "$DOTFILES_COMMANDS_FILE" ] && [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -ge "$1" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || return 1
    sleep 0.05
  done
}
# seed_lines N: N stats lines at the current time; `units` is the line number.
seed_lines() {
  local i
  for ((i = 1; i <= $1; i++)); do
    printf '{"task":"sync","timestamp":"%s","units":%d}\n' "$NOW" "$i"
  done >"$DOTFILES_STATS_FILE"
}

# ── The default key file ────────────────────────────────────────────────
@test "config/telemetry-key is empty or one write-only project key" {
  [ -f "$REPO/config/telemetry-key" ]
  [ "$(wc -l <"$REPO/config/telemetry-key")" -le 1 ]
  [[ "$(cat "$REPO/config/telemetry-key")" =~ ^(phc_[A-Za-z0-9]+)?$ ]]
}

@test "key lookup: env, then the default file; status names the source, never the value" {
  say_yes
  run bash "$TEL" status
  [[ "$output" == *"key: env"* ]]
  [[ "$output" != *phc_* ]]
  export DOTFILES_POSTHOG_KEY=""
  run bash "$TEL" status
  [[ "$output" == *"key: none"* ]]
  [[ "$output" == *"telemetry: off (no key"* ]]
  echo "phc_FileKey123" >"$DOTFILES_TELEMETRY_KEY_FILE"
  run bash "$TEL" status
  [[ "$output" == *"key: default"* ]]
  [[ "$output" == *"telemetry: on"* ]]
  [[ "$output" != *phc_* ]]
  echo "not a key; rm -rf" >"$DOTFILES_TELEMETRY_KEY_FILE"
  run bash "$TEL" status
  [[ "$output" == *"key: none"* ]]
}

@test "a key that is not phc_ plus letters and digits is no key: env, file, Keychain" {
  say_yes
  fake_security="$TEST_DIR/fake-security"
  printf '#!/bin/bash\necho called >>"%s/security.calls"\necho "%s"\n' "$TEST_DIR" 'phc_bad key; rm' >"$fake_security"
  chmod +x "$fake_security"
  export DOTFILES_TELEMETRY_SECURITY="$fake_security"
  for bad in "phc_with_underscore" "phc_" "sk_live123" "phc_abc def" 'phc_abc$(id)'; do
    export DOTFILES_POSTHOG_KEY="$bad"
    run bash "$TEL" status
    [[ "$output" == *"key: none"* ]] || { echo "$bad: $output"; return 1; }
    run bash "$TEL" send
    [[ "$output" == *"no key"* ]]
  done
  [ "$(requests)" -eq 0 ]
}

@test "the Keychain is read last, and only when the env and the file hold no key" {
  say_yes
  fake_security="$TEST_DIR/fake-security"
  printf '#!/bin/bash\necho called >>"%s/security.calls"\necho phc_FromKeychain9\n' "$TEST_DIR" >"$fake_security"
  chmod +x "$fake_security"
  export DOTFILES_TELEMETRY_SECURITY="$fake_security"
  run bash "$TEL" status
  [[ "$output" == *"key: env"* ]]
  export DOTFILES_POSTHOG_KEY=""
  echo "phc_FileKey123" >"$DOTFILES_TELEMETRY_KEY_FILE"
  run bash "$TEL" status
  [[ "$output" == *"key: default"* ]]
  [ ! -e "$TEST_DIR/security.calls" ]
  : >"$DOTFILES_TELEMETRY_KEY_FILE"
  run bash "$TEL" status
  [[ "$output" == *"key: keychain"* ]]
  [[ "$output" != *phc_* ]]
  [ "$(wc -l <"$TEST_DIR/security.calls" | tr -d ' ')" -eq 1 ]
}

@test "with no key at all, the daily path looks for one at most once an hour" {
  say_yes
  fake_security="$TEST_DIR/fake-security"
  printf '#!/bin/bash\necho called >>"%s/security.calls"\n' "$TEST_DIR" >"$fake_security"
  chmod +x "$fake_security"
  export DOTFILES_TELEMETRY_SECURITY="$fake_security" DOTFILES_POSTHOG_KEY=""
  bash "$TEL" daily
  bash "$TEL" daily
  bash "$TEL" daily
  [ "$(wc -l <"$TEST_DIR/security.calls" | tr -d ' ')" -eq 1 ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.lock" ]
}

@test "no key sends nothing" {
  say_yes
  export DOTFILES_POSTHOG_KEY=""
  run bash "$TEL" send
  [[ "$output" == *"no key"* ]]
  [ "$(requests)" -eq 0 ]
}

# ── Consent ─────────────────────────────────────────────────────────────
@test "a new install is unset, and unset sends nothing" {
  run bash "$TEL" status
  [[ "$output" == *"telemetry: off (not asked yet"* ]]
  [[ "$output" == *"consent: unset"* ]]
  run bash "$TEL" send
  [[ "$output" == *"not sent (not asked yet"* ]]
  bash "$TEL" daily
  [ "$(requests)" -eq 0 ]
}

@test "the question is loud: heading, example event, promise, where it goes, how to change" {
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [ "$status" -eq 0 ]
  for text in "Help make dotfiles faster: share anonymous performance numbers?" \
    '"event": "dotfiles.command"' '"command": "doctor"' '"duration_ms": 1840' '"runtime": "shell"' \
    "never a path, file name, host name, user name" "argument, message, or content" \
    "No person profile" "request IP address, like any web server" \
    "GeoIP lookup is disabled" "location is stored" "Only events recorded after your yes" \
    "An example event:" "bin/dotfiles-telemetry" "docs/observability.md#telemetry" "PostHog EU" \
    "dotfiles telemetry off" "Share anonymous performance numbers? [Y/n]" "telemetry: on."; do
    [[ "$output" == *"$text"* ]] || { echo "missing: $text"; echo "$output"; return 1; }
  done
  [ "$(consent)" = "yes" ]
}

@test "y records yes, with the day" {
  printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash "$TEL" ask --install 2>/dev/null
  [ "$(consent)" = "yes" ]
  [ "$(jq -r .consent_at "$DOTFILES_TELEMETRY_STATE")" = "$(date -u +%F)" ]
}

@test "Enter records yes" {
  printf '\n' | DOTFILES_TELEMETRY_TTY=1 bash "$TEL" ask --install 2>/dev/null
  [ "$(consent)" = "yes" ]
}

@test "on the first-run path Enter is not an answer: only a typed y or n is" {
  run bash -c "printf '\n\n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [[ "$output" == *"Share anonymous performance numbers? [y/n]"* ]]
  [[ "$output" == *"Please answer y or n."* ]]
  [[ "$output" == *"no answer, so nothing is sent"* ]]
  [ "$(consent)" = "unset" ]
  run bash -c "printf '\ny\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [ "$(consent)" = "yes" ]
}

# A real terminal (a pty from python): an Enter typed before the question
# shows must not answer it, not even at install, where Enter means yes.
@test "keys typed before the question shows are thrown away" {
  command -v python3 >/dev/null 2>&1 || skip "python3 is needed for a pty"
  cat >"$TEST_DIR/early-enter.py" <<'PY'
import os, pty, select, sys, time
tel, state = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    time.sleep(0.5)  # the early Enter is in the terminal buffer before the script starts
    os.execvp("bash", ["bash", tel, "ask", "--install"])
os.write(fd, b"\n")
seen = b""
deadline = time.time() + 30
while b"[Y/n]" not in seen and time.time() < deadline:
    if select.select([fd], [], [], 0.2)[0]:
        seen += os.read(fd, 4096)
time.sleep(1)
early = open(state).read() if os.path.exists(state) else ""
os.write(fd, b"n\n")
while time.time() < deadline:  # read to the end, or the child cannot exit
    try:
        if select.select([fd], [], [], 0.2)[0] and not os.read(fd, 4096):
            break
    except OSError:
        break
os.waitpid(pid, 0)
sys.exit(1 if '"consent":"yes"' in early or b"[Y/n]" not in seen else 0)
PY
  run python3 "$TEST_DIR/early-enter.py" "$TEL" "$DOTFILES_TELEMETRY_STATE"
  [ "$status" -eq 0 ]
  [ "$(consent)" = "no" ]
}

@test "a yes covers only later events: nothing recorded before it is sent" {
  seed_lines 300
  echo "{\"command\":\"doctor\",\"timestamp\":\"$NOW\",\"ok\":true,\"duration_ms\":12}" >"$DOTFILES_COMMANDS_FILE"
  bash "$TEL" on >/dev/null
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "300" ]
  [ "$(jq -r .sent_commands "$DOTFILES_TELEMETRY_STATE")" = "1" ]
  run bash "$TEL" status
  [[ "$output" == *"pending: 0 event(s)"* ]]
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(requests)" -eq 0 ]
  printf '{"task":"sync","timestamp":"%s","units":9001}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
  [ "$(jq -s -c '[.[].batch[].properties.units]' "$FAKE_LOG")" = "[9001]" ]
  # A second yes changes nothing; events recorded while the answer was no stay unsent.
  printf '{"task":"sync","timestamp":"%s","units":9002}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" on >/dev/null
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "301" ]
  bash "$TEL" off >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":9003}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" on >/dev/null
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "303" ]
}

@test "n records no, and no sends nothing" {
  run bash -c "printf 'n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [[ "$output" == *"telemetry: off. Nothing is sent. Turn it on any time: dotfiles telemetry on"* ]]
  [ "$(consent)" = "no" ]
  run bash "$TEL" send
  [[ "$output" == *"not sent (you said no"* ]]
  bash "$TEL" daily
  [ "$(requests)" -eq 0 ]
}

@test "another answer asks again; no answer at all stays unset" {
  run bash -c "printf 'maybe\nn\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [[ "$output" == *"Please answer y or n."* ]]
  [ "$(consent)" = "no" ]
  rm -f "$DOTFILES_TELEMETRY_STATE"
  run bash -c "DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask </dev/null"
  [[ "$output" == *"no answer, so nothing is sent"* ]]
  [ "$(consent)" = "unset" ]
}

@test "a non-interactive install asks nothing and stays unset" {
  run bash -c "bash '$TEL' ask --install </dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"telemetry: not asked (no terminal), so nothing is sent."* ]]
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "unset" ]
  run bash -c "printf 'y\n' | CI=1 DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "unset" ]
}

@test "install opt-outs record no without a question: --no-telemetry, DOTFILES_TELEMETRY=0, DO_NOT_TRACK" {
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install --no"
  [[ "$output" == *"telemetry: off (--no-telemetry). Nothing is sent."* ]]
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "no" ]
  rm -f "$DOTFILES_TELEMETRY_STATE"
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY=0 DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [[ "$output" == *"telemetry: off (DOTFILES_TELEMETRY=0)"* ]]
  [ "$(consent)" = "no" ]
  rm -f "$DOTFILES_TELEMETRY_STATE"
  run bash -c "printf 'y\n' | DO_NOT_TRACK=1 DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [[ "$output" == *"telemetry: off (DO_NOT_TRACK is set)"* ]]
  [ "$(consent)" = "no" ]
}

@test "an explicit opt-out at a re-install records no over a stored yes" {
  for optout in "ask --install --no" "DOTFILES_TELEMETRY=0 ask --install" "DO_NOT_TRACK=1 ask --install"; do
    say_yes
    case "$optout" in
      DOTFILES_TELEMETRY=0*) DOTFILES_TELEMETRY=0 run bash "$TEL" ask --install ;;
      DO_NOT_TRACK=1*) DO_NOT_TRACK=1 run bash "$TEL" ask --install ;;
      *) run bash "$TEL" ask --install --no ;;
    esac
    [[ "$output" == *"telemetry: off ("* ]]
    [ "$(consent)" = "no" ] || { echo "$optout kept a yes"; return 1; }
  done
}

@test "a re-install never asks again and never flips a no" {
  bash "$TEL" off >/dev/null
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [[ "$output" == *"your answer is no"* ]]
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "no" ]
  say_yes
  run bash -c "printf 'n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "yes" ]
}

@test "a corrupt state file is unset, sends nothing, and never resends the log" {
  say_yes
  printf '{"install_id": "broken' >"$DOTFILES_TELEMETRY_STATE"
  run bash "$TEL" status
  [[ "$output" == *"consent: unset"* ]]
  [[ "$output" == *"pending: 0 event(s)"* ]]
  bash "$TEL" daily
  run bash "$TEL" send
  [[ "$output" == *"not sent (not asked yet"* ]]
  [ "$(requests)" -eq 0 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "2" ]
  [[ "$(jq -r .install_id "$DOTFILES_TELEMETRY_STATE")" =~ ^[0-9a-f]{32}$ ]]
}

@test "a state file from before the question is unset; an old off is no" {
  echo '{"install_id":"0123456789abcdef0123456789abcdef","sent":0,"enabled":true,"last_send":"","noticed":true}' >"$DOTFILES_TELEMETRY_STATE"
  run bash "$TEL" status
  [[ "$output" == *"consent: unset"* ]]
  bash "$TEL" daily
  run bash "$TEL" send
  [ "$(requests)" -eq 0 ]
  echo '{"install_id":"0123456789abcdef0123456789abcdef","sent":0,"enabled":false,"last_send":"","noticed":true}' >"$DOTFILES_TELEMETRY_STATE"
  run bash "$TEL" status
  [[ "$output" == *"consent: no"* ]]
}

@test "telemetry on records yes and shows the example and the promise; off records no" {
  run bash "$TEL" on
  [[ "$output" == *'"event": "dotfiles.command"'* ]]
  [[ "$output" == *"never a path, file name, host name, user name"* ]]
  [ "$(consent)" = "yes" ]
  run bash "$TEL" status
  [[ "$output" == *"telemetry: on"* ]]
  [[ "$output" == *"consent: yes (given $(date -u +%F))"* ]]
  bash "$TEL" off >/dev/null
  [ "$(consent)" = "no" ]
  run bash "$TEL" status
  [[ "$output" == *"telemetry: off (you said no"* ]]
}

@test "DO_NOT_TRACK, CI, and DOTFILES_TELEMETRY=0 block a send whatever the answer is" {
  say_yes
  DO_NOT_TRACK=1 run bash "$TEL" send
  [[ "$output" == *"DO_NOT_TRACK"* ]]
  CI=true run bash "$TEL" send
  [[ "$output" == *"CI is set"* ]]
  DOTFILES_TELEMETRY=0 run bash "$TEL" send
  [[ "$output" == *"DOTFILES_TELEMETRY=0"* ]]
  DO_NOT_TRACK=1 bash "$TEL" daily
  CI=1 bash "$TEL" daily
  DOTFILES_TELEMETRY=0 bash "$TEL" daily
  [ "$(requests)" -eq 0 ]
  DO_NOT_TRACK=1 run bash "$TEL" status
  [[ "$output" == *"telemetry: off (DO_NOT_TRACK is set)"* ]]
}

# ── The dispatcher: first-run question and command timing ───────────────
# Regression (2026-11-09): the owner's Mac had telemetry on, 169,643 events
# pending, and "last send: never". Only the bare start screen could unlock
# sending, and every event came from scheduled jobs that never show it. Now
# any normal `dotfiles <command>` on a terminal asks, and a yes unlocks the
# daily send, which takes only the capped newest events.
@test "a normal command on a terminal asks once, then the daily send works and is small" {
  unset DOTFILES_TELEMETRY_SPAWN
  [ -n "${BATS_TEST_FILENAME:-}" ]
  seed_lines 2600
  export DOTFILES_STATS_LOG=1
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' stats"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Share anonymous performance numbers? [y/n]"* ]]
  [ "$(consent)" = "yes" ]
  wait_for_command_lines 1
  # The 2,600 events from before the yes are never sent; only later ones are.
  printf '{"task":"sync","timestamp":"%s","units":9001}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  local daily_status count
  unset DOTFILES_TELEMETRY_SPAWN
  if bash "$TEL" daily; then daily_status=0; else daily_status=$?; fi
  count="$(requests)" || count=unknown
  assert_request_count 2 "$count" yes "$daily_status"
  [ "$(jq -s -c '[.[].batch[].properties | (.units // .command)]' "$FAKE_LOG")" = '[9001,"stats"]' ]
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "$(date -u +%F)" ]
  run bash -c "printf 'n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' stats"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "yes" ]
}

@test "request count diagnostic is bounded and hides canaries" {
  local count
  for count in 0 1 3; do
    run assert_request_count 2 "$count" yes 0
    [ "$status" -eq 1 ]
    [ "$output" = "expected=2 observed=$count foreground_returned=yes status=0" ]
  done
  run assert_request_count 2 PRIVATE_CANARY_123 PRIVATE_CANARY_123 PRIVATE_CANARY_123
  [ "$status" -eq 1 ]
  [ "$output" = 'expected=2 observed=unknown foreground_returned=unknown status=unknown' ]
  [[ "$output" != *PRIVATE_CANARY_123* ]]
  run assert_request_count 2 2 yes 0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "request count diagnostic reads the fake transport without leaking payload" {
  local count
  printf '{"canary":"PRIVATE_CANARY_123"}' | "$FAKE" >/dev/null
  count="$(requests)"
  run assert_request_count 2 "$count" yes 0
  [ "$status" -eq 1 ]
  [ "$output" = 'expected=2 observed=1 foreground_returned=yes status=0' ]
  [[ "$output" != *PRIVATE_CANARY_123* ]]
}

@test "the first-run question does not nag: not before help, version, cd, or machine output" {
  for args in "cd" "help" "--help" "version" "--version" "actions --json" "stats --json" "doctor --help" "status -h" "telemetry status"; do
    run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' $args"
    [[ "$output" != *"Share anonymous performance numbers?"* ]] || { echo "asked before: dotfiles $args"; return 1; }
  done
  [ "$(consent)" = "unset" ]
}

@test "with no answer it asks at most once a day and 3 times, then stays silent" {
  ask() { run bash -c "DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' stats </dev/null"; }
  ask
  [[ "$output" == *"Share anonymous performance numbers?"* ]]
  [[ "$output" == *"asks again on a later run"* ]]
  [ "$(jq -r .asks "$DOTFILES_TELEMETRY_STATE")" = "1" ]
  ask # the same day: silent
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  # A later day: the stored day is older, and the day marker's time has passed.
  later_day() { set_state ".asked_day = \"$1\""; touch -t 202001010000 "$TEST_DIR/telemetry.asked-until"; }
  later_day 2020-01-01
  ask
  [[ "$output" == *"Share anonymous performance numbers?"* ]]
  later_day 2020-01-02
  ask
  [[ "$output" == *"dotfiles does not ask again"* ]]
  [ "$(jq -r .asks "$DOTFILES_TELEMETRY_STATE")" = "3" ]
  later_day 2020-01-03
  ask
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "unset" ]
  # An explicit ask still works.
  run bash -c "printf 'n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [ "$(consent)" = "no" ]
}

# The gate in lib/stats.sh is plain bash. A copy of lib/ next to a stub of the
# telemetry script counts how often the question process would start.
gate_root() {
  GATE="$TEST_DIR/gate"
  [ ! -d "$GATE" ] || return 0
  mkdir -p "$GATE/bin" "$GATE/lib"
  cp "$REPO"/lib/*.sh "$GATE/lib/"
  printf '#!/bin/bash\necho "$*" >>"%s/gate.calls"\n' "$TEST_DIR" >"$GATE/bin/dotfiles-telemetry"
  chmod +x "$GATE/bin/dotfiles-telemetry"
}
@test "test-owned detached sender reaches its final marker" {
  gate_root
  say_yes
  set_state '.last_send = "" | .try_hour = ""'
  cat > "$GATE/bin/dotfiles-telemetry" <<'SH'
#!/bin/bash
[ "$1" = daily ] || exit 1
printf 'done\n' > "$TEST_SENDER_MARKER"
SH
  chmod +x "$GATE/bin/dotfiles-telemetry"
  export TEST_SENDER_MARKER="$TEST_DIR/sender-finished"
  export DOTFILES_TELEMETRY_SPAWN=1 DOTFILES_TELEMETRY_TTY=1 DOTFILES_TELEMETRY_TEST_UID=1000
  bash -c 'source "$1/lib/stats.sh"; _telemetry_daily "$2"' _ "$GATE" "$NOW"
  local tries=0
  until [ -f "$TEST_SENDER_MARKER" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || { echo 'sender marker not observed'; return 1; }
    sleep 0.05
  done
  [ "$(cat "$TEST_SENDER_MARKER")" = done ]
}

ask_starts() {
  gate_root
  : >"$TEST_DIR/gate.calls"
  DOTFILES_TELEMETRY_TTY=1 bash -c "source '$GATE/lib/stats.sh'; dotfiles_telemetry_ask stats"
  wc -l <"$TEST_DIR/gate.calls" | tr -d ' '
}

@test "after a dismissed question, a run on the same day starts no question process" {
  state() { printf '{"install_id":"0123456789abcdef0123456789abcdef","consent":"unset","asks":%s,"asked_day":"%s"}\n' "$1" "$2" >"$DOTFILES_TELEMETRY_STATE"; }
  [ "$(ask_starts)" -eq 1 ] # never asked: the question starts
  state 1 "$(date -u +%F)"
  [ "$(ask_starts)" -eq 0 ] # dismissed today: nothing starts
  state 1 "2020-01-01"
  [ "$(ask_starts)" -eq 1 ] # an earlier day: it may come back
  state 3 "2020-01-01"
  [ "$(ask_starts)" -eq 0 ] # three times: never again
  # The real script writes the day and count in the shape the gate reads.
  rm -f "$DOTFILES_TELEMETRY_STATE"
  run bash -c "DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --first-run </dev/null"
  [ "$(ask_starts)" -eq 0 ]
}

@test "after a dismissed question, a run on the same day starts no process at all" {
  gate_root
  # The real script dismisses once: it writes the state and the day marker.
  run bash -c "DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --first-run </dev/null"
  [ "$(jq -r .asks "$DOTFILES_TELEMETRY_STATE")" -eq 1 ]
  [ -e "$TEST_DIR/telemetry.asked-until" ]
  # Every process start shows: PATH holds no command, so an external command
  # prints "not found", and the trace marks a command substitution with "++".
  trace() {
    DOTFILES_TELEMETRY_TTY=1 /bin/bash -c "source '$GATE/lib/stats.sh'; PATH='$TEST_DIR/no-commands'; PS4='+ '; set -x; dotfiles_telemetry_ask stats; set +x" 2>&1
  }
  run trace
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ dotfiles_telemetry_ask stats"* ]]
  [[ "$output" != *"++ "* ]]
  [[ "$output" != *"not found"* ]]
  [[ "$output" != *"No such file"* ]]
  [ ! -s "$TEST_DIR/gate.calls" ]
  # Positive control: after the marker's day ends the same trace shows starts.
  touch -t 202001010000 "$TEST_DIR/telemetry.asked-until"
  run trace
  [[ "$output" == *"not found"* ]]
  # With the real PATH the question comes back on the later day.
  set_state '.asked_day = "2020-01-01"'
  [ "$(ask_starts)" -eq 1 ]
  # No marker (a state file from before it existed): the day is still checked.
  rm -f "$TEST_DIR/telemetry.asked-until"
  set_state ".asked_day = \"$(date -u +%F)\""
  [ "$(ask_starts)" -eq 0 ]
  # An answer removes the marker.
  : >"$TEST_DIR/telemetry.asked-until"
  bash "$TEL" off >/dev/null
  [ ! -e "$TEST_DIR/telemetry.asked-until" ]
}

@test "with no key nobody is asked and nothing is printed; an opt-out is still recorded" {
  export DOTFILES_POSTHOG_KEY=""
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --install"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c "bash '$TEL' ask --install </dev/null"
  [ -z "$output" ]
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' stats"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "unset" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
  run bash "$TEL" ask --install --no
  [[ "$output" == *"telemetry: off (--no-telemetry)"* ]]
  [ "$(consent)" = "no" ]
}

@test "with no jq the question stays silent; other commands say how to fix it" {
  mkdir "$TEST_DIR/nojq"
  ln -s "$(command -v dirname)" "$TEST_DIR/nojq/dirname"
  run env PATH="$TEST_DIR/nojq" /bin/bash "$TEL" ask --install
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run env PATH="$TEST_DIR/nojq" /bin/bash "$TEL" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is not installed"* ]]
}

@test "a failure in the middle of a command still stops it when the run is timed" {
  mkdir -p "$TEST_DIR/repo/bin" "$TEST_DIR/repo/lib"
  cp "$REPO"/lib/*.sh "$TEST_DIR/repo/lib/"
  awk '/^  cd\)$/ { print "  canary-arm)"; print "    false"; print "    echo AFTER-FALSE"; print "    ;;" } { print }' \
    "$REPO/bin/dotfiles" >"$TEST_DIR/repo/bin/dotfiles"
  grep -q 'canary-arm)' "$TEST_DIR/repo/bin/dotfiles"
  DOTFILES_STATS_LOG=1 run bash "$TEST_DIR/repo/bin/dotfiles" canary-arm
  [ "$status" -eq 1 ]
  [[ "$output" != *"AFTER-FALSE"* ]]
  DOTFILES_STATS_LOG=0 run bash "$TEST_DIR/repo/bin/dotfiles" canary-arm
  [ "$status" -eq 1 ]
  [[ "$output" != *"AFTER-FALSE"* ]]
}

@test "a command with no terminal never asks; nor with CI or DO_NOT_TRACK; nor telemetry itself" {
  run bash -c "printf 'y\n' | bash '$REPO/bin/dotfiles' stats"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  run bash -c "printf 'y\n' | CI=1 DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' stats"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  run bash -c "printf 'y\n' | DO_NOT_TRACK=1 DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' stats"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' telemetry status"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [[ "$output" == *"consent: unset"* ]]
}

@test "every dotfiles command records one content-free timing line: the name, never an argument" {
  export DOTFILES_STATS_LOG=1
  run bash "$REPO/bin/dotfiles" cd
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO" ]
  wait_for_command_lines 1
  run bash "$REPO/bin/dotfiles" telemetry nosuch "$HOME/canary-user/secret.txt"
  [ "$status" -eq 2 ]
  run bash "$REPO/bin/dotfiles" canary-typed-word
  [ "$status" -eq 1 ]
  wait_for_command_lines 2
  sleep 0.3
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 2 ]
  [ "$(jq -c '[.command, .ok]' "$DOTFILES_COMMANDS_FILE" | tr '\n' ' ')" = '["cd",true] ["telemetry",false] ' ]
  [ "$(jq -s 'map(select((.duration_ms | type) == "number" and (keys | length) == 4)) | length' "$DOTFILES_COMMANDS_FILE")" -eq 2 ]
  run grep -c canary "$DOTFILES_COMMANDS_FILE"
  [ "$output" = "0" ]
}

@test "with the stats log off a command records nothing and keeps its exit code" {
  run bash "$REPO/bin/dotfiles" cd
  [ "$status" -eq 0 ]
  run bash "$REPO/bin/dotfiles" telemetry nosuch
  [ "$status" -eq 2 ]
  [ ! -e "$DOTFILES_COMMANDS_FILE" ]
}

# ── Privacy ─────────────────────────────────────────────────────────────
@test "send --dry-run prints only allowlisted fields, hides the key, and changes nothing" {
  say_yes
  echo "{\"command\":\"doctor\",\"timestamp\":\"$NOW\",\"ok\":true,\"duration_ms\":12}" >"$DOTFILES_COMMANDS_FILE"
  before="$(cat "$DOTFILES_TELEMETRY_STATE")"
  run bash "$TEL" send --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"api_key": "<posthog_key>"'* ]]
  [[ "$output" == *'"event": "dotfiles.run"'* ]]
  [[ "$output" == *'"task": "doctor"'* ]]
  [[ "$output" == *'"event": "dotfiles.command"'* ]]
  [[ "$output" == *'"command": "doctor"'* ]]
  [[ "$output" == *'"runtime": "shell"'* ]]
  [[ "$output" =~ \"os\":\ \"(darwin|linux)\" ]]
  [[ "$output" =~ \"arch\":\ \"(arm64|x64|other)\" ]]
  # shellcheck disable=SC2016 # literal $ in the expected JSON key
  [[ "$output" == *'"$process_person_profile": false'* ]]
  # shellcheck disable=SC2016 # literal $ in the expected JSON key
  [[ "$output" == *'"$geoip_disable": true'* ]]
  [[ "$output" == *"dry run: nothing sent. 3 event(s) pending"* ]]
  [[ "$output" != *canary* ]]
  [[ "$output" != *phc_test* ]]
  [ "$(requests)" -eq 0 ]
  [ "$(cat "$DOTFILES_TELEMETRY_STATE")" = "$before" ]
}

@test "canaries never reach the body: home path, user name, email, URL, long token" {
  say_yes
  token="tok_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUV"
  canaries=("$HOME/canaryuser/work" "canaryuser" "CANARYUSER" "canary" "canary-word" "canary@example.com" "https://canary.example.com/x" "$token")
  {
    for c in "${canaries[@]}"; do
      printf '{"task":"%s","timestamp":"%s","units":1}\n' "$c" "$NOW"
      printf '{"task":"sync","timestamp":"%s","units":"%s","ok":"%s","duration_ms":"%s"}\n' "$c" "$c" "$c" "$c"
      printf '{"task":"sync","timestamp":"%s","host":"%s","user":"%s","cwd":"%s","args":["%s"],"error":"%s","nested":{"task":"%s"}}\n' "$NOW" "$c" "$c" "$c" "$c" "$c" "$c"
      printf '%s\n' "$c"
    done
    printf '{"task":"Canaryuser","timestamp":"%s"}\n' "$NOW"
    printf '{"task":"canary user","timestamp":"%s"}\n' "$NOW"
  } >"$DOTFILES_STATS_FILE"
  for c in "${canaries[@]}"; do
    printf '{"command":"%s","timestamp":"%s","ok":true,"duration_ms":5,"argv":"%s"}\n' "$c" "$NOW" "$c"
  done >"$DOTFILES_COMMANDS_FILE"
  # A name leaves only when it is on the fixed list, so a plain lowercase or
  # uppercase word is dropped like every other shape and every other field.
  run bash "$TEL" send --dry-run
  [ "$status" -eq 0 ]
  dry="$output"
  [[ "$dry" != *[Cc][Aa][Nn][Aa][Rr][Yy]* ]] || { echo "$dry" | grep -i canary; return 1; }
  [[ "$dry" != *tok_0123* ]]
  run bash "$TEL" send
  [[ "$output" == *"sent"* ]]
  sent="$(cat "$FAKE_LOG")"
  [[ "$sent" != *[Cc][Aa][Nn][Aa][Rr][Yy]* ]]
  [[ "$sent" != *tok_0123* ]]
  # The fixed names still go through.
  [ "$(jq -s -c '[.[].batch[].properties.task | select(. != null)] | unique' "$FAKE_LOG")" = '["sync"]' ]
  # Only the allowlisted names ever appear.
  # shellcheck disable=SC2016 # literal $ in the jq program
  [ "$(jq -s -c '[.[].batch[].properties | keys[]] | unique - ["$geoip_disable","$process_person_profile","app_version","arch","command","duration_ms","fail","fixed","ok","os","pass","runtime","seconds_saved","skip","task","units","warn"]' "$FAKE_LOG")" = "[]" ]
  [ "$(jq -s -c '[.[].batch[] | keys[]] | unique' "$FAKE_LOG")" = '["distinct_id","event","properties","timestamp"]' ]
}

@test "every task name a script records is on the fixed list, and so is every command" {
  names="$(sed -n 's/^TASK_NAMES="\(.*\)"$/\1/p' "$TEL")"
  commands="$(sed -n 's/^COMMAND_NAMES="\(.*\)"$/\1/p' "$TEL")"
  [ -n "$names" ]
  [ -n "$commands" ]
  recorded="$(grep -rhE '^[^#]*log_run "?[a-z]' --exclude=dotfiles-telemetry "$REPO/bin" | grep -oE 'log_run "?[a-z][a-z0-9-]*' | sed -E 's/log_run "?//' | sort -u)"
  [ "$(echo "$recorded" | wc -l)" -ge 8 ]
  for name in $recorded doctor shell-start; do
    [[ " $names " == *" $name "* ]] || { echo "not in TASK_NAMES: $name"; return 1; }
  done
  # Every dispatch arm of bin/dotfiles is on the committed command list.
  arms="$(grep -E '^  [a-z0-9"|-]+\)' "$REPO/bin/dotfiles" | sed -e 's/).*//' -e 's/[" ]//g' | tr '|' '\n' | grep -E '^[a-z][a-z0-9-]{0,39}$' | sort -u)"
  [ "$(echo "$arms" | wc -l)" -ge 30 ]
  for name in $arms; do
    [[ " $commands " == *" $name "* ]] || { echo "not in COMMAND_NAMES: $name"; return 1; }
  done
  say_yes
  for name in $names; do printf '{"task":"%s","timestamp":"%s"}\n' "$name" "$NOW"; done >"$DOTFILES_STATS_FILE"
  for name in $commands forkonlyarm; do printf '{"command":"%s","timestamp":"%s","ok":true,"duration_ms":1}\n' "$name" "$NOW"; done >"$DOTFILES_COMMANDS_FILE"
  bash "$TEL" send >/dev/null
  [ "$(jq -s -r '[.[].batch[].properties.task | select(. != null)] | join(" ")' "$FAKE_LOG")" = "$names" ]
  [ "$(jq -s -r '[.[].batch[].properties.command | select(. != null)] | join(" ")' "$FAKE_LOG")" = "$commands" ]
}

@test "app_version is the last upstream commit, never a local commit" {
  repo="$TEST_DIR/fork"
  mkdir -p "$repo/bin" "$repo/config"
  cp "$TEL" "$repo/bin/dotfiles-telemetry"
  (
    cd "$repo"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
    git init -q .
    git add bin && git commit -q -m upstream
    git remote add origin https://github.com/fyodoriv/dotfiles.git
    git update-ref refs/remotes/origin/feat/chezmoi HEAD
    git rev-parse --short HEAD >"$TEST_DIR/upstream.sha"
    echo local >local.txt && git add local.txt && git commit -q -m "a local commit"
    git rev-parse --short HEAD >"$TEST_DIR/local.sha"
  )
  say_yes
  run bash "$repo/bin/dotfiles-telemetry" send --dry-run
  [[ "$output" == *"\"app_version\": \"$(cat "$TEST_DIR/upstream.sha")\""* ]]
  [[ "$output" != *"$(cat "$TEST_DIR/local.sha")"* ]]
  # A fork: its origin branch holds its own commits, so no SHA is sent.
  for url in https://github.com/someone/dotfiles.git git@github.com:fyodoriv/dotfiles-fork.git https://example.com/fyodoriv/dotfiles; do
    (cd "$repo" && GIT_CONFIG_GLOBAL=/dev/null git remote set-url origin "$url")
    run bash "$repo/bin/dotfiles-telemetry" send --dry-run
    [[ "$output" == *'"app_version": "unknown"'* ]] || { echo "$url: $output"; return 1; }
  done
  (cd "$repo" && GIT_CONFIG_GLOBAL=/dev/null git remote set-url origin git@github.com:fyodoriv/dotfiles.git)
  run bash "$repo/bin/dotfiles-telemetry" send --dry-run
  [[ "$output" == *"\"app_version\": \"$(cat "$TEST_DIR/upstream.sha")\""* ]]
  (cd "$repo" && git update-ref -d refs/remotes/origin/feat/chezmoi)
  run bash "$repo/bin/dotfiles-telemetry" send --dry-run
  [[ "$output" == *'"app_version": "unknown"'* ]]
}

@test "the key is never an argument of a process" {
  say_yes
  real_jq="$(command -v jq)"
  mkdir "$TEST_DIR/shim"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"%s/jq.args"\nexec "%s" "$@"\n' "$TEST_DIR" "$real_jq" >"$TEST_DIR/shim/jq"
  chmod +x "$TEST_DIR/shim/jq"
  PATH="$TEST_DIR/shim:$PATH" run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  [ "$(jq -s -r '.[0].api_key' "$FAKE_LOG")" = "phc_testFakeKey1" ]
  [ -s "$TEST_DIR/jq.args" ]
  run grep -c "phc_testFakeKey1" "$TEST_DIR/jq.args" "$FAKE_LOG.args"
  [[ "$output" != *":"[1-9]* ]]
}

# ── Reliability ─────────────────────────────────────────────────────────
@test "the count is of events sent, not of log lines" {
  say_yes
  printf 'not json\n[1,2]\n' >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "4" ]
}

@test "send posts the pending events once, then nothing new" {
  say_yes
  run bash "$TEL" send
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent 2 event(s)"* ]]
  [ "$(requests)" -eq 1 ]
  [ "$(jq -s '.[0].batch | length' "$FAKE_LOG")" -eq 2 ]
  [ "$(jq -s -r '.[0].api_key' "$FAKE_LOG")" = "phc_testFakeKey1" ]
  run grep -q canary "$FAKE_LOG"
  [ "$status" -ne 0 ]
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(requests)" -eq 1 ]
}

@test "a failed send keeps the cursor, never fails, and is logged without content" {
  say_yes
  FAKE_CODE=500 run bash "$TEL" send
  [ "$status" -eq 0 ]
  [[ "$output" == *"send failed (http 500)"* ]]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "0" ]
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "" ]
  grep -q "send failed (http 500)" "$TEST_DIR/telemetry.log"
  run bash "$TEL" status
  [[ "$output" == *"last problem:"*"send failed (http 500)"* ]]
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
}

@test "a curl that cannot run never fails the command" {
  say_yes
  DOTFILES_TELEMETRY_CURL="$TEST_DIR/no-such-curl" run bash "$TEL" send
  [ "$status" -eq 0 ]
  [[ "$output" == *"send failed (http 000)"* ]]
  set_state '.last_try = 0'
  DOTFILES_TELEMETRY_CURL="$TEST_DIR/no-such-curl" run bash "$TEL" daily
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a hung endpoint cannot hold the daily send: the request is killed" {
  say_yes
  # The fake records its own pid (exec keeps it), so the check never matches
  # a "sleep 60" of another process on this Mac.
  printf '#!/bin/bash\necho "$$" >>"%s/hung.calls"\nexec sleep 60\n' "$TEST_DIR" >"$FAKE"
  start="$(date +%s)"
  run bash "$TEL" daily
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ $(($(date +%s) - start)) -le 8 ]
  [ "$(wc -l <"$TEST_DIR/hung.calls" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "0" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.lock" ]
  hung_pid="$(cat "$TEST_DIR/hung.calls")"
  ! kill -0 "$hung_pid" 2>/dev/null || { kill "$hung_pid"; false; }
}

@test "the daily send stops after 3 seconds in total; the rest goes later" {
  say_yes
  seed_lines 2000
  cat >"$FAKE" <<'SH'
#!/bin/bash
cat >>"${FAKE_LOG:?}"
echo >>"$FAKE_LOG"
sleep 2
printf 200
SH
  bash "$TEL" daily
  [ "$(requests)" -le 2 ]
  [ "$(requests)" -ge 1 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" -ge 500 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" -le 1000 ]
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "" ]
}

@test "daily sends once a day, with a 3 second limit; manual send allows 10" {
  say_yes
  bash "$TEL" daily
  [ "$(requests)" -eq 1 ]
  # 3 seconds in total: on a slow machine a second or two is gone before the request.
  grep -Eq -- "--max-time [1-3] " "$FAKE_LOG.args"
  echo "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"units\":1}" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" daily
  [ "$(requests)" -eq 1 ]
  run bash "$TEL" send
  [ "$(requests)" -eq 2 ]
  grep -q -- "--max-time 10 " "$FAKE_LOG.args"
}

@test "after a failed daily try, the next try waits an hour" {
  say_yes
  FAKE_CODE=503 bash "$TEL" daily
  [ "$(requests)" -eq 1 ]
  bash "$TEL" daily
  [ "$(requests)" -eq 1 ]
  set_state '.last_try = (now | floor) - 3601'
  bash "$TEL" daily
  [ "$(requests)" -eq 2 ]
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "$(date -u +%F)" ]
}

@test "a big backlog: only the newest 2,000 go, 500 per request, and the rest is skipped for good" {
  say_yes
  seed_lines 2600
  run bash "$TEL" status
  [[ "$output" == *"pending: 2000 event(s) (600 older event(s) will be skipped, never sent)"* ]]
  run bash "$TEL" send
  [[ "$output" == *"sent 2000 event(s) (skipped 600 older event(s))"* ]]
  [ "$(requests)" -eq 4 ]
  [ "$(jq -s -c '[.[].batch | length]' "$FAKE_LOG")" = "[500,500,500,500]" ]
  [ "$(jq -s '.[0].batch[0].properties.units' "$FAKE_LOG")" -eq 601 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "2600" ]
}

@test "events older than 30 days are skipped, never sent" {
  say_yes
  {
    printf '{"task":"sync","timestamp":"2020-01-01T00:00:00Z","units":1}\n'
    printf '{"task":"sync","timestamp":"2020-01-02T00:00:00Z","units":2}\n'
    printf '{"task":"sync","timestamp":"%s","units":3}\n' "$NOW"
  } >"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s) (skipped 2 older event(s))"* ]]
  [ "$(jq -s -c '[.[].batch[].properties.units]' "$FAKE_LOG")" = "[3]" ]
}

@test "the cursor moves only after a 2xx, one request at a time" {
  say_yes
  seed_lines 1200
  cat >"$FAKE" <<'SH'
#!/bin/bash
cat >>"${FAKE_LOG:?}"
echo >>"$FAKE_LOG"
if [ "$(wc -l <"$FAKE_LOG")" -ge 2 ]; then printf 500; else printf 200; fi
SH
  run bash "$TEL" send
  [[ "$output" == *"send failed (http 500)"* ]]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "500" ]
}

@test "a log that was cut moves the cursor to the end, not to zero" {
  say_yes
  bash "$TEL" send >/dev/null
  set_state '.sent = 50'
  run bash "$TEL" status
  [[ "$output" == *"pending: 0 event(s)"* ]]
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(requests)" -eq 1 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "2" ]
}

@test "a cursor that is not a whole number means the end of the log" {
  say_yes
  for bad in '1.5' '"12"' '-3' '1e30' '[]'; do
    set_state ".sent = $bad"
    run bash "$TEL" status
    [[ "$output" == *"pending: 0 event(s)"* ]] || { echo "$bad: $output"; return 1; }
    run bash "$TEL" send
    [ "$(requests)" -eq 0 ]
  done
}

# Review fix 4: only a jq that ran and rejected the content resets the state.
@test "a failed jq read changes nothing: a stored no stays no, and a yes sends nothing" {
  fail_once_jq
  bash "$TEL" off >/dev/null
  cp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/before.json"
  for command in status daily "ask --install" "ask --first-run" send; do
    : >"$TEST_DIR/jq-fail"
    # shellcheck disable=SC2086
    run bash -c "printf 'y\n' | PATH='$TEST_DIR/jqshim:$PATH' DOTFILES_TELEMETRY_TTY=1 bash '$TEL' $command"
    [ ! -e "$TEST_DIR/jq-fail" ] # the fake failure was used
    cmp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/before.json" || { echo "$command changed the state: $output"; return 1; }
    [[ "$output" != *"Share anonymous performance numbers?"* ]] || { echo "$command asked again"; return 1; }
  done
  : >"$TEST_DIR/jq-fail"
  PATH="$TEST_DIR/jqshim:$PATH" run bash "$TEL" status
  [[ "$output" == *"consent: unknown"* ]]
  # A stored yes with a failed read sends nothing in that run.
  say_yes
  : >"$TEST_DIR/jq-fail"
  PATH="$TEST_DIR/jqshim:$PATH" run bash "$TEL" send
  [[ "$output" == *"not sent (the state file could not be read)"* ]]
  [ "$(requests)" -eq 0 ]
  [ "$(consent)" = "yes" ]
  # An answer that cannot be saved says so, and the file stays as it was.
  cp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/before.json"
  : >"$TEST_DIR/jq-fail-always"
  PATH="$TEST_DIR/jqshim:$PATH" run bash "$TEL" off
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not save your answer"* ]]
  cmp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/before.json"
  [ ! -e "$DOTFILES_TELEMETRY_STATE.wlock" ]
}

@test "a run that only reads never creates a state file or an install id" {
  rm -f "$DOTFILES_TELEMETRY_STATE"
  for command in daily status example "send --dry-run" send "ask --install"; do
    # shellcheck disable=SC2086
    run bash -c "bash '$TEL' $command </dev/null"
    [ ! -e "$DOTFILES_TELEMETRY_STATE" ] || { echo "$command created the state file"; return 1; }
  done
  [ ! -e "$DOTFILES_TELEMETRY_STATE.wlock" ]
  # A file from before the question (no answer) is left as it is by a wake.
  printf '{"install_id":"0123456789abcdef0123456789abcdef","sent":1}\n' >"$DOTFILES_TELEMETRY_STATE"
  cp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/before.json"
  bash "$TEL" daily
  cmp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/before.json"
}

@test "the state file is private, written whole, and leaves no temp file" {
  bash "$TEL" on >/dev/null
  [ "$(stat -c %a "$DOTFILES_TELEMETRY_STATE" 2>/dev/null || stat -f %Lp "$DOTFILES_TELEMETRY_STATE")" = "600" ]
  [ "$(wc -l <"$DOTFILES_TELEMETRY_STATE" | tr -d ' ')" -eq 1 ]
  jq -e . "$DOTFILES_TELEMETRY_STATE" >/dev/null
  run bash -c "ls '$TEST_DIR' | grep -c 'telemetry.json.tmp'"
  [ "$output" = "0" ]
  # The write is a temp file plus a rename.
  # shellcheck disable=SC2016 # literal source text
  grep -q 'mv -f "$tmp" "$STATE"' "$TEL"
}

@test "off during a send is kept, and stops the send before the next request" {
  say_yes
  seed_lines 1200
  cat >"$FAKE" <<SH
#!/bin/bash
cat >>"\${FAKE_LOG:?}"
echo >>"\$FAKE_LOG"
bash "$TEL" off >/dev/null
printf 200
SH
  run bash "$TEL" send
  [[ "$output" == *"sent 500 event(s), then stopped (turned off during the send)"* ]]
  [ "$(consent)" = "no" ]
  [ "$(requests)" -eq 1 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "500" ]
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "" ]
}

# The send reads the state, then waits one second before it writes (the test
# hold). An `off` in that second must not be lost: it waits for the lock.
@test "telemetry off between a send's read and its write is not lost" {
  say_yes
  DOTFILES_TELEMETRY_TEST_HOLD=1 bash "$TEL" send >/dev/null 2>&1 3>&- &
  send_pid=$!
  sleep 0.4
  bash "$TEL" off >/dev/null
  wait "$send_pid"
  [ "$(consent)" = "no" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.wlock" ]
  # A later send does nothing.
  before="$(requests)"
  bash "$TEL" send >/dev/null 2>&1 || true
  [ "$(requests)" -eq "$before" ]
}

# The send holds the state lock for 6 seconds, past the 3 second takeover.
# `off` takes the lock over and writes no. The send then sees that it lost
# the lock and reads again, instead of writing the yes it read before.
@test "a writer that stalls past the lock takeover does not save what it read before" {
  say_yes
  DOTFILES_TELEMETRY_TEST_HOLD=6 bash "$TEL" send >/dev/null 2>&1 3>&- &
  send_pid=$!
  sleep 0.4
  bash "$TEL" off >/dev/null
  [ "$(consent)" = "no" ]
  wait "$send_pid"
  [ "$(consent)" = "no" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.wlock" ]
}

@test "only one send runs at a time; a stale lock is cleared" {
  say_yes
  mkdir "$DOTFILES_TELEMETRY_STATE.lock"
  run bash "$TEL" send
  [[ "$output" == *"another send is running"* ]]
  [ "$(requests)" -eq 0 ]
  touch -t 202001010000 "$DOTFILES_TELEMETRY_STATE.lock"
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.lock" ]
}

# ── The real trigger path: log_run -> detached child -> send ────────────
# A local HTTP endpoint (python) and the real curl. The endpoint answers after
# one second, and the test kills the whole process group of the run in that
# second, as launchd and a closed terminal do. The send must still finish.
start_endpoint() {
  cat >"$TEST_DIR/endpoint.py" <<'PY'
import http.server, sys, time
out, port_file = sys.argv[1], sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        time.sleep(1)
        with open(out, "ab") as f:
            f.write(body + b"\n")
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
open(port_file, "w").write(str(server.server_address[1]))
server.serve_forever()
PY
  python3 "$TEST_DIR/endpoint.py" "$FAKE_LOG" "$TEST_DIR/port" >/dev/null 2>&1 3>&- &
  echo $! >"$TEST_DIR/server.pid"
  local tries=0
  until [ -s "$TEST_DIR/port" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 100 ] || return 1
    sleep 0.05
  done
  export DOTFILES_TELEMETRY_URL="http://127.0.0.1:$(cat "$TEST_DIR/port")" DOTFILES_TELEMETRY_CURL=curl
}
wait_for_last_send() {
  local tries=0
  until [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE" 2>/dev/null)" = "$(date -u +%F)" ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 200 ] || return 1
    sleep 0.05
  done
}

@test "the real path: a terminal run starts a send that outlives the run and its process group" {
  command -v python3 >/dev/null 2>&1 || skip "python3 is needed for the local endpoint"
  say_yes
  start_endpoint
  export DOTFILES_STATS_LOG=1 DOTFILES_TELEMETRY_SPAWN=1 DOTFILES_TELEMETRY_TTY=1
  (
    set -m
    bash -c "source '$REPO/lib/stats.sh'; log_run sync; echo \$\$ >'$TEST_DIR/parent.pid'" 3>&- &
    wait $!
  )
  # The run is over. Kill what is left of its process group, mid-request.
  [ -s "$TEST_DIR/parent.pid" ]
  kill -TERM -- "-$(cat "$TEST_DIR/parent.pid")" 2>/dev/null || true
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "" ]
  wait_for_last_send
  [ "$(requests)" -eq 1 ]
  [ "$(jq -s '.[0].batch | length' "$FAKE_LOG")" -eq 3 ]
  [ "$(jq -s -r '.[0].api_key' "$FAKE_LOG")" = "phc_testFakeKey1" ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "3" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.lock" ]
}

@test "a run with no terminal (a scheduled job) starts no send" {
  say_yes
  export DOTFILES_STATS_LOG=1 DOTFILES_TELEMETRY_SPAWN=1
  run bash -c "source '$REPO/lib/stats.sh'; log_run sync; log_command doctor ok 12" </dev/null
  sleep 1
  [ "$(requests)" -eq 0 ]
  [ "$(jq -r .last_try "$DOTFILES_TELEMETRY_STATE")" = "0" ]
}

@test "after a try this hour, a terminal run starts no new process for the send" {
  say_yes
  fake_security="$TEST_DIR/fake-security"
  printf '#!/bin/bash\necho called >>"%s/security.calls"\n' "$TEST_DIR" >"$fake_security"
  chmod +x "$fake_security"
  export DOTFILES_TELEMETRY_SECURITY="$fake_security" DOTFILES_POSTHOG_KEY=""
  export DOTFILES_STATS_LOG=1 DOTFILES_TELEMETRY_SPAWN=1 DOTFILES_TELEMETRY_TTY=1
  bash -c "source '$REPO/lib/stats.sh'; log_run sync"
  tries=0
  until [ -s "$TEST_DIR/security.calls" ]; do tries=$((tries + 1)); [ "$tries" -lt 100 ]; sleep 0.05; done
  [ "$(jq -r .try_hour "$DOTFILES_TELEMETRY_STATE")" = "$(date -u +%FT%H)" ]
  # Without the hour in the fast gate, each of these would start the send
  # script, and with last_try at 0 it would look for a key again.
  set_state '.last_try = 0'
  bash -c "source '$REPO/lib/stats.sh'; log_run sync; log_run sync; log_command doctor ok 12"
  sleep 1
  [ "$(wc -l <"$TEST_DIR/security.calls" | tr -d ' ')" -eq 1 ]
}

# Review fix 1: every return path of the daily send marks the clock hour, and
# the gate in lib/stats.sh also stops on an off switch.
@test "the daily path marks the hour on every return path, and only with a stored yes" {
  say_yes
  hour="$(date -u +%FT%H)"
  try_hour() { jq -r .try_hour "$DOTFILES_TELEMETRY_STATE"; }
  # A failed try under an hour ago, in the clock hour before this one.
  set_state ".last_try = $(($(date +%s) - 60)) | .try_hour = \"2020-01-01T00\""
  bash "$TEL" daily
  [ "$(try_hour)" = "$hour" ]
  [ "$(requests)" -eq 0 ]
  # A stored yes with an off switch set.
  for switch in DO_NOT_TRACK=1 DOTFILES_TELEMETRY=0 CI=1; do
    set_state '.last_try = 0 | .try_hour = ""'
    env "$switch" bash "$TEL" daily
    [ "$(try_hour)" = "$hour" ] || { echo "$switch did not mark the hour"; return 1; }
  done
  [ "$(requests)" -eq 0 ]
  # A no is never marked: the gate stops on the answer.
  bash "$TEL" off >/dev/null
  set_state '.try_hour = ""'
  bash "$TEL" daily
  [ "$(try_hour)" = "" ]
}

@test "with an off switch set, a terminal run starts no process for the send" {
  say_yes
  gate_root
  : >"$TEST_DIR/gate.calls"
  export DOTFILES_STATS_LOG=1 DOTFILES_TELEMETRY_SPAWN=1 DOTFILES_TELEMETRY_TTY=1
  DO_NOT_TRACK=1 bash -c "source '$GATE/lib/stats.sh'; log_run sync"
  DOTFILES_TELEMETRY=0 bash -c "source '$GATE/lib/stats.sh'; log_run sync"
  CI=1 bash -c "source '$GATE/lib/stats.sh'; log_command doctor ok 12"
  sleep 1
  [ ! -s "$TEST_DIR/gate.calls" ]
  # The control: with no switch the same run starts the send script once.
  bash -c "source '$GATE/lib/stats.sh'; log_run sync"
  tries=0
  until [ -s "$TEST_DIR/gate.calls" ]; do tries=$((tries + 1)); [ "$tries" -lt 100 ]; sleep 0.05; done
  [ "$(cat "$TEST_DIR/gate.calls")" = "daily" ]
}

# Review fix 2: the LaunchAgent exists only while the stored answer is yes.
@test "a yes loads the LaunchAgent; off unloads it and removes its plist" {
  fake_agent_tools
  bash "$TEL" on >/dev/null
  [ -s "$PLIST" ]
  grep -q '<string>daily</string>' "$PLIST"
  grep -q "^bootstrap gui/$(id -u) $PLIST\$" "$TEST_DIR/launchctl.log"
  bash "$TEL" off >/dev/null
  [ ! -e "$PLIST" ]
  grep -q "^bootout gui/$(id -u)/com.dotfiles.telemetry\$" "$TEST_DIR/launchctl.log"
  # A yes and a no at the question, and an install opt-out, do the same.
  rm -f "$DOTFILES_TELEMETRY_STATE"
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [ -s "$PLIST" ]
  run bash "$TEL" ask --install --no
  [ ! -e "$PLIST" ]
  rm -f "$DOTFILES_TELEMETRY_STATE"
  run bash -c "printf 'n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [ ! -e "$PLIST" ]
  # Nothing but an answer touches launchd.
  : >"$TEST_DIR/launchctl.log"
  bash "$TEL" on >/dev/null
  : >"$TEST_DIR/launchctl.log"
  bash "$TEL" status >/dev/null
  bash "$TEL" daily
  bash "$TEL" send >/dev/null
  [ ! -s "$TEST_DIR/launchctl.log" ]
  [ -s "$PLIST" ]
}

@test "a repeat yes leaves a loaded, unchanged LaunchAgent alone" {
  fake_agent_tools
  bash "$TEL" on >/dev/null
  [ -e "$TEST_DIR/agent-loaded" ]
  : >"$TEST_DIR/launchctl.log"
  bash "$TEL" on >/dev/null
  # No bootout and no bootstrap: only the question "is it loaded".
  refute grep -qE '^(bootout|bootstrap) ' "$TEST_DIR/launchctl.log"
  [ -e "$TEST_DIR/agent-loaded" ]
  [ -z "$(ls "$HOME/Library/LaunchAgents" | grep -v '^com.dotfiles.telemetry.plist$' || true)" ]
  # A changed plist is loaded again.
  echo "<!-- old -->" >>"$PLIST"
  bash "$TEL" on >/dev/null
  grep -q '^bootstrap ' "$TEST_DIR/launchctl.log"
  refute grep -q 'old' "$PLIST"
  # An unchanged plist whose job is not loaded is loaded again.
  rm -f "$TEST_DIR/agent-loaded"
  : >"$TEST_DIR/launchctl.log"
  bash "$TEL" on >/dev/null
  grep -q '^bootstrap ' "$TEST_DIR/launchctl.log"
  [ -e "$TEST_DIR/agent-loaded" ]
}

@test "a bootstrap that fails right after the bootout is tried once more" {
  fake_agent_tools
  : >"$TEST_DIR/bootstrap-fail-once"
  bash "$TEL" on >/dev/null
  [ "$(grep -c '^bootstrap ' "$TEST_DIR/launchctl.log")" -eq 2 ]
  [ -e "$TEST_DIR/agent-loaded" ]
  [ ! -e "$TEST_DIR/telemetry.log" ]
  # Two failures: logged, and the command still works.
  bash "$TEL" off >/dev/null
  : >"$TEST_DIR/launchctl.log"
  : >"$TEST_DIR/bootstrap-fail-always"
  run bash "$TEL" on
  [ "$status" -eq 0 ]
  [ "$(grep -c '^bootstrap ' "$TEST_DIR/launchctl.log")" -eq 2 ]
  grep -q 'could not load the LaunchAgent' "$TEST_DIR/telemetry.log"
}

@test "as root nothing is saved, loaded, or sent, and one line says so" {
  fake_agent_tools
  root() { DOTFILES_TELEMETRY_TEST_UID=0 "$@"; }
  run root bash "$TEL" on
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'as root')" -eq 1 ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.wlock" ]
  [ ! -e "$PLIST" ]
  [ ! -s "$TEST_DIR/launchctl.log" ]
  run root bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask"
  [ "$(printf '%s\n' "$output" | grep -c 'as root')" -eq 1 ]
  [[ "$output" != *"Share anonymous"* ]]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
  # With a stored yes of the user: root changes nothing and sends nothing.
  say_yes
  before="$(cat "$DOTFILES_TELEMETRY_STATE")"
  : >"$TEST_DIR/launchctl.log"
  run root bash "$TEL" off
  [ "$status" -eq 1 ]
  run root bash "$TEL" send
  [[ "$output" == *"not sent (running as root)"* ]]
  root bash "$TEL" daily 2>/dev/null
  root bash "$TEL" cap-commands 2>/dev/null
  [ "$(cat "$DOTFILES_TELEMETRY_STATE")" = "$before" ]
  [ "$(requests)" -eq 0 ]
  [ ! -s "$TEST_DIR/launchctl.log" ]
  [ ! -e "$TEST_DIR/telemetry.log" ]
  [ -s "$PLIST" ]
}

@test "apply runs the LaunchAgent script again when the telemetry answer changes" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  consent_line() {
    # Only this header line is rendered, so the test needs no chezmoi data.
    grep '^# telemetry consent:' "$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl" |
      chezmoi execute-template --source "$REPO"
  }
  none="$(consent_line)"
  bash "$TEL" off >/dev/null
  no="$(consent_line)"
  bash "$TEL" on >/dev/null
  yes="$(consent_line)"
  [ -n "$yes" ]
  [ "$yes" != "$no" ]
  [ "$no" = "$none" ] # both mean "not installed": no extra run
  # A field that changes every hour does not change the line.
  set_state '.try_hour = "2026-01-01T05" | .sent = 7'
  [ "$(consent_line)" = "$yes" ]
  # The default path (no test override) follows XDG_STATE_HOME.
  mkdir -p "$TEST_DIR/xdg/dotfiles"
  cp "$DOTFILES_TELEMETRY_STATE" "$TEST_DIR/xdg/dotfiles/telemetry.json"
  [ "$(env -u DOTFILES_TELEMETRY_STATE XDG_STATE_HOME="$TEST_DIR/xdg" bash -c "$(declare -f consent_line); REPO='$REPO' consent_line")" = "$yes" ]
  [ "$(env -u DOTFILES_TELEMETRY_STATE XDG_STATE_HOME="$TEST_DIR/none" bash -c "$(declare -f consent_line); REPO='$REPO' consent_line")" = "$none" ]
}

@test "the LaunchAgent gets XDG_STATE_HOME when it is set at render time" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  plist="$REPO/launchagents/com.dotfiles.telemetry.plist.tmpl"
  render() { { printf '{{- $_ := set . "dotfiles_dir" "apps/dotfiles" -}}\n'; cat "$plist"; } | chezmoi execute-template --source "$REPO"; }
  XDG_STATE_HOME="$TEST_DIR/my state" render >"$TEST_DIR/with.plist"
  (unset XDG_STATE_HOME; render >"$TEST_DIR/without.plist")
  grep -A1 '<key>XDG_STATE_HOME</key>' "$TEST_DIR/with.plist" | grep -qF "<string>$TEST_DIR/my state</string>"
  refute grep -q '<key>XDG_STATE_HOME</key>' "$TEST_DIR/without.plist"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$TEST_DIR/with.plist"
    plutil -lint "$TEST_DIR/without.plist"
  fi
}

@test "a yes with no chezmoi data installs no broken plist; apply does it later" {
  fake_agent_tools
  printf '#!/bin/bash\nexit 1\n' >"$TEST_DIR/fake-chezmoi"
  run bash "$TEL" on
  [ "$status" -eq 0 ]
  [ "$(consent)" = "yes" ]
  [ ! -e "$PLIST" ]
  [ -z "$(ls "$HOME/Library/LaunchAgents" 2>/dev/null)" ]
  [ ! -s "$TEST_DIR/launchctl.log" ]
}

@test "dotfiles apply installs the telemetry LaunchAgent only when the state says yes" {
  apply="$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  eval "$(sed -n '/^should_skip_agent() {/,/^}/p' "$apply")"
  SOURCE_DIR="$REPO"
  eval "$(sed -n '/^remove_skipped_agent() {/,/^}/p' "$apply")"
  self_reload_should_defer() { return 1; }
  launchctl() { echo "$*" >>"$TEST_DIR/launchctl.log"; }
  PROFILE=full
  should_skip_agent telemetry # no state file: nobody answered
  bash "$TEL" off >/dev/null
  should_skip_agent telemetry
  bash "$TEL" on >/dev/null
  refute should_skip_agent telemetry
  # An installed copy is unloaded and removed when the answer is no longer yes.
  mkdir -p "$HOME/Library/LaunchAgents"
  echo plist >"$HOME/Library/LaunchAgents/com.dotfiles.telemetry.plist"
  bash "$TEL" off >/dev/null
  should_skip_agent telemetry
  run remove_skipped_agent telemetry com.dotfiles.telemetry.plist
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/LaunchAgents/com.dotfiles.telemetry.plist" ]
  grep -q '^unload ' "$TEST_DIR/launchctl.log"
  # Uninstall still removes every com.dotfiles.* agent, this one too.
  grep -q 'LaunchAgents/com.dotfiles.\*.plist' "$REPO/bin/dotfiles-uninstall"
}

@test "the commands log is capped: over 20,000 lines it keeps the newest 10,000" {
  export DOTFILES_STATS_LOG=1
  for ((i = 1; i <= 20001; i++)); do echo "{\"command\":\"status\",\"timestamp\":\"$NOW\",\"ok\":true,\"duration_ms\":$i}"; done >"$DOTFILES_COMMANDS_FILE"
  DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$REPO/lib/stats.sh'; log_command doctor ok 5"
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10000 ]
  [[ "$(tail -n 1 "$DOTFILES_COMMANDS_FILE")" == *'"command":"doctor"'* ]]
  [ -z "$(ls "$TEST_DIR" | grep 'commands.jsonl.tmp' || true)" ]
  # A small log is left alone.
  DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$REPO/lib/stats.sh'; log_command doctor ok 5"
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10001 ]
  # Nobody answered: the cap creates no state file.
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
}

@test "the cap keeps unsent lines: the cursor moves back by the dropped lines" {
  export DOTFILES_STATS_LOG=1
  say_yes
  : >"$DOTFILES_STATS_FILE"
  line() { echo "{\"command\":\"$1\",\"timestamp\":\"$NOW\",\"ok\":true,\"duration_ms\":$2}"; }
  # 20,000 lines; the first 19,997 are sent, the last 3 are not.
  for ((i = 1; i <= 19997; i++)); do line status "$i"; done >"$DOTFILES_COMMANDS_FILE"
  for i in 1 2 3; do line doctor "$i"; done >>"$DOTFILES_COMMANDS_FILE"
  set_state '.sent_commands = 19997'
  DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$REPO/lib/stats.sh'; log_command sync ok 5"
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10000 ]
  # 10,001 lines were dropped, so the cursor is 19,997 - 10,001.
  [ "$(jq -r .sent_commands "$DOTFILES_TELEMETRY_STATE")" -eq 9996 ]
  [ "$(consent)" = "yes" ]
  # The 3 unsent lines and the new one are sent, and nothing older.
  bash "$TEL" send >/dev/null
  [ "$(jq -s '[.[].batch[]] | length' "$FAKE_LOG")" -eq 4 ]
  [ "$(jq -s -r '[.[].batch[].properties.command] | join(",")' "$FAKE_LOG")" = "doctor,doctor,doctor,sync" ]
  # A cursor behind the dropped lines stops at the start of the kept log.
  for ((i = 1; i <= 20001; i++)); do line status "$i"; done >"$DOTFILES_COMMANDS_FILE"
  set_state '.sent_commands = 5'
  bash "$TEL" cap-commands
  [ "$(jq -r .sent_commands "$DOTFILES_TELEMETRY_STATE")" -eq 0 ]
  # While a send runs, the log is left alone.
  for ((i = 1; i <= 20001; i++)); do line status "$i"; done >"$DOTFILES_COMMANDS_FILE"
  mkdir "$DOTFILES_TELEMETRY_STATE.lock"
  bash "$TEL" cap-commands
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 20001 ]
  rmdir "$DOTFILES_TELEMETRY_STATE.lock"
}

@test "the LaunchAgent runs the daily send and nothing else" {
  plist="$REPO/launchagents/com.dotfiles.telemetry.plist.tmpl"
  grep -q 'bin/dotfiles-telemetry</string>' "$plist"
  grep -q '<string>daily</string>' "$plist"
  grep -q '<key>StartInterval</key>' "$plist"
}

@test "log_run and log_command start no send in a test and drop a bad name or time" {
  export DOTFILES_STATS_LOG=1
  say_yes
  run bash -c "source '$REPO/lib/stats.sh'; log_run sync; log_command doctor ok 12; log_command 'Bad Name' ok 1; log_command doctor ok notanumber"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 1 ]
  [ "$(requests)" -eq 0 ]
}

# ── Review nits of PR #567 ──────────────────────────────────────────────

@test "a line appended during the cap's cut is kept and sent exactly once" {
  say_yes
  : >"$DOTFILES_STATS_FILE"
  line() { echo "{\"command\":\"$1\",\"timestamp\":\"$NOW\",\"ok\":true,\"duration_ms\":$2}"; }
  for ((i = 1; i <= 20001; i++)); do line status "$i"; done >"$DOTFILES_COMMANDS_FILE"
  set_state '.sent_commands = 20001' # every line is sent already
  # A tail that first appends one line: a command that ends during the cut.
  mkdir "$TEST_DIR/slow"
  line doctor 7 >"$TEST_DIR/late-line"
  printf '#!/bin/bash\ncat "%s" >>"%s"\nexec "%s" "$@"\n' \
    "$TEST_DIR/late-line" "$DOTFILES_COMMANDS_FILE" "$(command -v tail)" >"$TEST_DIR/slow/tail"
  chmod +x "$TEST_DIR/slow/tail"
  PATH="$TEST_DIR/slow:$PATH" bash "$TEL" cap-commands
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10001 ]
  [ "$(jq -r .sent_commands "$DOTFILES_TELEMETRY_STATE")" -eq 10000 ]
  bash "$TEL" send >/dev/null
  [ "$(jq -s -r '[.[].batch[].properties.command] | join(",")' "$FAKE_LOG")" = "doctor" ]
  bash "$TEL" send >/dev/null
  [ "$(jq -s '[.[].batch[]] | length' "$FAKE_LOG")" -eq 1 ]
}

@test "a state path with & or < still gives a valid LaunchAgent plist" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v plutil >/dev/null 2>&1 || skip "plutil not installed"
  plist="$REPO/launchagents/com.dotfiles.telemetry.plist.tmpl"
  render() { { printf '{{- $_ := set . "dotfiles_dir" "apps/dotfiles" -}}\n'; cat "$plist"; } | chezmoi execute-template --source "$REPO"; }
  XDG_STATE_HOME="$TEST_DIR/a&b <c>" render >"$TEST_DIR/odd.plist"
  plutil -lint "$TEST_DIR/odd.plist"
  # launchd reads back the same path.
  [ "$(plutil -extract EnvironmentVariables.XDG_STATE_HOME raw "$TEST_DIR/odd.plist")" = "$TEST_DIR/a&b <c>" ]
}

@test "an install opt-out as root says it was not saved, and how to save it" {
  run env DOTFILES_TELEMETRY_TEST_UID=0 bash "$TEL" ask --install --no
  [ "$status" -eq 0 ]
  [[ "$output" == *"was not saved"* ]]
  [[ "$output" == *"dotfiles telemetry off"* ]]
  [[ "$output" != *"telemetry: off (--no-telemetry). Nothing is sent."* ]]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
  # A stored no of the user needs no new save: the normal line shows.
  bash "$TEL" off >/dev/null
  run env DOTFILES_TELEMETRY_TEST_UID=0 bash "$TEL" ask --install --no
  [[ "$output" == *"telemetry: off (--no-telemetry)"* ]]
  [[ "$output" != *"was not saved"* ]]
}

@test "the hooks in lib/stats.sh start nothing for root: no question, no send" {
  gate_root
  # No answer yet: a normal user is asked, root is not.
  [ "$(ask_starts)" -eq 1 ]
  [ "$(DOTFILES_TELEMETRY_TEST_UID=0 ask_starts)" -eq 0 ]
  # A stored yes: a terminal run starts the daily send, but not for root.
  say_yes
  daily_starts() {
    local tries=0
    : >"$TEST_DIR/gate.calls"
    DOTFILES_TELEMETRY_SPAWN=1 DOTFILES_TELEMETRY_TTY=1 bash -c "source '$GATE/lib/stats.sh'; _telemetry_daily '$NOW'"
    until [ -s "$TEST_DIR/gate.calls" ] || [ "$tries" -ge 20 ]; do tries=$((tries + 1)); sleep 0.05; done
    grep -c '^daily$' "$TEST_DIR/gate.calls" || true
  }
  [ "$(DOTFILES_TELEMETRY_TEST_UID=0 daily_starts)" -eq 0 ]
  [ "$(daily_starts)" -eq 1 ]
}

@test "a dismissed question leaves no clock file behind" {
  gate_root
  run bash -c "DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --first-run </dev/null"
  [ -e "$TEST_DIR/telemetry.asked-until" ]
  [ "$(ask_starts)" -eq 0 ] # dismissed today: the gate compares the times
  [ ! -e "$TEST_DIR/telemetry.asked-until.now" ]
  # A file left by an older version goes away with the next question.
  : >"$TEST_DIR/telemetry.asked-until.now"
  set_state '.asked_day = "2020-01-01"'
  touch -t 202001010000 "$TEST_DIR/telemetry.asked-until"
  run bash -c "DOTFILES_TELEMETRY_TTY=1 bash '$TEL' ask --first-run </dev/null"
  [ "$(jq -r .asks "$DOTFILES_TELEMETRY_STATE")" -eq 2 ]
  [ ! -e "$TEST_DIR/telemetry.asked-until.now" ]
}

# ── The commands log cap without jq, and as root ────────────────────────

# Seed a log one line under the cut limit plus one; the hook adds one more.
over_limit_log() {
  for ((i = 1; i <= 20001; i++)); do echo "{\"command\":\"status\",\"timestamp\":\"$NOW\",\"ok\":true,\"duration_ms\":$i}"; done >"$DOTFILES_COMMANDS_FILE"
}

@test "with no jq and no state file the commands log is still capped" {
  export DOTFILES_STATS_LOG=1
  over_limit_log
  # A PATH with the plain tools only: no jq.
  mkdir "$TEST_DIR/nojq"
  for tool in bash date mkdir wc tail cp mv rm dirname; do ln -s "$(command -v "$tool")" "$TEST_DIR/nojq/$tool"; done
  env PATH="$TEST_DIR/nojq" DOTFILES_COMMANDS_ROTATE_NOW=1 /bin/bash -c "source '$REPO/lib/stats.sh'; log_command doctor ok 5"
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10000 ]
  [[ "$(tail -n 1 "$DOTFILES_COMMANDS_FILE")" == *'"command":"doctor"'* ]]
  [ -z "$(ls "$TEST_DIR" | grep 'commands.jsonl.tmp' || true)" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
}

@test "as root with no state file the commands log is still capped, and keeps its mode" {
  export DOTFILES_STATS_LOG=1
  over_limit_log
  chmod 640 "$DOTFILES_COMMANDS_FILE"
  DOTFILES_TELEMETRY_TEST_UID=0 DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$REPO/lib/stats.sh'; log_command doctor ok 5"
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10000 ]
  [[ "$(tail -n 1 "$DOTFILES_COMMANDS_FILE")" == *'"command":"doctor"'* ]]
  [[ "$(ls -l "$DOTFILES_COMMANDS_FILE")" == -rw-r-----* ]]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
}

@test "with a state file the cap goes through cap-commands, never the plain cut" {
  export DOTFILES_STATS_LOG=1
  gate_root # its fake bin/dotfiles-telemetry only logs the call
  over_limit_log
  echo '{"consent":"no"}' >"$DOTFILES_TELEMETRY_STATE"
  : >"$TEST_DIR/gate.calls"
  DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$GATE/lib/stats.sh'; log_command doctor ok 5"
  [ "$(cat "$TEST_DIR/gate.calls")" = "cap-commands" ]
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 20002 ]
  # With no state file the hook cuts by itself and starts no script.
  rm -f "$DOTFILES_TELEMETRY_STATE"
  : >"$TEST_DIR/gate.calls"
  DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$GATE/lib/stats.sh'; log_command doctor ok 5"
  [ ! -s "$TEST_DIR/gate.calls" ]
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10000 ]
}

# ── A state file that cannot be read ────────────────────────────────────

@test "apply still renders with an unreadable state file, and reads it as not yes" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  [ "$(id -u)" != "0" ] || skip "root can read every file"
  consent_line() {
    grep '^# telemetry consent:' "$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl" |
      chezmoi execute-template --source "$REPO"
  }
  bash "$TEL" on >/dev/null
  [[ "$(consent_line)" == *"consent: yes" ]]
  chmod 000 "$DOTFILES_TELEMETRY_STATE"
  run consent_line
  chmod 600 "$DOTFILES_TELEMETRY_STATE"
  [ "$status" -eq 0 ]
  [ "$output" = "# telemetry consent: not yes" ]
  # The script body agrees: the agent stays off for that file.
  apply="$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  eval "$(sed -n '/^should_skip_agent() {/,/^}/p' "$apply")"
  SOURCE_DIR="$REPO"
  PROFILE=full
  chmod 000 "$DOTFILES_TELEMETRY_STATE"
  run should_skip_agent telemetry
  chmod 600 "$DOTFILES_TELEMETRY_STATE"
  [ "$status" -eq 0 ]
}

@test "the doctor reports a telemetry state file that is not yours or not readable" {
  # Load only the telemetry part of the chezmoi doctor module, with a check
  # function that records the result and the help text.
  check() {
    if eval "$3" >/dev/null 2>&1; then echo "pass $1"; else echo "fail $1 | fix: $4 | $5"; fi
  }
  doctor() { eval "$(sed -n '/^# ── Telemetry state file/,/^# ── /p' "$REPO/modules/chezmoi/doctor.sh")"; }
  run doctor
  [ "$output" = "pass chezmoi.telemetry_state_readable" ] # no file: nobody answered
  bash "$TEL" off >/dev/null
  run doctor
  [ "$output" = "pass chezmoi.telemetry_state_readable" ]
  # No read bit (for example mode 000).
  chmod 000 "$DOTFILES_TELEMETRY_STATE"
  run doctor
  chmod 600 "$DOTFILES_TELEMETRY_STATE"
  [[ "$output" == "fail chezmoi.telemetry_state_readable"* ]]
  [[ "$output" == *"chmod 600"* ]]
  # Another owner (for example root after an old sudo run): the fix needs sudo.
  DOTFILES_TELEMETRY_TEST_UID=12345 run doctor
  [[ "$output" == "fail chezmoi.telemetry_state_readable"* ]]
  [[ "$output" == *"sudo chown"* ]]
  [[ "$output" == *"$DOTFILES_TELEMETRY_STATE"* ]]
  # The automatic fix repairs a file of your own.
  chmod 000 "$DOTFILES_TELEMETRY_STATE"
  fix="$(doctor | sed 's/.*| fix: \(.*\) | .*/\1/')"
  bash -c "$fix"
  run doctor
  [ "$output" = "pass chezmoi.telemetry_state_readable" ]
  [ "$(consent)" = "no" ]
}

# ── A state folder that cannot be entered ───────────────────────────────

@test "the doctor fails, with the fix command, when the state folder cannot be entered" {
  check() {
    if eval "$3" >/dev/null 2>&1; then echo "pass $1"; else echo "fail $1 | fix: $4 | $5"; fi
  }
  doctor() { eval "$(sed -n '/^# ── Telemetry state file/,/^# ── /p' "$REPO/modules/chezmoi/doctor.sh")"; }
  state_dir="$TEST_DIR/state-dir"
  mkdir "$state_dir"
  export DOTFILES_TELEMETRY_STATE="$state_dir/telemetry.json"
  run doctor
  [ "$output" = "pass chezmoi.telemetry_state_readable" ] # a folder you can enter, no file
  bash "$TEL" off >/dev/null
  chmod 000 "$state_dir"
  run doctor
  [[ "$output" == "fail chezmoi.telemetry_state_readable"* ]] || { chmod 700 "$state_dir"; echo "$output"; return 1; }
  [[ "$output" == *"chmod 700"* ]]
  [[ "$output" == *"$state_dir"* ]]
  # The automatic fix repairs a folder of your own.
  fix="$(doctor | sed 's/.*| fix: \(.*\) | .*/\1/')"
  bash -c "$fix"
  run doctor
  chmod 700 "$state_dir"
  [ "$output" = "pass chezmoi.telemetry_state_readable" ]
  [ "$(consent)" = "no" ]
}

@test "with a state file that cannot be read the commands log is still cut to its cap" {
  export DOTFILES_STATS_LOG=1
  over_limit_log
  echo '{"consent":"yes"}' >"$DOTFILES_TELEMETRY_STATE"
  chmod 000 "$DOTFILES_TELEMETRY_STATE"
  DOTFILES_COMMANDS_ROTATE_NOW=1 bash -c "source '$REPO/lib/stats.sh'; log_command doctor ok 5"
  chmod 600 "$DOTFILES_TELEMETRY_STATE"
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 10000 ]
  [[ "$(tail -n 1 "$DOTFILES_COMMANDS_FILE")" == *'"command":"doctor"'* ]]
}
