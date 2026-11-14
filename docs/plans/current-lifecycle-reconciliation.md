# Current lifecycle reconciliation

Registered before the current-source reconciliation. The historical ledger
stays pinned to its original revision. Its three later lifecycle changes need
source-bound records before they can inform the eventual validator manifest.

- **Hypothesis:** Reopening the three files at commit
  `b44d386373acb7b66e2233703d8d3ff69b667806` can bind each previously
  reviewed relationship to its current source, or mark it unresolved. The
  LaunchAgent file changed again after the previous review; the other two
  file identities match the previous candidate.
- **Measurement:** Compare each file at that commit with candidate
  `94eef660b9d531b401f1f78c7c788101eb3e7bfb` using `git diff` and inspect
  the current source using `git show`. Record Git blob IDs, line ranges,
  source-declared conditions and unresolved boundaries.
- **Success:** Three of three files have current blob IDs and a documented
  relationship or explicit unresolved status; zero historical receipts are
  overwritten and zero source declarations are presented as observed runs.
- **Pivot:** If a current relationship cannot be bound unambiguously, mark it
  unresolved and do not reuse its old classification as current evidence.
- **Anchor:** [source inventory](rust-source-inventory.md),
  [historical range prediction](stale-lifecycle-ranges-prediction.md),
  and Basili, Caldiera and Rombach (1994), Goal Question Metric.

This source review cannot establish runtime selection, ownership, complete
caller coverage, or validator acceptance. It does not modify the scripts.

## Current source findings

These records bind the listed source declarations at the registered commit.
They do not replace the historical ledger or establish that any branch ran.
The first two blobs are unchanged from `94eef660`; the LaunchAgent blob is
different.

| Source path | Blob | Current source relationship |
| --- | --- | --- |
| `.chezmoiscripts/run_after_claude-settings-env.sh` | `fc2d8e5dd63301428461d7c013b9516500d91960` | Lines 35–47 define desired values, print them on request, and otherwise stop when Claude or jq is absent. Lines 57–85 validate existing JSON and merge the values through a temporary file. Line 86 calls jq to format the completion message after the move. This identifies a child call, not an additional settings write. |
| `.chezmoiscripts/run_onchange_brew.sh.tmpl` | `1c924cfea92c672e1f23e9dd5d460624fd26639a` | Lines 193–201 read the optional agent configuration at render time and include the following branch only when desktop is enabled and the agent is not excluded. Lines 204–205 check the cask and report an install failure without making it fatal. Whether the template rendered and the branch ran is unknown. |
| `.chezmoiscripts/run_onchange_launchagents.sh.tmpl` | `be36ad00231fe1fd95f6d2036831d12235486716` | Lines 12–16 declare render-time telemetry checks; lines 82–87 call the telemetry helper when deciding whether to skip that agent. Since the earlier review, line 5 also declares a conditional render-time OpenCode version command. Lines 114–120, 149–152, 158–161 and 190–209 declare version-dependent service selection, a sourced version helper and guarded preservation of an existing plist. The actual version, selected branch, helper behavior and installed state are not established. |

The added OpenCode relationship makes the older LaunchAgent review incomplete
for this revision. Its caller and helper behavior need their own review before
classification. These three records do not establish a complete component or
edge inventory, a rendered template, or execution.
