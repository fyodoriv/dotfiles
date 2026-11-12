# Source receipt batch-read prediction

Registered before changing the source receipt checker on 2026-11-12.

Hypothesis: reading pinned Git blobs in one batch will preserve every generated
receipt and planted-error rejection while reducing repeated Git process starts
for the 135-file bin receipt.

Measurement: compare generated receipt bytes and checker results for every
existing source family against the current checker. Use a controlled Git
wrapper to count blob-read process starts and exercise missing or malformed
batch responses. Run the affected receipt tests and the hosted required gate.

Success: byte-identical generated receipts for all five generated source
families, unchanged rejection counts, one blob-read process for the bin
family instead of 135, and failed reads rejected without partial receipts.
Pivot: retain the current implementation if any output or failure guarantee
changes, or if the process count does not fall to one. No timing improvement
is claimed from process count alone.

Anchor: `doctor-source-receipt-check.py`, Basili, Caldiera and Rombach 1994
(GQM), and Munafò et al. 2017 (pre-registration).
