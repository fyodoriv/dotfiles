# Judge reader: image-ID build admission (draft)

The [lookup diagnostic](judge-image-lookup-diagnostic.md) found that both
pinned image IDs resolved with the expected architecture and repository
digest in the clean environment, while both digest references returned the
specific missing-image error. Independent review confirmed all four private
records. This observation does not establish the cause. Both prior
admissions remain consumed; neither created a build container.

Goal: qualify two offline builds of the pinned reader on each architecture.
Predict four fresh containers resolve the same registered image IDs, build
the pinned source, produce two identical artifacts per architecture, and
produce the expected ELF headers without interpreter segments. Success
requires 4/4 builds, both byte comparisons, input and image identity checks,
private receipts and verified cleanup. Wrong identity, malformed output,
different binaries or failed cleanup rejects this approach. Missing inputs,
failed builds, resource exhaustion and timeouts are inconclusive. This is a
distinct one-use admission: reference the pinned image IDs directly, and
independently require each image's repository digest before use.

The seven synthetic ELF and record controls must be frozen and pass under the
new runner hash, with no skips, before the actual builds. The exact commands,
input hashes, one-use markers, bounded isolation and output verification need
independent review and commitment before any control or build runs. Anchor:
Basili, Caldiera and Rombach (1994), Goal Question Metric.

The exact runner hash is `8be6e16d62b93a7331c85c175f609174967dedc6a1b43ba95125e8669e251b24`;
the control file hash is `4099bc1db965a8199f8c28d9a1a3bf173486064b0e210347a5de0f6930d8d56f`.
Predict all seven named synthetic controls pass, with no skips. Fewer than
seven rejects this runner approach. Run this control command once only after
independent review and commit. It makes no Docker call or build. Independent
review must revalidate its private evidence before any build admission.

```sh
set -eu
py="$HOME/.local/share/uv/python/cpython-3.13.18-macos-aarch64-none/bin/python3.13"
[ -f "$py" ]
[ ! -L "$py" ]
[ "$(stat -f '%u %Lp %z' "$py")" = '501 755 17593392' ]
[ "$(shasum -a 256 "$py" | cut -d ' ' -f 1)" = 747ca8797fea0949368e9e39d0f75b1eeadbae6c24edadda792ae22299e47a01 ]
JOBS=1 heavy-run /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/private/tmp LANG=C "$py" -I -S -B - <<'PY'
import hashlib, json, os, re, resource, stat, subprocess, sys
from pathlib import Path
home = Path.home()
plan = home / 'apps/tooling/wt.noindex/git-doctor-email-allowance-478/docs/tooling-command-center/plans'
runner = plan / 'judge-reader-build-runner-id-v3.py'
test = plan / 'test_judge_reader_elf_id_v3.py'
runner_hash = '8be6e16d62b93a7331c85c175f609174967dedc6a1b43ba95125e8669e251b24'
test_hash = '4099bc1db965a8199f8c28d9a1a3bf173486064b0e210347a5de0f6930d8d56f'
for path, expected in ((runner, runner_hash), (test, test_hash)):
    if path.resolve() != path or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('control input changed')
base = home / '.local/state/agentbrew/experiments'
info = base.lstat()
if base.resolve() != base or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
    raise SystemExit('private experiment root unavailable')
root = base / 'judge-reader-controls-v3-8be6e16d62b9'
os.mkdir(root, 0o700)
env = {'HOME': str(root), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'TMPDIR': str(root), 'LANG': 'C'}
with (root / 'controls.log').open('xb') as out:
    os.fchmod(out.fileno(), 0o600)
    def limit_output(): resource.setrlimit(resource.RLIMIT_FSIZE, (65536, 65536))
    result = subprocess.run([sys.executable, '-I', '-S', '-B', str(test), '-v'], env=env,
                            cwd=root, stdin=subprocess.DEVNULL, stdout=out,
                            stderr=subprocess.STDOUT, timeout=30, check=False, preexec_fn=limit_output)
    out.flush(); os.fsync(out.fileno())
log = (root / 'controls.log').read_bytes()
if len(log) > 65536:
    raise SystemExit('control output too large')
lines = log.decode('utf-8', 'strict').splitlines()
names = {'test_valid_headers_for_both_machines', 'test_wrong_machine_is_refused',
         'test_interpreter_segment_is_refused', 'test_bad_header_is_refused',
         'test_truncated_program_table_is_refused', 'test_publishes_complete_record',
         'test_existing_record_is_not_replaced'}
passed = [m.group(1) for line in lines if (m := re.fullmatch(r'(test_[a-z_]+) \([^)]+\) \.\.\. ok', line))]
if result.returncode or len(passed) != 7 or set(passed) != names or not any(re.fullmatch(r'Ran 7 tests in .*', line) for line in lines) or lines[-1:] != ['OK']:
    print('controls rejected; private log retained at', root, flush=True)
    raise SystemExit(1)
data = (json.dumps({'runner_sha256': runner_hash, 'test_sha256': test_hash,
                    'log_sha256': hashlib.sha256(log).hexdigest(), 'passed': sorted(passed)}, sort_keys=True) + '\n').encode()
with (root / 'control.json').open('xb') as out:
    os.fchmod(out.fileno(), 0o600); out.write(data); out.flush(); os.fsync(out.fileno())
fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try: os.fsync(fd)
finally: os.close(fd)
print('seven controls passed; private receipt:', root, flush=True)
PY
```

The seven controls passed and their private evidence passed independent
review. The separate command below revalidates those controls, both consumed
prior admissions and the independently verified four-row lookup diagnostic.
It checks both pinned image IDs with the expected repository digests before
reserving its one build admission. The preflight and build use distinct
exclusive v3 markers. Failure or interruption consumes the relevant marker;
do not retry automatically. Each build has the original one-CPU, 2 GiB
memory, 128-process, 1 GiB tmpfs and 600-second start limits. Docker's socket
may proxy, and container isolation is not a complete hostile-code boundary.
Retain partial files and investigate any unconfirmed cleanup. Run once only
after the exact command is independently reviewed and committed.

```sh
set -eu
py="$HOME/.local/share/uv/python/cpython-3.13.18-macos-aarch64-none/bin/python3.13"
[ -f "$py" ]
[ ! -L "$py" ]
[ "$(stat -f '%u %Lp %z' "$py")" = '501 755 17593392' ]
[ "$(shasum -a 256 "$py" | cut -d ' ' -f 1)" = 747ca8797fea0949368e9e39d0f75b1eeadbae6c24edadda792ae22299e47a01 ]
JOBS=1 heavy-run /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/private/tmp LANG=C "$py" -I -S -B - <<'PY'
import hashlib, json, os, re, resource, stat, subprocess, sys
from pathlib import Path
home = Path.home()
plan = home / 'apps/tooling/wt.noindex/git-doctor-email-allowance-478/docs/tooling-command-center/plans'
runner = plan / 'judge-reader-build-runner-id-v3.py'
test = plan / 'test_judge_reader_elf_id_v3.py'
runner_hash = '8be6e16d62b93a7331c85c175f609174967dedc6a1b43ba95125e8669e251b24'
test_hash = '4099bc1db965a8199f8c28d9a1a3bf173486064b0e210347a5de0f6930d8d56f'
def read(path, limit, private=False):
    if path.resolve(strict=True) != path:
        raise RuntimeError('input path alias')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit
            or (private and (before.st_uid != os.getuid() or stat.S_IMODE(before.st_mode) != 0o600))):
            raise RuntimeError('input file invalid')
        data = os.read(fd, limit + 1)
        after = os.fstat(fd)
        current = path.lstat()
        identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
        if len(data) > limit or identity(before) != identity(after) or identity(after) != identity(current):
            raise RuntimeError('input file changed')
        return data
    finally:
        os.close(fd)
for path, digest in ((runner, runner_hash), (test, test_hash)):
    if hashlib.sha256(read(path, 1024 * 1024)).hexdigest() != digest:
        raise SystemExit('registered input changed')
root = home / '.local/state/agentbrew/experiments/judge-reader-controls-v3-8be6e16d62b9'
info = root.lstat()
if (root.resolve(strict=True) != root or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
    or stat.S_IMODE(info.st_mode) != 0o700):
    raise SystemExit('control directory invalid')
receipt = json.loads(read(root / 'control.json', 8192, True))
log = read(root / 'controls.log', 65536, True)
names = {'test_valid_headers_for_both_machines', 'test_wrong_machine_is_refused',
         'test_interpreter_segment_is_refused', 'test_bad_header_is_refused',
         'test_truncated_program_table_is_refused', 'test_publishes_complete_record',
         'test_existing_record_is_not_replaced'}
lines = log.decode('utf-8', 'strict').splitlines()
passed = [m.group(1) for line in lines if (m := re.fullmatch(r'(test_[a-z_]+) \([^)]+\) \.\.\. ok', line))]
if (receipt != {'runner_sha256': runner_hash, 'test_sha256': test_hash,
                'log_sha256': hashlib.sha256(log).hexdigest(), 'passed': sorted(names)}
    or len(passed) != 7 or set(passed) != names
    or not any(re.fullmatch(r'Ran 7 tests in .*', line) for line in lines) or lines[-1:] != ['OK']):
    raise SystemExit('control evidence invalid')
after = root.lstat()
if (after.st_dev, after.st_ino, after.st_mode, after.st_uid) != (info.st_dev, info.st_ino, info.st_mode, info.st_uid):
    raise SystemExit('control directory changed')
old = home / '.local/state/agentbrew/experiments/judge-reader-controls-dff226d811d9'
for path in (old, old / 'preflight-v2', old / 'lookup-diagnostic'):
    oldinfo = path.lstat()
    if (path.resolve(strict=True) != path or not stat.S_ISDIR(oldinfo.st_mode) or oldinfo.st_uid != os.getuid()
        or stat.S_IMODE(oldinfo.st_mode) != 0o700):
        raise SystemExit('prior evidence directory invalid')
old_runner = 'dff226d811d9b2703da88e0e7ff5bb2161941dca976f0ca7c799b21849849494'
first = json.loads(read(old / 'build-admission.json', 8192, True))
second = json.loads(read(old / 'preflight-admission-v2.json', 8192, True))
if (first.get('runner_sha256') != old_runner or first.get('state') != 'admitted'
    or second.get('runner_sha256') != old_runner or second.get('state') != 'preflight-admitted'
    or (old / 'build-admission-v2.json').exists()):
    raise SystemExit('prior admissions invalid')
first_run = Path('/private/tmp/judge-reader-build-l4ujips4')
firstinfo = first_run.lstat()
if (first_run.resolve(strict=True) != first_run or not stat.S_ISDIR(firstinfo.st_mode)
    or firstinfo.st_uid != os.getuid() or stat.S_IMODE(firstinfo.st_mode) != 0o700):
    raise SystemExit('first outcome directory invalid')
if (json.loads(read(first_run / 'outcome.json', 8192, True)) != {'reason': 'docker-command-failed', 'status': 'inconclusive'}
    or read(first_run / 'events.log', 8192, True).decode().splitlines() != ['001 info start', '001 exit 0', '002 image start', '002 exit 1']
    or b'No such image: rust@sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632' not in read(first_run / '002.err', 8192, True)):
    raise SystemExit('first outcome invalid')
if (json.loads(read(old / 'preflight-v2/arm64.status', 8192, True)) != {'exit': 1}
    or b'No such image: rust@sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632' not in read(old / 'preflight-v2/arm64.err', 8192, True)
    or (old / 'preflight-v2/amd64.status').exists()):
    raise SystemExit('second outcome invalid')
diag = old / 'lookup-diagnostic'
if json.loads(read(diag / 'outcome.json', 8192, True)) != {'decisions': ['missing', 'correct', 'missing', 'correct'], 'outcome': 'success'}:
    raise SystemExit('lookup diagnostic invalid')
for arch, digest, image_id in [
    ('arm64', 'sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632', 'sha256:7a01cbf903e1ed14014bd087f2969bfdfa4bb5a46336ca44144834b1043a5343'),
    ('amd64', 'sha256:2c83bf1a38975801abfd05e92387242ab4d5f96fe05131e2a279f3009ad16393', 'sha256:40abe462ed26e555a0f7b7955254c583389f419045e7204f77ef75434fda4151')]:
    for kind in ('digest', 'id'):
        prefix = arch + '-' + kind
        row = json.loads(read(diag / (prefix + '.json'), 8192, True))
        output = read(diag / (prefix + '.out'), 1024 * 1024, True)
        errors = read(diag / (prefix + '.err'), 1024 * 1024, True)
        if (row.get('arch') != arch or row.get('kind') != kind or row.get('stdout_sha256') != hashlib.sha256(output).hexdigest()
            or row.get('stderr_sha256') != hashlib.sha256(errors).hexdigest()):
            raise SystemExit('lookup row invalid')
        if kind == 'digest':
            if row.get('decision') != 'missing' or row.get('exit') == 0 or (b'No such image: rust@' + digest.encode()) not in errors:
                raise SystemExit('lookup missing row invalid')
        else:
            obj = json.loads(output)
            if (row.get('decision') != 'correct' or row.get('exit') != 0 or len(obj) != 1
                or obj[0].get('Id') != image_id or obj[0].get('Os') != 'linux'
                or obj[0].get('Architecture') != arch or 'rust@' + digest not in (obj[0].get('RepoDigests') or [])):
                raise SystemExit('lookup ID row invalid')
directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    opened = os.fstat(directory)
    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
        raise SystemExit('control directory changed')
    fd = os.open('preflight-admission-v3.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
    try:
        data = (json.dumps({'runner_sha256': runner_hash, 'control_log_sha256': hashlib.sha256(log).hexdigest(), 'state': 'preflight-admitted'}, sort_keys=True) + '\n').encode()
        if os.write(fd, data) != len(data):
            raise SystemExit('preflight admission incomplete')
        os.fsync(fd)
    finally:
        os.close(fd)
    os.fsync(directory)
finally:
    os.close(directory)
cli = Path('/usr/local/' + 'bin/docker').resolve(strict=True)
info_cli = cli.stat()
if (not stat.S_ISREG(info_cli.st_mode) or info_cli.st_uid != os.getuid() or stat.S_IMODE(info_cli.st_mode) != 0o755
    or info_cli.st_size != 38294464 or hashlib.sha256(read(cli, 40 * 1024 * 1024)).hexdigest() != 'cac12f15213d5806f1ffcbc6c159da969e8bf606bf81eafcea89b4c79d7945fd'):
    raise SystemExit('Docker CLI identity changed')
socket = Path('/var/' + 'run/docker.sock')
sockinfo = socket.stat()
if (not stat.S_ISSOCK(sockinfo.st_mode) or sockinfo.st_uid != os.getuid()
    or socket.resolve() != (home / '.docker/run/docker.sock').resolve()):
    raise SystemExit('local Docker socket unavailable')
preflight = root / 'preflight-v3'
os.mkdir(preflight, 0o700)
preinfo = preflight.lstat()
if (preflight.resolve(strict=True) != preflight or not stat.S_ISDIR(preinfo.st_mode)
    or preinfo.st_uid != os.getuid() or stat.S_IMODE(preinfo.st_mode) != 0o700):
    raise SystemExit('preflight directory invalid')
(preflight / 'home').mkdir(mode=0o700)
(preflight / 'config').mkdir(mode=0o700)
docker_env = {'HOME': str(preflight / 'home'), 'DOCKER_CONFIG': str(preflight / 'config'),
              'DOCKER_HOST': 'unix:///var/run/docker.sock', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'C'}
images = [('arm64', 'sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632', 'sha256:7a01cbf903e1ed14014bd087f2969bfdfa4bb5a46336ca44144834b1043a5343'),
          ('amd64', 'sha256:2c83bf1a38975801abfd05e92387242ab4d5f96fe05131e2a279f3009ad16393', 'sha256:40abe462ed26e555a0f7b7955254c583389f419045e7204f77ef75434fda4151')]
def limit_output(): resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))
validated = []
for arch, digest, pinned_id in images:
    image = 'rust@' + digest
    with (preflight / (arch + '.out')).open('xb') as out, (preflight / (arch + '.err')).open('xb') as err:
        os.fchmod(out.fileno(), 0o600); os.fchmod(err.fileno(), 0o600)
        result = subprocess.run([str(cli), 'image', 'inspect', pinned_id], env=docker_env, cwd=preflight,
                                stdin=subprocess.DEVNULL, stdout=out, stderr=err, timeout=15,
                                check=False, preexec_fn=limit_output)
        out.flush(); err.flush(); os.fsync(out.fileno()); os.fsync(err.fileno())
    with (preflight / (arch + '.status')).open('xb') as status:
        os.fchmod(status.fileno(), 0o600)
        status.write((json.dumps({'exit': result.returncode}, sort_keys=True) + '\n').encode())
        status.flush(); os.fsync(status.fileno())
    if result.returncode:
        raise SystemExit('image preflight inconclusive; private records retained')
    output = read(preflight / (arch + '.out'), 1024 * 1024, True)
    errors = read(preflight / (arch + '.err'), 1024 * 1024, True)
    data = json.loads(output)
    if (len(data) != 1 or data[0].get('Os') != 'linux' or data[0].get('Architecture') != arch
        or image not in (data[0].get('RepoDigests') or [])
        or data[0].get('Id') != pinned_id):
        raise SystemExit('image preflight mismatch; approach rejected')
    validated.append({'arch': arch, 'image_id': data[0]['Id'], 'output_sha256': hashlib.sha256(output).hexdigest(),
                      'error_sha256': hashlib.sha256(errors).hexdigest()})
predir = os.open(preflight, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    opened = os.fstat(predir)
    after_pre = preflight.lstat()
    if (opened.st_uid != os.getuid() or stat.S_IMODE(opened.st_mode) != 0o700
        or (opened.st_dev, opened.st_ino) != (preinfo.st_dev, preinfo.st_ino)
        or (after_pre.st_dev, after_pre.st_ino) != (preinfo.st_dev, preinfo.st_ino)):
        raise SystemExit('preflight directory changed')
    os.fsync(predir)
finally:
    os.close(predir)
print('Both pinned image preflights passed', flush=True)
directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    opened = os.fstat(directory)
    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
        raise SystemExit('control directory changed')
    data = (json.dumps({'runner_sha256': runner_hash, 'control_log_sha256': hashlib.sha256(log).hexdigest(),
                        'preflight': validated, 'state': 'admitted'}, sort_keys=True) + '\n').encode()
    fd = os.open('build-admission-v3.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
    try:
        if os.write(fd, data) != len(data):
            raise SystemExit('build admission incomplete')
        os.fsync(fd)
    finally:
        os.close(fd)
    os.fsync(directory)
finally:
    os.close(directory)
env = {'HOME': str(home), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'TMPDIR': '/private/tmp',
       'LANG': 'C', 'JUDGE_READER_BUILD_ADMITTED': 'registered-id-v3-control-passed'}
os.execve(sys.executable, [sys.executable, '-I', '-S', '-B', str(runner)], env)
PY
```

The build produces private artifacts only. It does not qualify reader
behavior, production delivery, no-Cargo installation, calibration or connectors.
