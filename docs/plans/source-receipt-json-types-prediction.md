# Source receipt JSON type-safety prediction

Registered before the correction on 2026-11-12. A synthetic copy of the source
join receipt with integer `1` substituted for a true boolean was accepted by
the existing Python equality check. No pinned source or receipt was changed.

Hypothesis: a shared strict JSON reader and type-sensitive comparison will
reject numeric/boolean substitutions and duplicate object keys while retaining
all valid receipt results.

Measurement: plant boolean-for-integer and integer-for-boolean substitutions
and duplicate keys in synthetic copies for the seven listed source receipt
checkers. Require each altered input to fail and each original pinned receipt to
pass and regenerate byte for byte. Run focused controls and hosted CI.

Success: zero planted type or duplicate-key errors are accepted across all
seven checkers; all seven valid receipts still pass and regenerate identically.
Pivot: any accepted malformed receipt or changed valid result blocks the fix.
This corrects receipt validation only; it does not prove runtime execution,
ownership or complete source coverage.

Anchor: the reproduced source-join type-confusion case, the seven source
receipt checkers, Basili, Caldiera and Rombach 1994 (GQM), and Munafò et al.
2017 (pre-registration).
