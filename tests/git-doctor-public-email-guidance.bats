#!/usr/bin/env bats

load test_helper

setup() {
  ROOT="$BATS_TEST_TMPDIR/public email"
  REPO="$ROOT/repo with space"
  HOME="$ROOT/home"
  mkdir -p "$REPO/bin" "$REPO/modules/identity" "$ROOT/bin" "$HOME"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$REPO/lib"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$REPO/bin/dotfiles-doctor"
  python3 - "$BATS_TEST_DIRNAME/../modules/git/doctor.sh" "$REPO/modules/identity/doctor.sh" <<'PY'
from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text().splitlines(keepends=True)
starts=[i for i,line in enumerate(lines) if line.startswith('if [ -n "${OSS_READINESS_PRIVATE_EMAIL_PATTERN:-}" ]; then')]
assert len(starts)==1
i=starts[0]; block=[]
while True:
    line=lines[i]; block.append(line); i+=1
    if line.strip() == 'fi': break
assert sum('check "git.user_email_is_public_safe"' in line for line in block)==1
Path(sys.argv[2]).write_text('source "$DOTFILES_DIR/lib/oss-readiness.sh"\n'+''.join(block))
PY
  cat > "$ROOT/bin/chezmoi" <<'SH'
#!/bin/sh
case "$1" in source-path) printf '%s\n' "$REPO" ;; *) exit 1 ;; esac
SH
  chmod +x "$ROOT/bin/chezmoi"
  export HOME REPO GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1 DOTFILES_DOCTOR_NOTIFY=0
  export OSS_READINESS_PRIVATE_EMAIL_PATTERN='@private[.]example$'
  export PATH="$ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
  export XDG_STATE_HOME="$HOME/.local/state"
  /usr/bin/git init -q "$REPO"
}

config_hashes() {
  shasum -a 256 "$REPO/.git/config" "$HOME/.gitconfig" | awk '{print $1}'
}

@test "private local email gets human guidance without a fix or disclosure" {
  /usr/bin/git config --file "$HOME/.gitconfig" user.email public@example.com
  /usr/bin/git -C "$REPO" config --local user.email person@private.example
  before=$(config_hashes)
  quoted_repo=$(printf '%q' "$REPO")
  expected_command="git -C $quoted_repo config --local user.email \"YOUR PUBLIC EMAIL\""
  run bash "$REPO/bin/dotfiles-doctor" --module identity --json
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e --arg command "$expected_command" '
    any(.[]; .id == "git.user_email_is_public_safe" and .status == "fail" and
      (has("fix") | not) and (.message | contains("You:")) and
      (.message | contains("inspect")) and (.message | contains("choose")) and
      (.message | contains("public-safe")) and (.message | contains($command)))' >/dev/null
  [[ "$output" != *'person@private.example'* && "$output" != *'@private[.]example$'* ]]
  [ "$(config_hashes)" = "$before" ]
  run bash "$REPO/bin/dotfiles-doctor" --module identity
  [ "$status" -ne 0 ]
  [[ "$output" == *'You:'* && "$output" == *"$expected_command"* && "$output" == *'choose'* ]]
  [[ "$output" != *'person@private.example'* && "$output" != *'@private[.]example$'* ]]
  [ "$(config_hashes)" = "$before" ]
  run bash "$REPO/bin/dotfiles-doctor" --module identity --fix --json
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "git.user_email_is_public_safe" and .status == "fail" and (has("fix") | not))' >/dev/null
  [[ "$output" != *'person@private.example'* && "$output" != *'@private[.]example$'* ]]
  [ "$(config_hashes)" = "$before" ]
}

@test "safe local email wins over a private global email" {
  /usr/bin/git config --file "$HOME/.gitconfig" user.email person@private.example
  /usr/bin/git -C "$REPO" config --local user.email public@example.com
  before=$(config_hashes)
  run bash "$REPO/bin/dotfiles-doctor" --module identity --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "git.user_email_is_public_safe" and .status == "pass" and .message == "git user.email does not match the configured private-email pattern")' >/dev/null
  [[ "$output" != *'person@private.example'* && "$output" != *'@private[.]example$'* ]]
  [ "$(config_hashes)" = "$before" ]
  run bash "$REPO/bin/dotfiles-doctor" --module identity
  [ "$status" -eq 0 ]
  [[ "$output" == *'git user.email does not match the configured private-email pattern'* ]]
  [[ "$output" != *'person@private.example'* && "$output" != *'@private[.]example$'* ]]
  [ "$(config_hashes)" = "$before" ]
  run bash "$REPO/bin/dotfiles-doctor" --module identity --fix --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "git.user_email_is_public_safe" and .status == "pass" and (has("fix") | not))' >/dev/null
  [[ "$output" != *'person@private.example'* && "$output" != *'@private[.]example$'* ]]
  [ "$(config_hashes)" = "$before" ]
}
