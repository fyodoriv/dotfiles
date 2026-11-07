# Judge reader: image lookup diagnostic

Two separate, single-use build admissions stopped before creating a
container because Docker returned `No such image` for the pinned ARM digest.
Both were independently classified as inconclusive and remain consumed.
Separate read-only listing showed the digest and image ID; inspection by ID
also succeeded. The reason for the difference is unknown.

Goal: distinguish digest resolution from image-ID lookup in one bounded,
clean environment. Predict both pinned image IDs resolve with the registered
OS, architecture and repository digest, while both digest references report
`No such image`. Success is 2/2 correct ID results and 2/2 matching missing
digest results. Any successful digest or wrong ID/architecture rejects this
explanation. A timeout, a different command error or partial evidence is
inconclusive. In a complete cohort, an observed contradiction takes precedence
over an inconclusive row. This diagnostic only inspects images; it does not admit a
container, build, pull, delete or retry either earlier admission. Measure once
with the command below after independent review and commit. Anchor: Basili,
Caldiera and Rombach (1994), Goal Question Metric.

The two known image IDs are
`sha256:7a01cbf903e1ed14014bd087f2969bfdfa4bb5a46336ca44144834b1043a5343`
(ARM64) and
`sha256:40abe462ed26e555a0f7b7955254c583389f419045e7204f77ef75434fda4151`
(AMD64). The command checks four fixed references in order, with 15-second
child timeouts and 1 MiB output caps. It reserves one exclusive marker before
inspection, retains private output and status, and never retries. A missing
or partial outcome is inconclusive. Docker socket proxying, daemon-side
activity after interruption, repeated signals and host failure remain limits.

```sh
set -eu
py="$HOME/.local/share/uv/python/cpython-3.13.18-macos-aarch64-none/bin/python3.13"
[ -f "$py" ]
[ ! -L "$py" ]
[ "$(stat -f '%u %Lp %z' "$py")" = '501 755 17593392' ]
[ "$(shasum -a 256 "$py" | cut -d ' ' -f 1)" = 747ca8797fea0949368e9e39d0f75b1eeadbae6c24edadda792ae22299e47a01 ]
JOBS=1 heavy-run /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/private/tmp LANG=C "$py" -I -S -B - <<'PYCODE'
import hashlib, json, os, re, resource, stat, subprocess
from pathlib import Path
home = Path.home()
base = home / '.local/state/agentbrew/experiments/judge-reader-controls-dff226d811d9'
info = base.lstat()
if (base.resolve(strict=True) != base or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
    or stat.S_IMODE(info.st_mode) != 0o700):
    raise SystemExit('private control root unavailable')
cli = Path('/usr/local/' + 'bin/docker').resolve(strict=True)
fd = os.open(cli, os.O_RDONLY | os.O_NOFOLLOW)
try:
    c = os.fstat(fd)
    if not stat.S_ISREG(c.st_mode) or c.st_uid != os.getuid() or stat.S_IMODE(c.st_mode) != 0o755 or c.st_size != 38294464:
        raise SystemExit('Docker CLI identity changed')
    with os.fdopen(os.dup(fd), 'rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != 'cac12f15213d5806f1ffcbc6c159da969e8bf606bf81eafcea89b4c79d7945fd':
            raise SystemExit('Docker CLI identity changed')
finally:
    os.close(fd)
socket = Path('/var/' + 'run/docker.sock')
sockinfo = socket.stat()
if (not stat.S_ISSOCK(sockinfo.st_mode) or sockinfo.st_uid != os.getuid()
    or socket.resolve() != (home / '.docker/run/docker.sock').resolve()):
    raise SystemExit('local Docker socket unavailable')
dirfd = os.open(base, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    current = os.fstat(dirfd)
    if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
        raise SystemExit('private control root changed')
    marker = os.open('lookup-diagnostic-admission.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dirfd)
    try:
        if os.write(marker, b'{"state":"admitted"}\n') != 21:
            raise SystemExit('admission incomplete')
        os.fsync(marker)
    finally:
        os.close(marker)
    os.fsync(dirfd)
finally:
    os.close(dirfd)
root = base / 'lookup-diagnostic'
os.mkdir(root, 0o700)
(root / 'home').mkdir(mode=0o700)
(root / 'config').mkdir(mode=0o700)
print('Private lookup evidence:', root, flush=True)
env = {'HOME': str(root / 'home'), 'DOCKER_CONFIG': str(root / 'config'),
       'DOCKER_HOST': 'unix:///var/run/docker.sock', 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'C'}
images = [
 ('arm64', 'sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632', 'sha256:7a01cbf903e1ed14014bd087f2969bfdfa4bb5a46336ca44144834b1043a5343'),
 ('amd64', 'sha256:2c83bf1a38975801abfd05e92387242ab4d5f96fe05131e2a279f3009ad16393', 'sha256:40abe462ed26e555a0f7b7955254c583389f419045e7204f77ef75434fda4151'),
]
def limit_output(): resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))
rows = []
for arch, digest, image_id in images:
    for kind, ref in (('digest', 'rust@' + digest), ('id', image_id)):
        prefix = arch + '-' + kind
        with (root / (prefix + '.out')).open('xb') as out, (root / (prefix + '.err')).open('xb') as err:
            os.fchmod(out.fileno(), 0o600); os.fchmod(err.fileno(), 0o600)
            result = subprocess.run([str(cli), 'image', 'inspect', ref], env=env, cwd=root,
                stdin=subprocess.DEVNULL, stdout=out, stderr=err, timeout=15, check=False, preexec_fn=limit_output)
            out.flush(); err.flush(); os.fsync(out.fileno()); os.fsync(err.fileno())
        output = (root / (prefix + '.out')).read_bytes()
        errors = (root / (prefix + '.err')).read_bytes()
        if len(output) > 1024 * 1024 or len(errors) > 1024 * 1024:
            raise SystemExit('output limit exceeded')
        if kind == 'digest':
            decision = 'missing' if result.returncode != 0 and (b'No such image: ' + ref.encode()) in errors else ('resolved' if result.returncode == 0 else 'inconclusive')
        elif result.returncode:
            decision = 'inconclusive'
        else:
            try:
                obj = json.loads(output)
                good = (len(obj) == 1 and obj[0].get('Id') == image_id and obj[0].get('Os') == 'linux'
                        and obj[0].get('Architecture') == arch and 'rust@' + digest in (obj[0].get('RepoDigests') or []))
                decision = 'correct' if good else 'wrong'
            except (ValueError, TypeError, AttributeError):
                decision = 'inconclusive'
        row = {'arch': arch, 'kind': kind, 'exit': result.returncode, 'decision': decision,
               'stdout_sha256': hashlib.sha256(output).hexdigest(), 'stderr_sha256': hashlib.sha256(errors).hexdigest()}
        with (root / (prefix + '.json')).open('x', encoding='utf-8') as receipt:
            os.fchmod(receipt.fileno(), 0o600); json.dump(row, receipt, sort_keys=True); receipt.write('\n'); receipt.flush(); os.fsync(receipt.fileno())
        rows.append(row)
decisions = [row['decision'] for row in rows]
outcome = ('success' if decisions == ['missing', 'correct', 'missing', 'correct'] else
           'pivot' if any(x in ('resolved', 'wrong') for x in decisions) else 'inconclusive')
data = (json.dumps({'outcome': outcome, 'decisions': decisions}, sort_keys=True) + '\n').encode()
with (root / 'outcome.pending').open('xb') as out:
    os.fchmod(out.fileno(), 0o600); out.write(data); out.flush(); os.fsync(out.fileno())
os.link(root / 'outcome.pending', root / 'outcome.json', follow_symlinks=False)
os.unlink(root / 'outcome.pending')
dirfd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try: os.fsync(dirfd)
finally: os.close(dirfd)
print('image lookup diagnostic:', outcome, flush=True)
if outcome != 'success': raise SystemExit(1)
PYCODE
```

A successful result supports a lookup distinction only. It does not establish
the root cause or admit a reader build. The result and all four row logs need
independent verification; outcome presence alone is not proof.
