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

The real build needs a separately reviewed and committed exact launcher,
which must revalidate the completed four-row diagnostic, both consumed prior
admissions and the new control receipt. It must use distinct one-use v3
preflight and build markers. This control command authorizes no build and
makes no claim about reader behavior, production delivery, no-Cargo
installation, judge calibration or connectors.
