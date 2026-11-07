#!/usr/bin/env python3
"""Draft only: prepare a bounded snapshot for the registered reader experiment."""

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import struct
import subprocess
import tempfile
import uuid
import stat
import tomllib

SOURCE_HASHES = {
    'Cargo.toml': '7b53a661ba633fb639bf03868e32ccc9e95fceb3c12c6755fbcb6678dae43989',
    'Cargo.lock': '5785c2146fc405d9fa4db9d9f9d5373743bcbcf7760d639fc620bd329ddc499e',
    'src/lib.rs': 'ecada5ad6f1c0254f5d761467145c0acbd00c1deb947b70892b7f3dc9e71d170',
    'src/main.rs': 'd6c9b1dfcc02c548f6e8bf7dff95c63734ae157dbc1e5a24868cfd13c2691795',
}
LINUX_PACKAGES = {'bitflags', 'errno', 'libc', 'linux-raw-sys', 'rustix'}
ALL_PACKAGES = LINUX_PACKAGES | {'windows-link', 'windows-sys'}
REGISTRY = 'registry+https://github.com/rust-lang/crates.io-index'
INDEX_HASHES = {
    'bitflags': '6713b703da401faa62e3df0a4a42a7d14a9d777511ac010512a5dd7b3417faaa',
    'errno': '609acf9108184ab8ca087991bf5d634262cea1dc157c6e31e4b7051c08d30fa6',
    'libc': '0c0c0edd0d15a477311bebab5f7b35d68767bb2ebeea274f85404cd2921c498a',
    'linux-raw-sys': 'e20d72e863f9d5a06f29138ba8505b919eb7127bedb6bee3b4e294328b8cfb5e',
    'rustix': '9137126a41483248c64f056fd7a4414e7d30cceb5af9fc7001ab22c90be69889',
    'windows-link': 'd22f6b9ac1dea4587d049cfe5acaa4a769c18feb63dd29aa61bee99837a06546',
    'windows-sys': 'beab389ed4ab8a0aca87fde6a1195814c27d62aae5f6ffb39bb2207ad2f9ad66',
}


def read_regular(path: Path, limit: int) -> bytes:
    if path.resolve(strict=True) != path:
        raise RuntimeError('input-path-alias')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
            raise RuntimeError('input-file-invalid')
        data = bytearray()
        while len(data) <= limit:
            chunk = os.read(fd, min(1024 * 1024, limit + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(fd)
        current = path.lstat()
        identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
        if len(data) > limit or identity(before) != identity(after) or identity(after) != identity(current):
            raise RuntimeError('input-file-changed')
        return bytes(data)
    finally:
        os.close(fd)


def index_path(name: str) -> str:
    if len(name) == 1:
        return '1/' + name
    if len(name) == 2:
        return '2/' + name
    if len(name) == 3:
        return '3/' + name[0] + '/' + name
    return name[:2] + '/' + name[2:4] + '/' + name


def prepare(root: Path) -> tuple[dict[str, tuple], tuple[int, int], tuple[int, int]]:
    descriptors: list[int] = []
    try:
        return _prepare(root, descriptors)
    finally:
        for fd in descriptors:
            os.close(fd)


def _prepare(root: Path, descriptors: list[int]) -> tuple[dict[str, tuple], tuple[int, int], tuple[int, int]]:
    source = Path.home() / 'apps/tooling/wt.noindex/ab-judge-declarations/rust/judge-source'
    registry = Path.home() / '.cargo/registry'
    crate = Path.home() / '.local/state/agentbrew/experiments/judge-crate-probe-szmgwlga/linux-raw-sys-0.12.1.crate'
    for path in (root, registry, registry / 'cache', registry / 'index'):
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) or path.resolve(strict=True) != path:
            raise RuntimeError('input-directory-invalid')
    info = root.lstat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise RuntimeError('private-root-invalid')
    root_identity = (info.st_dev, info.st_ino)
    caches = [x for x in (registry / 'cache').iterdir() if re.fullmatch(r'index\.crates\.io-[a-f0-9]{16}', x.name)]
    if len(caches) != 1:
        raise RuntimeError('registry-cache-ambiguous')
    cache = caches[0].name
    for path in (registry / 'cache' / cache, registry / 'index' / cache):
        if path.resolve(strict=True) != path or not stat.S_ISDIR(path.lstat().st_mode):
            raise RuntimeError('registry-directory-invalid')
    snapshot = root / 'input'
    snapshot.mkdir(mode=0o700)
    snapshotfd = os.open(snapshot, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    descriptors.append(snapshotfd)
    os.fchmod(snapshotfd, 0o755)
    info = os.fstat(snapshotfd)
    snapshot_identity = (info.st_dev, info.st_ino)
    expected: dict[str, tuple] = {}
    total = 0

    def put(name: str, data: bytes) -> None:
        nonlocal total
        if name in expected or len(data) > 32 * 1024 * 1024:
            raise RuntimeError('snapshot-input-invalid')
        total += len(data)
        if total > 64 * 1024 * 1024:
            raise RuntimeError('snapshot-size-exceeded')
        parts = Path(name).parts
        if not parts or any(part in ('', '.', '..') for part in parts):
            raise RuntimeError('snapshot-path-invalid')
        directory = os.dup(snapshotfd)
        try:
            for part in parts[:-1]:
                try:
                    os.mkdir(part, 0o755, dir_fd=directory)
                except FileExistsError:
                    pass
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
                info = os.fstat(child)
                if info.st_uid != os.getuid():
                    os.close(child)
                    raise RuntimeError('snapshot-directory-invalid')
                os.fchmod(child, 0o755)
                os.close(directory)
                directory = child
            fd = os.open(parts[-1], os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
            try:
                with os.fdopen(os.dup(fd), 'wb') as out:
                    out.write(data)
                    out.flush()
                os.fchmod(fd, 0o444)
                os.fsync(fd)
                os.lseek(fd, 0, os.SEEK_SET)
                with os.fdopen(os.dup(fd), 'rb') as check:
                    if check.read(len(data) + 1) != data:
                        raise RuntimeError('snapshot-write-mismatch')
                info = os.fstat(fd)
                at_path = os.stat(parts[-1], dir_fd=directory, follow_symlinks=False)
                if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1
                    or stat.S_IMODE(info.st_mode) != 0o444 or (info.st_dev, info.st_ino) != (at_path.st_dev, at_path.st_ino)):
                    raise RuntimeError('snapshot-file-invalid')
            finally:
                os.close(fd)
            os.fsync(directory)
        finally:
            os.close(directory)
        expected[name] = (hashlib.sha256(data).hexdigest(), info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)

    source_bytes = {}
    for name, digest in SOURCE_HASHES.items():
        data = read_regular(source / name, 1024 * 1024)
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError('source-hash-mismatch')
        source_bytes[name] = data
        put('source/' + name, data)
    lock = tomllib.loads(source_bytes['Cargo.lock'].decode('utf-8'))
    packages = [item for item in lock['package'] if item.get('source')]
    if len(packages) != len(ALL_PACKAGES) or {item['name'] for item in packages} != ALL_PACKAGES:
        raise RuntimeError('lock-package-set-mismatch')
    put('registry/index/' + cache + '/config.json', b'{"dl":"https://static.crates.io/crates","api":"https://crates.io"}')
    for item in packages:
        name, version, digest = item['name'], item['version'], item['checksum']
        if (item['source'] != REGISTRY or not re.fullmatch(r'[a-z0-9-]+', name)
            or not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[a-f0-9]{64}', digest)):
            raise RuntimeError('lock-package-invalid')
        index = index_path(name)
        index_data = read_regular(registry / 'index' / cache / '.cache' / index, 32 * 1024 * 1024)
        if hashlib.sha256(index_data).hexdigest() != INDEX_HASHES[name]:
            raise RuntimeError('index-hash-mismatch')
        matches = []
        for part in index_data.split(b'\0'):
            if part.startswith(b'{'):
                entry = json.loads(part)
                if entry.get('vers') == version:
                    matches.append(entry)
        if len(matches) != 1 or matches[0].get('name') != name or matches[0].get('cksum') != digest:
            raise RuntimeError('index-package-mismatch')
        declared = {dependency.split(' ', 1)[0] for dependency in item.get('dependencies', [])}
        available = {dependency.get('package') or dependency.get('name') for dependency in matches[0].get('deps', [])
                     if dependency.get('kind') != 'dev'}
        if not declared <= available:
            raise RuntimeError('index-dependency-mismatch')
        put('registry/index/' + cache + '/.cache/' + index, index_data)
        if name in LINUX_PACKAGES:
            archive = name + '-' + version + '.crate'
            path = crate if name == 'linux-raw-sys' else registry / 'cache' / cache / archive
            data = read_regular(path, 32 * 1024 * 1024)
            if hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError('crate-hash-mismatch')
            put('registry/cache/' + cache + '/' + archive, data)
    os.fsync(snapshotfd)
    verify_snapshot(root, expected, root_identity, snapshot_identity)
    return expected, root_identity, snapshot_identity


def verify_snapshot(root: Path, expected: dict[str, tuple], root_identity: tuple[int, int], snapshot_identity: tuple[int, int]) -> None:
    snapshot = root / 'input'
    dirs = {str(Path(name).parent) for name in expected}
    dirs |= {str(parent) for name in expected for parent in Path(name).parents if str(parent) != '.'}
    seen_files, seen_dirs = set(), set()
    info = root.lstat()
    if (not stat.S_ISDIR(info.st_mode) or root.resolve(strict=True) != root or info.st_uid != os.getuid()
        or stat.S_IMODE(info.st_mode) != 0o700 or (info.st_dev, info.st_ino) != root_identity):
        raise RuntimeError('private-root-invalid')
    info = snapshot.lstat()
    if (not stat.S_ISDIR(info.st_mode) or snapshot.resolve(strict=True) != snapshot or info.st_uid != os.getuid()
        or stat.S_IMODE(info.st_mode) != 0o755 or (info.st_dev, info.st_ino) != snapshot_identity):
        raise RuntimeError('snapshot-root-invalid')
    for base, dirnames, filenames in os.walk(snapshot, followlinks=False):
        for name in dirnames:
            path = Path(base) / name
            info = path.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o755:
                raise RuntimeError('snapshot-directory-invalid')
            seen_dirs.add(str(path.relative_to(snapshot)))
        for name in filenames:
            path = Path(base) / name
            rel = str(path.relative_to(snapshot))
            info = path.lstat()
            if (rel not in expected or not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o444
                or (hashlib.sha256(read_regular(path, 32 * 1024 * 1024)).hexdigest(), info.st_dev, info.st_ino,
                    info.st_size, info.st_mtime_ns, info.st_ctime_ns) != expected[rel]):
                raise RuntimeError('snapshot-file-invalid')
            seen_files.add(rel)
    if seen_files != set(expected) or seen_dirs != (dirs - {'.'}):
        raise RuntimeError('snapshot-inventory-mismatch')
    for path, identity, mode in ((root, root_identity, 0o700), (snapshot, snapshot_identity, 0o755)):
        info = path.lstat()
        if (not stat.S_ISDIR(info.st_mode) or path.resolve(strict=True) != path or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != mode or (info.st_dev, info.st_ino) != identity):
            raise RuntimeError('snapshot-boundary-changed')


def run_containers(root, expected, root_identity, snapshot_identity):
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
    (root / 'config').mkdir(mode=0o700)
    (root / 'home').mkdir(mode=0o700)
    print(f'Private reader build logs: {root}', flush=True)
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
        resource.setrlimit(resource.RLIMIT_FSIZE, (8 * 1024 * 1024, 8 * 1024 * 1024))

    def call(args, timeout, allow_failure=False):
        nonlocal counter
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
        ('arm64', 'aarch64-unknown-linux-musl', 183, 'sha256:0a555e8b51945db91fd7b8411b4272bb5b8bfa04261d31eaeb2ada564bc02632'),
        ('amd64', 'x86_64-unknown-linux-musl', 62, 'sha256:2c83bf1a38975801abfd05e92387242ab4d5f96fe05131e2a279f3009ad16393'),
    ]
    _, daemon = call(['info', '--format', '{{.OSType}}'], 15)
    if daemon != 'linux':
        raise RuntimeError('non-linux-daemon')
    outputs = {}
    for arch, triple, machine, digest in images:
        image = 'rust@' + digest
        _, raw = call(['image', 'inspect', image], 15)
        data = json.loads(raw)
        if (len(data) != 1 or data[0].get('Os') != 'linux' or data[0].get('Architecture') != arch
            or image not in (data[0].get('RepoDigests') or [])):
            raise RuntimeError('image-platform-mismatch')
        image_id = data[0].get('Id') or ''
        if not re.fullmatch('sha256:[0-9a-f]{64}', image_id):
            raise RuntimeError('image-identity-mismatch')
        binaries = []
        for iteration in ('a', 'b'):
            verify_snapshot(root, expected, root_identity, snapshot_identity)
            nonce = uuid.uuid4().hex
            name = 'agentbrew-reader-build-' + nonce
            _, existing = call(['container', 'ls', '-aq', '--no-trunc', '--filter', 'label=agentbrew.probe=' + nonce], 15)
            if existing:
                raise RuntimeError('container-label-collision')
            ownership = root / ('ownership-' + nonce + '.json')
            with ownership.open('x', encoding='utf-8') as out:
                json.dump({'name': name, 'nonce': nonce, 'image': image, 'image_id': image_id}, out, sort_keys=True)
                out.flush()
                os.fsync(out.fileno())
            source = '/tmp/' + iteration
            command = (
                'set -eu; mkdir -p /tmp/cargo; cp -R /input/registry /tmp/cargo/registry; '
                + 'cp -R /input/source ' + source + '; '
                + 'env -i PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin '
                + 'HOME=/tmp CARGO_HOME=/tmp/cargo RUSTUP_HOME=/usr/local/rustup CARGO_TARGET_DIR=/tmp/target '
                + 'CARGO_INCREMENTAL=0 RUSTFLAGS="--remap-path-prefix=' + source + '=/source --remap-path-prefix=/tmp/cargo=/registry -C strip=symbols" '
                + 'cargo build --offline --locked --release --manifest-path ' + source + '/Cargo.toml --target ' + triple + ' -j 1; '
                + 'base64 /tmp/target/' + triple + '/release/judge-source'
            )
            target = None
            create_attempted = False
            try:
                create_attempted = True
                _, cid = call(['create', '--name', name, '--label', 'agentbrew.probe=' + nonce,
                    '--platform', 'linux/' + arch, '--network', 'none', '--read-only', '--cap-drop', 'ALL',
                    '--security-opt', 'no-new-privileges', '--user', '65534:65534',
                    '--tmpfs', '/tmp:rw,exec,size=1024m,mode=1777', '--mount', 'type=bind,src=' + str(root / 'input') + ',dst=/input,readonly',
                    '--memory', '2048m', '--cpus', '1', '--pids-limit', '128', '--entrypoint', '/bin/sh', image, '-c', command], 30)
                if not re.fullmatch('[0-9a-f]{64}', cid):
                    raise RuntimeError('container-id-invalid')
                target = cid
                with (root / ('id-' + nonce)).open('x', encoding='ascii') as out:
                    out.write(cid + '\n')
                    out.flush()
                    os.fsync(out.fileno())
                state = inspect(cid)
                host = state['HostConfig'] if state else {}
                config = state.get('Config') or {} if state else {}
                labels = config.get('Labels') or {}
                mounts = state.get('Mounts') or [] if state else []
                binds = [m for m in mounts if m.get('Type') == 'bind']
                if (not state or labels.get('agentbrew.probe') != nonce or state.get('Id') != cid
                    or state.get('Image') != image_id or (state.get('State') or {}).get('Running') is not False
                    or config.get('Entrypoint') != ['/bin/sh'] or config.get('Cmd') != ['-c', command]
                    or host.get('NetworkMode') != 'none' or not host.get('ReadonlyRootfs')
                    or host.get('Privileged') or host.get('Binds') or host.get('Devices')
                    or host.get('Tmpfs') != {'/tmp': 'rw,exec,size=1024m,mode=1777'}
                    or len(binds) != 1 or binds[0].get('Source') != str(root / 'input')
                    or binds[0].get('Destination') != '/input' or binds[0].get('RW') is not False
                    or any(m.get('Type') not in ('bind', 'tmpfs') or (m.get('Type') == 'tmpfs' and m.get('Destination') != '/tmp') for m in mounts)
                    or host.get('CapDrop') != ['ALL'] or 'no-new-privileges' not in (host.get('SecurityOpt') or [])
                    or config.get('User') != '65534:65534' or host.get('Memory') != 2048 * 1024**2
                    or host.get('NanoCpus') != 10**9 or host.get('PidsLimit') != 128
                    or host.get('PidMode') or host.get('IpcMode') == 'host'):
                    raise RuntimeError('container-isolation-mismatch')
                verify_snapshot(root, expected, root_identity, snapshot_identity)
                rc, output = call(['start', '--attach', cid], 600, allow_failure=True)
                final = inspect(cid)
                final_state = (final.get('State') or {}) if final else {}
                if (rc or final_state.get('Running') is not False or final_state.get('Status') != 'exited'
                    or final_state.get('ExitCode') != 0):
                    record('build-inconclusive')
                    raise RuntimeError('build-inconclusive')
                if not re.fullmatch(r'[A-Za-z0-9+/=\r\n]+', output):
                    raise RuntimeError('build-output-invalid')
                try:
                    binary = base64.b64decode(''.join(output.splitlines()), validate=True)
                except ValueError as error:
                    raise RuntimeError('build-output-invalid') from error
                inspect_elf(binary, machine)
                verify_snapshot(root, expected, root_identity, snapshot_identity)
                asset = root / ('reader-' + arch + '-' + iteration)
                fd = os.open(asset, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, 'wb') as out:
                    out.write(binary)
                    out.flush()
                    os.fsync(out.fileno())
                binaries.append(binary)
            finally:
                try:
                    if target:
                        cleanup(target, nonce)
                        record('cleanup-verified')
                    elif create_attempted:
                        current = inspect(name)
                        labels = (current.get('Config') or {}).get('Labels') or {} if current else {}
                        cid = current.get('Id') or '' if current else ''
                        if labels.get('agentbrew.probe') == nonce and re.fullmatch('[0-9a-f]{64}', cid):
                            cleanup(cid, nonce)
                        record('creation-unconfirmed')
                except BaseException as error:
                    record('cleanup-unconfirmed')
                    raise RuntimeError('cleanup-unconfirmed') from error
            verify_snapshot(root, expected, root_identity, snapshot_identity)
        if binaries[0] != binaries[1]:
            record('registered-pivot')
            raise RuntimeError('binary-reproducibility-mismatch')
        outputs[arch] = hashlib.sha256(binaries[0]).hexdigest()
        print(arch + ': two offline reader builds matched', flush=True)
    return outputs


def inspect_elf(data: bytes, machine: int) -> None:
    if len(data) < 64 or len(data) > 2 * 1024 * 1024 or data[:6] != b'\x7fELF\x02\x01':
        raise RuntimeError('elf-identity-mismatch')
    kind, actual_machine = struct.unpack_from('<HH', data, 16)
    offset = struct.unpack_from('<Q', data, 32)[0]
    entry_size, count = struct.unpack_from('<HH', data, 54)
    if (kind not in (2, 3) or actual_machine != machine or entry_size < 56 or count < 1 or count > 128
        or offset + entry_size * count > len(data)):
        raise RuntimeError('elf-identity-mismatch')
    types = [struct.unpack_from('<I', data, offset + i * entry_size)[0] for i in range(count)]
    if 1 not in types or 3 in types:
        raise RuntimeError('elf-link-mismatch')


def publish_record(root: Path, name: str, data: bytes) -> None:
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    pending = name + '.pending'
    fd = None
    try:
        fd = os.open(pending, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1:
            raise RuntimeError('record-identity-invalid')
        if os.write(fd, data) != len(data):
            raise RuntimeError('record-write-incomplete')
        os.fsync(fd)
        os.lseek(fd, 0, os.SEEK_SET)
        if os.read(fd, len(data) + 1) != data:
            raise RuntimeError('record-mismatch')
        at_path = os.stat(pending, dir_fd=directory, follow_symlinks=False)
        if (at_path.st_dev, at_path.st_ino) != (before.st_dev, before.st_ino):
            raise RuntimeError('record-identity-invalid')
        os.link(pending, name, src_dir_fd=directory, dst_dir_fd=directory, follow_symlinks=False)
        linked = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if (linked.st_dev, linked.st_ino) != (before.st_dev, before.st_ino):
            raise RuntimeError('record-identity-invalid')
        os.unlink(pending, dir_fd=directory)
        os.fsync(directory)
        linked = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if linked.st_nlink != 1 or stat.S_IMODE(linked.st_mode) != 0o600:
            raise RuntimeError('record-identity-invalid')
        check = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        try:
            info = os.fstat(check)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1
                or (info.st_dev, info.st_ino) != (before.st_dev, before.st_ino)
                or os.read(check, len(data) + 1) != data):
                raise RuntimeError('record-mismatch')
        finally:
            os.close(check)
    finally:
        if fd is not None:
            os.close(fd)
        os.close(directory)


def finalize(root: Path, outputs: dict[str, str], expected: dict[str, tuple], root_identity, snapshot_identity) -> None:
    if set(outputs) != {'arm64', 'amd64'}:
        raise RuntimeError('result-set-invalid')
    verify_snapshot(root, expected, root_identity, snapshot_identity)
    for arch, machine in (('arm64', 183), ('amd64', 62)):
        samples = []
        for iteration in ('a', 'b'):
            path = root / ('reader-' + arch + '-' + iteration)
            info = path.lstat()
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1
                or stat.S_IMODE(info.st_mode) != 0o600):
                raise RuntimeError('artifact-identity-invalid')
            sample = read_regular(path, 2 * 1024 * 1024)
            inspect_elf(sample, machine)
            if hashlib.sha256(sample).hexdigest() != outputs[arch]:
                raise RuntimeError('artifact-hash-mismatch')
            samples.append(sample)
        if samples[0] != samples[1]:
            raise RuntimeError('binary-reproducibility-mismatch')
    data = (json.dumps({'revision': '9db12ffc85591dddc75f38e7170c6ab0f7a60f25',
                        'source_sha256': SOURCE_HASHES, 'index_sha256': INDEX_HASHES,
                        'outputs_sha256': outputs}, sort_keys=True) + '\n').encode()
    verify_snapshot(root, expected, root_identity, snapshot_identity)
    publish_record(root, 'receipt.json', data)


def main() -> None:
    os.umask(0o077)
    root = Path(tempfile.mkdtemp(prefix='judge-reader-build-', dir='/private/tmp'))
    info = root.lstat()
    identity = (info.st_dev, info.st_ino)
    print('Private reader build directory: ' + str(root), flush=True)
    pivot = {'binary-reproducibility-mismatch', 'elf-identity-mismatch', 'elf-link-mismatch',
             'build-output-invalid', 'container-isolation-mismatch', 'cleanup-unconfirmed'}
    status = 'inconclusive'
    reason = 'interrupted'
    try:
        expected, root_identity, snapshot_identity = prepare(root)
        if root_identity != identity:
            raise RuntimeError('private-root-invalid')
        outputs = run_containers(root, expected, root_identity, snapshot_identity)
        finalize(root, outputs, expected, root_identity, snapshot_identity)
        status, reason = 'success', 'four-builds-and-receipt-verified'
    except BaseException as error:
        reason = str(error) if isinstance(error, RuntimeError) and re.fullmatch('[a-z0-9-]+', str(error)) else 'unexpected-or-interrupted'
        status = 'pivot' if reason in pivot else 'inconclusive'
    finally:
        current = root.lstat()
        if (not stat.S_ISDIR(current.st_mode) or current.st_uid != os.getuid()
            or stat.S_IMODE(current.st_mode) != 0o700 or (current.st_dev, current.st_ino) != identity):
            raise SystemExit('Private result directory changed; outcome unrecorded')
        data = (json.dumps({'status': status, 'reason': reason}, sort_keys=True) + '\n').encode()
        publish_record(root, 'outcome.json', data)
    print('reader build outcome: ' + status + ' (' + reason + ')', flush=True)
    if status != 'success':
        raise SystemExit(1)


if __name__ == '__main__':
    if os.environ.get('JUDGE_READER_BUILD_ADMITTED') != 'registered-control-passed':
        raise SystemExit('Reader build is not admitted')
    main()
