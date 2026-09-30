#!/usr/bin/env bats
# Validate every `launchagents/*.plist*` template/plain plist.
#
# The repo ships a fleet of LaunchAgents — auto-sync, auto-doctor,
# morning, sleepwatcher, upgrade, etc. They're rendered via chezmoi
# templating, copied into ~/Library/LaunchAgents/, and loaded by
# launchctl. Per-agent tests cover specific behaviors (sleepwatcher
# routes to network-watchdog, etc.); this file is the generic gate
# that catches three failure classes across all 15+ plists at once:
#
#   1. plutil refuses the rendered XML (typo, missing closing tag).
#   2. The `Label` doesn't match the filename → launchctl bootout
#      can't find the agent under the expected label.
#   3. `ProgramArguments[0]` doesn't resolve to a real executable
#      → the agent silently fails on first load.
#   4. `EnvironmentVariables.LANG` is missing → launchd starts the job
#      with no locale, and Homebrew gawk (the bin/awk shim) then fails
#      every regex match that is not anchored at the start of the line.
#
# Closes add-launchagent-plist-validation-test.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
LAUNCHAGENTS="$REPO_ROOT/launchagents"

# Render a plist (template or plain) into a fresh temp file and echo
# the path. Caller is responsible for removing the result.
_render_plist() {
  local src="$1"
  local out
  out=$(mktemp)
  if [[ "$src" == *.tmpl ]]; then
    chezmoi execute-template --source "$REPO_ROOT" < "$src" > "$out"
  else
    cp "$src" "$out"
  fi
  echo "$out"
}

# Pull the first <string> following <key>NAME</key> in a plist.
_plist_string_for_key() {
  local plist="$1" key="$2"
  awk -v k="$key" '
    $0 ~ "<key>" k "</key>" { found = 1; next }
    found && /<string>/ {
      sub(/^[[:space:]]*<string>/, "")
      sub(/<\/string>.*$/, "")
      print
      exit
    }
  ' "$plist"
}

# Pull the first <string> inside the ProgramArguments array.
_plist_program_arg0() {
  local plist="$1"
  awk '
    /<key>ProgramArguments<\/key>/ { in_prog = 1; next }
    in_prog && /<\/array>/ { exit }
    in_prog && /<string>/ {
      sub(/^[[:space:]]*<string>/, "")
      sub(/<\/string>.*$/, "")
      print
      exit
    }
  ' "$plist"
}

_plist_bool_for_key() {
  local plist="$1" key="$2"
  awk -v k="$key" '
    $0 ~ "<key>" k "</key>" { found = 1; next }
    found && /<true\/>/ { print "true"; exit }
    found && /<false\/>/ { print "false"; exit }
  ' "$plist"
}

# Resolve `prog` as one of: absolute path that exists, or
# Mac-app launcher (/Applications/...) that may legitimately be
# missing on a CI machine. Returns 0 if acceptable.
_program_resolves() {
  local prog="$1"
  case "$prog" in
    "") return 1 ;;  # empty arg
    /Applications/*)
      # Chrome / other Mac apps may not be installed on every machine
      # (CI especially). The plist still has to point at a real path
      # shape; we don't fail when the binary itself is absent.
      return 0
      ;;
    /*)
      # Absolute path — it must exist as an executable file. The
      # sleepwatcher plist is special: chezmoi templating picks
      # /opt/homebrew/sbin/sleepwatcher when present, falling back to
      # /usr/local/sbin/sleepwatcher; whichever path the renderer
      # chose is the one we expect to find.
      [ -x "$prog" ]
      ;;
    *)
      # Bare command — not currently used by any of our plists, but
      # would resolve via the plist's EnvironmentVariables.PATH at
      # launch time. We don't do that lookup here; flag for review.
      return 1
      ;;
  esac
}

@test "every launchagent plist exists and parses (plutil -lint)" {
  shopt -s nullglob
  local plists=("$LAUNCHAGENTS"/*.plist*)
  shopt -u nullglob
  [ "${#plists[@]}" -gt 0 ] || { echo "no launchagent plists found"; return 1; }

  local src rendered
  for src in "${plists[@]}"; do
    rendered=$(_render_plist "$src")
    plutil -lint "$rendered" >/dev/null 2>&1 || {
      echo "plutil -lint failed for $(basename "$src")"
      plutil -lint "$rendered"
      rm -f "$rendered"
      return 1
    }
    rm -f "$rendered"
  done
}

@test "every launchagent plist Label matches its filename" {
  shopt -s nullglob
  local plists=("$LAUNCHAGENTS"/*.plist*)
  shopt -u nullglob

  local src basename expected actual rendered
  for src in "${plists[@]}"; do
    basename=$(basename "$src")
    # com.dotfiles.morning.plist.tmpl → com.dotfiles.morning
    expected="${basename%.plist*}"
    expected="${expected%.tmpl}"

    rendered=$(_render_plist "$src")
    actual=$(_plist_string_for_key "$rendered" "Label")
    rm -f "$rendered"
    [ "$actual" = "$expected" ] || {
      echo "$basename: Label '$actual' does not match filename-derived '$expected'"
      return 1
    }
  done
}

@test "every launchagent plist ProgramArguments[0] resolves to an executable" {
  shopt -s nullglob
  local plists=("$LAUNCHAGENTS"/*.plist*)
  shopt -u nullglob

  local src basename prog rendered
  for src in "${plists[@]}"; do
    basename=$(basename "$src")
    rendered=$(_render_plist "$src")
    prog=$(_plist_program_arg0 "$rendered")
    rm -f "$rendered"
    [ -n "$prog" ] || { echo "$basename: ProgramArguments[0] is empty"; return 1; }
    _program_resolves "$prog" || {
      echo "$basename: ProgramArguments[0] does not resolve to an executable"
      echo "  prog: $prog"
      return 1
    }
  done
}

@test "every launchagent PATH prepends dotfiles bin before /usr/bin" {
  shopt -s nullglob
  local plists=("$LAUNCHAGENTS"/*.plist*)
  shopt -u nullglob

  local src rendered path first_component
  for src in "${plists[@]}"; do
    rendered=$(_render_plist "$src")
    path=$(_plist_string_for_key "$rendered" "PATH")
    rm -f "$rendered"
    [ -n "$path" ] || continue

    first_component="${path%%:*}"
    [[ "$first_component" == */bin && "$first_component" != "/usr/bin" ]] || {
      echo "$(basename "$src"): first PATH entry must be dotfiles bin shim directory"
      echo "  first=$first_component"
      echo "  PATH=$path"
      return 1
    }
  done
}

@test "every launchagent plist sets LANG=C.UTF-8" {
  shopt -s nullglob
  local plists=("$LAUNCHAGENTS"/*.plist*)
  shopt -u nullglob

  local src rendered lang
  for src in "${plists[@]}"; do
    rendered=$(_render_plist "$src")
    lang=$(plutil -extract EnvironmentVariables.LANG raw -o - "$rendered" 2>/dev/null || true)
    rm -f "$rendered"
    [ "$lang" = "C.UTF-8" ] || {
      echo "$(basename "$src"): EnvironmentVariables.LANG must be C.UTF-8 (got '$lang')"
      return 1
    }
  done
}

@test "launchagent-path template puts ~/.local/bin before /usr/local/bin" {
  local rendered path local_idx usr_local_idx
  rendered=$(_render_plist "$LAUNCHAGENTS/com.dotfiles.dotfiles-doctor.plist.tmpl")
  path=$(_plist_string_for_key "$rendered" "PATH")
  rm -f "$rendered"
  [ -n "$path" ]
  local_idx=$(awk -v p="$path" 'BEGIN{n=split(p,a,":"); for(i=1;i<=n;i++) if(a[i] ~ /\.local\/bin$/) {print i; exit}}')
  usr_local_idx=$(awk -v p="$path" 'BEGIN{n=split(p,a,":"); for(i=1;i<=n;i++) if(a[i]=="/usr/local/bin") {print i; exit}}')
  [ -n "$local_idx" ] && [ -n "$usr_local_idx" ] && [ "$local_idx" -lt "$usr_local_idx" ]
}

@test "managed Chrome launchagents do not KeepAlive-reopen during shutdown" {
  local src rendered keepalive
  for src in \
    "$LAUNCHAGENTS/com.dotfiles.agent-browser-chrome.plist.tmpl" \
    "$LAUNCHAGENTS/com.dotfiles.debug-chrome.plist.tmpl" \
    "$LAUNCHAGENTS/com.dotfiles.tooling-chrome.plist.tmpl"; do
    rendered=$(_render_plist "$src")
    keepalive=$(_plist_bool_for_key "$rendered" "KeepAlive")
    rm -f "$rendered"
    [ "$keepalive" = "false" ] || {
      echo "$(basename "$src"): KeepAlive must be false so Chrome stays closed for logout/shutdown"
      return 1
    }
  done
}
