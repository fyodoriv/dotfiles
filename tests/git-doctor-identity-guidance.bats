#!/usr/bin/env bats

load test_helper

setup() {
  ROOT="$BATS_TEST_TMPDIR/identity"
  REPO="$ROOT/repo"
  HOME="$ROOT/home"
  mkdir -p "$REPO/bin" "$REPO/modules/identity" "$ROOT/bin" "$HOME"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$REPO/lib"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$REPO/bin/dotfiles-doctor"
  cp "$BATS_TEST_DIRNAME/../gitconfig.local.example" "$REPO/gitconfig.local.example"
  python3 - "$BATS_TEST_DIRNAME/../modules/git/doctor.sh" "$REPO/modules/identity/doctor.sh" <<'PY'
from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text().splitlines(keepends=True)
ids=('git.local_config','git.user_name','git.user_email')
blocks=[]
for target in ids:
    starts=[i for i,line in enumerate(lines) if line.startswith('check "'+target+'" ')]
    assert len(starts)==1
    i=starts[0]; block=[]
    while True:
        line=lines[i]; block.append(line); i+=1
        if not line.rstrip().endswith('\\'): break
    blocks.extend(block)
Path(sys.argv[2]).write_text(''.join(blocks))
PY
  cat > "$ROOT/bin/chezmoi" <<'SH'
#!/bin/sh
case "$1" in source-path) printf '%s\n' "$REPO" ;; *) exit 1 ;; esac
SH
  chmod +x "$ROOT/bin/chezmoi"
  export HOME REPO GIT_CONFIG_GLOBAL="$HOME/.gitconfig.local" GIT_CONFIG_NOSYSTEM=1 DOTFILES_DOCTOR_NOTIFY=0
  export PATH="$ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
  export XDG_STATE_HOME="$HOME/.local/state"
}

@test "missing identity failures name the person and actions in JSON and text" {
  run bash "$REPO/bin/dotfiles-doctor" --module identity --json
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e '
    [.[] | select(.id == "git.local_config" or .id == "git.user_name" or .id == "git.user_email")] as $checks |
    ($checks | length) == 3 and all($checks[]; .status == "fail" and (.message | contains("You:")) and (has("fix") | not)) and
    any($checks[]; .id == "git.local_config" and (.message | contains("cp -n")) and (.message | contains("$(chezmoi source-path)/gitconfig.local.example")) and (.message | contains("$HOME/.gitconfig.local")) and (.message | contains("edit the example name and email"))) and
    any($checks[]; .id == "git.user_name" and (.message | contains("inspect your Git configuration")) and (.message | contains("$HOME/.gitconfig.local")) and (.message | contains("if user.name is absent")) and (.message | contains("--add user.name")) and (.message | contains("otherwise correct")) and (.message | contains("ensure Git includes"))) and
    any($checks[]; .id == "git.user_email" and (.message | contains("inspect your Git configuration")) and (.message | contains("$HOME/.gitconfig.local")) and (.message | contains("if user.email is absent")) and (.message | contains("--add user.email")) and (.message | contains("otherwise correct")) and (.message | contains("ensure Git includes")))' >/dev/null
  [ ! -e "$HOME/.gitconfig.local" ]
  run bash "$REPO/bin/dotfiles-doctor" --module identity
  [ "$status" -ne 0 ]
  [[ "$output" == *"You:"* && "$output" == *"--add user.name"* && "$output" == *"--add user.email"* ]]
  [ ! -e "$HOME/.gitconfig.local" ]
}

@test "fix mode does not create an absent identity file" {
  run bash "$REPO/bin/dotfiles-doctor" --module identity --fix --json
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.gitconfig.local" ]
  printf '%s' "$output" | jq -e '[.[] | select(.id == "git.local_config" or .id == "git.user_name" or .id == "git.user_email")] | length == 3 and all(.[]; .status == "fail" and (has("fix") | not))' >/dev/null
}

@test "partial identity is preserved during fix mode" {
  printf '[user]\n\tname = Existing Person\n' > "$HOME/.gitconfig.local"
  before=$(shasum -a 256 "$HOME/.gitconfig.local" | cut -d ' ' -f 1)
  run bash "$REPO/bin/dotfiles-doctor" --module identity --fix --json
  [ "$status" -ne 0 ]
  after=$(shasum -a 256 "$HOME/.gitconfig.local" | cut -d ' ' -f 1)
  [ "$before" = "$after" ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "git.user_name" and .status == "pass") and any(.[]; .id == "git.user_email" and .status == "fail" and (.message | contains("--add user.email")))' >/dev/null
}

@test "existing email is preserved when the name is missing" {
  printf '[user]\n\temail = person@example.com\n' > "$HOME/.gitconfig.local"
  before=$(shasum -a 256 "$HOME/.gitconfig.local" | cut -d ' ' -f 1)
  run bash "$REPO/bin/dotfiles-doctor" --module identity --fix --json
  [ "$status" -ne 0 ]
  after=$(shasum -a 256 "$HOME/.gitconfig.local" | cut -d ' ' -f 1)
  [ "$before" = "$after" ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "git.user_email" and .status == "pass") and any(.[]; .id == "git.user_name" and .status == "fail" and (.message | contains("--add user.name")))' >/dev/null
}

@test "passing identity checks keep their original descriptions" {
  printf '[user]\n\tname = Example Person\n\temail = person@example.com\n' > "$HOME/.gitconfig.local"
  before=$(shasum -a 256 "$HOME/.gitconfig.local" | cut -d ' ' -f 1)
  run bash "$REPO/bin/dotfiles-doctor" --module identity --json
  printf '%s' "$output" | jq -e '
    any(.[]; .id == "git.local_config" and .status == "pass" and .message == "$HOME/.gitconfig.local exists (name + email)") and
    any(.[]; .id == "git.user_name" and .status == "pass" and .message == "git user.name is set") and
    any(.[]; .id == "git.user_email" and .status == "pass" and .message == "git user.email is set")' >/dev/null
  after=$(shasum -a 256 "$HOME/.gitconfig.local" | cut -d ' ' -f 1)
  [ "$before" = "$after" ]
}
