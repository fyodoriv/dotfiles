# Judge reader: offline source build experiment (draft)

Issue #752 and draft #755 require Linux reader assets bound to their actual
source. The two Linux runtimes, Rust toolchains and synthetic two-build
controls have passed independently reviewed probes. The missing locked
`linux-raw-sys` archive was acquired and reverified without extraction.

Goal: qualify two reproducible offline builds of the pinned reader source on
each Linux architecture. Predict 4/4 builds succeed, the two binaries for each
architecture are byte-identical, and each result has the expected ELF header
and no interpreter segment.
Success requires both architecture results and verified cleanup. Unequal
binaries, malformed build output, wrong ELF header, isolation mismatch or
unconfirmed cleanup rejects this approach. A
missing dependency, failed build, resource exhaustion, timeout or unavailable
runtime is inconclusive and must be diagnosed without retrying automatically.
Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric.

The only source inputs are the four files bound to PR #755 head
`9db12ffc85591dddc75f38e7170c6ab0f7a60f25`. Their SHA-256 values are:

- `Cargo.toml`: `7b53a661ba633fb639bf03868e32ccc9e95fceb3c12c6755fbcb6678dae43989`
- `Cargo.lock`: `5785c2146fc405d9fa4db9d9f9d5373743bcbcf7760d639fc620bd329ddc499e`
- `src/lib.rs`: `ecada5ad6f1c0254f5d761467145c0acbd00c1deb947b70892b7f3dc9e71d170`
- `src/main.rs`: `d6c9b1dfcc02c548f6e8bf7dff95c63734ae157dbc1e5a24868cfd13c2691795`

The intended implementation uses pinned Rust image digests already verified,
an owned read-only input snapshot, verified lockfile crate hashes, no network,
a bounded writable tmpfs, offline locked Cargo, separate build paths, explicit
resource and time caps, and container-ID/nonce cleanup. Registry index data
is a private local input and is not yet independently provenance-qualified.
The copied input snapshot must contain only the fixed source, public registry
metadata and checksum-verified package archives. The lockfile, cache, source,
container configuration, exact build commands, exit classifications and
result receipt all require fail-closed validation.

Independent design review requires four fresh containers, one per build, and
separate Cargo homes and target directories. Compare only within an
architecture. Preserve private output bytes and verify ELF class, endianness,
machine and the absence of an interpreter segment without executing the reader.
These checks do not establish that a binary is usable or fully statically linked.
Enumerate the full
lockfile, freeze the minimal registry index and selected archives, and exclude
credentials, source overrides and preexisting build caches. Recheck snapshot
identities and hashes before and after use. Cargo build scripts execute package
code; matching checksums do not make that code safe. Real-source tests and
live-reader behavior remain outside this experiment.

The seven frozen sparse-index hashes will be listed in the exact runner before
registration. Its name/version/checksum and dependency-name checks are only
preliminary consistency checks, not a complete resolution oracle. The local
index is not independently authenticated. Missing target-specific archives or
offline resolution failures are inconclusive. Whole index entries can include
unrelated public versions and remain in private storage.
The read-only container mount is checked separately. The snapshot checks do
not prove immutability against a concurrent writer with the same user identity.
The receipt is published first and the outcome record last, with exclusive
pending files and atomic links. Neither file's presence proves success. A
consumer must independently revalidate the outcome, receipt, artifact bytes,
input identities and cleanup evidence. Any missing, partial or inconsistent
record is unqualified. A crash between the records leaves no qualified result.

The registered runner SHA-256 is
`dff226d811d9b2703da88e0e7ff5bb2161941dca976f0ca7c799b21849849494`.
The registered control file SHA-256 is
`0d93961089bc3144ab49485406310b2c2c95ae143a3ab9ad4064eb4e33899b65`.
Their exact index hashes are in the frozen runner. A passing probe would not itself publish assets,
qualify the Darwin reader, validate a no-Cargo installation, resolve PR
conflicts, calibrate the judge or prove its connectors.

The following seven synthetic controls must all pass, with no skips, before
the real build is admitted: valid headers for both machines; wrong machine;
interpreter segment; bad header; truncated program table; complete record
publication; and refusal to replace an existing record. Pivot if fewer than
seven pass. These controls do not measure crashes, concurrent publication,
fsync failure or tampering. The positive ELF samples are synthetic headers,
not runnable executables.

Run the control command exactly once, after this prediction is committed.
Have an independent reviewer verify its private receipt and log before the
build command. The fixed control directory must not already exist.

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
for path, expected in ((runner, runner_hash), (test, test_hash)):
    if path.resolve() != path or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('control input changed')
base = home / '.local/state/agentbrew/experiments'
info = base.lstat()
if base.resolve() != base or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
    raise SystemExit('private experiment root unavailable')
root = base / 'judge-reader-controls-dff226d811d9'
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

The build is a separate admission. Its launcher must revalidate the control
receipt and log, exact names, runner and test hashes, and pinned Python before
setting `JUDGE_READER_BUILD_ADMITTED`. The exact launcher must be committed and
reviewed before the build. No build is authorized by this control command.
