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

teardown() { rm -rf "$TEST_DIR"; }

# A yes covers only later events. say_yes also moves both cursors back to the
# start, so the lines a test seeded count as recorded after the yes.
say_yes() {
  bash "$TEL" on >/dev/null
  set_state '.sent = 0 | .sent_commands = 0'
}
consent() { jq -r .consent "$DOTFILES_TELEMETRY_STATE"; }
requests() { if [ -f "$FAKE_LOG" ]; then jq -s 'length' "$FAKE_LOG"; else echo 0; fi; }
set_state() { jq -c "$1" "$DOTFILES_TELEMETRY_STATE" >"$TEST_DIR/state.new" && mv "$TEST_DIR/state.new" "$DOTFILES_TELEMETRY_STATE"; }
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
    "bin/dotfiles-telemetry" "docs/observability.md#telemetry" "PostHog EU" \
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
  seed_lines 2600
  export DOTFILES_STATS_LOG=1
  run bash -c "printf 'y\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' cd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Share anonymous performance numbers? [y/n]"* ]]
  [ "$(consent)" = "yes" ]
  wait_for_command_lines 1
  # The 2,600 events from before the yes are never sent; only later ones are.
  printf '{"task":"sync","timestamp":"%s","units":9001}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" daily
  [ "$(requests)" -eq 2 ]
  [ "$(jq -s -c '[.[].batch[].properties | (.units // .command)]' "$FAKE_LOG")" = '[9001,"cd"]' ]
  [ "$(jq -r .last_send "$DOTFILES_TELEMETRY_STATE")" = "$(date -u +%F)" ]
  run bash -c "printf 'n\n' | DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' cd"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  [ "$(consent)" = "yes" ]
}

@test "a command with no terminal never asks; nor with CI or DO_NOT_TRACK; nor telemetry itself" {
  run bash -c "printf 'y\n' | bash '$REPO/bin/dotfiles' cd"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  run bash -c "printf 'y\n' | CI=1 DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' cd"
  [[ "$output" != *"Share anonymous performance numbers?"* ]]
  run bash -c "printf 'y\n' | DO_NOT_TRACK=1 DOTFILES_TELEMETRY_TTY=1 bash '$REPO/bin/dotfiles' cd"
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
  [ -n "$names" ]
  recorded="$(grep -rhE '^[^#]*log_run "?[a-z]' --exclude=dotfiles-telemetry "$REPO/bin" | grep -oE 'log_run "?[a-z][a-z0-9-]*' | sed -E 's/log_run "?//' | sort -u)"
  [ "$(echo "$recorded" | wc -l)" -ge 8 ]
  for name in $recorded doctor shell-start; do
    [[ " $names " == *" $name "* ]] || { echo "not in TASK_NAMES: $name"; return 1; }
  done
  say_yes
  for name in $names; do printf '{"task":"%s","timestamp":"%s"}\n' "$name" "$NOW"; done >"$DOTFILES_STATS_FILE"
  for name in doctor apply sync telemetry start; do printf '{"command":"%s","timestamp":"%s","ok":true,"duration_ms":1}\n' "$name" "$NOW"; done >"$DOTFILES_COMMANDS_FILE"
  bash "$TEL" send >/dev/null
  [ "$(jq -s -r '[.[].batch[].properties.task | select(. != null)] | join(" ")' "$FAKE_LOG")" = "$names" ]
  [ "$(jq -s -r '[.[].batch[].properties.command | select(. != null)] | join(" ")' "$FAKE_LOG")" = "doctor apply sync telemetry start" ]
}

# ── Reliability ─────────────────────────────────────────────────────────
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
  printf '#!/bin/bash\necho started >>"%s/hung.calls"\nexec sleep 60\n' "$TEST_DIR" >"$FAKE"
  start="$(date +%s)"
  run bash "$TEL" daily
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ $(($(date +%s) - start)) -le 8 ]
  [ "$(wc -l <"$TEST_DIR/hung.calls" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "0" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE.lock" ]
  run pgrep -f "sleep 60"
  [ "$status" -ne 0 ] || { pkill -f "sleep 60"; false; }
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
  grep -q -- "--max-time 3 " "$FAKE_LOG.args"
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

@test "log_run and log_command start no send in a test and drop a bad name or time" {
  export DOTFILES_STATS_LOG=1
  say_yes
  run bash -c "source '$REPO/lib/stats.sh'; log_run sync; log_command doctor ok 12; log_command 'Bad Name' ok 1; log_command doctor ok notanumber"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$DOTFILES_COMMANDS_FILE" | tr -d ' ')" -eq 1 ]
  [ "$(requests)" -eq 0 ]
}
