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

The [baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44243713834)
failed all three scratch cases. The first
[candidate](https://github.com/fyodoriv/dotfiles/actions/runs/44243959123)
passed them. Independent review added explicit cache inputs, ordinary
exit status preservation, and direct inode and permission assertions.
The cross-tool publication and revocation decision is still open.

The [final shell candidate](https://github.com/fyodoriv/dotfiles/actions/runs/44244426770)
passed all three cases. The lock's device, inode, owner and mode stayed
the same across refusal, trust and revoke. Registry ownership and mode
also stayed the same. A temporary Git index with only the Perl helper
changed selected both plugin Bats suites through the real affected-test
script. Keep the Bash 3.2 cache dependency explicit.

## Run both writers inside a real native publication

- **Hypothesis**: The selected native publisher holds the same short
  signer lock that Dotfiles trust and revoke use. The lock releases after
  a publication fault even while the private publisher record remains.
- **Measurement**: On hosted Linux and Mac, use the real selected native
  publisher with a signed plugin in a scratch home. At its first real
  payload write, call the current Dotfiles trust and revoke commands.
  Compare registry bytes and lock identity. After a normal return, retry
  both commands. In a separate scratch case after a real payload write,
  interrupt publication, revoke the signer, and verify the retained record
  and refused publisher retry.
- **Success**: Both writers return 75 with zero changed registry bytes
  during publication and return 0 after release. Revocation after the
  interrupted write returns 0 without changing the private owner record.
  The next publisher refuses with zero additional writes. Both hosts
  preserve the signer lock identity and unrelated rows.
- **Pivot**: A competing write, lost row, replaced signer lock, blocked
  emergency revocation, or changed output after refused retry rejects a
  cross-tool claim. Live publisher activation remains a separate check.
- **Anchor**: The previous cross-tool writer and selected signer tests,
  plus the native publisher's private owner and signed scratch fixture.

### Combined result

The [hosted result](https://github.com/fyodoriv/agentbrew/actions/runs/44401181354)
passed both focused cases on Linux and Mac. It used Agentbrew main
`1a6b3bcdfa5fe24f1981036b25a25c0335820b74` and Dotfiles
`e76d872f7761fb84480860694fb97458e6122b07`. The scratch branch
added the test and workflow. The publisher and signer implementations
were the default-branch versions.

Both Dotfiles commands returned 75 during the real selected write and
left the registry bytes and lock identity unchanged. After the write
finished, both commands returned 0 and preserved the unrelated signer.
A second fixture performed a real payload write and injected an
exception. Dotfiles then revoked the signer while the mode-0600 owner
record stayed byte-for-byte unchanged. The next publisher refused with
zero writes. Independent review confirmed the file and command scope.

This result qualifies shared signer ordering and emergency revocation
with a retained record. Live activation and recovery after abrupt
process death still need their own evidence.
