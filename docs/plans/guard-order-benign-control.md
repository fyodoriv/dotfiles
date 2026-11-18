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

### Keep the existing auto-mode behavior

[Claude Code's auto-mode contract](https://code.claude.com/docs/en/hooks#pretooluse-updatedinput-in-auto-mode)
allows some changed calls to be denied because the server reviewed the
original input. A live auto-mode session is outside this fixture's
scope. Keep the path hook neutral in that mode.

- **Hypothesis**: The default-mode rewrite stays active. A Claude
  auto-mode payload returns no update and makes no approval decision.
- **Measurement**: Invoke the same adapter with the fixed harmless Bash
  input under default and auto envelopes. Replay the native default-mode
  case and run the hosted hook compatibility suite.
- **Success**: One native default rewrite; zero auto updates and approval
  decisions; the native Codex and legacy fixtures pass.
- **Pivot**: Any auto rewrite, unsolicited approval, or lost ordinary
  rewrite rejects this scope.
- **Anchor**: The documented auto-mode response contract and the
  independent adapter review.

## Observed result

The unmodified Claude Code process ran all three registered inputs.
The plain control printed the original marker. The native reference
control printed the replacement marker. With the candidate Dotfiles
hook, both before-tool observers saw the original command. The hook
returned a native prefix, preserved the other Bash arguments, and made
no approval decision. The executor printed the changed-path marker
once, and the post-tool event recorded the prefixed command.

The scripted service was the only reachable network endpoint. A separate
local listener received no connection, and the client reported permission
refusal. The first run stopped before starting Claude because the Darwin
network profile rejected an IP literal in its rule. The verified profile
used the supported `localhost` address and a specific fixture port.

A direct adapter test required an empty auto-mode reply. It first found
an update, then passed after the auto scope guard. The same adapter
check passed default Claude, Codex and legacy responses. The runtime
result covers the harmless Claude default-mode cases. Broader Codex execution ordering, auto-mode rewriting and
general guard ordering remain open.

## Check the Codex executor on isolated Linux

Codex 0.167.0 reported the exact configured scratch hooks. In a separate
Mac control the dispatcher observed the original benign input, then
passed the replacement to the post-tool record. The nested macOS
sandbox refused the Bash launch. That run supplied no executor marker.

- **Hypothesis**: The stock Codex 0.167.0 executor accepts the same
  harmless control in a Linux network namespace with only loopback.
- **Measurement**: Install the pinned Codex CLI in the hosted test
  directory, then isolate the runtime with read-only shell permissions
  and a loopback-only namespace. Check exact hook metadata before running
  the scripted local provider. Run plain and rewritten marker cases.
- **Success**: Exactly one original execution and one replacement
  execution. One receipt per configured observer, no unexpected inputs,
  no interface beyond loopback, and no live account or trust changes.
- **Pivot**: A sandbox failure, missing or duplicate execution, changed
  hook input, or unknown source leaves this platform unqualified.
- **Anchor**: Codex 0.167.0 native hook discovery and the Mac launch receipt.

The [hosted Linux control](https://github.com/fyodoriv/dotfiles/actions/runs/44411528315)
passed with the pinned Codex CLI. The test verified that loopback was the
only network interface before loading the fixture. The configured hook
list contained only the three expected synthetic handlers. The test
accepted those vetted handlers for that invocation in the disposable
home. The read-only shell continued to enforce its normal policy.

In both cases the two before-tool handlers received the original input.
The plain case printed the original marker. The rewrite case printed
the replacement marker, and the after-tool hook recorded the rewritten
input. The scripted endpoint received one proposal and one tool result
in each case. A
[structured result check](https://github.com/fyodoriv/dotfiles/actions/runs/44412009656)
confirmed one completed command per case, with exit code 0 and the exact
expected output marker.

This verifies the selected Codex hook behavior on the hosted Linux
fixture. The local Mac sandbox still refused the shell launch, and
the full configured guard-order check remains open.
