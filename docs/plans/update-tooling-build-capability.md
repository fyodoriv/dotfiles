# Update-tooling inventory and build capability (#776)

Dotfiles owns this skill and the destructive Git guard. Agentbrew issue 776
reports a read-only inventory command blocked by a deployed guard and a
missing native compiler discovered after an applied build starts. Preserve
all work and the existing distribution while diagnosing readiness.

## Prediction before changes

Use the existing Git symbolic-ref command to read the current branch. Keep
branch deletion protection intact. Test the current source guard with literal
read-only commands and prose before deciding whether it needs a code change;
a reported older deployment is not proof of a current-source defect.

On Apple Silicon, preflight the advanced checkout's actual build capability
before calling the build. A source-bound prebuilt verifier, when provided by
that checkout, is authoritative. Otherwise the legacy Cargo-on-PATH
requirement applies. Do not demand Cargo when the supported prebuilt route
passes, install a compiler implicitly, or execute Node during endpoint safe
mode. Other hosts retain their existing build path.

Hypothesis: three deterministic workflow gaps become zero: unsafe branch-read
guidance, starting a legacy build without Cargo, and starting a build despite
a failed native capability probe. Positive controls retain the verified
prebuilt build, available-Cargo legacy build, other-host build and safe-mode
skip. The fixture executes the actual skill build block with synthetic tools
and a scratch distribution; no live build, hook deployment or machine apply.

Measurement: `heavy-run env JOBS=1 bats tests/update-tooling-capability.bats`
then `JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=`. Freeze the test
before its first baseline run. Success: zero missing requirements, every
positive control passes, old distribution bytes remain on both refusals,
and the required gate exits zero. Pivot on any false-ready result, lost
positive control or distribution overwrite. Agent eval additions are contract
coverage, not measured model behavior. Anchor: Basili, Caldiera and Rombach
(1994), GQM; Munafò et al. (2017), preregistration.

Git guard regression commands are strings sent to the guard, never executed
as Git mutations. If current-source controls already pass, retain the guard
and report that evidence rather than loosening its safety policy.
