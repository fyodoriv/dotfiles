# Give the scheduled memory sync a compatible Node

Registration date: 2026-11-20. Target: `c18cb5a3`. Task: #787.

- **Hypothesis**: The daily job can start Agentbrew on a verified compatible Node when the first Node on its path lacks `util.styleText`. The installed script inherits the given path and invokes Agentbrew without checking this feature.
- **Measurement**: Run `bats tests/memory-sync-projects.bats` on hosted macOS. Put two scratch Node executables on the simulated job inputs and a scratch Agentbrew at the normal command name. Count actual dispatches and which runtime received them. Treat the legacy path as a red control before changing code.
- **Success**: A legacy path dispatches on the compatible default once. A compatible path dispatches on that same Node once. Under the existing managed-endpoint publisher rule a blocked candidate has 0 dispatches or runtime probes. A fresh stamp and a caller-supplied Agentbrew override each make 0 runtime probes. Existing normal-path tests pass. Zero real stores or jobs are touched.
- **Pivot**: Stop after 1 managed policy bypass, 1 changed unrelated job, 1 real ingestion or 1 extra runtime probe on a fresh stamp. Require the initial scratch case to reproduce exactly 1 dispatch to the old Node before editing the job.
- **Anchor**: [Reported job failure #787](https://github.com/fyodoriv/dotfiles/issues/787) and the [Node API's styleText history](https://nodejs.org/api/util.html#utilstyletextformat-text-options).

Keep runtime selection in this scheduled job. Reuse the existing managed
endpoint and explicit approved Node checks. Probe the feature without loading
Agentbrew or user Node options. All test binaries and stores are synthetic.

## Scheduled handoff controls

Verify two routing details before enabling the new path. The rendered memory
job alone declares the scheduled context. The executable chosen for Agentbrew
stays the same if the selected Node directory also contains an Agentbrew.

Keep the existing operator override and fresh-stamp paths ahead of the probe.
Reuse the configured fnm resolver. A default fnm alias can supply a fallback
when the configured runtime is absent or fails the probe. Run the fixed
feature probe with a clean environment.

Use the existing endpoint safe-mode marker even when the launch environment
omits endpoint variables. Without the existing exception, require an
explicit approved compatible Node while that marker is present. A known
blocked publisher must receive zero probes. A caller that selects its own
Agentbrew retains that command and its interpreter contract.

## Baseline

The [unchanged macOS job](https://github.com/fyodoriv/dotfiles/actions/runs/44784727640/job/136456429681)
used the old Node in the scratch setup. The case returned exit 18 and
one `old:dispatch` marker. The other 34 memory-sync cases passed.

## Managed launcher handoff

The scheduled marker reaches the existing Agentbrew shim. The shim selects
the same CLI path it normally would. For a launcher with the standard
`#!/usr/bin/env node` line, it starts the qualified Node directly. A shell
startup can still reorder PATH before the check, but cannot change that
direct handoff. A launcher that selects its own interpreter keeps using it.

Cover the real shim with a scratch checkout and a shell startup that moves
the old Node first. Require 1 compatible dispatch and 0 alternate Agentbrew
dispatches. Require the approved path with a different basename to work.
A known Node launcher with no compatible candidate exits 1 before dispatch.
A standalone launcher dispatches once with 0 probes.
