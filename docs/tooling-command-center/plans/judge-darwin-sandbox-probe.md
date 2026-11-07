# Judge reader: Darwin sandbox boundary probe (draft)

The Linux reader build and smoke checks passed, but the existing judge draft
also needs a source-bound Darwin reader before it can compose safely with the
compiler-free native pair. This probe tests only a synthetic sandbox boundary;
it does not compile or run the reader and does not qualify process-tree
ownership or cleanup for a compiler.
The loopback positive control is performed by the parent process; it does not
independently test that the same child interpreter can connect unsandboxed.

Goal: establish a bounded initial I/O boundary on this Mac. Predict 6/6
checks pass: unsandboxed loopback control connects; sandboxed loopback does
not connect; a private canary cannot be read; an outside file cannot be
changed; a scratch file can be written; and the pinned `rustc --version`
remains available. Any forbidden access or missing allowed behavior rejects
this sandbox approach. Missing prerequisites, timeout or interrupted setup
is inconclusive. Run the exact command below only once after independent review
and commit. Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric.

The test creates only synthetic owned data and a loopback listener. Children
are fixed single-purpose commands with a five-second deadline and 64 KiB log
caps. A fixed private directory is created exclusively, so an interruption
does not authorize a rerun. It retains all output and per-check results for
independent review. It does not prove that a compiler or its descendants can
be supervised safely; that needs a separate registered qualification. A
same-user adversary, repeated signals, uninterruptible processes and host
failure remain outside this probe's guarantee.

```sh
set -eu
py="$HOME/.local/share/uv/python/cpython-3.13.18-macos-aarch64-none/bin/python3.13"
[ -f "$py" ]
[ ! -L "$py" ]
[ "$(stat -f '%u %Lp %z' "$py")" = '501 755 17593392' ]
[ "$(shasum -a 256 "$py" | cut -d ' ' -f 1)" = 747ca8797fea0949368e9e39d0f75b1eeadbae6c24edadda792ae22299e47a01 ]
JOBS=1 heavy-run /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/private/tmp LANG=C "$py" -I -S -B - <<'PY'
import hashlib, json, os, resource, socket, stat, subprocess, sys
from pathlib import Path
home = Path.home()
base = home / '.local/state/agentbrew/experiments'
info = base.lstat()
if base.resolve(strict=True) != base or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
    raise SystemExit('experiment root unavailable')
for path, uid, mode, size, digest in (
    (Path('/usr/bin/sandbox-exec'), 0, 0o755, 135136, '58839ef01b4eef8aac0d2aa8f9d1c074ae45aafe3533965b030672450064acc8'),
    (Path('/bin/sh'), 0, 0o755, 166576, '84ca7f9b83021621e16059a1c7850df72a462d879e8239d566236ca6ddd00953'),
    (Path('/bin/cat'), 0, 0o755, 184336, '1e238665b377c3ef21734890c783aa828cf912d175b90998b88276cefad0b25a'),
    (Path('/opt/homebrew/Cellar/rust/1.99.1/bin/rustc'), os.getuid(), 0o555, 323008, '302dacde7af194bebcdd7d45c821fefed52e5b96eacc00de80e4b32863def01b'),
):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        item = os.fstat(fd)
        if not stat.S_ISREG(item.st_mode) or item.st_uid != uid or stat.S_IMODE(item.st_mode) != mode or item.st_size != size:
            raise SystemExit('pinned executable unavailable')
        with os.fdopen(os.dup(fd), 'rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != digest:
                raise SystemExit('pinned executable changed')
    finally:
        os.close(fd)
root = base / 'judge-darwin-sandbox-v1'
os.mkdir(root, 0o700)
work = root / 'work'; private = root / 'private'; outside = root / 'outside'
for path in (work, private, outside): path.mkdir(mode=0o700)
(private / 'canary').write_text('synthetic-private\n')
(outside / 'canary').write_text('untouched\n')
for path in (private / 'canary', outside / 'canary'): os.chmod(path, 0o600)
if (private / 'canary').read_text() != 'synthetic-private\n': raise SystemExit('private canary setup failed')
(outside / 'canary').write_text('writable-control\n')
if (outside / 'canary').read_text() != 'writable-control\n': raise SystemExit('outside control failed')
(outside / 'canary').write_text('untouched\n')
if (outside / 'canary').read_text() != 'untouched\n': raise SystemExit('outside reset failed')
with (root / 'canary-control.status').open('x', encoding='utf-8') as status:
    os.fchmod(status.fileno(), 0o600)
    json.dump({'private_readable': True, 'outside_writable_and_reset': True}, status, sort_keys=True)
    status.write('\n'); status.flush(); os.fsync(status.fileno())
print('Private sandbox evidence:', root, flush=True)
runtime = Path(sys.executable).parent.parent
if runtime.resolve(strict=True) != runtime or not stat.S_ISDIR(runtime.lstat().st_mode):
    raise SystemExit('Python runtime unavailable')
paths = [home / '.local', home / '.local/state', home / '.local/state/agentbrew', base, root, work]
parent = runtime
while parent != home:
    if home not in parent.parents:
        raise SystemExit('Python runtime path unexpected')
    paths.append(parent)
    parent = parent.parent
if any('"' in str(path) or '\\' in str(path) for path in [home, runtime, *paths]):
    raise SystemExit('unsupported path')
profile = ('(version 1)(allow default)(deny network*)(deny process-fork)'
           + '(deny file-read* (subpath "' + str(home) + '"))'
           + '(allow file-read* (subpath "' + str(work) + '"))'
           + '(allow file-read* (subpath "' + str(runtime) + '"))'
           + '(deny file-write*)(allow file-write* (subpath "' + str(work) + '") (literal "/dev/null"))'
           + ''.join('(allow file-read-metadata (literal "' + str(path) + '"))' for path in paths))
profile_path = root / 'sandbox.sb'
profile_path.write_text(profile)
os.chmod(profile_path, 0o600)
env = {'HOME': str(work), 'TMPDIR': str(work), 'PATH': '/usr/bin:/bin', 'LANG': 'C'}
def limit(): resource.setrlimit(resource.RLIMIT_FSIZE, (65536, 65536))
def run(name, args):
    with (root / (name + '.out')).open('xb') as out, (root / (name + '.err')).open('xb') as err:
        os.fchmod(out.fileno(), 0o600); os.fchmod(err.fileno(), 0o600)
        result = subprocess.run(['/usr/bin/sandbox-exec', '-f', str(profile_path), *args],
            stdin=subprocess.DEVNULL, stdout=out, stderr=err, cwd=work, env=env,
            timeout=5, check=False, preexec_fn=limit)
        out.flush(); err.flush(); os.fsync(out.fileno()); os.fsync(err.fileno())
    with (root / (name + '.status')).open('x', encoding='utf-8') as status:
        os.fchmod(status.fileno(), 0o600); json.dump({'exit': result.returncode}, status, sort_keys=True)
        status.write('\n'); status.flush(); os.fsync(status.fileno())
    return result.returncode, (root / (name + '.out')).read_bytes(), (root / (name + '.err')).read_bytes()
def denied(rc, out, err):
    if rc == 0: return False
    if rc < 0 or rc >= 126 or not any(token in err for token in (b'Operation not permitted', b'Permission denied')):
        raise RuntimeError('denial control unqualified')
    return not out
def has_text(path, expected):
    try: return path.is_file() and not path.is_symlink() and path.read_text() == expected
    except OSError: return False
results = {}
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.bind(('127.0.0.1', 0)); listener.listen(2); listener.settimeout(1)
    port = listener.getsockname()[1]
    with socket.create_connection(('127.0.0.1', port), timeout=1):
        conn, _ = listener.accept(); conn.close()
    results['loopback_control'] = True
    with (root / 'loopback-control.status').open('x', encoding='utf-8') as status:
        os.fchmod(status.fileno(), 0o600); status.write('{"connected":true}\n'); status.flush(); os.fsync(status.fileno())
    code = 'import socket,sys\ntry:\n s=socket.create_connection(("127.0.0.1",int(sys.argv[1])),1); s.close(); sys.exit(0)\nexcept OSError as e:\n print("denied" if e.errno in (1,13) else "other"); sys.exit(3 if e.errno in (1,13) else 4)'
    rc, out, err = run('network', [sys.executable, '-I', '-S', '-B', '-c', code, str(port)])
    try:
        conn, _ = listener.accept(); conn.close(); reached = True
    except TimeoutError:
        reached = False
    if rc not in (0, 3) or (rc == 3 and out != b'denied\n'):
        raise RuntimeError('network control unqualified')
    results['network_denied'] = rc == 3 and out == b'denied\n' and not reached
rc, out, err = run('private-read', ['/bin/cat', str(private / 'canary')])
results['private_read_denied'] = denied(rc, out, err) and has_text(private / 'canary', 'synthetic-private\n')
rc, out, err = run('outside-write', ['/bin/sh', '-c', 'printf changed > "$1"', '_', str(outside / 'canary')])
results['outside_write_denied'] = denied(rc, out, err) and has_text(outside / 'canary', 'untouched\n')
rc, out, err = run('scratch-write', ['/bin/sh', '-c', 'printf allowed > "$1"', '_', str(work / 'allowed')])
if rc < 0 or rc >= 126: raise RuntimeError('scratch control unqualified')
results['scratch_write_allowed'] = rc == 0 and not out and has_text(work / 'allowed', 'allowed')
rc, out, err = run('rustc-version', ['/opt/homebrew/Cellar/rust/1.99.1/bin/rustc', '--version'])
if rc < 0 or rc >= 126: raise RuntimeError('toolchain control unqualified')
results['toolchain_version_allowed'] = rc == 0 and out.startswith(b'rustc 1.99.1 ')
data = (json.dumps(results, sort_keys=True) + '\n').encode()
with (root / 'results.json').open('xb') as out:
    os.fchmod(out.fileno(), 0o600); out.write(data); out.flush(); os.fsync(out.fileno())
directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try: os.fsync(directory)
finally: os.close(directory)
if len(results) != 6 or not all(results.values()):
    print('sandbox probe rejected; private evidence retained', flush=True)
    raise SystemExit(1)
print('sandbox probe: 6 checks passed', flush=True)
PY
```

The `results.json` file alone is not proof. An independent reviewer must
recheck the logs, canaries, profile, ownership and result. No compiler build
or release follows automatically.
