# Read-only branch metadata preflight

The November 17 delivery preflight compared the current branch name with
the head branch reported by a pull request. The expression was the first
condition in a chain. The guard refused the comparison as branch deletion.
Separate metadata lookups allowed delivery to continue.

- **Hypothesis**: The existing shell parser can prove and isolate the
  initial metadata comparison. The guard will accept all three frozen
  read-only controls and preserve every existing guard decision.
- **Measurement**: Send the sanitized command strings only as JSON input
  to the hook. Never evaluate the input. Use the observed chain, the
  standalone comparison and the existing standalone branch lookup. Run
  these controls on hosted macOS before the repair,
  then run the same cases and both existing Git guard suites.
- **Success**: The observed case reproduces exit 2 on the old hook. The
  updated hook accepts all three controls with zero fixture command
  executions, and the existing hosted cases pass.
- **Pivot**: A different refusal, parser uncertainty, any attempt to run
  the fixture input, or a changed existing decision rejects the repair.
- **Anchor**: The November 17 delivery preflight, PR #752 and the shared
  shfmt syntax-tree boundary in the current Git guard.

A qualified comparison has four fixed words. Its two quoted operands
contain one literal metadata command each: a current Git branch read
and a pull request head name read with a decimal request number. Check
the original input with the ordinary guard. During branch classification,
only the first parser-proven comparison may be removed from the detector
view. Keep the complete suffix, any other guards and the pre-existing
refusal when the parser cannot prove this exact structure.

In hosted baseline run 44227377503, both comparison controls failed.
The existing standalone branch lookup passed. The original live refusal
reported branch deletion, and neither source lookup ran in the hosted
fixture.
