# Hook header reader prediction

Hypothesis: a narrow adapter over the existing no-follow source reader can
bind a bounded header to a stable regular file in a synthetic private root,
without launching it. This is preparation, not runtime tool evidence.

Measurement: `python3 tests/hook_header_reader_test.py` and independent review.

Success: accept a stable owned regular fixture and reject at least eight
unsafe path, identity, type, link, size or change cases. Feed only bounded
header bytes to the shebang decoder. Pivot: reject uncertain cases; do not
claim executable or native-binary trust. Run only synthetic fixtures.

Anchor: `tests/helpers/hook_snapshot_acquire.py` and
[the input evidence requirements](hook-effective-input-audit.md).

The adapter accepts only two ordinary relative path components and a supplied
root identity and an owned root with mode 0700. It reads owned, executable regular files without following the
final links, then checks root and file identities again. The tests use private
synthetic files only. A missing shebang is not proof of a native or trusted
executable. This does not audit root ancestors, filesystem locality, symlink
chains, root-owned system files, transient changes, dynamic libraries or
process completion. Bounded bytes do not imply bounded filesystem latency.
