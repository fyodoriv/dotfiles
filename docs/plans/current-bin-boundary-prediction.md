# Current bin boundary prediction

Registered before implementing the current boundary receipt on 2026-11-12.
The historical bin receipt names seven selected Perl and AWK boundaries in
three files. It does not establish all executable boundaries or dynamic calls.

Hypothesis: pinning the corresponding current definitions and call lines will
make changes to those seven selected boundaries visible without treating the
historical line numbers as current evidence.

Measurement: compare the historical receipt against the current pinned Git
blobs and record each selected definition and call line with its exact text.
Regenerate the receipt byte for byte and plant missing, duplicate, identity,
line and text errors in each row. Run the focused receipt tests and hosted CI.

Success: all seven named boundaries and their eight selected calls are accounted
for; regeneration matches byte for byte; every planted error is rejected.
Pivot: if an anchor cannot be mapped unambiguously or a planted error passes,
retain the historical receipt and label the current boundary unresolved. Do
not infer runtime execution or repository-wide completeness from this check.

Anchor: `rust-bin-source-inventory-evidence.json`, Basili, Caldiera and
Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
