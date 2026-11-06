#!/usr/bin/env bats

load test_helper

setup() {
  WRAPPER="$BATS_TEST_DIRNAME/../bin/git"
  SCRATCH="$BATS_TEST_TMPDIR/lazy-git"
  mkdir -p "$SCRATCH/bin" "$SCRATCH/config"
  STUB="$SCRATCH/real-git"
  MARKER="$SCRATCH/pushed"
  cat > "$STUB" <<'STUB'
#!/bin/bash
case "${1:-}" in
  fail) printf 'out\n'; printf 'err\n' >&2; exit 23 ;;
  signal) printf 'out\n'; printf 'err\n' >&2; kill -TERM "$$" ;;
  stream) printf first; read -r line; printf '%s' "$line" ;;
esac
case " $* " in
  *" remote get-url "*) [ -n "${FAKE_REMOTE_URL:-}" ] || exit 1; printf '%s\n' "$FAKE_REMOTE_URL" ;;
  *" push "*)
    printf called > "$MARKER"
    if [ -n "${DOTFILES_PUBLIC_PUSH_ALLOWLIST:-}" ] && [ -f "$DOTFILES_PUBLIC_PUSH_ALLOWLIST" ]; then
      cat "$DOTFILES_PUBLIC_PUSH_ALLOWLIST" > "$MARKER.allowlist"
      printf '%s' "$DOTFILES_PUBLIC_PUSH_ALLOWLIST" > "$MARKER.path"
    fi ;;
esac
STUB
  chmod +x "$STUB"
  : > "$SCRATCH/private"
  export MARKER
}

compare_command() {
  run bash -c 'out=$1; err=$2; shift 2; "$@" > "$out" 2> "$err"' _ "$SCRATCH/direct.out" "$SCRATCH/direct.err" /usr/bin/git "$@"
  local direct_status="$status"
  run bash -c 'out=$1; err=$2; shift 2; "$@" > "$out" 2> "$err"' _ "$SCRATCH/wrapper.out" "$SCRATCH/wrapper.err" env -u DOTFILES_REAL_GIT -u DOTFILES_SYSTEM_GIT -u DOTFILES_PUBLIC_PUSH_ALLOWLIST -u DOTFILES_PRIVATE_PUSH_ALLOWLIST "$WRAPPER" "$@"
  [ "$status" -eq "$direct_status" ]
  cmp -s "$SCRATCH/direct.out" "$SCRATCH/wrapper.out"
  cmp -s "$SCRATCH/direct.err" "$SCRATCH/wrapper.err"
}

@test "lazy wrapper preserves version output" {
  compare_command --version
}

@test "lazy wrapper preserves git-dir output" {
  compare_command rev-parse --git-dir
}

@test "lazy wrapper preserves ordinary failure output and status" {
  compare_command rev-parse --verify refs/heads/nonexistent-lazy-483
}

@test "lazy wrapper preserves a signal exit and both output streams" {
  run bash -c '"$1" signal > "$2" 2> "$3"' _ "$STUB" "$SCRATCH/direct.out" "$SCRATCH/direct.err"
  local direct_status="$status"
  run bash -c 'env DOTFILES_REAL_GIT="$1" "$2" signal > "$3" 2> "$4"' _ "$STUB" "$WRAPPER" "$SCRATCH/wrapper.out" "$SCRATCH/wrapper.err"
  [ "$direct_status" -eq 143 ]
  [ "$status" -eq "$direct_status" ]
  cmp -s "$SCRATCH/direct.out" "$SCRATCH/wrapper.out"
  cmp -s "$SCRATCH/direct.err" "$SCRATCH/wrapper.err"
}

@test "lazy wrapper streams output before stdin closes" {
  run python3 - "$WRAPPER" "$STUB" <<'PY'
import os, select, subprocess, sys
wrapper, stub = sys.argv[1:]
for argv, env in (([stub, "stream"], os.environ.copy()), ([wrapper, "stream"], {**os.environ, "DOTFILES_REAL_GIT": stub})):
    p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        ready, _, _ = select.select([p.stdout], [], [], 3)
        assert ready and os.read(p.stdout.fileno(), 5) == b"first"
        p.stdin.write(b"second\n"); p.stdin.flush(); p.stdin.close()
        assert p.stdout.read() == b"second"
        assert p.wait(timeout=3) == 0
    finally:
        if p.poll() is None:
            p.kill(); p.wait(timeout=3)
PY
  [ "$status" -eq 0 ]
}

@test "lazy wrapper uses default allowlist for approved push" {
  run env -u DOTFILES_PUBLIC_PUSH_ALLOWLIST CODEX_AGENT=1 DOTFILES_REAL_GIT="$STUB" DOTFILES_PRIVATE_PUSH_ALLOWLIST="$SCRATCH/private" "$WRAPPER" push https://github.com/fyodoriv/agentbrew.git topic
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
}

@test "lazy wrapper blocks unapproved and unresolved pushes" {
  run env -u DOTFILES_PUBLIC_PUSH_ALLOWLIST CODEX_AGENT=1 DOTFILES_REAL_GIT="$STUB" DOTFILES_PRIVATE_PUSH_ALLOWLIST="$SCRATCH/private" "$WRAPPER" push https://github.com/example/not-approved.git topic
  [ "$status" -eq 1 ]
  [ ! -e "$MARKER" ]
  run env -u DOTFILES_PUBLIC_PUSH_ALLOWLIST CODEX_AGENT=1 DOTFILES_REAL_GIT="$STUB" DOTFILES_PRIVATE_PUSH_ALLOWLIST="$SCRATCH/private" "$WRAPPER" push origin topic
  [ "$status" -eq 1 ]
  [ ! -e "$MARKER" ]
}

@test "lazy wrapper honors an override allowlist" {
  printf '%s\n' github.com/example/allowed > "$SCRATCH/allowed"
  run env CODEX_AGENT=1 DOTFILES_REAL_GIT="$STUB" DOTFILES_PUBLIC_PUSH_ALLOWLIST="$SCRATCH/allowed" DOTFILES_PRIVATE_PUSH_ALLOWLIST="$SCRATCH/private" "$WRAPPER" push https://github.com/example/allowed.git topic
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
}

@test "lazy wrapper resolves a symlink invocation as before" {
  ln -s "$WRAPPER" "$SCRATCH/bin/git"
  printf '%s\n' github.com/example/allowed > "$SCRATCH/config/public-push-remotes.txt"
  run env -u DOTFILES_PUBLIC_PUSH_ALLOWLIST CODEX_AGENT=1 DOTFILES_REAL_GIT="$STUB" DOTFILES_PRIVATE_PUSH_ALLOWLIST="$SCRATCH/private" "$SCRATCH/bin/git" push https://github.com/example/allowed.git topic
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
}

@test "lazy wrapper snapshots a FIFO allowlist" {
  mkfifo "$SCRATCH/allowed-fifo"
  python3 - "$SCRATCH/allowed-fifo" <<'PY' &
import signal, sys
signal.alarm(5)
with open(sys.argv[1], 'w') as out:
    out.write('github.com/example/allowed\n')
PY
  writer=$!
  run env CODEX_AGENT=1 DOTFILES_REAL_GIT="$STUB" DOTFILES_PUBLIC_PUSH_ALLOWLIST="$SCRATCH/allowed-fifo" DOTFILES_PRIVATE_PUSH_ALLOWLIST="$SCRATCH/private" "$WRAPPER" push https://github.com/example/allowed.git topic
  wait "$writer"
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
  [ "$(<"$MARKER.allowlist")" = 'github.com/example/allowed' ]
  snapshot=$(<"$MARKER.path")
  [ "$snapshot" != "$SCRATCH/allowed-fifo" ]
  [ ! -e "$snapshot" ]
}

@test "lazy benchmark evaluator rejects invalid comparisons" {
  run python3 - "$BATS_TEST_DIRNAME/../docs/plans/git-wrapper-lazy-483-evaluate.py" "$SCRATCH" <<'PY'
import copy, json, subprocess, sys
from pathlib import Path
evaluator, root = sys.argv[1], Path(sys.argv[2])
commands = ['/usr/bin/git --version', './bin/git --version', '/usr/bin/git rev-parse --git-dir', './bin/git rev-parse --git-dir']
def record(phase, wrapper, started, wrapped):
    values = [.020, wrapped, .020, wrapped]
    paths=['bin/git','docs/plans/git-wrapper-lazy-483-bench.sh','docs/plans/git-wrapper-lazy-483-evaluate.py','tests/git-wrapper-lazy-483.bats','/usr/bin/git']
    hashes={path:'a'*64 for path in paths}; hashes['bin/git']=wrapper*64
    return {'phase':phase, 'head':'a'*40, 'environmentHash':'b'*64, 'hashes':hashes, 'loadBefore':1, 'loadAfter':1, 'logicalCpus':10, 'startedNs':started, 'endedNs':started+1, 'results':[{'command':command,'median':value,'stddev':.001,'times':[value]*20} for command,value in zip(commands,values)]}
before, after = record('before','a',1,.030), record('after','b',3,.026)
def run(a,b):
    (root/'before.json').write_text(json.dumps(a)); (root/'after.json').write_text(json.dumps(b))
    return subprocess.run([sys.executable,evaluator,str(root/'before.json'),str(root/'after.json')],capture_output=True).returncode
assert run(before,after) == 0
cases = []
x=copy.deepcopy(after); x['results'][0]['command']='wrong'; cases.append(x)
x=copy.deepcopy(after); x['hashes']['bin/git']='a'*64; cases.append(x)
x=copy.deepcopy(after); x['results'][1]['median']=.029; x['results'][1]['times']=[.029]*20; cases.append(x)
x=copy.deepcopy(after); x['loadAfter']=11; cases.append(x)
x=copy.deepcopy(after); x['results'][0]['times'].pop(); cases.append(x)
x=copy.deepcopy(after); x['startedNs']=1; cases.append(x)
x=copy.deepcopy(after); x['hashes'].pop('/usr/bin/git'); cases.append(x)
x=copy.deepcopy(after); x['loadAfter']=float('nan'); cases.append(x)
assert all(run(before,x) != 0 for x in cases)
PY
  [ "$status" -eq 0 ]
}
