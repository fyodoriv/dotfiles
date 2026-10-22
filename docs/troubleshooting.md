# Troubleshooting

Symptom-first guide. Find what you're experiencing, follow the fix.

**Quick diagnosis**: run `dotfiles doctor --quiet` to see which checks fail, then search this page for the symptom.

---

## Shell takes >200ms to start

Tool init caches are missing or stale. The shell re-evaluates fnm, fzf, or zoxide on every launch instead of reading cached output.

**Fix:**

```bash
dotfiles doctor --fix --module shell
```

This regenerates caches at `~/.cache/zsh/{fnm,fzf,zoxide}.zsh`. Verify with:

```bash
time zsh -i -c exit
```

If still slow, check `~/.zshrc.local` for heavy inits (nvm, pyenv, conda) — move them behind a lazy-load function.

---

## "command not found: brew"

Homebrew is not on PATH. On Apple Silicon Macs the binary is at `/opt/homebrew/bin/brew`; on Intel it's `/usr/local/bin/brew`.

**Fix:**

```bash
# Check if installed
ls /opt/homebrew/bin/brew 2>/dev/null || ls /usr/local/bin/brew 2>/dev/null

# If missing, install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Reload shell to pick up PATH
source ~/.zshrc
```

If brew is installed but not found, ensure `~/.zshrc` is a symlink to dotfiles (not a stale copy):

```bash
ls -la ~/.zshrc   # should point to ~/apps/dotfiles/home/zshrc
dotfiles doctor --fix --module shell
```

---

## "command not found: node" (or npm, npx)

fnm (Fast Node Manager) is not initialized or cached.

**Fix:**

```bash
# Regenerate fnm cache
dotfiles doctor --fix --module shell

# Or manually
fnm env --shell zsh > ~/.cache/zsh/fnm.zsh
source ~/.zshrc
```

If fnm itself is missing: `brew install fnm && fnm install --lts`.

---

## brew install hangs or times out

Corporate VPN or proxy blocks Homebrew downloads.

**Fix:**

1. Disconnect from VPN
2. Run `brew install <package>`
3. Reconnect to VPN

For casks that fail quarantine checks:

```bash
brew install --cask <name> --no-quarantine
```

---

## `curl` or `git clone` fails with SSL certificate error

A TLS-intercepting proxy replaces upstream certificates with its own root CA. Tools that don't trust that root reject connections with errors like `SSL certificate problem: unable to get local issuer certificate` or `CERT_HAS_EXPIRED`.

**Fix — add the proxy root to the system trust store:**

```bash
# Export the proxy root cert (name varies by org — check Keychain Access)
security find-certificate -a -p /Library/Keychains/System.keychain \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > /tmp/proxy-root.pem

# Tell git to trust it
git config --global http.sslCAInfo /tmp/proxy-root.pem

# Tell curl/Homebrew to trust it
export SSL_CERT_FILE=/tmp/proxy-root.pem
# Add to ~/.zshenv.secrets to persist:
echo 'export SSL_CERT_FILE=/tmp/proxy-root.pem' >> ~/.zshenv.secrets
```

**Alternatively**, bypass the proxy for the specific operation:

```bash
# Disconnect VPN / disable the proxy → run the command → reconnect
```

If your org deploys the proxy cert via MDM, it should already be in the system keychain. Verify:

```bash
security find-certificate -a -c "<proxy name>" /Library/Keychains/System.keychain
```

---

## `brew tap` fails for GitHub Enterprise taps

Private Homebrew taps on GHE (e.g., `<your-ghe-host>/<org>/homebrew-<tap>`) fail because `brew tap` uses HTTPS by default and can't authenticate.

**Fix — authenticate via `gh`:**

```bash
# Ensure you're authenticated to GHE
gh auth login --hostname <your-ghe-host>

# Set GHE auth token for Homebrew
export HOMEBREW_GITHUB_API_TOKEN=$(gh auth token --hostname <your-ghe-host> 2>/dev/null)

# Now tap the private repo
brew tap <org>/<tap> https://<your-ghe-host>/<org>/homebrew-<tap>
```

**Alternatively**, use SSH for the tap:

```bash
brew tap <org>/<tap> git@<your-ghe-host>:<org>/homebrew-<tap>.git
```

Ensure your SSH key is loaded (`ssh-add -l`) and you're on VPN.

---

## A managed-endpoint agent blocks or flags a binary

Some managed Macs run an endpoint-security agent. It can show a dialog, or block a
process, when a script starts a system binary or an unsigned binary. Common
triggers are `/usr/bin/jq`, `/usr/bin/curl`, `/usr/bin/perl`, `/usr/bin/python3`,
`/usr/bin/env`, unsigned Homebrew bottles, and unsigned uv-managed Pythons.

The dotfiles turn this behavior on only when you set it:

```bash
export DOTFILES_MANAGED_ENDPOINT=1
# or list agent app paths (colon-separated); any existing path counts
export DOTFILES_ENDPOINT_AGENT_APPS="/Applications/Example Agent.app"
```

The org overlay normally sets these. With neither set, the endpoint checks do nothing.

**What the dotfiles do when it is on:**

- Put `dotfiles/bin` ahead of `/usr/bin` so GNU-tool shims (`jq`, `curl`, `grep`,
  `perl`, `otool`, `python3`) route to Homebrew binaries.
- Ad-hoc sign Homebrew bottles, uv-managed Pythons, and the shims.
- Avoid `#!/usr/bin/env` shebangs in dotfiles executables. Use `#!/bin/bash`.
- Keep user-dir version managers (`fnm`, `uv`, `rustup`) instead of admin-path installs.

**Fix (runs on every `dotfiles apply`):**

```bash
dotfiles-doctor --module security --fix
# or directly:
~/apps/tooling/dotfiles/bin/dotfiles-adhoc-sign-bottles
~/apps/tooling/dotfiles/bin/dotfiles-adhoc-sign-endpoint-shims
chezmoi apply   # refreshes ~/.config/dotfiles/env.sh (prepends dotfiles/bin to PATH)
```

**Verify:**

```bash
which -a jq curl grep perl
command -v jq           # must not print /usr/bin/jq
codesign -dv "$(command -v jq)" 2>&1 | rg 'Signature|Authority'   # Signature=adhoc
```

**Sandboxed shells:** a shell that starts with a minimal `PATH`
(`env -i PATH=/usr/bin:/bin bash -c ...`) skips `~/.zshenv` and resolves system
binaries. `zsh -c` still loads `~/.zshenv`, so prefer zsh for agent automation.
Agent hooks that prepend `dotfiles/bin` (`prepend-endpoint-path.sh`) cover agent shells.

**LaunchAgent PATH repair:** `dotfiles-fix-launchagent-endpoint-path` (run by
`dotfiles apply` and upgrade) puts `dotfiles/bin` first in each deployed
LaunchAgent's `PATH`. It skips plists with no `Label` quietly: vendor updaters
(Google Keystone, Dropbox) leave valid stubs with an empty `<dict/>`. It warns
only when `plutil -lint` fails, which means the plist is really broken.

**Blocked runtimes:** if policy blocks a runtime such as Node or Ollama by
publisher, run `dotfiles-disable-blocked-node-automation` to stop recurring jobs,
then ask for a machine-scoped exception. After approval, set
`DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER=1` (or
`DOTFILES_ALLOW_BLOCKED_OLLAMA_PUBLISHER=1`) and reinstall the jobs you need.

**Agent Node from another publisher:** to keep agentbrew running while the
Node.js Foundation publisher is blocked, set `DOTFILES_AGENT_NODE_BIN` to a Node
from another publisher (for example `/opt/homebrew/bin/node`), then run
`dotfiles apply`. Agentbrew sync, its LaunchAgents, and its doctors then run on
that Node. The default `node` and Topgrade stay in safe mode. If the variable
names a missing file or a binary from the blocked publisher, nothing changes.

**Python:** `uv` Pythons have no publisher identity, so a strict policy can still
flag them after ad-hoc signing. Python-dependent doctor modules stay off unless
`DOTFILES_ALLOW_PUBLISHER_NA_PYTHON=1` is set.

---

## Network operations hang on VPN (slow DNS, timeouts)

VPN routes all traffic through the corporate network, adding latency to public endpoints. Symptoms: `brew update` takes minutes, `npm install` stalls, `git fetch` from GitHub.com times out.

**Fix — split tunnel when possible:**

If your VPN supports split tunneling, enable it so public traffic goes direct:

```bash
# Check if split tunnel is active (macOS)
scutil --nwi | grep -A5 "VPN"
```

**Workaround — batch operations off VPN:**

1. Disconnect VPN
2. Run all package installs: `brew bundle`, `npm install`, etc.
3. Reconnect VPN

**For persistent DNS issues on VPN:**

```bash
# Flush DNS cache
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

# Check DNS resolution
nslookup github.com
nslookup <your-ghe-host>
```

The `network-resilience` LaunchAgent already handles DNS flushes automatically, but you can trigger it manually if needed.

---

## `dotfiles doctor` check keeps failing

A check has no auto-fix, or the fix doesn't apply in your environment.

**Fix:**

```bash
# See all checks and their status
dotfiles doctor --list

# Skip a check permanently
dotfiles doctor --skip <CHECK_ID>

# Verify overrides are still valid
dotfiles doctor --validate-overrides

# See what's currently skipped
cat ~/apps/dotfiles/.overrides
```

If the check is a symlink check (e.g., `symlink.zshrc`), a file exists at the target instead of a symlink. Re-run `dotfiles doctor --fix --module <module>` to recreate the symlink.

---

## `dotfiles audit` shows security warnings

Security audit warnings are advisory: they do not make `dotfiles audit` fail,
but they point at hardening steps that are worth resolving on a shared laptop or
team-managed machine. Recent versions print the fix next to each warning.

**Fix sensitive-file permission warnings:**

```bash
chmod 600 ~/.npmrc
chmod 600 ~/.docker/config.json
chmod 700 ~/.gnupg
```

Use `600` for token/config files and `700` for directories. Re-run:

```bash
dotfiles audit
dotfiles doctor --module security
```

**Fix "Git commits GPG signed":**

```bash
git config --global commit.gpgsign true
```

Skip that warning only if your team does not require signed commits, your GPG or
SSH signing key is not set up yet, or the repo intentionally handles signing in
another layer. If you opt out, document the reason with:

```bash
dotfiles doctor --skip security.git_gpgsign
```

---

## `agentbrew sync` fails during `dotfiles apply`

Agentbrew sync is non-fatal during chezmoi apply so the rest of dotfiles can
finish installing. Rerun the lifecycle directly to see the real error:

```bash
agentbrew init
dotfiles apply
agentbrew status
dotfiles doctor --module agentbrew
```

If `agentbrew` is not on `PATH`, install it with `npm install -g agentbrew` or
use the local checkout fallback documented in
[agentbrew-setup.md#agentbrew-sync-fails-during-dotfiles-apply](agentbrew-setup.md#agentbrew-sync-fails-during-dotfiles-apply).

---

## MCP server fails because credentials are missing

Agentbrew generated the MCP config, but the server cannot start without local
tokens in `~/.zshenv.secrets`.

**Fix:**

```bash
dotfiles doctor --module agentbrew
agentbrew setup <server-name>
source ~/.zshenv
dotfiles apply
```

Use [home/zshenv.secrets.example](../home/zshenv.secrets.example) as the field
list. Never add token values to `Agentfile.yaml` or generated agent config.

---

## Edited Claude config keeps reverting

Agentbrew owns generated agent config. Files under `~/.claude/` are
outputs from `Agentfile.yaml` plus agentbrew state.

**Fix:**

```bash
agentbrew status --fix
dotfiles apply
dotfiles doctor --module agentbrew
```

Move shared changes into `Agentfile.yaml`. For corrupted
`~/.config/agentbrew/state.yaml`, back it up and rebuild with `agentbrew init`;
see [agentbrew-setup.md#generated-config-keeps-drifting](agentbrew-setup.md#generated-config-keeps-drifting).

---

## `dotfiles doctor` shows "git.local_config" failure

`~/.gitconfig.local` doesn't exist. This file holds your git identity (name, email) and is not tracked by the repo.

**Fix:**

```bash
cat > ~/.gitconfig.local << 'EOF'
[user]
    name = Your Name
    email = your.email@example.com
EOF
```

---

## Git is slow (`git status` takes seconds)

`core.fsmonitor` or `core.splitIndex` may be enabled globally. These cause lock contention and slow operations on large repos.

**Fix:**

```bash
dotfiles doctor --fix --module git
```

Or manually:

```bash
git config --global core.fsmonitor false
git config --global --unset core.splitIndex
```

---

## Git diff shows plain text (no syntax highlighting)

The delta pager is not configured or not installed.

**Fix:**

```bash
# Install delta
brew install git-delta

# Verify config
git config --global core.pager   # should output "delta"

# Auto-fix all git settings
dotfiles doctor --fix --module git
```

---

## Git push fails: "could not read from remote"

SSH key not loaded in the agent, or GitHub access not configured.

**Fix:**

```bash
# Load SSH key
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Test GitHub access
ssh -T git@github.com

# If using GitHub Enterprise
ssh -T git@github.your-company.com
```

If you're on VPN and pushing to GitHub.com, VPN may block the connection — try switching networks or using HTTPS.

---

## `chezmoi apply` fails or shows unexpected diffs

A tracked file was edited directly instead of through the dotfiles source dir.

**Fix:**

```bash
# See what would change
chezmoi diff

# Accept dotfiles version (overwrites local changes)
chezmoi apply --force

# Or keep your version and update the source
chezmoi re-add ~/.zshrc   # copies your file back to source dir
```

If the error mentions template rendering, check `.chezmoi.yaml.tmpl` for syntax errors in Go template expressions.

---

## Bootstrap script didn't run / need to re-run setup

Chezmoi's `run_once_` scripts only execute once per machine. If the initial bootstrap failed partway through (network error, missing permissions) or you need to re-trigger it after a major config change, chezmoi won't re-run it automatically.

**Fix:**

```bash
# Clear chezmoi's record of which scripts have run
chezmoi state delete-bucket --bucket=scriptState

# Re-apply — all run_once scripts will execute again
dotfiles apply
```

This re-runs `run_once_bootstrap.sh` (initial setup), which is idempotent — it skips steps that are already complete. The `run_onchange_*` scripts (brew, macos, launchagents) re-run whenever their content changes, so they don't need manual clearing.

---

## `chezmoi init` fails with age encryption error

You selected `use_encryption: true` during init but don't have an age key.

**Fix (Option A — generate a key):**

```bash
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
```

Re-run init and paste the public key when prompted.

**Fix (Option B — skip encryption):**

```bash
chezmoi init --source ~/apps/dotfiles --apply
# Select 'false' for age encryption when prompted
```

---

## LaunchAgents not running (no auto-sync, no auto-doctor)

The LaunchAgent plists are not loaded into launchctl.

**Fix:**

```bash
# Auto-load all dotfiles LaunchAgents
dotfiles doctor --fix --module workflow

# Verify they're loaded
launchctl list | grep com.dotfiles
```

If a specific agent won't load, check plist syntax:

```bash
plutil ~/Library/LaunchAgents/com.dotfiles.dotfiles-sync.plist
```

---

## Dotfiles not auto-updating (sync LaunchAgent fails silently)

The sync agent runs `dotfiles sync` on a schedule. It fails if the repo has uncommitted changes or a stuck rebase.

**Fix:**

```bash
cd ~/apps/dotfiles
git status              # check for uncommitted changes
git rebase --abort      # if a rebase is stuck
dotfiles sync --dry-run # test manually
```

---

## PATH has duplicate entries

Multiple tool inits (fnm, Homebrew, pyenv) add the same paths. This is cosmetic but can slow lookups.

**Fix:** Open a new terminal tab. The shell config runs `typeset -U PATH` at the end of `.zshrc`, which deduplicates entries. If you're running `source ~/.zshrc` multiple times, duplicates accumulate until the next fresh shell.

---

## "too many open files" error

The default macOS file descriptor limit is 256, which is too low for Node.js projects and watch-mode tools.

**Fix:** Already handled by `.zshrc` (`ulimit -n 65535`). If you still see this error, your `~/.zshrc` symlink may be broken:

```bash
dotfiles doctor --fix --module shell
source ~/.zshrc
ulimit -n   # should output 65535
```

If the error comes from a LaunchAgent job (a dotfiles agent, a minsky worker, opencode), the `.zshrc` limit does not apply. launchd gives its jobs a soft limit of 256. Raise it once in a human terminal:

```bash
launchctl limit maxfiles            # shows the launchd soft and hard limits
dotfiles-launchd-maxfiles           # installs a root LaunchDaemon (sudo once)
dotfiles-launchd-maxfiles --check   # should pass
```

Then restart the affected LaunchAgent, or log out and back in.

---

## Enterprise module checks fail

You enabled enterprise mode but tools (aws, kubectl, etc.) aren't installed or paths are wrong.

**Fix:**

```bash
dotfiles doctor --fix --module enterprise
```

If specific tools aren't found, ensure Homebrew's bin is on PATH:

```bash
echo $PATH | tr ':' '\n' | grep -E 'homebrew|Homebrew'
# Should show /opt/homebrew/bin (Apple Silicon) or /usr/local/bin (Intel)
```

For GitHub Enterprise SSH issues, check VPN connectivity first:

```bash
ssh -T git@github.your-company.com
```

---

## Chrome flashes open then closes / focus switched to main desktop

The persistent agents Chrome (`9223`) should stay running in the
background with **no visible window**. A jump to the main desktop while you are
fullscreen on another Space usually means headed Chrome briefly became frontmost
(often during agent-browser CDP tab create on a non-headless path) or dotfiles
tried to **hide** Chrome via System Events after the fact — that hide step itself
can switch Spaces and is forbidden.

**Dotfiles policy:** nothing in dotfiles may steal user focus or switch desktops.
LaunchAgents use `--headless=new`; the agent-browser wrapper **logs** suspected
focus steals to `~/.local/share/dotfiles/logs/focus-steal.log` and never hides
Chrome or re-activates your previous app.

Common causes:

1. **LaunchAgent Chromes missing `--headless=new`** — CDP tab create opens a
   headed window and macOS switches Spaces. Fix: `chezmoi apply`, then reload
   the managed agents Chrome LaunchAgent (below).
2. **Global `AGENT_BROWSER_ARGS` leaking into `--cdp` attach** — same symptom
   when agent-browser creates a CDP tab. Fix: `dotfiles apply` so the shell
   wrapper clears `AGENT_BROWSER_ARGS` on the CDP path.
3. **Legacy `--window-position=-2400,-2400` on launchd Chromes** — off-screen
   windows can auto-close and restart. Fix: remove `--window-position` from plists
   (doctor check `agent-browser.launchagent_no_offscreen_position`).
4. **Cold-path agent-browser without headless** — default is now
   `--headless=new`; override only for visible SSO with `--headed`.
5. **`open -a` without `-g` / `--background` / `--gj`** in dotfiles scripts —
   doctor checks `focus.no_steal_open_flags` and `focus.no_osascript_activate`
   flag these across `bin/`, `lib/`, `launchagents/`, and `macos-apps.sh`.
6. **Legacy restore helper hiding Chrome** — if an old checkout still runs
   `set visible to false` on Google Chrome, upgrade dotfiles; doctor check
   `agent-browser.restore_no_activate` fails until fixed.

For visible SSO or MFA, use `agent-browser --headed` (sets
`AGENT_BROWSER_ALLOW_FOCUS` behavior via the wrapper). Do not remove headless
from launchd Chromes unless you accept focus steal.

**Diagnose recurring steals:**

```bash
tail -20 ~/.local/share/dotfiles/logs/focus-steal.log
dotfiles doctor --module agent-browser | grep -E 'focus\.|restore_no'
```

**Reload LaunchAgents after plist changes:**

```bash
for label in com.dotfiles.agent-browser-chrome; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/${label}.plist"
done
```

Verify CDP stays up:

```bash
curl -sf http://127.0.0.1:9223/json/version | jq -r .Browser
```

---

## Slack, Mail, or Messages links do nothing

HTTP(S) links from macOS apps use LaunchServices, not an editor's browser setting.
Dotfiles routes them through `~/Applications/ChromeWork.app`, which starts your
Work Chrome profile explicitly and avoids agent-browser Chrome daemons taking the
link.

**Fix:**

```bash
chrome-heal
# or:
chromework-install
dotfiles doctor --module chrome --fix
```

`chrome-heal` (also run hourly by `com.dotfiles.chrome-profile`) patches the
Work profile in Local State and reasserts ChromeWork as the default browser
when macOS has drifted (raw Chrome, Safari, Velja, Finicky, etc.).

**Verify:**

```bash
defaultbrowser
osadecompile ~/Applications/ChromeWork.app | rg 'activateWorkChrome|chromework-activate|survive-handoff|chromework-open-url'
```

The `defaultbrowser` output must mark `browser` with `*`. If it does not, run
`defaultbrowser browser`, then click an HTTP(S) link in Slack again.

---

## Link opens in Chrome but focus stays on Slack (or jumps to empty desktop)

ChromeWork used to launch Work Chrome in the background (`> /dev/null 2>&1 &`),
so the URL opened invisibly. A later fix used `tell application "Google Chrome"
to activate`, but with headless agent-browser CDP Chromes running that AppleScript
targeted a 0-window headless instance — macOS switched Spaces to an empty desktop
instead of the Space where Work Chrome already lives.

The Chrome module registers and maintains `ChromeWork.app` as the macOS default
browser, so links reach the Work profile without an app-specific path.
ChromeWork runs inline `activateWorkChrome()` during the click, then spawns
`chromework-activate --survive-handoff` to keep Work Chrome frontmost after the
ChromeWork applet exits and macOS restores Slack.

**Fix:**

```bash
dotfiles doctor --module chrome --fix
```

**Verify:** with Work Chrome open on another Space, click an http(s) link in
Slack — macOS should switch to Chrome's Space and open the tab there.

---

## Shell running under Rosetta (Apple Silicon)

Apps or terminals show “needs Rosetta” / run as Intel on an M-series Mac.
Common causes from dotfiles history:

1. **Ghostty or other work apps forced to x86_64** — pre-2026 dotfiles set
   `LSArchitecturePriority = x86_64` in `macos-apps.sh` (Ghostty). Finder →
   Get Info → “Open using Rosetta” on Ghostty, Terminal, or Chrome has
   the same effect. Fixed now; apply clears `LSArchitecturePriority` for all
   managed apps (Ghostty, Chrome, Slack, Outlook, Terminal).
   Manual fix:

   ```bash
   defaults delete com.mitchellh.ghostty LSArchitecturePriority        # Ghostty
   # Quit each app completely, reopen
   ```

2. **Intel Homebrew at `/usr/local`** still on PATH before `/opt/homebrew`.
   Native arm64 shell + Intel brew → every `brew`-installed CLI runs under
   Rosetta.

   ```bash
   uname -m          # should be arm64 in a native terminal
   brew --prefix     # should be /opt/homebrew on Apple Silicon
   which -a brew
   ```

   Install native Homebrew if missing (`https://brew.sh`), then migrate or
   remove Intel brew. Reinstall formulae: `brew reinstall $(brew list --formula)`.

3. **Terminal.app “Open using Rosetta”** — disable in Finder → Get Info on
   Terminal/iTerm/Ghostty.

**Verify:**

```bash
dotfiles doctor --module terminal    # apps.no_rosetta_override, tool.ghostty.arch
dotfiles doctor --module security    # security.homebrew_native_prefix
dotfiles doctor --module resilience  # resilience.native_arm64_shell
sysctl sysctl.proc_translated        # 0 = native, 1 = Rosetta
```

After fixes: `chezmoi apply` (re-runs uv python symlinks to `~/.local/bin` on
arm64) and reopen terminals.

---

## opencode silently 404s every call (Rosetta-mode shell, MLX server missing)

You see `oc` (the `opencode attach http://127.0.0.1:4096` alias) connect
but every prompt returns a 404 / empty response. `~/.config/opencode/opencode.json`
points at `http://127.0.0.1:8080/v1` (MLX) but nothing is listening there.

**Why:** `home/zshrc.ai-tools` boots an MLX server (`python3 -m mlx_lm
server`) on shell startup, but MLX's prebuilt wheels are arm64-only. On
an Apple Silicon machine running the user shell under Rosetta (`uname
-m` reports `x86_64` even though the hardware is arm64), the import
fails with `mach-o file, but is an incompatible architecture`. The MLX
listener never comes up; opencode never gets a backend.

**Fix:** the dotfiles MLX startup auto-skips when `uname -m == x86_64`.
Point opencode at the Ollama LaunchAgent on :11434 instead — that
backend is engine-agnostic and works under Rosetta:

```jsonc
// ~/.config/opencode/opencode.json
{
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": { "baseURL": "http://127.0.0.1:11434/v1" },
      "models": {
        "qwen3-coder:30b": { "name": "Qwen3 Coder 30B" },
        "qwen3:0.6b":      { "name": "Qwen3 0.6B (small_model)" }
      }
    }
  },
  "model":       "ollama/qwen3-coder:30b",
  "small_model": "ollama/qwen3:0.6b"
}
```

Make sure the right Ollama models are on disk:

```bash
ollama pull qwen3-coder:30b qwen3:0.6b
dotfiles doctor --module local-ai   # both checks should be green
```

**If you actually want MLX under Rosetta:** install an arm64 Python and
either set `DOTFILES_FORCE_MLX_STARTUP=1` in `~/.zshenv.secrets` with a
patched `arch -arm64 python3` shim, or fix the shell-startup snippet in
`home/zshrc.ai-tools` to call `arch -arm64 /usr/local/bin/python3 -m
mlx_lm server`.

---

## Stuck agent git sessions

Agents can appear frozen mid-task when a git fetch hangs:

1. **Hung `git-upload-pack` SSH sessions** to your GHE host — editor and agent git workers can wait forever. SSH keepalive + `ConnectTimeout` in `~/.ssh/config` (chezmoi-managed) prevents new hangs; doctor check `security.git_ssh_hung_upload_pack` detects sessions older than 30 minutes.

2. **Idle SSH mux sockets** — a stale `ControlMaster` socket can block new git sessions. The heal resets it only when it has no active sessions.

**Manual heal (no focus steal):**

```bash
dotfiles-heal-stuck-agents              # report counts
dotfiles-heal-stuck-agents --dry-run  # preview kills/resets
dotfiles-heal-stuck-agents --fix      # kill hung git workers; reset idle mux
dotfiles doctor --fix                 # also runs heal proactively before module checks
```

**Automatic heal:** `dotfiles doctor --fix` (daily LaunchAgent) and `dotfiles-agent-wake-recover` run `dotfiles-heal-stuck-agents --fix --quiet`. There is no separate LaunchAgent. `com.dotfiles.network-resilience` owns periodic DNS recovery. Logs: `~/.local/share/dotfiles/logs/heal-stuck-agents.log`.

**SSH canonical fix:** `~/.ssh/config` sets `ConnectTimeout 15`, `ServerAliveInterval` / `ServerAliveCountMax`, and `ControlPersist 300` on `Host *` (plus optional per-GHE-host block when `ghe_ssh_host` is configured in chezmoi). Re-apply with `chezmoi apply` or `dotfiles doctor --module ssh --fix`. Set `DOTFILES_GHE_SSH_HOST` or chezmoi `ghe_ssh_host` so heal/mux logic targets your enterprise Git host.

---

## Claude Code stops when the laptop sleeps or the lid closes

**What macOS can guarantee:** Local processes cannot run while the Mac is truly
asleep. Forced sleep, an empty battery, or battery below the configured policy
stops local work. Dotfiles cannot override that kernel behavior.

**Process-scoped policy:**

1. **Normal idle timers when no agent runs** — AC uses `sleep 1` and
   `disksleep 10`. Dotfiles does not set global `disablesleep` or permanent
   `sleep 0`.
2. **Track all relevant processes** — `com.dotfiles.agent-keepawake` runs every
   five seconds and finds every Claude Code executable: the CLI
   (`~/.local/bin/claude` or `claude` on `PATH`) and each Claude desktop app
   session. The desktop app runs Claude Code from
   `~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude`.
   The manager matches that path shape, not one version, so app updates need
   no change. The LaunchAgent is deployed when either install exists.
   It starts one manager-owned `caffeinate -ims -w <pid>` child per process.
3. **Power boundary** — protection applies on AC and on battery at or above
   20%. Below 20% on battery, the manager ends only its own protection.
4. **Lid-closed work** — while protection qualifies, the manager starts an
   Amphetamine session that it owns and verifies Closed-Display Mode.
   Amphetamine provides the supported closed-lid behavior; `caffeinate` alone
   is not a lid-close guarantee.
5. **Prompt release** — once Claude Code exits, the manager
   removes its recorded `caffeinate` children and owned Amphetamine session.
   A user-owned Amphetamine session that existed before the manager runs is
   left unchanged.
6. **Recovery after real sleep** — `~/.wakeup` runs
   `dotfiles-agent-wake-recover --quiet` to heal agents and restart the
   network/keepawake agents.

Display sleep and screen lock still work. The manager does not block an
explicit Restart or Shut Down.

**`pmset sleep 0` does not stop lid-close sleep.** It only turns off the idle
timer. A closed lid sleeps the Mac unless one of these holds: an Amphetamine
session with Closed-Display Mode, `pmset disablesleep 1`, or clamshell mode
(external display and power connected). `caffeinate` alone does not stop it.
To see the state of this Mac, run `dotfiles-resilience-setup --lid-close`. It
is read-only: it never runs `sudo`, changes `pmset`, or sends AppleScript.

**Scheduled jobs while the lid is closed (out of scope for the manager).** A
user LaunchAgent with `StartCalendarInterval` (for example a 06:00 morning job)
needs the Mac awake at its time. With the lid closed, launchd runs it late, at
the next wake. The keepawake manager does not cover these jobs: nothing runs
at lid-close time to hold protection, and covering "a job is due in N hours"
would hold a closed-lid session all night, every night. Pick one fix by hand:

- **On the charger, with Amphetamine:** start a session before you close the
  lid (Amphetamine menu → Start New Session → Indefinitely), and end it when
  you are back. With the managed baseline, its sessions keep a closed Mac
  awake. Do not add an Amphetamine Trigger for this: the managed baseline
  turns Triggers off. `resilience.amphetamine_stale_single_use` warns when a
  manual session runs 12 hours or more.
- **No app:** `sudo pmset -a disablesleep 1`. The Mac then never sleeps, also
  on battery. It drains the battery and heats a closed bag. Undo it with
  `sudo pmset -a disablesleep 0`.

`dotfiles-resilience-setup --lid-close` lists the enabled scheduled
LaunchAgents in `~/Library/LaunchAgents` that a closed lid would delay.

**One-time lid-close setup:** Install Amphetamine. Apply the managed baseline
with `dotfiles-amphetamine-sync apply`. If it reports `cannot read Amphetamine
preferences`, macOS blocks your terminal from the Amphetamine app container.
Grant the terminal Full Disk Access, then run `apply` again. Leave generic Amphetamine Triggers,
Start Session At Launch, Start Session On Wake, and AC-reconnect sessions off.
In Amphetamine → Preferences → Sessions, toggle **Allow System to Sleep When
Display is Closed** once and choose **Do Not Show This Message Again** in its
warning. Then leave the setting off. When macOS asks whether `osascript` may
control Amphetamine, choose **Allow**. On Apple Silicon, install Amphetamine
Power Protect when Amphetamine offers it. It prevents repeated administrator
authentication for Closed-Display Mode. If Amphetamine rejects or cannot
understand a scripting command, the manager records the failure and stops
sending it every five seconds. It retries temporary failures after five minutes
and retries a protocol failure after an Amphetamine app update. Automation
denials retry after five minutes once approval is granted. To force one retry
after correcting Amphetamine settings, remove only
`~/.local/state/dotfiles/agent-keepawake-amphetamine-quarantine`; do not
remove the ownership marker. Without Automation approval, normal `caffeinate`
protection continues, but lid-closed protection is degraded and the resilience
doctor reports it.

**Diagnose:**

```bash
dotfiles doctor --module resilience --quiet
pmset -g batt                    # AC Power or Battery + percentage
launchctl print "gui/$(id -u)/com.dotfiles.agent-keepawake"
dotfiles-agent-keepawake --dry-run
dotfiles-resilience-setup --lid-close   # does closing the lid sleep this Mac?
pmset -g assertions
cat ~/.local/state/dotfiles/agent-keepawake-amphetamine-error
cat ~/.local/state/dotfiles/agent-keepawake-amphetamine-quarantine
```

**Doctor checks:** `resilience.agent_keepawake_loaded`,
`resilience.agent_keepawake_battery_policy`,
`resilience.agent_keepawake_lid_closed_automation`,
`resilience.agent_keepawake_idle_release`, and
`resilience.ac_idle_timers_normal`.

### Amphetamine has kept the Mac awake for too long

`resilience.amphetamine_stale_single_use` warns when a manual Amphetamine
Single-Use assertion lasts 12 hours or more. A valid manager-owned session with
live qualifying agent processes is excluded. Set
`AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS` to change the manual-session threshold.

If the doctor identifies a stale manual session, end it:

```bash
osascript -e 'tell application "Amphetamine" to end session'
```

`resilience.amphetamine_managed_session_policy` restores the no-trigger,
no-auto-start baseline with `dotfiles doctor --fix`. The manager owns
long-running agent sessions; do not add an indefinite generic Trigger as a
substitute.

---

## Recovery and rollback

If something is seriously wrong and you want to start over:

```bash
# Remove all dotfiles symlinks (keeps the repo intact)
chezmoi purge

# Re-apply from scratch
chezmoi init --source ~/apps/dotfiles --apply

# Nuclear option: remove the source dir and re-clone
rm -rf ~/apps/dotfiles
git clone <your-fork-url> ~/apps/dotfiles
chezmoi init --source ~/apps/dotfiles --apply
```

See [onboarding.md](onboarding.md) for the full setup walkthrough.

---

## Still stuck?

1. Run `dotfiles doctor` with verbose output — the check ID tells you exactly what failed
2. Check `dotfiles doctor --list` to see all available checks
3. Search this repo's issues or ask in your team channel
4. For module-specific issues, run `dotfiles doctor --fix --module <name>` — most checks have auto-fix
