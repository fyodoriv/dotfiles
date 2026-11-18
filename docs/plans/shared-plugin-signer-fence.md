# Share plugin signer write admission with Agentbrew

Dotfiles and Agentbrew both write the same allowed signers registry. A
native publication can skip an untrusted plugin only if final
publication and signer changes agree on who has the right to commit.
The shell trust and revoke commands need to cooperate with the
publisher's short operating system lock.

Use the adjacent `<registry>.agentbrew-signer-v1.lock` file. Resolve the
registry's physical parent before deriving the address. Keep this
lock file and its inode across operations. Refuse a linked or
foreign-owned registry or lock path. Do not reuse the long publisher
owner record for signer changes. A stale long record cannot prevent
revocation. Keep trust reads outside this change.

- **Hypothesis**: A Dotfiles signer writer held by a cooperating
  publisher refuses before it changes any registry bytes. A free lock
  permits one atomic trust or revoke and keeps every other row.
- **Measurement**: Extend the isolated plugin Bats tests. Create a
  scratch signer registry and hold its commit lock from an independent
  process. Test trust and revoke under contention, subsequent success,
  a custom registry path, and an unknown lock file type. Compare bytes,
  file owners and the unrelated signer rows. Prove the integrated
  two-tool ordering separately.
- **Success**: Two competing writes return a retry status with zero
  changed bytes. Both operations succeed after release. An unknown
  path refuses unchanged. The existing unsigned and wrong-signer
  controls still pass.
- **Pivot**: An extra write, dropped unrelated row, invalid lock
  cleanup, new signer bypass, or ordinary plugin lifecycle regression
  rejects the candidate. Leave the companion publisher unwired if the
  installed writer versions cannot establish one commit boundary.
- **Anchor**: `lib/plugin-signers.sh`, the existing Bats signer fixtures,
  and the [Agentbrew descriptor experiment](https://github.com/fyodoriv/agentbrew/actions/runs/44243184248).
