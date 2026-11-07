# GitHub token scope checks: exact names

Dotfiles #475 asks the doctor to require only intended GitHub scopes. The
default excludes the optional administrative scopes, but the current scope
check searches every status line for a substring. For example, `delete_repo`
can satisfy `repo`. The current installed `gh auth status --help` documents
`--active`, which limits status output to the active account. Its
[manual](https://cli.github.com/manual/gh_auth_status) also documents this flag.

Goal: avoid false scope passes without requesting or changing a token. Predict
the three synthetic false positives below fall from 3/3 to 0/3; three positive
formats must stay 3/3. Add eight named cases to the existing scratch-only
`tests/module-git-auth-snapshot.bats` fixture. The fake `gh` may accept the
current or proposed status argument during the red check; it records arguments
without printing any real account or token. The cases are:

1. `scope exact rejects delete_repo as repo`: `Token scopes: delete_repo, gist, read:org` must fail `repo`.
2. `scope exact ignores non-scope text`: a missing `gist` plus a separate `gist not granted` line must fail `gist`.
3. `scope exact rejects longer org name`: `read:organization` must not satisfy `read:org`.
4. `scope exact accepts bare names`: `repo, gist, read:org` all pass.
5. `scope exact accepts quoted names`: single-quoted comma-separated names all pass.
6. `scope exact accepts double-quoted names`: double-quoted comma-separated names all pass.
7. `scope exact selects active account`: the fake returns an active account without `repo` and an inactive account with it unless `--active` is passed. `repo` must fail, and the fake must record the flag.
8. `scope exact rejects ambiguous evidence`: missing, duplicate, unterminated-quote, empty or invalid scope-line evidence must not grant a scope.

Before code changes, run the first three cases and require all three to fail
because their expected missing-scope result is not observed. Each fake must be
invoked, and each failure prints a fixed diagnostic: `false repo grant`,
`false gist grant`, or `false org grant`. Then select only
the active account in the cached `gh auth status` call. Parse complete tokens
from its `Token scopes:` line, not other lines or substrings. Accept leading
whitespace and an optional `- ` prefix. Refuse multiple scope lines, unmatched
quotes, invalid tokens and missing or unrecognized evidence; a fine-grained
token or unsupported `--active` result must not claim a scope is granted. Keep the existing
scope list, fix-mode refresh, listing/override no-probe behavior and recorded
authentication/pipefail semantics: with pipefail disabled, a successful scope
parse can remain successful even when cached auth failed; with pipefail enabled
its failure is retained. The fake must verify `--active` is passed
after the fix. Do not print captured auth output or run a real auth probe.

Use the self-checking commands below. Success requires all eight named cases,
the full existing auth snapshot and admin-scope tests, no real auth probe and
the normal `heavy-run make check`. Any false pass, false rejection of a named
positive, changed scope requirements, unsupported output treated as granted,
or existing snapshot-contract regression rejects this approach.

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run bats -f 'scope exact rejects delete_repo as repo|scope exact ignores non-scope text|scope exact rejects longer org name' tests/module-git-auth-snapshot.bats >"$log" 2>&1
result=$?
[ "$result" -ne 0 ] && [ "$(grep -Ec '^not ok [0-9]+ scope exact ' "$log")" -eq 3 ] && grep -Fxq '1..3' "$log" || exit 2
for name in 'rejects delete_repo as repo' 'ignores non-scope text' 'rejects longer org name'; do [ "$(grep -Ec "^not ok [0-9]+ scope exact $name$" "$log")" -eq 1 ] || exit 2; done
for marker in 'false repo grant' 'false gist grant' 'false org grant'; do grep -Fq "$marker" "$log" || exit 2; done
BASH
```

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run bats -f 'scope exact ' tests/module-git-auth-snapshot.bats >"$log" 2>&1 || exit 1
for name in 'rejects delete_repo as repo' 'ignores non-scope text' 'rejects longer org name' 'accepts bare names' 'accepts quoted names' 'accepts double-quoted names' 'selects active account' 'rejects ambiguous evidence'; do
  [ "$(grep -Ec "^ok [0-9]+ scope exact $name$" "$log")" -eq 1 ] || exit 2
done
[ "$(grep -Ec '^ok [0-9]+ scope exact ' "$log")" -eq 8 ] && grep -Fxq '1..8' "$log" && ! grep -Eq '^not ok |# skip' "$log"
BASH
```

Run `heavy-run bats tests/module-git-auth-snapshot.bats tests/gh-admin-scopes.bats`
and the full dotfiles gate after the named controls. Anchors: #475 and the
GitHub CLI manual above; Basili, Caldiera and Rombach (1994), Goal Question
Metric; Munafò et al. (2017), preregistration.
