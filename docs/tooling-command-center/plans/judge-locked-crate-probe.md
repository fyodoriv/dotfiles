# Judge reader: bounded locked crate acquisition

The independently checked Linux toolchains can build a synthetic program.
The judge reader's locked `linux-raw-sys` 0.12.1 archive is absent from the
local cache. Its committed candidate lockfile at revision `9db12ffc` has
SHA-256 `5785c2146fc405d9fa4db9d9f9d5373743bcbcf7760d639fc620bd329ddc499e`
and records crate checksum
`32a66949e030da00e8c7d4434b251670a91556f4144941d37452769c25d58a53`.
The public crate endpoint reported 3,006,116 bytes on Nov 7, 2026.

Goal: acquire one locked dependency without extracting it. Predict 1/1
archive matches the registered size and lockfile checksum. Success requires
the exact lock mapping, size, two hashes of the completed file, a separate rehash,
private file identity and a verified receipt. A size or checksum mismatch
rejects this approach; unavailable network, disk or interruption is
inconclusive. Measure once using the exact command below, after independent
review and commit. Anchor: Basili, Caldiera and Rombach (1994), Goal Question
Metric. Source: https://static.crates.io/crates/linux-raw-sys/linux-raw-sys-0.12.1.crate .

The command reuses the reviewed private acquisition and receipt pattern. It
downloads only this fixed HTTPS URL with no credentials, redirects or proxy.
It never extracts or executes the archive. Partial data and logs stay private.
A future consumer must revalidate the archive and receipt; a receipt alone is
not proof. The 120-second deadline applies to the direct child; external
network framing and system failures remain outside its accounting.
Repeated signals, SIGKILL, host failure or an uninterruptible child can defeat
cleanup; retained partial data does not prove successful completion.

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
root = Path(tempfile.mkdtemp(prefix='judge-crate-probe-', dir=base))
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
        if code == 63:
            raise RuntimeError('size-mismatch')
        if code != 0:
            raise RuntimeError('curl-exit-' + str(code))
        os.fsync(fd)
        check = os.fstat(fd)
        pathcheck = os.stat(name, dir_fd=rootfd, follow_symlinks=False)
        if (not stat.S_ISREG(check.st_mode) or check.st_uid != os.getuid() or check.st_nlink != 1
            or stat.S_IMODE(check.st_mode) != 0o600
            or (check.st_dev, check.st_ino) != (before.st_dev, before.st_ino)
            or (check.st_dev, check.st_ino) != (pathcheck.st_dev, pathcheck.st_ino)):
            raise RuntimeError('file-identity')
        if check.st_size != expected_size:
            raise RuntimeError('size-mismatch')
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

deadline = time.monotonic() + 120
try:
    lockpath = Path.home() / 'apps/tooling/wt.noindex/ab-judge-declarations/rust/judge-source/Cargo.lock'
    lockfd = os.open(lockpath, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(lockfd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > 1024 * 1024:
            raise RuntimeError('lock-identity')
        with os.fdopen(os.dup(lockfd), 'rb') as stream:
            raw = stream.read(1024 * 1024 + 1)
        if hashlib.sha256(raw).hexdigest() != '5785c2146fc405d9fa4db9d9f9d5373743bcbcf7760d639fc620bd329ddc499e':
            raise RuntimeError('lock-identity')
        lock = tomllib.loads(raw.decode('utf-8'))
    finally:
        os.close(lockfd)
    matches = [p for p in lock['package'] if p.get('name') == 'linux-raw-sys' and p.get('version') == '0.12.1']
    expected = '32a66949e030da00e8c7d4434b251670a91556f4144941d37452769c25d58a53'
    if len(matches) != 1 or matches[0].get('checksum') != expected or matches[0].get('source') != 'registry+https://github.com/rust-lang/crates.io-index':
        raise RuntimeError('lock-mapping')
    name = 'linux-raw-sys-0.12.1.crate'
    url = 'https://static.crates.io/crates/linux-raw-sys/' + name
    identity = fetch(name, url, 3006116, 3006116, expected, deadline)
    verify_again(name, 3006116, expected, identity)
    data = (json.dumps({'lock_sha256': hashlib.sha256(raw).hexdigest(), 'name': name, 'bytes': 3006116, 'sha256': expected, 'url': url}, sort_keys=True) + '\n').encode()
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
    print('judge locked crate: 1 verified', flush=True)
except BaseException as error:
    category = str(error) if isinstance(error, RuntimeError) and str(error).startswith(('curl-', 'file-', 'root-', 'digest-', 'size-', 'lock-', 'manifest-', 'network-', 'receipt-', 'log-')) else 'unexpected-or-interrupted'
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

Passing does not qualify registry metadata, the other dependencies, a reader
build or any delivered asset. No automatic retry is authorized.
