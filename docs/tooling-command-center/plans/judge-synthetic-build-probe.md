# Judge reader: synthetic Linux compiler probe

Issue #752 and draft #755 need source-qualified Linux readers. Both pinned
Rust images previously passed independent version, platform, configuration
and cleanup checks. This distinct experiment tests a small synthetic program;
it does not build the reader or inspect sealed evaluation cases.

Goal: qualify basic compiler and linker availability and a repeatable tiny
build. Predict 2/2 architectures compile the same fixed source in two separate
paths, produce byte-identical binaries, and run one with the expected output.
Success requires those results plus verified configuration and cleanup. A
nonidentical binary, unexpected program output, failed isolation check or
failed cleanup rejects this approach. Missing resources, image, daemon,
timeout or an unavailable compiler is inconclusive and requires diagnosis.
Exit 41 or 42 records a pivot; compile/setup failures and failed execution
are inconclusive. The measurement is the command below, after independent
review and commit.
Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric.

Two pinned official Rust 1.99.1 Alpine images run sequentially without network
or host mounts. They use a read-only root, one writable 128 MiB tmpfs at
`/tmp` with explicit exec permission, no capabilities, no new privileges, an unprivileged user, one CPU,
1 GiB memory and 64 processes. The tmpfs must allow execution of the synthetic
binary. Verify the configuration before execution. Remove only a verified
owned ID and label. Do not remove shared images. The host-root free-space check
is not a daemon-store quota. Socket proxying, incomplete hostile-code isolation,
daemon-side work after timeout, and possible leftover containers after repeated
signals, host failure or cleanup failure remain limitations. Do not retry an
inconclusive or failed admission automatically.

```sh
set -eu
umask 077
py="$HOME/.local/share/uv/python/cpython-3.13.18-macos-aarch64-none/bin/python3.13"
[ -f "$py" ]
[ ! -L "$py" ]
[ "$(stat -f '%u %Lp %z' "$py")" = '501 755 17593392' ]
[ "$(shasum -a 256 "$py" | cut -d ' ' -f 1)" = 747ca8797fea0949368e9e39d0f75b1eeadbae6c24edadda792ae22299e47a01 ]
JOBS=1 heavy-run /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/private/tmp LANG=C "$py" -I -S - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import signal
import shutil
import stat
import subprocess
import tempfile
import uuid

cli = Path('/usr/local/' + 'bin/docker').resolve(strict=True)
info = cli.stat()
if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o755 or info.st_size != 38294464:
    raise SystemExit('Docker CLI identity changed')
with cli.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != 'cac12f15213d5806f1ffcbc6c159da969e8bf606bf81eafcea89b4c79d7945fd':
        raise SystemExit('Docker CLI identity changed')
socket = Path('/var/' + 'run/docker.sock')
socketinfo = socket.stat()
if (not stat.S_ISSOCK(socketinfo.st_mode) or socketinfo.st_uid != os.getuid()
    or socket.resolve() != (Path.home() / '.docker/run/docker.sock').resolve()):
    raise SystemExit('local Docker socket unavailable')
if shutil.disk_usage('/').free < 6 * 1024**3:
    raise SystemExit('insufficient free disk')
root = Path(tempfile.mkdtemp(prefix='judge-rust-build-probe-', dir='/private/tmp'))
(root / 'config').mkdir(mode=0o700)
(root / 'home').mkdir(mode=0o700)
print(f'Private probe logs: {root}', flush=True)
env = {'HOME': str(root / 'home'), 'DOCKER_CONFIG': str(root / 'config'),
       'DOCKER_HOST': 'unix:///var/run/docker.sock', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'C'}
counter = 0
events = root / 'events.log'

def record(message):
    with events.open('a', encoding='ascii') as out:
        out.write(message + '\n')
        out.flush()
        os.fsync(out.fileno())

def interrupted(signum, frame):
    raise InterruptedError('interrupted')

for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, interrupted)

def limit_output():
    resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))

def call(args, timeout, allow_failure=False):
    global counter
    counter += 1
    record(f'{counter:03d} {args[0]} start')
    outpath = root / f'{counter:03d}.out'
    errpath = root / f'{counter:03d}.err'
    with outpath.open('xb') as out, errpath.open('xb') as err:
        try:
            result = subprocess.run([str(cli), *args], env=env, cwd=root, stdin=subprocess.DEVNULL,
                                    stdout=out, stderr=err, timeout=timeout, check=False,
                                    preexec_fn=limit_output)
        except subprocess.TimeoutExpired:
            record(f'{counter:03d} timeout')
            raise
    record(f'{counter:03d} exit {result.returncode}')
    if result.returncode and not allow_failure:
        raise RuntimeError('docker-command-failed')
    return result.returncode, outpath.read_text(errors='replace').strip()

def inspect(target):
    rc, text = call(['container', 'inspect', target], 15, allow_failure=True)
    if rc:
        return None
    value = json.loads(text)
    if len(value) != 1:
        raise RuntimeError('ambiguous-container')
    return value[0]

def cleanup(target, nonce):
    current = inspect(target)
    if not current:
        raise RuntimeError('container-identity-unavailable')
    labels = (current.get('Config') or {}).get('Labels') or {}
    cid = current.get('Id') or ''
    if labels.get('agentbrew.probe') != nonce or cid != target or not re.fullmatch('[0-9a-f]{64}', cid):
        raise RuntimeError('container-identity-mismatch')
    if (current.get('State') or {}).get('Running'):
        call(['stop', '--time', '1', cid], 15)
    call(['container', 'rm', cid], 15)
    _, remaining = call(['container', 'ls', '-aq', '--no-trunc', '--filter', 'id=' + cid], 15)
    if remaining:
        raise RuntimeError('container-removal-unconfirmed')

images = [
    ('arm64', 'aarch64', 'sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632'),
    ('amd64', 'x86_64', 'sha256:2c83bf1a38975801abfd05e92387242ab4d5f96fe05131e2a279f3009ad16393'),
]
try:
    _, daemon = call(['info', '--format', '{{.OSType}}'], 15)
    if daemon != 'linux':
        raise RuntimeError('non-linux-daemon')
    for arch, machine, digest in images:
        image = 'rust@' + digest
        nonce = uuid.uuid4().hex
        name = 'agentbrew-judge-probe-' + nonce
        _, existing = call(['container', 'ls', '-aq', '--no-trunc', '--filter', 'label=agentbrew.probe=' + nonce], 15)
        if existing:
            raise RuntimeError('container-label-collision')
        call(['pull', '--quiet', '--platform', 'linux/' + arch, image], 300)
        _, raw = call(['image', 'inspect', image], 15)
        data = json.loads(raw)
        if len(data) != 1 or data[0].get('Os') != 'linux' or data[0].get('Architecture') != arch:
            raise RuntimeError('image-platform-mismatch')
        image_id = data[0].get('Id') or ''
        if not re.fullmatch('sha256:[0-9a-f]{64}', image_id) or image not in (data[0].get('RepoDigests') or []):
            raise RuntimeError('image-identity-mismatch')
        ownership = root / ('ownership-' + nonce + '.json')
        with ownership.open('x', encoding='utf-8') as out:
            json.dump({'name': name, 'nonce': nonce, 'image': image, 'image_id': image_id}, out, sort_keys=True)
            out.flush()
            os.fsync(out.fileno())
        target = None
        create_attempted = False
        try:
            create_attempted = True
            _, cid = call(['create', '--name', name, '--label', 'agentbrew.probe=' + nonce,
                '--platform', 'linux/' + arch, '--network', 'none', '--read-only', '--cap-drop', 'ALL',
                '--security-opt', 'no-new-privileges', '--user', '65534:65534', '--tmpfs', '/tmp:rw,exec,size=128m,mode=1777', '--memory', '1024m',
                '--cpus', '1', '--pids-limit', '64', '--entrypoint', '/bin/sh', image, '-c', 'set -u; mkdir /tmp/a /tmp/b || exit 40; printf \'%s\\n\' \'fn main() { println!("judge-probe"); }\' > /tmp/a/probe.rs || exit 40; cp /tmp/a/probe.rs /tmp/b/probe.rs || exit 40; rustc --crate-name probe --remap-path-prefix=/tmp/a=/source -C strip=symbols /tmp/a/probe.rs -o /tmp/a/probe || exit 40; rustc --crate-name probe --remap-path-prefix=/tmp/b=/source -C strip=symbols /tmp/b/probe.rs -o /tmp/b/probe || exit 40; if cmp /tmp/a/probe /tmp/b/probe; then :; else rc=$?; if [ "$rc" -eq 1 ]; then exit 41; else exit 40; fi; fi; output=$(/tmp/a/probe) || exit 43; [ "$output" = judge-probe ] || exit 42; printf \'%s\\n\' "$output"'], 30)
            if not re.fullmatch('[0-9a-f]{64}', cid):
                raise RuntimeError('container-id-invalid')
            target = cid
            with (root / ('id-' + nonce)).open('x', encoding='ascii') as out:
                out.write(cid + '\n')
                out.flush()
                os.fsync(out.fileno())
            state = inspect(cid)
            host = state['HostConfig'] if state else {}
            labels = (state.get('Config') or {}).get('Labels') or {} if state else {}
            mounts = state.get('Mounts') or [] if state else []
            config = state.get('Config') or {} if state else {}
            if (not state or labels.get('agentbrew.probe') != nonce or state.get('Id') != cid
                or state.get('Image') != image_id or (state.get('State') or {}).get('Running')
                or config.get('Entrypoint') != ['/bin/sh'] or config.get('Cmd') != ['-c', 'set -u; mkdir /tmp/a /tmp/b || exit 40; printf \'%s\\n\' \'fn main() { println!("judge-probe"); }\' > /tmp/a/probe.rs || exit 40; cp /tmp/a/probe.rs /tmp/b/probe.rs || exit 40; rustc --crate-name probe --remap-path-prefix=/tmp/a=/source -C strip=symbols /tmp/a/probe.rs -o /tmp/a/probe || exit 40; rustc --crate-name probe --remap-path-prefix=/tmp/b=/source -C strip=symbols /tmp/b/probe.rs -o /tmp/b/probe || exit 40; if cmp /tmp/a/probe /tmp/b/probe; then :; else rc=$?; if [ "$rc" -eq 1 ]; then exit 41; else exit 40; fi; fi; output=$(/tmp/a/probe) || exit 43; [ "$output" = judge-probe ] || exit 42; printf \'%s\\n\' "$output"']
                or host.get('NetworkMode') != 'none' or not host.get('ReadonlyRootfs')
                or host.get('Privileged') or host.get('Binds') or host.get('Devices')
                or host.get('Tmpfs') != {'/tmp': 'rw,exec,size=128m,mode=1777'}
                or any(m.get('Type') != 'tmpfs' or m.get('Destination') != '/tmp' for m in mounts)
                or host.get('CapDrop') != ['ALL'] or 'no-new-privileges' not in (host.get('SecurityOpt') or [])
                or (state.get('Config') or {}).get('User') != '65534:65534'
                or host.get('Memory') != 1024 * 1024**2 or host.get('NanoCpus') != 10**9
                or host.get('PidsLimit') != 64 or host.get('PidMode') or host.get('IpcMode') == 'host'):
                raise RuntimeError('container-isolation-mismatch')
            rc, output = call(['start', '--attach', cid], 300, allow_failure=True)
            final = inspect(cid)
            if rc:
                state = (final.get('State') or {}) if final else {}
                code = state.get('ExitCode') if state.get('Running') is False and state.get('Status') == 'exited' else None
                if code in (41, 42):
                    record('registered-pivot')
                    raise RuntimeError('registered-pivot')
                record('build-inconclusive')
                raise RuntimeError('build-inconclusive')
            if (output != 'judge-probe'
                or not final or (final.get('State') or {}).get('Running') is not False
                or (final.get('State') or {}).get('Status') != 'exited'
                or (final.get('State') or {}).get('ExitCode') != 0):
                raise RuntimeError('build-output-mismatch')
        finally:
            try:
                if target:
                    cleanup(target, nonce)
                    record('cleanup-verified')
                elif create_attempted:
                    # A matching label is required even for the known random name.
                    current = inspect(name)
                    labels = (current.get('Config') or {}).get('Labels') or {} if current else {}
                    cid = current.get('Id') or '' if current else ''
                    if labels.get('agentbrew.probe') == nonce and re.fullmatch('[0-9a-f]{64}', cid):
                        cleanup(cid, nonce)
                    # The daemon may still finish a timed-out create later.
                    record('creation-unconfirmed')
                    print('container creation unconfirmed; retain private logs', flush=True)
            except BaseException:
                record('cleanup-unconfirmed')
                raise
        print(arch + ': isolated build probe passed', flush=True)
    print('judge Rust build probe: 2 passed', flush=True)
except (OSError, ValueError, KeyError, subprocess.SubprocessError, RuntimeError) as error:
    print('runtime probe stopped; inspect private logs', flush=True)
    raise SystemExit(1)
PY
```

Passing qualifies only this tiny isolated example. Reader source, offline
dependencies, real builds, full artifact provenance, no-Cargo installation,
publisher compatibility and evaluation remain separate work.
