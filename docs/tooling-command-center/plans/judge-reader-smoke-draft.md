# Judge reader: isolated smoke test (draft)

Four offline builds of the pinned candidate source passed independent
same-architecture byte comparisons and limited ELF inspection. The retained
artifact SHA-256 values are `ca0da52cd054e5cbcc9e3dba8c7081308bca1f59674c09297c0d6286be443b5f`
for ARM64 and `cdfd1e06373381ce154c16fb11f9458641a719231ef08c62e0d5039466601842`
for AMD64. The build receipt and output files stay private.

Goal: test the exact private reader outputs in minimal Linux images. Predict
4/4 checks: each architecture returns `clarity` plus LF for a synthetic
allowed file, and each refuses a synthetic symlink with exit 2, empty stdout
and the exact expected error. Success requires both configurations and
verified cleanup. A wrong byte, exit status, refusal, isolation check or
cleanup rejects this approach. Missing input or image, setup, runtime
unavailability and timeout are inconclusive. The command below is a draft;
it must be independently reviewed and committed before any execution.
Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric.

The private input copy is mounted read-only, with no network, no capabilities,
no new privileges and non-root execution. The two pinned Alpine images are
identified by image ID and checked against their registry digests. Each
container uses one CPU, 1 GiB memory, 64 processes, a 128 MiB writable tmpfs
and a 120-second start timeout. It uses only generated test data. One exclusive
marker permits a single attempt. Missing or partial records and unconfirmed
cleanup are not successful results. Docker is not a complete hostile-code
boundary, its Unix socket may proxy, and a timeout or host failure can leave
daemon activity or a container. The successful result needs independent
revalidation of the event logs, outputs, identities and cleanup. It does not
qualify production installation, all reader edge cases, calibration or hooks.
The prior build's source, index, locked archives and cleanup were independently
audited; that external audit is a prerequisite. The launcher rechecks the
receipt and exact artifact bytes but does not repeat that entire audit. Repeated
signals, failed cleanup or an uninterruptible process may leave a container.

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
root = Path(tempfile.mkdtemp(prefix='judge-reader-smoke-probe-', dir='/private/tmp'))
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

control = Path.home() / '.local/state/agentbrew/experiments/judge-reader-controls-v3-8be6e16d62b9'
controlinfo = control.lstat()
if (control.resolve(strict=True) != control or not stat.S_ISDIR(controlinfo.st_mode) or controlinfo.st_uid != os.getuid()
    or stat.S_IMODE(controlinfo.st_mode) != 0o700):
    raise SystemExit('private control root unavailable')
source = Path('/private/tmp/judge-reader-build-nxrsqbwu')
sourceinfo = source.lstat()
if (source.resolve(strict=True) != source or not stat.S_ISDIR(sourceinfo.st_mode) or sourceinfo.st_uid != os.getuid()
    or stat.S_IMODE(sourceinfo.st_mode) != 0o700):
    raise SystemExit('private build root unavailable')
def safe_read(path, limit):
    if path.resolve(strict=True) != path: raise RuntimeError('input-alias')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) != 0o600 or before.st_size > limit): raise RuntimeError('input-identity')
        with os.fdopen(os.dup(fd), 'rb') as stream: data = stream.read(limit + 1)
        after = os.fstat(fd); current = path.lstat()
        identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
        if len(data) > limit or identity(before) != identity(after) or identity(after) != identity(current): raise RuntimeError('input-changed')
        return data
    finally: os.close(fd)
expected = {'arm64': 'ca0da52cd054e5cbcc9e3dba8c7081308bca1f59674c09297c0d6286be443b5f',
            'amd64': 'cdfd1e06373381ce154c16fb11f9458641a719231ef08c62e0d5039466601842'}
outcome = json.loads(safe_read(source / 'outcome.json', 8192))
receipt = json.loads(safe_read(source / 'receipt.json', 32768))
if outcome != {'status': 'success', 'reason': 'four-builds-and-receipt-verified'} or receipt.get('outputs_sha256') != expected:
    raise SystemExit('build result is not qualified')
if receipt.get('revision') != '9db12ffc85591dddc75f38e7170c6ab0f7a60f25': raise SystemExit('build source changed')
assets = {}
for arch, digest in expected.items():
    a = safe_read(source / ('reader-' + arch + '-a'), 2 * 1024 * 1024)
    b = safe_read(source / ('reader-' + arch + '-b'), 2 * 1024 * 1024)
    if a != b or hashlib.sha256(a).hexdigest() != digest: raise SystemExit('build artifact mismatch')
    assets[arch] = a
controlfd = os.open(control, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    opened = os.fstat(controlfd)
    if (opened.st_dev, opened.st_ino) != (controlinfo.st_dev, controlinfo.st_ino): raise SystemExit('control root changed')
    fd = os.open('reader-smoke-admission-v1.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=controlfd)
    try:
        data = (json.dumps({'outputs_sha256': expected, 'state': 'admitted'}, sort_keys=True) + '\n').encode()
        if os.write(fd, data) != len(data): raise SystemExit('smoke admission incomplete')
        os.fsync(fd)
    finally: os.close(fd)
    os.fsync(controlfd)
finally: os.close(controlfd)
inputs = root / 'inputs'
inputs.mkdir(mode=0o755)
os.chmod(inputs, 0o755)
input_ids = {}
for arch, data in assets.items():
    path = inputs / arch
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(os.dup(fd), 'wb') as stream: stream.write(data); stream.flush()
        os.fchmod(fd, 0o555); os.fsync(fd); os.lseek(fd, 0, os.SEEK_SET)
        with os.fdopen(os.dup(fd), 'rb') as stream:
            if stream.read(len(data) + 1) != data: raise RuntimeError('input-copy-mismatch')
        info = os.fstat(fd)
        input_ids[arch] = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
    finally: os.close(fd)
def verify_input(arch):
    path = inputs / arch
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd); at_path = path.lstat()
        identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) != 0o555 or identity(before) != input_ids[arch]
            or identity(at_path) != input_ids[arch]): raise RuntimeError('input-identity')
        with os.fdopen(os.dup(fd), 'rb') as stream: digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != expected[arch] or identity(os.fstat(fd)) != input_ids[arch] or identity(path.lstat()) != input_ids[arch]:
            raise RuntimeError('input-changed')
    finally: os.close(fd)

images = [
    ('arm64', 'aarch64', 'sha256:1829893486be257df5049ab3b7fc95afbd0fc09d89803cbc580bda1ba5386b29', 'sha256:abbc135a7d3909a5eb6a56aac4c769cf15be025e3c9e226b8660f2b2b378158b'),
    ('amd64', 'x86_64', 'sha256:0f49f331d9212aff11b932863be4eb01cdf962969aa86dab7d1ee21ac6f5f52b', 'sha256:3ea06e4cb95e726ea6c6cc4377570ac4c4050d78710004cbd631ca809daf7e8e'),
]
try:
    _, daemon = call(['info', '--format', '{{.OSType}}'], 15)
    if daemon != 'linux':
        raise RuntimeError('non-linux-daemon')
    for arch, machine, digest, pinned_id in images:
        verify_input(arch)
        image = 'alpine@' + digest
        nonce = uuid.uuid4().hex
        name = 'agentbrew-judge-probe-' + nonce
        _, existing = call(['container', 'ls', '-aq', '--no-trunc', '--filter', 'label=agentbrew.probe=' + nonce], 15)
        if existing:
            raise RuntimeError('container-label-collision')
        call(['pull', '--quiet', '--platform', 'linux/' + arch, image], 300)
        _, raw = call(['image', 'inspect', pinned_id], 15)
        data = json.loads(raw)
        if len(data) != 1 or data[0].get('Os') != 'linux' or data[0].get('Architecture') != arch:
            raise RuntimeError('image-platform-mismatch')
        image_id = data[0].get('Id') or ''
        if image_id != pinned_id or image not in (data[0].get('RepoDigests') or []):
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
                '--mount', 'type=bind,src=' + str(root / 'inputs' / arch) + ',dst=/reader,readonly', '--cpus', '1', '--pids-limit', '64', '--entrypoint', '/bin/sh', pinned_id, '-c', 'set -u; mkdir /tmp/owner || exit 40; printf \'clarity\\n\' > /tmp/owner/clarity.md || exit 40; printf \'outside\\n\' > /tmp/outside.md || exit 40; ln -s /tmp/outside.md /tmp/owner/link.md || exit 40; /reader /tmp/owner clarity.md > /tmp/allow.out 2> /tmp/allow.err; rc=$?; [ "$rc" -lt 126 ] || exit 40; [ "$rc" -eq 0 ] || exit 41; printf \'clarity\\n\' > /tmp/expected-allow || exit 40; if cmp -s /tmp/allow.out /tmp/expected-allow; then :; else cmp_rc=$?; [ "$cmp_rc" -eq 1 ] && exit 41 || exit 40; fi; [ ! -s /tmp/allow.err ] || exit 41; printf \'allowed-ok\\n\' || exit 40; /reader /tmp/owner link.md > /tmp/refuse.out 2> /tmp/refuse.err; rc=$?; [ "$rc" -lt 126 ] || exit 40; [ "$rc" -eq 2 ] || exit 42; [ ! -s /tmp/refuse.out ] || exit 42; printf \'Judge source unavailable.\\n\' > /tmp/expected-refuse || exit 40; if cmp -s /tmp/refuse.err /tmp/expected-refuse; then :; else cmp_rc=$?; [ "$cmp_rc" -eq 1 ] && exit 42 || exit 40; fi; printf \'refused-ok\\n\''], 30)
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
                or config.get('Entrypoint') != ['/bin/sh'] or config.get('Cmd') != ['-c', 'set -u; mkdir /tmp/owner || exit 40; printf \'clarity\\n\' > /tmp/owner/clarity.md || exit 40; printf \'outside\\n\' > /tmp/outside.md || exit 40; ln -s /tmp/outside.md /tmp/owner/link.md || exit 40; /reader /tmp/owner clarity.md > /tmp/allow.out 2> /tmp/allow.err; rc=$?; [ "$rc" -lt 126 ] || exit 40; [ "$rc" -eq 0 ] || exit 41; printf \'clarity\\n\' > /tmp/expected-allow || exit 40; if cmp -s /tmp/allow.out /tmp/expected-allow; then :; else cmp_rc=$?; [ "$cmp_rc" -eq 1 ] && exit 41 || exit 40; fi; [ ! -s /tmp/allow.err ] || exit 41; printf \'allowed-ok\\n\' || exit 40; /reader /tmp/owner link.md > /tmp/refuse.out 2> /tmp/refuse.err; rc=$?; [ "$rc" -lt 126 ] || exit 40; [ "$rc" -eq 2 ] || exit 42; [ ! -s /tmp/refuse.out ] || exit 42; printf \'Judge source unavailable.\\n\' > /tmp/expected-refuse || exit 40; if cmp -s /tmp/refuse.err /tmp/expected-refuse; then :; else cmp_rc=$?; [ "$cmp_rc" -eq 1 ] && exit 42 || exit 40; fi; printf \'refused-ok\\n\'']
                or host.get('NetworkMode') != 'none' or not host.get('ReadonlyRootfs')
                or host.get('Privileged') or host.get('Binds') or host.get('Devices')
                or len([m for m in mounts if m.get('Type') == 'bind']) != 1
                or not any(m.get('Type') == 'bind' and m.get('Source') == str(root / 'inputs' / arch) and m.get('Destination') == '/reader' and m.get('RW') is False for m in mounts)
                or host.get('Tmpfs') != {'/tmp': 'rw,exec,size=128m,mode=1777'}
                or any(m.get('Type') not in ('bind', 'tmpfs') or (m.get('Type') == 'tmpfs' and m.get('Destination') != '/tmp') for m in mounts)
                or host.get('CapDrop') != ['ALL'] or 'no-new-privileges' not in (host.get('SecurityOpt') or [])
                or (state.get('Config') or {}).get('User') != '65534:65534'
                or host.get('Memory') != 1024 * 1024**2 or host.get('NanoCpus') != 10**9
                or host.get('PidsLimit') != 64 or host.get('PidMode') or host.get('IpcMode') == 'host'):
                raise RuntimeError('container-isolation-mismatch')
            verify_input(arch)
            rc, output = call(['start', '--attach', cid], 120, allow_failure=True)
            final = inspect(cid)
            final_state = (final.get('State') or {}) if final else {}
            if final_state.get('OOMKilled') is not False or final_state.get('Error') != '':
                record('runtime-inconclusive')
                raise RuntimeError('runtime-inconclusive')
            if rc:
                state = (final.get('State') or {}) if final else {}
                code = state.get('ExitCode') if state.get('Running') is False and state.get('Status') == 'exited' else None
                if code in (41, 42):
                    record('registered-pivot')
                    raise RuntimeError('registered-pivot')
                record('build-inconclusive')
                raise RuntimeError('build-inconclusive')
            if (output != 'allowed-ok\nrefused-ok'
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
        verify_input(arch)
        print(arch + ': isolated reader smoke probe passed', flush=True)
    record('all-smoke-checks-verified')
    print('judge reader smoke probe: 4 checks passed', flush=True)
except (OSError, ValueError, KeyError, subprocess.SubprocessError, RuntimeError) as error:
    print('runtime probe stopped; inspect private logs', flush=True)
    raise SystemExit(1)
PY
```
