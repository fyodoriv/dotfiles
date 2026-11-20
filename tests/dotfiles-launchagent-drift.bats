#!/usr/bin/env bats
# bin/dotfiles-launchagent-drift (issue #297): after `dotfiles apply`, a plist
# on disk can be right while launchd still runs the old loaded copy, and a
# KeepAlive job bootstrapped from a non-GUI shell can stay not running. The
# script compares each loaded com.dotfiles.* job with its plist and, with
# --fix, reloads a drifted job and kickstarts a stopped one. A launchctl stub
# stands in for launchd; nothing real is loaded.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-launchagent-drift"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  AGENTS="$HOME/Library/LaunchAgents"
  mkdir -p "$AGENTS" "$TEST_DIR/bin" "$TEST_DIR/print"
  cat > "$TEST_DIR/bin/launchctl" <<EOF2
#!/bin/bash
echo "\$*" >> "$TEST_DIR/calls"
case "\$1" in
  print)
    f="$TEST_DIR/print/\${2##*/}"
    [ -f "\$f" ] || exit 113
    cat "\$f" ;;
  print-disabled) cat "$TEST_DIR/disabled" 2>/dev/null ;;
  asuser)
    [ "\$3" = /bin/launchctl ] && [ "\$4" = getenv ] || exit 2
    [ ! -e "$TEST_DIR/domain-env-offline" ] || exit 2
    case "\$5" in
      TOOLING_ROOT|BASH_ENV) cat "$TEST_DIR/inherited-\$5" 2>/dev/null || true ;;
      *) exit 2 ;;
    esac ;;
  bootout) rm -f "$TEST_DIR/print/\${2##*/}" ;;
esac
exit 0
EOF2
  chmod +x "$TEST_DIR/bin/launchctl"
  export PATH="$TEST_DIR/bin:$PATH"
  export DOTFILES_LAUNCHCTL="$TEST_DIR/bin/launchctl"
}

teardown() { rm -rf "$TEST_DIR"; }

# plist <label> <keepalive true|false> <arg>...
plist() {
  local label="$1" keep="$2" a args=""
  shift 2
  for a in "$@"; do args="$args<string>$a</string>"; done
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array>%s</array><key>RunAtLoad</key><true/><key>KeepAlive</key><%s/></dict></plist>\n' \
    "$label" "$args" "$keep" > "$AGENTS/$label.plist"
}

# loaded <label> <state> <arg>...: what `launchctl print` shows.
loaded() {
  local label="$1" state="$2" a
  shift 2
  { printf 'gui/501/%s = {\n\tstate = %s\n\targuments = {\n' "$label" "$state"
    for a in "$@"; do printf '\t\t%s\n' "$a"; done
    printf '\t}\n\tjob state = exited\n}\n'
  } > "$TEST_DIR/print/$label"
}

tool_checkout() {
  TOOL_CHECKOUT="$TEST_DIR/checkout"
  mkdir -p "$TOOL_CHECKOUT/bin" "$TOOL_CHECKOUT/lib" "$TEST_DIR/job-bin"
  cp "$SCRIPT" "$TOOL_CHECKOUT/bin/dotfiles-launchagent-drift"
  cp "$BATS_TEST_DIRNAME/../lib/launchagent-args.sh" "$TOOL_CHECKOUT/lib/"
}

sync_fixture() {
  tool_checkout
  SYNC_PROBE="$TOOL_CHECKOUT/bin/dotfiles-launchagent-drift"
  SYNC_SCRIPT="$TOOL_CHECKOUT/bin/dotfiles-sync"
  SYNC_LABEL=com.dotfiles.dotfiles-sync
  SYNC_PLIST="$AGENTS/$SYNC_LABEL.plist"
  printf '#!/bin/bash\ntouch "%s"\n' "$TEST_DIR/script-ran" > "$SYNC_SCRIPT"
  printf '#!/bin/bash\ntouch "%s"\n' "$TEST_DIR/tool-ran" > "$TEST_DIR/bin/chezmoi"
  chmod +x "$SYNC_SCRIPT" "$TEST_DIR/bin/chezmoi"
  plist "$SYNC_LABEL" true /bin/bash "$SYNC_SCRIPT"
}

sync_job_path() {
  /usr/bin/plutil -insert EnvironmentVariables -xml '<dict/>' "$SYNC_PLIST"
  /usr/bin/plutil -insert EnvironmentVariables.PATH -string "$1" "$SYNC_PLIST"
}

@test "the sync job reports a missing tool without using the caller PATH or repairing" {
  sync_fixture
  sync_job_path "$TEST_DIR/job-bin"
  loaded "$SYNC_LABEL" waiting /bin/bash "$SYNC_SCRIPT"
  run "$SYNC_PROBE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $SYNC_LABEL: chezmoi is missing"* ]]
  [[ "$output" != *"$TEST_DIR/job-bin"* ]]
  run "$SYNC_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $SYNC_LABEL:"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/script-ran" ] && [ ! -e "$TEST_DIR/tool-ran" ]
}

@test "the sync job uses the stripped default to stop an unsafe bootstrap" {
  sync_fixture
  run "$SYNC_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $SYNC_LABEL: chezmoi is missing"* ]]
  [ -z "$(grep '^bootstrap ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/script-ran" ] && [ ! -e "$TEST_DIR/tool-ran" ]
}

@test "the sync job can find an executable on the declared PATH without running it" {
  sync_fixture
  cp "$TEST_DIR/bin/chezmoi" "$TEST_DIR/job-bin/chezmoi"
  sync_job_path "/usr/bin:$TEST_DIR/job-bin"
  loaded "$SYNC_LABEL" running /bin/bash "$SYNC_SCRIPT"
  run "$SYNC_PROBE"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $SYNC_LABEL" ]
  [ ! -e "$TEST_DIR/script-ran" ] && [ ! -e "$TEST_DIR/tool-ran" ]
}

@test "the tool check never runs a startup file or an unregistered command form" {
  sync_fixture
  printf '#!/bin/bash\ntouch "%s"\n' "$TEST_DIR/startup-ran" > "$TEST_DIR/startup"
  sync_job_path "$TEST_DIR/job-bin"
  /usr/bin/plutil -insert EnvironmentVariables.BASH_ENV -string "$TEST_DIR/startup" "$SYNC_PLIST"
  loaded "$SYNC_LABEL" running /bin/bash "$SYNC_SCRIPT"
  run "$SYNC_PROBE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool-path-unverified $SYNC_LABEL:"* ]]
  [[ "$output" != *"$TEST_DIR/startup"* ]]
  [ ! -e "$TEST_DIR/startup-ran" ]
  rm "$TEST_DIR/print/$SYNC_LABEL"
  run "$SYNC_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $SYNC_LABEL:"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/startup-ran" ]
  plist "$SYNC_LABEL" true /bin/bash -c "touch $TEST_DIR/inline-ran"
  loaded "$SYNC_LABEL" running /bin/bash -c "touch $TEST_DIR/inline-ran"
  run "$SYNC_PROBE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool-path-unverified $SYNC_LABEL:"* ]]
  [ ! -e "$TEST_DIR/inline-ran" ]
  [ ! -e "$TEST_DIR/script-ran" ] && [ ! -e "$TEST_DIR/tool-ran" ]
}

@test "a disabled sync job stays out of the tool check and repair" {
  sync_fixture
  printf '    "%s" => disabled\n' "$SYNC_LABEL" > "$TEST_DIR/disabled"
  run "$SYNC_PROBE" --fix
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/script-ran" ] && [ ! -e "$TEST_DIR/tool-ran" ]
}

@test "the load sampler needs both declared tools before repair" {
  tool_checkout
  local label=com.dotfiles.load-sampler
  local sampler="$TOOL_CHECKOUT/bin/dotfiles-load-sampler"
  local probe="$TOOL_CHECKOUT/bin/dotfiles-launchagent-drift"
  local file="$AGENTS/$label.plist" tool other
  for tool in "$sampler" "$TEST_DIR/bin/sysctl" "$TEST_DIR/bin/ps"; do
    printf '#!/bin/bash\ntouch "%s"\n' "$TEST_DIR/executed" > "$tool"
    chmod +x "$tool"
  done
  plist "$label" true /bin/bash "$sampler"
  /usr/bin/plutil -insert EnvironmentVariables -xml '<dict/>' "$file"
  /usr/bin/plutil -insert EnvironmentVariables.PATH -string "$TEST_DIR/job-bin" "$file"
  loaded "$label" waiting /bin/bash "$sampler"

  for tool in sysctl ps; do
    other=ps
    [ "$tool" = ps ] && other=sysctl
    cp "$TEST_DIR/bin/$other" "$TEST_DIR/job-bin/$other"
    run "$probe"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tool-path $label: $tool is missing"* ]]
    [[ "$output" != *"$TEST_DIR"* ]]
    run "$probe" --fix
    [ "$status" -eq 1 ]
    [[ "$output" == *"tool-path $label: $tool is missing"* ]]
    rm "$TEST_DIR/job-bin/$other"
  done

  cp "$TEST_DIR/bin/sysctl" "$TEST_DIR/bin/ps" "$TEST_DIR/job-bin/"
  loaded "$label" running /bin/bash "$sampler"
  run "$probe"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $label" ]

  plist "$label" true /bin/bash "$sampler" --report
  rm "$TEST_DIR/print/$label"
  run "$probe" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $label:"* ]]

  printf '    "%s" => disabled\n' "$label" > "$TEST_DIR/disabled"
  run "$probe" --fix
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "the Git maintenance job needs Git on its declared PATH before repair" {
  tool_checkout
  local label=com.dotfiles.git-maintain
  local job="$TOOL_CHECKOUT/bin/git-maintain"
  local probe="$TOOL_CHECKOUT/bin/dotfiles-launchagent-drift"
  local file="$AGENTS/$label.plist" executable
  for executable in "$job" "$TEST_DIR/bin/git"; do
    printf '#!/bin/bash\ntouch "%s"\n' "$TEST_DIR/executed" > "$executable"
    chmod +x "$executable"
  done
  plist "$label" false /bin/bash "$job"
  /usr/bin/plutil -insert EnvironmentVariables -xml '<dict/>' "$file"
  /usr/bin/plutil -insert EnvironmentVariables.PATH -string "$TEST_DIR/job-bin" "$file"
  loaded "$label" running /bin/bash "$job"

  run "$probe"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $label: git is missing"* ]]
  [[ "$output" != *"$TEST_DIR"* ]]

  rm "$TEST_DIR/print/$label"
  run "$probe" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $label: git is missing"* ]]

  cp "$TEST_DIR/bin/git" "$TEST_DIR/job-bin/git"
  loaded "$label" running /bin/bash "$job"
  run "$probe"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $label" ]

  plist "$label" false /bin/bash "$job" --quick
  rm "$TEST_DIR/print/$label"
  run "$probe" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $label:"* ]]

  printf '    "%s" => disabled\n' "$label" > "$TEST_DIR/disabled"
  run "$probe" --fix
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

tooling_sync_fixture() {
  tool_checkout
  TOOLING_PROBE="$TOOL_CHECKOUT/bin/dotfiles-launchagent-drift"
  TOOLING_SCRIPT="$TOOL_CHECKOUT/bin/tooling-sync"
  TOOLING_LABEL=com.dotfiles.tooling-sync
  TOOLING_PLIST="$AGENTS/$TOOLING_LABEL.plist"
  TOOLING_REPO="$HOME/apps/tooling/agentbrew"
  local executable
  for executable in "$TOOLING_SCRIPT" "$TEST_DIR/bin/git"; do
    printf '#!/bin/bash\ntouch "%s"\n' "$TEST_DIR/executed" > "$executable"
    chmod +x "$executable"
  done
  plist "$TOOLING_LABEL" false /bin/bash "$TOOLING_SCRIPT"
  tooling_sync_env
}

tooling_sync_env() {
  /usr/bin/plutil -insert EnvironmentVariables -xml '<dict/>' "$TOOLING_PLIST"
  /usr/bin/plutil -insert EnvironmentVariables.HOME -string "$HOME" "$TOOLING_PLIST"
  /usr/bin/plutil -insert EnvironmentVariables.PATH -string "$TEST_DIR/job-bin" "$TOOLING_PLIST"
}

@test "the hourly tooling sync reports missing Git for an eligible checkout" {
  tooling_sync_fixture
  mkdir -p "$TOOLING_REPO/.git"
  loaded "$TOOLING_LABEL" waiting /bin/bash "$TOOLING_SCRIPT"
  run "$TOOLING_PROBE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $TOOLING_LABEL: git is missing"* ]]
  [[ "$output" != *"$TEST_DIR"* ]]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "the hourly tooling sync with missing Git cannot be bootstrapped" {
  tooling_sync_fixture
  mkdir -p "$TOOLING_REPO/.git"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path $TOOLING_LABEL: git is missing"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "hourly tooling sync tool lookup matches the default checkout condition" {
  tooling_sync_fixture
  loaded "$TOOLING_LABEL" waiting /bin/bash "$TOOLING_SCRIPT"
  run "$TOOLING_PROBE"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $TOOLING_LABEL" ]

  mkdir -p "$TOOLING_REPO"
  printf '%s\n' 'gitdir: synthetic-worktree' > "$TOOLING_REPO/.git"
  run "$TOOLING_PROBE"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $TOOLING_LABEL" ]

  rm "$TOOLING_REPO/.git"
  mkdir "$TOOLING_REPO/.git"
  cp "$TEST_DIR/bin/git" "$TEST_DIR/job-bin/git"
  run "$TOOLING_PROBE"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $TOOLING_LABEL" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "hourly tooling sync keeps repair off with unsupported inputs" {
  tooling_sync_fixture
  /usr/bin/plutil -replace EnvironmentVariables.HOME -string "$TEST_DIR/other" "$TOOLING_PLIST"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]
  [[ "$output" != *"$TEST_DIR"* ]]

  /usr/bin/plutil -replace EnvironmentVariables.HOME -string "$HOME" "$TOOLING_PLIST"
  /usr/bin/plutil -insert EnvironmentVariables.TOOLING_ROOT -string "$TEST_DIR/other" "$TOOLING_PLIST"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]

  plist "$TOOLING_LABEL" false /bin/bash "$TOOLING_SCRIPT" --dry-run
  tooling_sync_env
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "hourly tooling sync leaves repair off with an inherited checkout override" {
  tooling_sync_fixture
  printf '%s\n' "$TEST_DIR/custom" > "$TEST_DIR/inherited-TOOLING_ROOT"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]
  [[ "$output" != *"$TEST_DIR"* ]]
  printf '\n' > "$TEST_DIR/inherited-TOOLING_ROOT"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "hourly tooling sync reports the plan but keeps repair off with inherited startup" {
  tooling_sync_fixture
  mkdir -p "$TOOLING_REPO/.git"
  cp "$TEST_DIR/bin/git" "$TEST_DIR/job-bin/git"
  printf '%s\n' "$TOOLING_SCRIPT" > "$TEST_DIR/inherited-BASH_ENV"
  loaded "$TOOLING_LABEL" waiting /bin/bash "$TOOLING_SCRIPT"
  run "$TOOLING_PROBE"
  [ "$status" -eq 0 ]
  [ "$output" = "ok $TOOLING_LABEL" ]
  rm "$TEST_DIR/print/$TOOLING_LABEL"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]
  [[ "$output" != *"$TEST_DIR"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "hourly tooling sync leaves repair off when the user-domain check fails" {
  tooling_sync_fixture
  touch "$TEST_DIR/domain-env-offline"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool-path-unverified $TOOLING_LABEL:"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "an intentionally disabled hourly tooling sync job remains off" {
  tooling_sync_fixture
  mkdir -p "$TOOLING_REPO/.git"
  printf '    "%s" => disabled\n' "$TOOLING_LABEL" > "$TEST_DIR/disabled"
  run "$TOOLING_PROBE" --fix
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ ! -e "$TEST_DIR/executed" ]
}

@test "a job whose loaded arguments match its plist and that runs is ok" {
  plist com.dotfiles.a true /bin/bash /x/a.sh
  loaded com.dotfiles.a running /bin/bash /x/a.sh
  run "$SCRIPT"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok com.dotfiles.a"* ]]
}

@test "a plist with unexpanded log paths is reported without restarting it" {
  local label=com.dotfiles.bad-logs
  plist "$label" true /bin/bash /x/a.sh
  loaded "$label" running /bin/bash /x/old.sh
  /usr/bin/plutil -insert StandardOutPath -string '${HOME}/logs/out' "$AGENTS/$label.plist"
  /usr/bin/plutil -insert StandardErrorPath -string '${HOME}/logs/err' "$AGENTS/$label.plist"
  local before
  before="$(shasum "$AGENTS/$label.plist")"

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"log-path $label: unexpanded HOME in StandardOutPath, StandardErrorPath."* ]]
  [[ "$output" != *"/logs/"* ]]
  run "$SCRIPT" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"log-path $label:"* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
  [ "$(shasum "$AGENTS/$label.plist")" = "$before" ]
}

@test "a bad log path prevents bootstrap and a rendered log path can bootstrap" {
  local label=com.dotfiles.new
  plist "$label" true /bin/bash /x/c.sh
  /usr/bin/plutil -insert StandardErrorPath -string '${HOME}/logs/err' "$AGENTS/$label.plist"
  run "$SCRIPT" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"log-path $label: unexpanded HOME in StandardErrorPath."* ]]
  [ -z "$(grep '^bootstrap ' "$TEST_DIR/calls")" ]

  /usr/bin/plutil -replace StandardErrorPath -string "$HOME/logs/err" "$AGENTS/$label.plist"
  run "$SCRIPT" --fix
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrapped $label"* ]]
  grep -q '^bootstrap ' "$TEST_DIR/calls"
}

@test "a stopped job with a stale loaded log path does not kickstart" {
  local label=com.dotfiles.stale-log
  plist "$label" true /bin/bash /x/a.sh
  /usr/bin/plutil -insert StandardOutPath -string "$HOME/logs/out" "$AGENTS/$label.plist"
  printf 'gui/501/%s = {\n\tstate = not running\n\targuments = {\n\t\t/bin/bash\n\t\t/x/a.sh\n\t}\n\tstdout path = %s\n}\n' \
    "$label" '${HOME}/logs/old' > "$TEST_DIR/print/$label"

  run "$SCRIPT" --fix
  [ "$status" -eq 1 ]
  [[ "$output" == *"log-path $label: unexpanded HOME in loaded StandardOutPath."* ]]
  [ -z "$(grep -E '^(bootout|bootstrap|kickstart) ' "$TEST_DIR/calls")" ]
}

@test "a job whose loaded arguments differ from its plist is drift, and --fix reloads it" {
  plist com.dotfiles.chrome false /bin/bash /x/relay "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9223
  loaded com.dotfiles.chrome running "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9223
  run "$SCRIPT"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift com.dotfiles.chrome: the loaded job runs other arguments than its plist"* ]]
  run "$SCRIPT" --fix
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q "^bootout gui/$(id -u)/com.dotfiles.chrome" "$TEST_DIR/calls"
  grep -q "^bootstrap gui/$(id -u) $AGENTS/com.dotfiles.chrome.plist" "$TEST_DIR/calls"
  [[ "$output" == *"reloaded com.dotfiles.chrome"* ]]
}

@test "a KeepAlive job that is not running is stopped, and --fix kickstarts it" {
  plist com.dotfiles.b true /bin/bash /x/b.sh
  loaded com.dotfiles.b "not running" /bin/bash /x/b.sh
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stopped com.dotfiles.b: KeepAlive job is not running"* ]]
  run "$SCRIPT" --fix
  grep -q "^kickstart gui/$(id -u)/com.dotfiles.b" "$TEST_DIR/calls"
  [[ "$output" == *"kickstarted com.dotfiles.b"* ]]
}

@test "a job without KeepAlive may be not running (it ran and exited)" {
  plist com.dotfiles.c false /bin/bash /x/c.sh
  loaded com.dotfiles.c "not running" /bin/bash /x/c.sh
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a plist that is not loaded is reported, and --fix bootstraps it" {
  plist com.dotfiles.d true /bin/bash /x/d.sh
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unloaded com.dotfiles.d"* ]]
  run "$SCRIPT" --fix
  grep -q "^bootstrap gui/$(id -u) $AGENTS/com.dotfiles.d.plist" "$TEST_DIR/calls"
}

@test "only com.dotfiles jobs are checked" {
  plist com.other.e true /bin/bash /x/e.sh
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"com.other.e"* ]]
}

@test "a disabled job that is not loaded is off on purpose: no line, and --fix leaves it" {
  plist com.dotfiles.dotfiles-upgrade true /bin/bash /x/u.sh
  printf 'disabled services = {\n\t"com.dotfiles.dotfiles-upgrade" => disabled\n}\n' > "$TEST_DIR/disabled"
  run env PATH="/usr/bin:/bin:$TEST_DIR/bin" bash "$SCRIPT" --fix
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" != *dotfiles-upgrade* ]]
  ! grep -q '^bootstrap' "$TEST_DIR/calls"
}

@test "in endpoint safe mode --fix only reports" {
  plist com.dotfiles.d true /bin/bash /x/d.sh
  mkdir -p "$HOME/.local/state/dotfiles" && touch "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  run "$SCRIPT" --fix
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"endpoint safe mode: --fix only reports"* ]]
  [[ "$output" == *"unloaded com.dotfiles.d"* ]]
  ! grep -q '^bootstrap' "$TEST_DIR/calls"
}

@test "a job with only Program is compared by its program line" {
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>com.dotfiles.p</string><key>Program</key><string>/x/p</string></dict></plist>\n' > "$AGENTS/com.dotfiles.p.plist"
  printf 'gui/501/com.dotfiles.p = {\n\tstate = running\n\tprogram = /x/p\n}\n' > "$TEST_DIR/print/com.dotfiles.p"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok com.dotfiles.p"* ]]
}
