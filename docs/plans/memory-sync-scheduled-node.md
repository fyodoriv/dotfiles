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
