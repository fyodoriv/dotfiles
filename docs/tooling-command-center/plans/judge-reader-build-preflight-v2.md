# Judge reader: preflight-bound build admission

The first single-use reader build admission stopped before container creation
because Docker returned `No such image` for the pinned ARM image. The result
was inconclusive. Independent review confirmed no container or build was
attempted, and the first admission remains consumed. A later read-only check
found both images present; the reason for the earlier response is unknown.
That first-attempt fact is independently checked registration evidence; it
is not a machine-enforced precondition of this launcher.

This distinct admission adds a read-only, bounded preflight for both pinned
images before reserving its one build attempt. Predict 2/2 preflights report
the registered image digest, Linux OS and matching architecture. Missing image
or timeout is inconclusive; wrong identity is a pivot. If both pass, the
original four-build prediction, source/index pins, controls, safety limits and
revalidation rules in [the first plan](judge-reader-build-draft.md) apply.
A preflight does not prevent later cache changes or prove why the first
inspection failed. The command performs no image pull and no automatic retry.

Both the preflight and build admissions have new exclusive fixed markers.
Reserve the preflight marker before either image check and the build marker
only after both pass. A crash or failure leaves the relevant marker consumed.
Any incomplete outcome stays inconclusive and cannot authorize a retry.
An independent reviewer classifies the retained per-image status and logs;
missing or partial status is inconclusive. Preflight logs stay private.
Basili, Caldiera and Rombach (1994), Goal
Question Metric, anchors both numeric predictions. Run this exact command
once only after independent review and commit.

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
runner = plan / 'judge-reader-build-runner.py'
test = plan / 'test_judge_reader_elf.py'
runner_hash = 'dff226d811d9b2703da88e0e7ff5bb2161941dca976f0ca7c799b21849849494'
test_hash = '0d93961089bc3144ab49485406310b2c2c95ae143a3ab9ad4064eb4e33899b65'
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
root = home / '.local/state/agentbrew/experiments/judge-reader-controls-dff226d811d9'
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
directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    opened = os.fstat(directory)
    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
        raise SystemExit('control directory changed')
    fd = os.open('preflight-admission-v2.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
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
preflight = root / 'preflight-v2'
os.mkdir(preflight, 0o700)
preinfo = preflight.lstat()
if (preflight.resolve(strict=True) != preflight or not stat.S_ISDIR(preinfo.st_mode)
    or preinfo.st_uid != os.getuid() or stat.S_IMODE(preinfo.st_mode) != 0o700):
    raise SystemExit('preflight directory invalid')
(preflight / 'home').mkdir(mode=0o700)
(preflight / 'config').mkdir(mode=0o700)
docker_env = {'HOME': str(preflight / 'home'), 'DOCKER_CONFIG': str(preflight / 'config'),
              'DOCKER_HOST': 'unix:///var/run/docker.sock', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'C'}
images = [('arm64', 'sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632'),
          ('amd64', 'sha256:2c83bf1a38975801abfd05e92387242ab4d5f96fe05131e2a279f3009ad16393')]
def limit_output(): resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))
validated = []
for arch, digest in images:
    image = 'rust@' + digest
    with (preflight / (arch + '.out')).open('xb') as out, (preflight / (arch + '.err')).open('xb') as err:
        os.fchmod(out.fileno(), 0o600); os.fchmod(err.fileno(), 0o600)
        result = subprocess.run([str(cli), 'image', 'inspect', image], env=docker_env, cwd=preflight,
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
        or not re.fullmatch('sha256:[0-9a-f]{64}', data[0].get('Id') or '')):
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
    fd = os.open('build-admission-v2.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
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
       'LANG': 'C', 'JUDGE_READER_BUILD_ADMITTED': 'registered-control-passed'}
os.execve(sys.executable, [sys.executable, '-I', '-S', '-B', str(runner)], env)
PY
```
