# Rust vendor ownership evidence

Registered before the repository check on 2026-11-15. A read-only review of
revision `7d6aee8` found registry package checksums in the Rust lockfiles and
matching vendor file checksums. Vendored sources are upstream-owned; the
separate pinned agentbrew core remains agentbrew-owned.

**Hypothesis:** A small source-bound review can classify each locked registry
package outside dotfiles-owned migration scope and reject a changed package,
file, or unlisted vendor path without executing vendor code.

**Measurement:** Hosted CI checks the committed review against the lockfiles,
vendor manifests and every listed file. Synthetic in-memory controls change a
package digest, file digest and path set.

**Success:** All current identities match and all three planted errors are
rejected. **Pivot:** A mismatch, untracked vendor path, or accepted planted
error leaves vendor ownership unqualified until the evidence is fixed.

This checks ownership and content identity only. It does not establish full
source discovery, runtime behavior, or the final migration audit.

**Anchor:** `rust-source-inventory`, the pinned Cargo lockfiles and vendor
checksums; Basili, Caldiera and Rombach 1994 (GQM).
