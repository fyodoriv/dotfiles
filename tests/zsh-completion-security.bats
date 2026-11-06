#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" SAFE="$TEST_DIR/safe" UNSAFE="$TEST_DIR/unsafe"
  mkdir -p "$HOME" "$SAFE" "$UNSAFE"
  chmod 755 "$SAFE"
  chmod 755 "$UNSAFE"
  printf '#compdef safe-fixture\n' > "$SAFE/_safe_fixture"
  printf '#compdef unsafe-fixture\nprint executed > "$HOME/unsafe-marker"\n' > "$UNSAFE/_unsafe_fixture"
  /bin/zsh -dfc 'fpath=("$UNSAFE" "$SAFE" $fpath); autoload -Uz compinit; compinit -i -d "$HOME/.zcompdump"; [[ ${_comps[unsafe-fixture]} == _unsafe_fixture ]]'
  [ -s "$HOME/.zcompdump" ]
  grep -q unsafe-fixture "$HOME/.zcompdump"
  chmod 777 "$UNSAFE"
  export BLOCK="$TEST_DIR/completion.zsh"
  awk '/^# ── Completion/{active=1; next} active && /zstyle /{exit} active {print}' "$BATS_TEST_DIRNAME/../home/zshrc" > "$BLOCK"
  touch -t 202001010000 "$HOME/.zcompdump"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "old completion dump skips insecure paths and initializes completion" {
  run /bin/zsh -dfc 'setopt extendedglob; fpath=("$UNSAFE" "$SAFE" $fpath); source "$BLOCK"; whence -w compdef; print -r -- "SAFE:${_comps[safe-fixture]-missing}" "UNSAFE:${_comps[unsafe-fixture]-missing}"; print -rl -- $fpath' </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"compdef: function"* ]]
  [[ "$output" == *"$SAFE"* ]]
  [[ "$output" != *"$UNSAFE"* ]]
  [[ "$output" == *"SAFE:_safe_fixture"* ]]
  [[ "$output" == *"UNSAFE:missing"* ]]
  [ ! -e "$HOME/unsafe-marker" ]
  [[ "$output" != *"insecure directories"* ]]
}

@test "current completion dump skips insecure paths and initializes completion" {
  touch "$HOME/.zcompdump"
  run /bin/zsh -dfc 'setopt extendedglob; fpath=("$UNSAFE" "$SAFE" $fpath); source "$BLOCK"; whence -w compdef; print -r -- "SAFE:${_comps[safe-fixture]-missing}" "UNSAFE:${_comps[unsafe-fixture]-missing}"; print -rl -- $fpath' </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"compdef: function"* ]]
  [[ "$output" == *"$SAFE"* ]]
  [[ "$output" != *"$UNSAFE"* ]]
  [[ "$output" == *"SAFE:_safe_fixture"* ]]
  [[ "$output" == *"UNSAFE:missing"* ]]
  [ ! -e "$HOME/unsafe-marker" ]
}

@test "interactive startup preserves the first typed command" {
  run python3 - "$BLOCK" "$SAFE" "$UNSAFE" "$HOME" <<'PY'
import os, pty, select, signal, sys, time
block, safe, unsafe, home = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    env = {**os.environ, "BLOCK": block, "SAFE": safe, "UNSAFE": unsafe, "HOME": home}
    os.execve("/bin/zsh", ["zsh", "-dfi", "-c", 'fpath=("$UNSAFE" "$SAFE" $fpath); source "$BLOCK"; read -r line; print -r -- "INPUT:$line"'], env)
output = b""
status = None
deadline = time.monotonic() + 15
try:
    os.write(fd, b"alpha\n")
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                output += os.read(fd, 4096)
            except OSError:
                pass
        finished, value = os.waitpid(pid, os.WNOHANG)
        if finished:
            status = value
            break
    if status is None:
        raise TimeoutError("interactive shell timed out")
finally:
    if status is None:
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
    os.close(fd)
print(output.decode(errors="replace"))
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"INPUT:alpha"* ]]
  [[ "$output" != *"insecure directories"* ]]
}

@test "doctor advises an audit when a completion directory is insecure" {
  export FPATH="$UNSAFE:$SAFE:$(/bin/zsh -dfc 'print -r -- ${(j.:.)fpath}')"
  check() { :; }
  check_symlink() { :; }
  check_managed() { :; }
  check_advisory() {
    if [ "$1" = shell.completion_permissions ] && ! eval "$3" >/dev/null 2>&1; then
      audit_result=warn
      remediation="$4"
    fi
  }
  DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  audit_result=pass remediation=
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ "$audit_result" = warn ]
  [[ "$remediation" == *zsh-completion-audit.zsh* ]]
}

@test "doctor does not load compaudit from an insecure inherited path" {
  printf 'print unsafe > "$HOME/doctor-marker"\n' > "$UNSAFE/compaudit"
  export FPATH="$UNSAFE:$SAFE:$(/bin/zsh -dfc 'print -r -- ${(j.:.)fpath}')"
  check() { :; }
  check_symlink() { :; }
  check_managed() { :; }
  check_advisory() {
    if [ "$1" = shell.completion_permissions ] && ! eval "$3" >/dev/null 2>&1; then audit_result=warn; fi
  }
  DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  audit_result=pass
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ ! -e "$HOME/doctor-marker" ]
  [ "$audit_result" = warn ]
}

@test "doctor treats a source path with shell syntax as data" {
  local special='$(touch "$HOME/path-marker")'
  DOTFILES_DIR="$TEST_DIR/$special"
  mkdir -p "$DOTFILES_DIR/lib"
  cp "$BATS_TEST_DIRNAME/../lib/zsh-completion-audit.zsh" "$DOTFILES_DIR/lib/"
  check() { :; }
  check_symlink() { :; }
  check_managed() { :; }
  check_advisory() { [ "$1" != shell.completion_permissions ] || eval "$3" >/dev/null 2>&1 || true; }
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ ! -e "$HOME/path-marker" ]
}
