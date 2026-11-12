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
