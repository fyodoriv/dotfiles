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
