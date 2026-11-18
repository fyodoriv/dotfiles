# Observe a harmless shell rewrite in Claude Code

Start the `guard-final-command-hook-order` task with an exact-host control.
Use Claude Code 2.1.312 in a disposable workspace. A local scripted service
returns one requested Bash call and one completion. The two possible fixture
commands print fixed markers. They write no files and use no network.

- **Hypothesis**: A harmless input rewrite changes the observed Bash
  result. An observation hook and the post-tool record reveal whether
  the original or updated command reached each stage.
- **Measurement**: Run `heavy-run python3 guard-order-probe.py` from the
  scratch fixture. The script checks the installed host version, launches
  a stock Claude Code process with a disposable home, and limits all
  client network access to the scripted service. Record the exact
  synthetic tool proposal, observation-hook input, rewrite-hook input,
  post-tool input and execution marker. Compare plain observation and a
  documented native rewrite. Keep real account settings and approval
  modes outside the fixture.
- **Success**: Each case has one proposal, one observation input, one
  post-tool input and one execution marker. The plain case executes the
  original marker. The rewrite case records the replacement marker.
  All execution remains inside the fixture and only the five expected
  event fields enter the result.
- **Pivot**: Any missing event, tool refusal, unexpected command, duplicate
  execution, network boundary failure or unknown hook ordering leaves the
  host unqualified. The test uses only two harmless variants. General
  policy enforcement and Codex ordering remain separate.
- **Anchor**: [Claude Code PreToolUse](https://code.claude.com/docs/en/hooks#pretooluse-decision-control)
  and the existing Dotfiles path hook's native response fixture.

This first control exercises the documented Claude hook output. It can
qualify how a benign rewrite reaches the executor. It leaves the configured
Dotfiles path hook's exact response and all other host versions open.

## Check the configured Dotfiles path hook

- **Hypothesis**: The configured Dotfiles hook changes the path used by
  the Bash executor on Claude Code 2.1.312. Both harmless variants can
  run through the same independently bounded fixture.
- **Measurement**: Copy the exact default-branch hook and the two files
  it sources into the disposable workspace. Run the real hook on the
  local scripted Bash input and forward its exact response. Record only
  the response form and whether it proposed a path change. The Bash
  command checks for a fixture-only path and prints one of two markers.
  Compare with the documented Claude output control above.
- **Success**: One actual hook rewrite is received and one execution
  marker shows the fixture-only path. The plain case still shows the
  original marker. No unknown input or extra execution occurs.
- **Pivot**: A response that proposes the fixture path while Bash
  executes with the original path establishes a compatibility failure
  for this host. Keep the run isolated and record the exact distinction
  before changing any adapter.
- **Anchor**: Dotfiles `agent-hooks/prepend-endpoint-path.sh` at
  `dff45d70` and the native Claude Code control above.

## Qualify the native Claude response

The original path hook proposed the fixture prefix under its legacy
`updated_input` field. Claude Code ran the original command and Bash
printed the original marker. The independent native rewrite reached the
executor in the same run. The observed Claude envelope had the
`PreToolUse` event, a permission mode and a transcript path.

- **Hypothesis**: A native response changes the configured fixture command
  and preserves its other arguments without making an approval decision.
- **Measurement**: Replay the exact local fixture with the candidate
  script and compare the hook reply, executor marker and post-tool input.
  Run the hosted hook suite with a synthetic Claude envelope, a native
  Codex envelope and the existing legacy controls.
- **Success**: The real Claude executor prints the changed-path marker
  once. The response keeps all other tool inputs and omits a permission
  decision. Existing Codex and legacy fixtures pass.
- **Pivot**: An unchanged executor marker, missing argument, unsolicited
  approval, or any compatibility regression rejects the adapter.
- **Anchor**: The old-path native receipt and the documented Claude
  `PreToolUse` output contract.
