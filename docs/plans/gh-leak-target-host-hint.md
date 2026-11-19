# Explain why an unqualified repository landed on public GitHub

[Dotfiles #781](https://github.com/fyodoriv/dotfiles/issues/781) reports that
the public leak check names private text when an unqualified repository flag
selects public GitHub from a checkout with a different origin host.

- **Hypothesis:** An explicit host hint on the blocked command helps the
  operator identify the mismatch and name the intended repository.
- **Measurement:** Run the existing GitHub wrapper fixture with a scratch
  checkout, fake private text, and a fake GitHub command. Check unqualified,
  host-qualified, explicit public, and public-origin cases. Read the hosted
  wrapper test results and verify the fake command never records a blocked post.
- **Success:** The unqualified case still exits 1 and reports one host hint
  without the origin name. Both existing explicit enterprise target forms
  still post once. An explicit public target and a public-origin checkout
  still block without a hint.
- **Pivot:** Reject this change if it alters any routing or scan decision,
  exposes one private value, or adds a hint to either public control.
- **Anchor:** Issue #781 and existing target resolution in
  `lib/gh-public-leak.sh`.
