# Dynamic Git guard false alarms (#502)

## Prediction before implementation

Goal: allow two reported non-destructive command shapes while retaining
the guard against branch deletion. Question: can the guard distinguish those
safe examples from both direct and dynamically spelled branch deletion?

Measure with `bats --filter '^issue 502 ' tests/agent-hooks-block-dangerous-git.bats`
and `bats tests/agent-hooks-block-dangerous-git.bats`. Feed the exact command
strings below to the hook as JSON; never execute those strings. Set the hook's
`cwd` to a scratch Git repository with an unmerged `topic` branch for every
case. The expected exit is zero for each of these two safe strings:

```text
git commit -m "branch head" -F "$(mktemp -d)/msg"
rg 'branch -D' agent-hooks/block-dangerous-git.sh "$(mktemp -d)"
```

The expected exit is two for each of these seven destructive controls. The
heredoc examples each form one multiline JSON command:

```text
git branch -D topic
git $(echo branch) -D topic
git commit -m "$(git branch -D topic)"
rg "branch $(git branch -D topic)" file
cat <<'NOTE' > "$(git branch -D topic)"
branch -D is mentioned here
NOTE
cat <<'NOTE' | sh
git branch -D topic
NOTE
git status; git branch -D topic
```

Prediction: the current hook rejects at least one of the two safe examples.
A successful fix allows both and blocks all seven controls: 9/9 focused checks
and the entire existing hook suite passing. If fewer than nine
safe and destructive checks pass, or any existing hook check fails, abandon
the approach.
Confirm the reported safe-case failure before changing the hook. Do not weaken
unknown shell behavior merely to satisfy these examples. Other destructive
spellings remain covered by the existing suite. In particular, inspect
executable substitutions and shell-fed heredocs, retain conservative fallback
on parse failure, and preserve the existing restrictions on heredoc paths.
The report's expanded heredoc destination remains out of scope until its path
safety can be established; this experiment alone cannot close #502.

Anchor: [Goal Question Metric](https://doi.org/10.1002/9780470172669.ch12).
