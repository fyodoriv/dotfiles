# Judge reader: isolated Linux runtime probe

Issue #752 and draft #755 need source-qualified native readers. On Nov 7 the
local Docker endpoint used a Unix socket. Alpine images were not cached.
Docker Hub's official metadata advertised the pinned Alpine 3.24 manifests
below, about 8 MB compressed together. This is a setup probe; it does not mount
the downloaded Rust archives, build the judge, qualify emulation speed, or
prove artifact reproducibility.

- Manifest list: `sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a`.
- Linux ARM64: `sha256:1829893486be257df5049ab3b7fc95afbd0fc09d89803cbc580bda1ba5386b29`.
- Linux AMD64: `sha256:0f49f331d9212aff11b932863be4eb01cdf962969aa86dab7d1ee21ac6f5f52b`.

Source: https://hub.docker.com/v2/repositories/library/alpine/tags/3.24 .

Goal: qualify a bounded local Linux runtime route. Predict both pinned images
can report their expected machine architecture in an owned, network-disabled
container. Success requires 2/2 correct results, zero reported mounts, the
requested isolation configuration and verified cleanup. This inspects the
network configuration; it does not independently test network egress. A wrong architecture, failed
isolation check or failed cleanup rejects the approach. A missing image,
daemon, resources, timeout or emulation is inconclusive.

Use a clean Docker configuration with the explicit local Unix socket, no
credentials and no repository, Cargo cache, home or socket mount. Pull only
the two pinned public image digests. The two containers run sequentially with
no network, a read-only root, no capabilities, no new privileges, a non-root
user, one CPU, 256 MiB and 16 processes, with no extra mounts. Inspect
the actual container configuration before starting it. Track each owned ID and
random ownership label. Stop or remove only a container whose ID and label are
verified. Keep public image cache entries; do not delete shared images. A pull
timeout may leave daemon activity and cannot be reported as clean cancellation.

Independent review found no remaining concrete blocker. Commit the prediction
before executing the command below. It
checks 2 GiB free on the host root, not on the daemon's image-store filesystem;
there is no hard per-pull quota here. The two registry-reported compressed
images total 8,044,268 bytes. The local Unix socket does not by itself prove
the server cannot proxy elsewhere. Docker and its daemon are not a complete
hostile-code boundary. A
timeout can leave daemon-side pull or create activity after the CLI stops; the
script reports that as inconclusive, retains its private log and never guesses
ownership. SIGKILL, host failure, repeated signals or an interrupted/failed
cleanup command can leave a container. Its private ownership record supports
later investigation; the record alone does not prove removal.

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
if shutil.disk_usage('/').free < 2 * 1024**3:
    raise SystemExit('insufficient free disk')
root = Path(tempfile.mkdtemp(prefix='judge-alpine-probe-', dir='/private/tmp'))
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
    ('arm64', 'aarch64', 'sha256:1829893486be257df5049ab3b7fc95afbd0fc09d89803cbc580bda1ba5386b29'),
    ('amd64', 'x86_64', 'sha256:0f49f331d9212aff11b932863be4eb01cdf962969aa86dab7d1ee21ac6f5f52b'),
]
try:
    _, daemon = call(['info', '--format', '{{.OSType}}'], 15)
    if daemon != 'linux':
        raise RuntimeError('non-linux-daemon')
    for arch, machine, digest in images:
        image = 'alpine@' + digest
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
                '--security-opt', 'no-new-privileges', '--user', '65534:65534', '--memory', '256m',
                '--cpus', '1', '--pids-limit', '16', '--entrypoint', '/bin/uname', image, '-m'], 30)
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
                or config.get('Entrypoint') != ['/bin/uname'] or config.get('Cmd') != ['-m']
                or host.get('NetworkMode') != 'none' or not host.get('ReadonlyRootfs')
                or host.get('Privileged') or host.get('Binds') or host.get('Devices') or mounts
                or host.get('CapDrop') != ['ALL'] or 'no-new-privileges' not in (host.get('SecurityOpt') or [])
                or (state.get('Config') or {}).get('User') != '65534:65534'
                or host.get('Memory') != 256 * 1024**2 or host.get('NanoCpus') != 10**9
                or host.get('PidsLimit') != 16 or host.get('PidMode') or host.get('IpcMode') == 'host'):
                raise RuntimeError('container-isolation-mismatch')
            _, output = call(['start', '--attach', cid], 120)
            final = inspect(cid)
            if (output != machine or not final or (final.get('State') or {}).get('Running')
                or (final.get('State') or {}).get('ExitCode') != 0):
                raise RuntimeError('architecture-mismatch')
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
        print(arch + ': isolated runtime probe passed', flush=True)
    print('judge Alpine runtime probe: 2 passed', flush=True)
except (OSError, ValueError, KeyError, subprocess.SubprocessError, RuntimeError) as error:
    print('runtime probe stopped; inspect private logs', flush=True)
    raise SystemExit(1)
PY
```

The committed command authorizes only the two runtime probes, not a build. A successful
probe would still leave source/lock identities, offline dependencies, two
clean builds per target, artifact verification, no-Cargo installation and
publisher compatibility to separate registered work. Anchor: the official
metadata above and Basili, Caldiera and Rombach (1994), Goal Question Metric.
