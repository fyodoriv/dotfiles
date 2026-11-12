# Host-load helper relationship prediction

An exploratory source review found two direct source statements and a
conditional helper path. That observation predates this prediction. It does
not prove execution or complete caller coverage.

Hypothesis: a pinned source receipt can bind the host-load helper identity to
the two direct source statements and distinguish the conditional fallback.

Measurement: `python3 docs/plans/host-load-relationships.py --check` plus its
focused mutation controls against the pinned source revision.

Success: the helper identity, both direct source statements and the
conditional fallback are anchored, with at least four altered identity or
anchor controls rejected. Pivot: keep any unsupported route unresolved. The
Bats test directory and fallback environment remain runtime inputs. A Makefile
cache dependency and shellcheck comment are not calls.

Anchor: `docs/plans/rust-source-inventory.md` and the pinned source locations
recorded in the receipt.
