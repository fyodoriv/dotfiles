#!/usr/bin/env bats
# bin/dotfiles-install: plan, backup, apply, heal, verify, auto-restore, and
# the agentbrew hand-off. chezmoi, defaults, launchctl, brew, zsh, and the
# doctor are stubs, so nothing touches the real Mac.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_DIR/home" XDG_STATE_HOME="$TEST_DIR/home/.local/state"
  STUBS="$TEST_DIR/stubs"; LOG="$TEST_DIR/calls.log"; STORE="$TEST_DIR/defaults"
  mkdir -p "$HOME/.config/chezmoi" "$STUBS" "$STORE"
  printf '# my zshrc\n' > "$HOME/.zshrc"
  printf 'old-config\n' > "$HOME/.config/chezmoi/chezmoi.yaml"
  printf 'original-dock\n' > "$STORE/com.apple.dock"

  stub() { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
  stub chezmoi 'echo "chezmoi $*" >> "$LOG"
case "$1" in
  init) mkdir -p "$HOME/.config/chezmoi"; echo new-config > "$HOME/.config/chezmoi/chezmoi.yaml" ;;
  managed) case "$*" in *dirs*) printf ".agent-browser\n" ;; *) printf ".zshrc\n.gitconfig\n.agent-browser/config.json\n" ;; esac ;;
  apply)
    echo "# dotfiles zshrc" > "$HOME/.zshrc"; echo "[user]" > "$HOME/.gitconfig"
    mkdir -p "$HOME/.agent-browser"; echo "{}" > "$HOME/.agent-browser/config.json"
    [ -z "${SCRIPT_CACHE:-}" ] || { mkdir -p "$HOME/.cache/e2e-tool"; echo x > "$HOME/.cache/e2e-tool/data"; }
    mkdir -p "$HOME/Library/LaunchAgents"; echo plist > "$HOME/Library/LaunchAgents/com.dotfiles.sync.plist"
    [ "${DOTFILES_SKIP_MACOS_DEFAULTS:-}" = 1 ] || { defaults write com.apple.dock autohide -bool true; defaults write com.apple.finder X -bool true; }
    exit "${FAIL_APPLY:-0}" ;;
  verify)
    # Real chezmoi verify always fails while scripts are included.
    [[ " $* " == *" --exclude scripts "* ]] || exit 1
    exit "${FAIL_VERIFY:-0}" ;;
esac'
  stub defaults 'echo "defaults $*" >> "$LOG"
case "$1" in
  export) [ -f "$STORE/$2" ] && cp "$STORE/$2" "$3" ;;
  import) cp "$3" "$STORE/$2" ;;
  write) echo "changed $*" > "$STORE/$2" ;;
  delete) rm -f "$STORE/$2" ;;
esac'
  for tool in launchctl brew killall xcode-select; do stub "$tool" "echo \"$tool \$*\" >> \"\$LOG\""; done
  stub zsh 'exit 0'
  stub doctor 'echo "doctor $*" >> "$LOG"'
  # Homebrew jq lives under the brew prefix; the endpoint scripts need it.
  mkdir -p "$TEST_DIR/brew/bin"; printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/brew/bin/jq"; chmod +x "$TEST_DIR/brew/bin/jq"
  export PATH="$STUBS:$PATH" LOG STORE DOTFILES_INSTALL_DOCTOR="$STUBS/doctor" DOTFILES_BREW_PREFIX="$TEST_DIR/brew"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "plan explains needs, steps, backup, rollback limits, and choices, and changes nothing" {
  run bash "$REPO/bin/dotfiles-install" plan
  [ "$status" -eq 0 ]
  for text in "What you need" "Your Mac password" "Back up to" "macOS settings domains" \
    "restores the backup automatically" "Homebrew packages stay installed" "Also install agentbrew"; do
    [[ "$output" == *"$text"* ]] || { echo "missing: $text"; return 1; }
  done
  [ ! -e "$XDG_STATE_HOME/dotfiles" ]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]
}

@test "plan says will be installed for missing chezmoi and Homebrew jq, and installs nothing" {
  rm -f "$STUBS/chezmoi" "$TEST_DIR/brew/bin/jq"
  run env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$REPO/bin/dotfiles-install" plan
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"chezmoi: will be installed"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"jq (Homebrew): will be installed"* ]] || { echo "$output"; return 1; }
  if printf '%s\n' "$output" | grep -E '✓ (chezmoi|jq)'; then return 1; fi
  if grep -q 'brew install' "$LOG" 2>/dev/null; then cat "$LOG"; return 1; fi
}

@test "run installs Homebrew jq when only /usr/bin/jq is on PATH" {
  rm -f "$TEST_DIR/brew/bin/jq"
  stub brew "echo \"brew \$*\" >> \"\$LOG\"; [ \"\$1 \$2\" = 'install jq' ] && printf '#!/bin/bash\\nexit 0\\n' > \"$TEST_DIR/brew/bin/jq\" && chmod +x \"$TEST_DIR/brew/bin/jq\"; exit 0"
  run env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'brew install jq' "$LOG"
  [[ "$output" == *"jq (Homebrew) (installed)"* ]]
}

@test "a failed apply removes the targets it created, so the file list matches the one before" {
  mkdir -p "$HOME/Library/LaunchAgents"
  # Everything but the backup itself (under ~/.local/state) must match.
  list() { (cd "$HOME" && find . | grep -vxE '\./\.local(/state.*)?' | LC_ALL=C sort); }
  local before; before="$(list)"
  FAIL_APPLY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.agent-browser" ] || { echo "left behind: $(cd "$HOME" && find .agent-browser)"; return 1; }
  diff <(printf '%s\n' "$before") <(list)
}

@test "a failed run removes a chezmoi config folder it created and lists script leftovers it keeps" {
  rm -rf "$HOME/.config"
  SCRIPT_CACHE=1 FAIL_APPLY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.config" ] || { echo "left behind: $(cd "$HOME" && find .config)"; return 1; }
  [[ "$output" == *"not chezmoi targets, so restore keeps them"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"      ~/.cache"* ]]
  [[ "$output" != *"~/.cache/e2e-tool"* ]]
  # Paths were kept, so it must not claim the Mac is exactly as before.
  [[ "$output" != *"Your Mac is back to how it was before"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"apart from the new path(s) listed above"* ]] || { echo "$output"; return 1; }
  [ -e "$HOME/.cache/e2e-tool/data" ]
}

@test "plan shows this Mac's baseline: zsh start median, free disk, and the profile's disk use" {
  stub zsh 'echo "zsh $*" >> "$LOG"; exit 0'
  run bash "$REPO/bin/dotfiles-install" plan
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" =~ zsh\ start:\ median\ [0-9]+\ ms\ of\ 3\ runs ]] || { echo "$output"; return 1; }
  [[ "$output" =~ Free\ disk:\ [0-9]+\.[0-9]\ GB ]] || { echo "$output"; return 1; }
  [[ "$output" =~ Expected\ disk\ use\ \(core\):\ about\ [0-9.]+\ GB ]] || { echo "$output"; return 1; }
  [[ "$output" == *"dotfiles metrics --baseline"* ]]
  [ "$(grep -c '^zsh -i -c exit' "$LOG")" -eq 3 ]
  run bash "$REPO/bin/dotfiles-install" plan --profile full
  [[ "$output" =~ Expected\ disk\ use\ \(full\):\ about\ [0-9.]+\ GB ]] || { echo "$output"; return 1; }
}

@test "run saves an install receipt: the before snapshot, its time, and the outcome" {
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  receipt="$XDG_STATE_HOME/dotfiles/install-receipt.json"
  [ -f "$receipt" ] || { echo "no receipt at $receipt"; return 1; }
  jq -e '.profile == "core"' "$receipt"
  jq -e '(.before.zsh_ms | type) == "number" and (.before.free_gb | type) == "number"' "$receipt"
  # The snapshot is taken before apply adds com.dotfiles.sync.plist.
  jq -e '.before.launchagents == 0' "$receipt"
  jq -e '.run.ok == true and (.run.seconds | type) == "number" and .run.seconds >= 0' "$receipt"
  jq -e '(.before.taken_at | type) == "string" and (.run.finished_at | type) == "string"' "$receipt"
}

@test "the before snapshot also records the agent setup that was there" {
  mkdir -p "$HOME/.claude/skills/a" "$HOME/.claude/skills/b"
  printf '%s\n' '{"permissions":{"defaultMode":"default"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}' > "$HOME/.claude/settings.json"
  printf 'hello\n' > "$HOME/.claude/CLAUDE.md"
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  receipt="$XDG_STATE_HOME/dotfiles/install-receipt.json"
  jq -e '.before.claude_skills == 2 and .before.claude_hooks == 1' "$receipt"
  jq -e '.before.claude_md_bytes == 6 and .before.claude_permissions == "default"' "$receipt"
}

@test "with no Claude setup the agent fields are zero and none" {
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  jq -e '.before.claude_skills == 0 and .before.claude_hooks == 0 and .before.claude_md_bytes == 0 and .before.claude_permissions == "none"' \
    "$XDG_STATE_HOME/dotfiles/install-receipt.json"
}

@test "a failed run records the failure in the receipt" {
  FAIL_APPLY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  jq -e '.run.ok == false and .run.failed_step == "chezmoi apply"' "$XDG_STATE_HOME/dotfiles/install-receipt.json"
}

@test "a second run keeps the first before snapshot" {
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  first="$(jq -r '.before.taken_at' "$XDG_STATE_HOME/dotfiles/install-receipt.json")"
  sleep 1
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ]
  jq -e --arg t "$first" '.before.taken_at == $t and .before.launchagents == 0' "$XDG_STATE_HOME/dotfiles/install-receipt.json"
}

@test "metrics --gains shows before vs now, time to configured, and labels estimates" {
  mkdir -p "$XDG_STATE_HOME/dotfiles"
  printf '%s\n' '{"profile":"core","before":{"taken_at":"2026-10-01T10:00:00Z","zsh_ms":400,"free_gb":200.5,"launchagents":3,"claude_skills":5,"claude_hooks":0,"claude_md_bytes":0,"claude_permissions":"default"},"run":{"started_at":"2026-10-01T10:00:00Z","finished_at":"2026-10-01T10:14:00Z","seconds":840,"ok":true}}' \
    > "$XDG_STATE_HOME/dotfiles/install-receipt.json"
  printf '%s\n' '{"task":"sync","timestamp":"2026-10-05T10:00:00Z","seconds_saved":120,"units":1}' \
    '{"task":"sync","timestamp":"2026-09-01T10:00:00Z","seconds_saved":999,"units":1}' > "$HOME/.dotfiles-stats.jsonl"
  run bash "$REPO/bin/dotfiles-metrics" --gains
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"zsh start"*"400"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"LaunchAgents"*"3"* ]]
  [[ "$output" == *"Claude skills"*"5"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"Claude permissions"*"default"* ]]
  [[ "$output" == *"Time to configured: 14 min"* ]]
  # Only stats rows after the install count, and they are called estimates.
  [[ "$output" == *"2 min"*"estimate"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"999"* ]]
}

@test "metrics --gains without a receipt says how to get one" {
  run bash "$REPO/bin/dotfiles-metrics" --gains
  [ "$status" -eq 0 ]
  [[ "$output" == *"No install receipt yet"*"dotfiles-install run"* ]]
}

@test "run refuses without --yes" {
  run bash "$REPO/bin/dotfiles-install" run
  [ "$status" -eq 2 ]
}

@test "run backs up, applies with the answers, heals, verifies, and suggests a fork PR" {
  run bash "$REPO/bin/dotfiles-install" run --yes --profile full --name "Alex Example" --email alex@example.com --no-agentbrew
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'promptChoice Installation profile.*=full' "$LOG"
  grep -q 'Git commit email for work/default identity=alex@example.com' "$LOG"
  grep -q 'chezmoi apply' "$LOG"
  grep -q 'doctor --fix' "$LOG"
  grep -q 'chezmoi verify' "$LOG"
  [[ "$output" == *"dotfiles contribute"* ]]
  [[ "$output" == *"add a test and update the docs"* ]]
  local backup; backup="$(ls "$XDG_STATE_HOME/dotfiles/install-backups")"
  [ -f "$XDG_STATE_HOME/dotfiles/install-backups/$backup/defaults/com.apple.dock.plist" ]
  [ "$(cat "$XDG_STATE_HOME/dotfiles/install-backups/$backup/chezmoi.yaml")" = "old-config" ]
}

@test "a failed verify restores files, LaunchAgents, chezmoi config, and macOS settings by itself" {
  FAIL_VERIFY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Critical error during verification"* ]]
  [[ "$output" == *"Your Mac is back to how it was before"* ]] || { echo "$output"; return 1; }
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]
  [ ! -e "$HOME/.gitconfig" ]
  [ ! -e "$HOME/Library/LaunchAgents/com.dotfiles.sync.plist" ]
  [ "$(cat "$HOME/.config/chezmoi/chezmoi.yaml")" = "old-config" ]
  [ "$(cat "$STORE/com.apple.dock")" = "original-dock" ]
  [ ! -e "$STORE/com.apple.finder" ]
}

@test "a failed apply restores too, and --no-macos-defaults leaves settings alone" {
  FAIL_APPLY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]

  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew --no-macos-defaults
  [ "$status" -eq 0 ]
  [ "$(cat "$STORE/com.apple.dock")" = "original-dock" ]
  run bash "$REPO/bin/dotfiles-install" restore < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--yes"* ]]
  # --help prints the usage, and an unknown flag is no backup ID.
  run bash "$REPO/bin/dotfiles-install" restore --help < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-install restore"* ]]
  run bash "$REPO/bin/dotfiles-install" restore --bogus --yes < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown flag: --bogus"* ]]
  run bash "$REPO/bin/dotfiles-install" restore --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]
}

@test "hands off to agentbrew's installer with the user's agentbrew flags" {
  mkdir -p "$TEST_DIR/agentbrew/.git" "$TEST_DIR/agentbrew/scripts"
  printf '#!/bin/bash\necho "agentbrew-install $*" >> "%s"\n' "$LOG" > "$TEST_DIR/agentbrew/scripts/install.sh"
  run bash "$REPO/bin/dotfiles-install" run --yes --agentbrew-dir "$TEST_DIR/agentbrew" --agentbrew-flags "--no-auto-repair"
  [ "$status" -eq 0 ]
  grep -q 'agentbrew-install run --yes --no-auto-repair' "$LOG"
}

@test "preflight installs a missing tool with Homebrew instead of stopping" {
  stub brew "echo \"brew \$*\" >> \"\$LOG\"; [ \"\$1\" = install ] && printf '#!/bin/bash\\nexit 0\\n' > \"$STUBS/\$2\" && chmod +x \"$STUBS/\$2\"; exit 0"
  run env DOTFILES_INSTALL_TOOLS="git e2e-missing-tool" bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'brew install e2e-missing-tool' "$LOG"
  [[ "$output" == *"e2e-missing-tool (installed)"* ]]
}

@test "preflight stops with the fix when Homebrew cannot install a tool" {
  stub brew 'echo "brew $*" >> "$LOG"; exit 1'
  run env DOTFILES_INSTALL_TOOLS="e2e-missing-tool" bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ e2e-missing-tool: brew install e2e-missing-tool"* ]]
  [[ "$output" == *"Nothing was changed"* ]]
}

@test "running the install twice succeeds and leaves the same files" {
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ]
  local first_zshrc first_gitconfig
  first_zshrc="$(cat "$HOME/.zshrc")"; first_gitconfig="$(cat "$HOME/.gitconfig")"
  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles is installed"* ]]
  [ "$(cat "$HOME/.zshrc")" = "$first_zshrc" ]
  [ "$(cat "$HOME/.gitconfig")" = "$first_gitconfig" ]
  ls "$XDG_STATE_HOME/dotfiles/install-backups"/*/files.tar.gz >/dev/null
}

@test "optional steps warn instead of failing: a failing doctor --fix and agentbrew installer" {
  stub doctor 'echo "doctor $*" >> "$LOG"; exit 1'
  mkdir -p "$TEST_DIR/agentbrew/.git" "$TEST_DIR/agentbrew/scripts"
  printf '#!/bin/bash\nexit 1\n' > "$TEST_DIR/agentbrew/scripts/install.sh"
  run bash "$REPO/bin/dotfiles-install" run --yes --agentbrew-dir "$TEST_DIR/agentbrew"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Some checks still fail"* ]]
  [[ "$output" == *"agentbrew did not install"* ]]
  [[ "$output" == *"dotfiles is installed"* ]]
}

@test "README quick start offers the one sentence for the agent, and INSTALL.md covers every phase" {
  head -40 "$REPO/README.md" | grep -qF "Install dotfiles by following https://github.com/fyodoriv/dotfiles/blob/feat/chezmoi/INSTALL.md"
  for text in "dotfiles-install plan" "dotfiles-install run --yes" "dotfiles-install restore" \
    "full context" "restores the backup by itself" "add or update a test" "dotfiles contribute"; do
    grep -qF "$text" "$REPO/INSTALL.md" || { echo "INSTALL.md missing: $text"; return 1; }
  done
  # Every flag the playbook maps answers to exists in the installer.
  for flag in $(grep -oE -- '--(no-[a-z-]+|profile|name|email|agentbrew-flags)' "$REPO/INSTALL.md" | sort -u); do
    grep -qF -- "$flag" "$REPO/bin/dotfiles-install" || { echo "unknown flag in INSTALL.md: $flag"; return 1; }
  done
  grep -qx 'INSTALL.md' "$REPO/.chezmoiignore"
}
