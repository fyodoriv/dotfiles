# Judge reader: bounded official archive verification

The earlier unexecuted draft did not sufficiently bound network operations or
make a partial receipt distinguishable from a completed one. This draft uses a
pinned system curl in a directly owned child, verifies the official manifest
and its six mappings before downloading, records only fixed private status
messages, and publishes a receipt atomically. Independent review found no
remaining concrete blocker. Commit this prediction before executing it.

Predict six of six public Rust 1.99.1 musl archives match their registered
sizes and SHA-256 values. A size, digest or manifest-mapping mismatch rejects
the source path. Unavailable network, TLS, disk, or an unreaped child is
inconclusive. The command accepts at most the registered 321,890,416 archive
bytes and one bounded manifest; network framing can add bytes in transit. It
never extracts or executes the archives, sends no
repository or private data, and makes no linker, emulation, build or artifact
claim. The network deadline is 900 seconds plus bounded child termination;
local process creation, filesystem reads, writes and fsync have no hard
wall-clock guarantee.
Keep partial files and the private status log on failure. Never use the
presence of a receipt alone as proof: a later consumer must revalidate the
manifest, receipt and all six archive identities.

The exact command below needs a fresh repository check and a commit before
execution. Its fixed metadata was independently checked against the official
manifest and HTTP HEAD responses on Nov 7, 2026.
The SHA-256 of https://static.rust-lang.org/dist/channel-rust-1.99.1.toml is
`fb152be80975c194aa5fc684b2aec3a6e14e2b855efe2faa4e5f8ae6e590f463`.

```sh
set -eu
py="$HOME/.local/share/uv/python/cpython-3.13.18-macos-aarch64-none/bin/python3.13"
[ -f "$py" ]
[ ! -L "$py" ]
[ "$(stat -f '%u %Lp %z' "$py")" = '501 755 17593392' ]
[ "$(shasum -a 256 "$py" | cut -d ' ' -f 1)" = 747ca8797fea0949368e9e39d0f75b1eeadbae6c24edadda792ae22299e47a01 ]
JOBS=1 heavy-run /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=/private/tmp LANG=C "$py" -I -S - <<'PY'
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import tempfile
import time
import tomllib

entries = [
    ('rustc', 'aarch64-unknown-linux-musl', 116397484, '4c80eab52764172618197bd23000c739fdf561ae9415caa2a5ef62ab5c785175'),
    ('rustc', 'x86_64-unknown-linux-musl', 108931484, '034e2cfea9551483c8cedbf89e52d045b89dcf860ab73aae618c89b1a87b0f18'),
    ('cargo', 'aarch64-unknown-linux-musl', 11738916, '50f323ec9e1e60c41d42ef4dd988cc87d0a79f7b4ea10fd364df177212b89106'),
    ('cargo', 'x86_64-unknown-linux-musl', 12334640, 'f70f6f9b251a2d9cbb0f5792c612fde478e06cfa76abb639aceaada2c6453b1f'),
    ('rust-std', 'aarch64-unknown-linux-musl', 31162764, '2f3eb0d0610e2b7f6b2121d106e2490ac648decfa0c09b30873bdfc60de6c1ab'),
    ('rust-std', 'x86_64-unknown-linux-musl', 41325128, '1dd241eaeb19ff3b5180461c77bdee93d6cafc669eda9de834e7c06b0ec3ca95'),
]
manifest_hash = 'fb152be80975c194aa5fc684b2aec3a6e14e2b855efe2faa4e5f8ae6e590f463'
curl = '/usr/' + 'bin/curl'
curl_expected = '625cd93eb0043214d5f74974d34f0b4d748977473e236a2e7f4704ecc2b95950'

def checked_curl():
    fd = os.open(curl, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o755 or info.st_size != 829680:
            raise RuntimeError('curl-identity')
        with os.fdopen(os.dup(fd), 'rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != curl_expected:
                raise RuntimeError('curl-identity')
        return (info.st_dev, info.st_ino)
    finally:
        os.close(fd)

curl_id = checked_curl()
base = Path.home() / '.local/state/agentbrew/experiments'
info = base.lstat()
if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or base.resolve() != base:
    raise SystemExit('private experiment root unavailable')
if shutil.disk_usage(base).free < 2 * 1024**3:
    raise SystemExit('insufficient scratch disk')
root = Path(tempfile.mkdtemp(prefix='judge-rust-archives-', dir=base))
rootfd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
rootinfo = os.fstat(rootfd)
if rootinfo.st_uid != os.getuid() or stat.S_IMODE(rootinfo.st_mode) != 0o700:
    raise SystemExit('private archive directory unavailable')
print(f'Private archive directory: {root}', flush=True)
logfd = os.open('events.log', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=rootfd)

def log(message):
    data = (message + '\n').encode('ascii')
    if os.write(logfd, data) != len(data):
        raise RuntimeError('log-write')
    os.fsync(logfd)

def same_root():
    current = root.lstat()
    opened = os.fstat(rootfd)
    if (not stat.S_ISDIR(current.st_mode) or current.st_uid != os.getuid()
        or stat.S_IMODE(current.st_mode) != 0o700 or opened.st_uid != os.getuid()
        or stat.S_IMODE(opened.st_mode) != 0o700
        or (current.st_dev, current.st_ino) != (rootinfo.st_dev, rootinfo.st_ino)
        or (opened.st_dev, opened.st_ino) != (rootinfo.st_dev, rootinfo.st_ino)):
        raise RuntimeError('root-changed')

def fetch(name, url, limit, expected_size, expected_hash, deadline):
    same_root()
    if checked_curl() != curl_id:
        raise RuntimeError('curl-changed')
    remaining = min(240, int(deadline - time.monotonic()))
    if remaining < 1:
        raise RuntimeError('network-deadline')
    fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=rootfd)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1 or stat.S_IMODE(before.st_mode) != 0o600:
            raise RuntimeError('file-identity')
        log(name + ':start')
        args = [curl, '-q', '--silent', '--fail', '--noproxy', '*', '--proto', '=https',
                '--max-redirs', '0', '--connect-timeout', '15', '--max-time', str(remaining),
                '--max-filesize', str(limit), '--output', '-', url]
        env = {'HOME': str(root), 'PATH': '/usr/bin:/bin', 'LANG': 'C'}
        watched = {signal.SIGINT, signal.SIGTERM, signal.SIGHUP}
        old_handlers = {sig: signal.getsignal(sig) for sig in watched}
        def interrupted(signum, frame):
            raise InterruptedError('interrupted')
        for sig in watched:
            signal.signal(sig, interrupted)
        child = None
        try:
            oldmask = signal.pthread_sigmask(signal.SIG_BLOCK, watched)
            try:
                child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=fd, stderr=subprocess.DEVNULL, env=env,
                                         preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, oldmask))
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, oldmask)
            try:
                code = child.wait(timeout=remaining + 5)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError('curl-timeout') from error
        finally:
            cleanup_mask = signal.pthread_sigmask(signal.SIG_BLOCK, watched)
            try:
                if child is not None and child.poll() is None:
                    try:
                        child.kill()
                    except ProcessLookupError:
                        pass
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired as error:
                        raise RuntimeError('curl-unreaped') from error
            finally:
                try:
                    signal.pthread_sigmask(signal.SIG_SETMASK, cleanup_mask)
                finally:
                    for sig, handler in old_handlers.items():
                        signal.signal(sig, handler)
        if code != 0:
            raise RuntimeError('curl-exit-' + str(code))
        os.fsync(fd)
        check = os.fstat(fd)
        pathcheck = os.stat(name, dir_fd=rootfd, follow_symlinks=False)
        if (not stat.S_ISREG(check.st_mode) or check.st_uid != os.getuid() or check.st_nlink != 1
            or stat.S_IMODE(check.st_mode) != 0o600 or check.st_size != expected_size
            or (check.st_dev, check.st_ino) != (before.st_dev, before.st_ino)
            or (check.st_dev, check.st_ino) != (pathcheck.st_dev, pathcheck.st_ino)):
            raise RuntimeError('file-identity')
        digests = []
        for _ in range(2):
            os.lseek(fd, 0, os.SEEK_SET)
            h = hashlib.sha256()
            while True:
                chunk = os.read(fd, 1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
            digests.append(h.hexdigest())
        after = os.fstat(fd)
        pathcheck = os.stat(name, dir_fd=rootfd, follow_symlinks=False)
        if (digests != [expected_hash, expected_hash] or after.st_size != expected_size
            or after.st_mtime_ns != check.st_mtime_ns or after.st_ctime_ns != check.st_ctime_ns
            or (after.st_dev, after.st_ino) != (pathcheck.st_dev, pathcheck.st_ino)):
            raise RuntimeError('digest-mismatch')
        same_root()
        log(name + ':verified')
        return (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
    finally:
        os.close(fd)

def verify_again(name, expected_size, expected_hash, identity):
    same_root()
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=rootfd)
    try:
        before = os.fstat(fd)
        pathinfo = os.stat(name, dir_fd=rootfd, follow_symlinks=False)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) != 0o600
            or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != identity
            or (before.st_dev, before.st_ino) != (pathinfo.st_dev, pathinfo.st_ino)):
            raise RuntimeError('file-identity')
        with os.fdopen(os.dup(fd), 'rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        after = os.fstat(fd)
        pathinfo = os.stat(name, dir_fd=rootfd, follow_symlinks=False)
        if (digest != expected_hash or after.st_size != expected_size
            or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns) != identity
            or (after.st_dev, after.st_ino) != (pathinfo.st_dev, pathinfo.st_ino)):
            raise RuntimeError('digest-mismatch')
    finally:
        os.close(fd)

deadline = time.monotonic() + 900
try:
    manifest_url = 'https://static.rust-lang.org/dist/channel-rust-1.99.1.toml'
    manifest_identity = fetch('manifest.toml', manifest_url, 943486, 943486, manifest_hash, deadline)
    manifestfd = os.open('manifest.toml', os.O_RDONLY | os.O_NOFOLLOW, dir_fd=rootfd)
    try:
        info = os.fstat(manifestfd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or info.st_size != 943486:
            raise RuntimeError('manifest-identity')
        with os.fdopen(os.dup(manifestfd), 'rb') as stream:
            raw = stream.read(943487)
        pathinfo = os.stat('manifest.toml', dir_fd=rootfd, follow_symlinks=False)
        if (len(raw) != 943486 or hashlib.sha256(raw).hexdigest() != manifest_hash
            or (info.st_dev, info.st_ino) != (pathinfo.st_dev, pathinfo.st_ino)):
            raise RuntimeError('manifest-identity')
        manifest = tomllib.loads(raw.decode('utf-8'))
    finally:
        os.close(manifestfd)
    records = []
    for package, target, size, expected in entries:
        name = f'{package}-1.99.1-{target}.tar.xz'
        url = 'https://static.rust-lang.org/dist/2026-10-15/' + name
        item = manifest['pkg'][package]['target'][target]
        if item.get('available') is not True or item.get('xz_url') != url or item.get('xz_hash') != expected:
            raise RuntimeError('manifest-mapping')
        records.append({'name': name, 'bytes': size, 'sha256': expected, 'url': url})
    log('manifest:mappings-verified')
    identities = {}
    for record in records:
        identities[record['name']] = fetch(record['name'], record['url'], record['bytes'], record['bytes'], record['sha256'], deadline)
    verify_again('manifest.toml', 943486, manifest_hash, manifest_identity)
    for record in records:
        verify_again(record['name'], record['bytes'], record['sha256'], identities[record['name']])
    data = (json.dumps({'manifest_sha256': manifest_hash, 'archives': records}, sort_keys=True) + '\n').encode()
    pending = os.open('receipt.pending', os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=rootfd)
    try:
        pendinginfo = os.fstat(pending)
        if not stat.S_ISREG(pendinginfo.st_mode) or pendinginfo.st_uid != os.getuid() or pendinginfo.st_nlink != 1 or stat.S_IMODE(pendinginfo.st_mode) != 0o600:
            raise RuntimeError('receipt-identity')
        if os.write(pending, data) != len(data):
            raise RuntimeError('receipt-write')
        os.fsync(pending)
        os.lseek(pending, 0, os.SEEK_SET)
        if os.read(pending, len(data) + 1) != data:
            raise RuntimeError('receipt-reread')
        same_root()
        before = os.stat('receipt.pending', dir_fd=rootfd, follow_symlinks=False)
        if (before.st_dev, before.st_ino) != (pendinginfo.st_dev, pendinginfo.st_ino):
            raise RuntimeError('receipt-identity')
        os.link('receipt.pending', 'receipt.json', src_dir_fd=rootfd, dst_dir_fd=rootfd, follow_symlinks=False)
        linked = os.stat('receipt.json', dir_fd=rootfd, follow_symlinks=False)
        if (not stat.S_ISREG(linked.st_mode) or linked.st_uid != os.getuid()
            or stat.S_IMODE(linked.st_mode) != 0o600
            or (linked.st_dev, linked.st_ino) != (pendinginfo.st_dev, pendinginfo.st_ino)):
            raise RuntimeError('receipt-identity')
        os.unlink('receipt.pending', dir_fd=rootfd)
        os.fsync(rootfd)
        linked = os.stat('receipt.json', dir_fd=rootfd, follow_symlinks=False)
        if linked.st_nlink != 1 or (linked.st_dev, linked.st_ino) != (pendinginfo.st_dev, pendinginfo.st_ino):
            raise RuntimeError('receipt-identity')
    finally:
        os.close(pending)
    receiptfd = os.open('receipt.json', os.O_RDONLY | os.O_NOFOLLOW, dir_fd=rootfd)
    try:
        info = os.fstat(receiptfd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != 0o600
            or (info.st_dev, info.st_ino) != (pendinginfo.st_dev, pendinginfo.st_ino)
            or os.read(receiptfd, len(data) + 1) != data):
            raise RuntimeError('receipt-reread')
    finally:
        os.close(receiptfd)
    same_root()
    log('complete')
    print('judge Rust archives: 6 verified', flush=True)
except BaseException as error:
    category = str(error) if isinstance(error, RuntimeError) and str(error).startswith(('curl-', 'file-', 'root-', 'digest-', 'manifest-', 'network-', 'receipt-', 'log-')) else 'unexpected-or-interrupted'
    try:
        log('stopped:' + category)
    finally:
        print('archive probe stopped: ' + category, flush=True)
    raise SystemExit(1)
finally:
    os.close(logfd)
    os.close(rootfd)
PY
```

The OS may leave server-side transfer activity after a local timeout; the
probe makes no claim otherwise. SIGKILL, host failure, repeated signals or an
uninterruptible OS operation can prevent cleanup or the final failure log.
The probe never signals a process group. A complete
receipt is only a hint until a future consumer rechecks all inputs. The
source manifest and curl manual are primary references:
https://static.rust-lang.org/dist/channel-rust-1.99.1.toml and
https://curl.se/docs/manpage.html#--max-filesize . Basili, Caldiera and
Rombach (1994), Goal Question Metric, anchors the measurement.
