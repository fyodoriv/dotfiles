# Plugin update plan: adopt the 2026-11 core

**Task**: `org-plugin-adopt-core-2026-11` in [TASKS.md](../../TASKS.md).
**Who runs it**: an agent or person on a company machine, in the company
plugin repo (`dotfiles-<org>`) and its agentbrew side. The personal Mac never
touches those repos. Nothing company-specific ever comes back into this
public repo.
**Contract**: [plugins.md](../plugins.md) (the plugin system) and
[observability.md](../observability.md#org-log-sink) (the org log sink).

## Why

Between 2026-11-10 and 2026-11-16 the core changed in five ways that a
company plugin must follow. A plugin that does nothing keeps working, but:

| Area | What changed in the core | What a plugin misses if it does nothing |
|---|---|---|
| Public repo | The core is public. Its leak gates fail closed. | Nothing breaks. The rules below keep company data out of the core. |
| CI | Tests run on hosted CI, not on laptops. The plugin template's CI pins actions, caches Homebrew and checks the newest core weekly. | Unpinned actions (`@v4`), no cache, and no early warning when a core change breaks the plugin. |
| Telemetry | A plugin can ship the org log sink policy (`contributes.telemetry_sink`). The hourly sender works again. | Company Macs send the opt-in events to the public PostHog project instead of the company log system, or send nothing. |
| Rust migration | Every core path is classified. app-priority runs in Rust. The agent hooks stay in shell. | Nothing, unless the plugin calls a core script by path (see step 4). |
| Docs and metrics | The docs map, metrics and the scorecard are current. | Employee docs point at old commands. |

## Before you start

Get these from the owner. Do not guess any of them.

1. A written yes from the company security or IT contact to send these events
   and error lines to the company log system. With no written yes, skip step 3
   and do the rest.
2. The log system details:
   - (a) the Splunk HTTP Event Collector URL (`https`, normally port 8088,
     path `/services/collector/event`);
   - (b) the index for developer-tool events;
   - (c) a HEC token that may write to that index, and where it is kept;
   - (d) the consent mode: `managed` (send with no question;
     `dotfiles telemetry off` still stops it for one person) or `ask`;
   - (e) error logs on or off.
3. A dotfiles core commit that has this plan: `rg -c "plugin-update-plan"
   ~/apps/tooling/dotfiles/docs/plugins.md` prints 1 or more. Write down its
   full SHA. This is `CORE_REF` below.

**Token rule**: never paste, print, log or commit the token. The owner stores
it, and the policy names only the place. Preferred place: the macOS Keychain,
added by the owner (`security add-generic-password -s org-telemetry -a
hec_token -w`, which asks for the value). Other places: a file that group and
others cannot read, or an env var name.

## Step 1: public boundary (every plugin)

1. Keep the plugin repo private, on the company host.
2. Keep `oss-readiness.env` (the private-reference pattern) in the plugin
   root. The core's pre-commit, pre-push and `gh` gates load it; with a plugin
   installed and no pattern, they block ([privacy-gates.md](../privacy-gates.md)).
3. Never open an issue or PR on the public core that names the company, a
   company host, an index or a person. Use `<org-overlay>`, `*.example.com`
   and `PROJ-123`. Report core bugs with `agentbrew report` (it scrubs first).
4. Check: `dotfiles plugin lint <name>` exits 0, and `dotfiles doctor
   --module plugins` shows `plugins.<name>.verified` ok.

## Step 2: CI (every plugin)

1. Copy `data/plugin-template/.github/workflows/ci.yml` from the core at
   `CORE_REF` over the plugin's `.github/workflows/ci.yml`. If the plugin's
   CI has extra steps, keep them below the template's steps.
2. Set `CORE_REF:` in that file to the full core SHA from "Before you start".
   Pull requests then test against the core the release is built for. The
   weekly job tests against the newest core.
3. If the company host is GitHub Enterprise, the `uses:` lines need the
   same actions at the same SHAs on that host (or its allowed-actions list).
   If a SHA is not available there, use the company's approved mirror of
   that action and pin its SHA. Never fall back to a tag.
4. Use the company's standard runners. Do not pick a larger or billed
   runner type without the owner's yes.
5. Copy `data/plugin-template/tests/plugin.bats` over the plugin's
   `tests/plugin.bats`, keeping the plugin's own extra tests. The new test
   checks a shipped telemetry sink policy against the core.
6. Run no tests on the laptop: push a branch and read the CI result. Locally
   run only `shellcheck` and `dotfiles plugin lint <name>`.
7. Check: the plugin CI is green on the pull request, and the first weekly
   run (Monday 06:17 UTC, against the newest core) is green.

## Step 3: telemetry sink (only with the written yes)

1. Add the policy file to the plugin root as `telemetry-sink.json`. Replace
   only the example values:

   ```json
   {"version": 1, "kind": "splunk-hec", "consent": "managed", "error_logs": true,
    "url": "https://splunk.example.com:8088/services/collector/event",
    "token": {"keychain": {"service": "org-telemetry", "account": "hec_token"}},
    "index": "devtools", "sourcetype": "dotfiles:telemetry", "source": "dotfiles"}
   ```

   A policy is invalid (then nothing is sent anywhere, and status says
   `sink policy invalid: <reason code>`) with any unknown key, bad JSON,
   `version` other than 1, a URL that is not `https` or holds user info, a
   missing token source, or `index`/`sourcetype`/`source` outside
   `[A-Za-z0-9_:.-]{1,64}`.
2. In `dotfiles-plugin.yaml`:

   ```yaml
   capabilities:
     telemetry_sink: true
     network_hosts: [splunk.example.com]   # the URL host, without the port
   contributes:
     telemetry_sink: telemetry-sink.json
   ```

3. If a machine already has `~/.config/dotfiles/telemetry-sink.json` from the
   old overlay, apply leaves it alone and says so: a policy that a person or
   an older overlay wrote is never replaced. Remove that file once in the
   rollout (step 6), then apply installs the plugin's copy and from then on
   manages it.
4. **If the company uses a log forwarder and not HEC**: ship `"kind": "file"`
   with `"path": "~/Library/Logs/org-telemetry/dotfiles.jsonl"` (no `url`, no
   `token`, no `network_hosts` entry), and point the forwarder at that file.
   It holds one JSON line per event and rotates to `.1` at 10 MB.
5. What the log system receives: one POST per batch with header
   `Authorization: Splunk <token>`. The body is one JSON object per event,
   joined by newlines: `{"time", "source", "sourcetype", "index", "event":
   {...}}`. `event` holds the event name, its properties, `install_id` (a
   random id, not a person) and `version`. With error logs on, error lines
   arrive as event `dotfiles.error_log` with sourcetype `dotfiles:error_log`
   and fields `file` and `line`. URL credentials are hidden, the home folder
   shows as `~`, and a line is cut at 2000 characters. Only `telemetry.log`
   and `errors.jsonl` under `~/.local/state/dotfiles/` are read.
6. Under `managed`, `dotfiles apply` installs the hourly `com.dotfiles.telemetry`
   LaunchAgent. The install and gains events still need a stored yes
   (`dotfiles telemetry on`).
7. agentbrew: ship `~/.config/agentbrew/telemetry-sink.json` (same format,
   sourcetype `agentbrew:telemetry`, source `agentbrew`) through the
   agentbrew side of the plugin, as the agentbrew task
   `org-overlay-splunk-sink-agentbrew` says.
8. **Known limit**: the sink was tested against a fake receiver that follows
   Splunk's public HEC format, not a real Splunk server. If the real
   collector refuses a request, record the HTTP status and stop. Then offer
   an upstream report (`agentbrew report`). Do not work around it.

## Step 4: Rust migration (every plugin)

1. Find every core path the plugin calls:
   `rg -n 'apps/tooling/dotfiles|DOTFILES_DIR|dotfiles/bin/' <plugin repo>`.
2. For each hit, check it still exists at `CORE_REF`, and that it is a
   documented command (`dotfiles <command>` or a `bin/` script listed in the
   README). Replace internal paths with the command.
3. Do not call `bin/app-priority` or the agent hooks directly. They are core
   internals: app-priority runs the Rust binary when it is installed and
   falls back to shell, and the agent hooks stay in shell by decision
   ([rust-migration.md](rust-migration.md#recorded-exceptions)).
4. A plugin adds no Rust code of its own. The core's migration inventory
   covers only the core repo.
5. Check: the plugin CI (step 2) is green against `CORE_REF`.

## Step 5: docs and metrics (every plugin)

1. Plugin README: the install, update and check commands from the template
   README, the `CORE_REF` it is built for, and a "Where tests run" line (CI
   only).
2. One employee doc page (in the plugin repo or the company wiki): what is
   sent, where it goes, how to stop it (`dotfiles telemetry off`), and who
   approved it.
3. Record the rollout numbers (step 7) in the plugin's CHANGELOG or release
   notes.

## Step 6: release and roll out

1. Bump `version:` in `dotfiles-plugin.yaml`. Create an SSH-signed tag:
   `git tag -s vX.Y.Z -m vX.Y.Z`, then push the tag.
2. The capabilities changed (`telemetry_sink`, `network_hosts`), so the
   weekly unattended `dotfiles upgrade` will skip this release and name it.
   On each Mac, a person runs `dotfiles plugin update <name>` once and
   approves the new capabilities. A fleet tool may run it with `--yes`.
3. If the machine has an old hand-placed policy, remove it first:
   `rm ~/.config/dotfiles/telemetry-sink.json` (only that file).
4. Run `dotfiles apply`.
5. Apply on one company machine first. Run step 7 there. Then roll out to
   the other machines.

## Step 7: verify (paste the output in the plugin PR or release notes)

```sh
dotfiles plugin verify <name>
dotfiles telemetry status
dotfiles telemetry send --dry-run
dotfiles telemetry send; echo "exit=$?"
launchctl print "gui/$UID/com.dotfiles.telemetry" | grep -E 'state|last exit'
```

Expected:
- `status` shows `sink: splunk-hec at <company host>` (or `sink: file …`),
  `consent: managed by org policy` (or the stored answer under `ask`),
  error logs on or off as chosen, and the token source kind, with no token
  value.
- The dry run names the company URL and `<token>`, and no public address.
- The send exits 0.
- One event is found in the log system with
  `index=<index> sourcetype=dotfiles:* | stats count by host` (paste it with
  host names removed). With error logs on, wait for one
  `dotfiles:error_log` event too.
- The plugin CI is green on the PR and on the weekly run.

## Measurement

- **Hypothesis**: company Macs whose dotfiles events reach the company log
  system, with 0 requests to the public default, go from 0 to every machine
  with the plugin. Plugin CI breaks found before a person's Mac breaks go
  from 0 (no weekly core check) to every break the weekly job sees.
- **Measurement**: step 7 on each machine, then the search
  `index=<index> sourcetype=dotfiles:* | stats count by host`.
- **Success**: the send exits 0, the dry run names no public address, and
  the search returns 1 or more events from each machine with the plugin
  within 24 hours.
- **Pivot**: if the real collector refuses the HEC request shape (any 4xx
  that a correct token and index do not fix), switch to `kind: file` plus the
  company log forwarder, and report the refused shape upstream.
- **Anchor**: Basili, Caldiera, Rombach 1994 (Goal Question Metric); Splunk
  documentation, "Format events for HTTP Event Collector".

## Done

Delete the `org-plugin-adopt-core-2026-11` block from the public TASKS.md in
a PR that names no company detail.
