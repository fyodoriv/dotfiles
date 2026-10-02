#!/bin/bash
# Doctor checks for security module — SSH, secrets, permissions, git config safety.
# Migrated from bin/dotfiles-audit. Runs as part of dotfiles-doctor (severity: critical)
# and standalone via dotfiles-audit.

DOTFILES_MODULE_DIR="$DOTFILES_DIR"
if [ -n "${DOTFILES_MODULE_DIR:-}" ] && [ -f "$DOTFILES_MODULE_DIR/lib/dotfiles-endpoint-paths.sh" ]; then
  source "$DOTFILES_MODULE_DIR/lib/dotfiles-endpoint-paths.sh"
fi
if [ -n "${DOTFILES_MODULE_DIR:-}" ] && [ -f "$DOTFILES_MODULE_DIR/lib/brew-bottle-audit.sh" ]; then
  source "$DOTFILES_MODULE_DIR/lib/brew-bottle-audit.sh"
fi
source "$DOTFILES_MODULE_DIR/lib/secret-scan.sh"
DOTFILES_LINK_DIR="${DOTFILES_LINK_DIR:-$DOTFILES_MODULE_DIR}"
DOTFILES_LINK_BIN="$DOTFILES_LINK_DIR/bin"
# A doctor invoked from a dev checkout or worktree audits the applied machine
# state. Keep module helpers from the running checkout, but resolve all checks
# and repairs against chezmoi's source checkout.
if [ "${DOTFILES_SECURITY_USE_APPLIED_ROOT:-0}" = "1" ]; then
  DOTFILES_DIR="$DOTFILES_LINK_DIR"
fi
if declare -f dotfiles_resolve_find >/dev/null 2>&1; then
  _DOTFILES_FIND="$(dotfiles_resolve_find "$DOTFILES_LINK_BIN")"
else
  _DOTFILES_FIND="$_DOTFILES_FIND"
  for _fc in /opt/homebrew/bin/gfind /usr/local/bin/gfind; do [ -x "$_fc" ] && _DOTFILES_FIND="$_fc" && break; done
fi

# ── SSH Key Permissions ──────────────────────────────────────────

if [ -d "$HOME/.ssh" ]; then
  check "security.ssh_dir_perms" ".ssh directory permissions" \
    "[ \"\$(stat -f '%Lp' \"\$HOME/.ssh\" 2>/dev/null || stat -c '%a' \"\$HOME/.ssh\" 2>/dev/null)\" = '700' ]" \
    "chmod 700 \"\$HOME/.ssh\""

  # Private key permissions (should be 600)
  if command -v fd >/dev/null 2>&1; then
    while IFS= read -r key_file; do
      [ ! -f "$key_file" ] && continue
      case "$key_file" in
        *.pub|*/known_hosts*|*/authorized_keys|*/config) continue ;;
      esac
      if head -1 "$key_file" 2>/dev/null | grep -q "BEGIN"; then
        key_name="$(basename "$key_file")"
        check "security.ssh_key.$key_name" "$key_name permissions" \
          "[ \"\$(stat -f '%Lp' '$key_file' 2>/dev/null)\" = '600' ]" \
          "chmod 600 '$key_file'"
      fi
    done < <(fd -t f -d 1 . "$HOME/.ssh" 2>/dev/null)
  else
    check_advisory "security.fd_available" "fd available for SSH key scan" \
      "command -v fd >/dev/null 2>&1" \
      "brew install fd"
  fi

  # SSH config permissions
  if [ -f "$HOME/.ssh/config" ]; then
    check_advisory "security.ssh_config_perms" ".ssh/config permissions" \
      "perms=\$(stat -f '%Lp' \"\$HOME/.ssh/config\" 2>/dev/null); [ \"\$perms\" = '644' ] || [ \"\$perms\" = '600' ]" \
      "chmod 600 ~/.ssh/config"
  fi

  # SSH agent forwarding safety
  if [ -f "$HOME/.ssh/config" ]; then
    check_advisory "security.ssh_agent_forwarding" "SSH agent forwarding not global" \
      "! grep -qi 'ForwardAgent yes' \"\$HOME/.ssh/config\" 2>/dev/null || ! awk '/^Host \\*/{found=1} found && /ForwardAgent yes/{print; exit}' \"\$HOME/.ssh/config\" | grep -q 'ForwardAgent'" \
      "move ForwardAgent yes from Host * to explicit hosts, or set ForwardAgent no globally"
  fi
else
  check_advisory "security.ssh_dir_exists" ".ssh directory exists" "[ -d \"\$HOME/.ssh\" ]" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
fi

# ── Secrets in Tracked Files ─────────────────────────────────────

secrets_found=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  check "security.secret_in_file.${rel//\//_}" "No secrets in $rel" "false"
  secrets_found=$((secrets_found + 1))
done < <(dotfiles_scan_tracked_secrets "$DOTFILES_DIR")

if [ "$secrets_found" -eq 0 ]; then
  check "security.no_secrets" "No secrets detected in tracked files" "true"
fi

# Check .env files that shouldn't be tracked
env_tracked=0
while IFS= read -r line; do
  case "$line" in
    *.env|*.env.*)
      check "security.tracked_env.${line//\//_}" "Not tracked: $line" "false"
      env_tracked=$((env_tracked + 1))
      ;;
  esac
done < <(git -C "$DOTFILES_DIR" ls-files 2>/dev/null)

if [ "$env_tracked" -eq 0 ]; then
  check "security.no_env_tracked" "No .env files tracked in git" "true"
fi

# ── Sensitive File Permissions ───────────────────────────────────

sensitive_files=(
  "$HOME/.netrc"
  "$HOME/.npmrc"
  "$HOME/.pypirc"
  "$HOME/.docker/config.json"
  "$HOME/.aws/credentials"
  "$HOME/.gnupg"
  "$HOME/.config/gh/hosts.yml"
)

for sf in "${sensitive_files[@]}"; do
  if [ -e "$sf" ]; then
    sf_name="$(basename "$sf")"
    case "$sf" in
      "$HOME"/*) sf_display='~'"/${sf#"$HOME"/}" ;;
      *) sf_display="$sf" ;;
    esac
    sf_chmod="600"
    [ -d "$sf" ] && sf_chmod="700"
    check_advisory "security.sensitive_perms.$sf_name" "$sf_name not world-readable" \
      "perms=\$(stat -f '%Lp' '$sf' 2>/dev/null || stat -c '%a' '$sf' 2>/dev/null); [ \"\${perms: -1}\" = '0' ]" \
      "chmod $sf_chmod $sf_display"
  fi
done

# ── Git Configuration Safety ────────────────────────────────────

check_advisory "security.git_credential" "Git credential helper not plaintext store" \
  "! git config --global credential.helper 2>/dev/null | grep -q 'store'" \
  "git config --global --unset credential.helper, then use osxkeychain or an OS keychain helper"

check_advisory "security.git_gpgsign" "Git commits GPG signed" \
  "git config --global commit.gpgsign 2>/dev/null | grep -q 'true'" \
  "git config --global commit.gpgsign true; skip only if your team does not require signed commits or keys are unavailable"

# ── endpoint agent: nohup invocations in shell init ──────────────
# Endpoint security treats /usr/bin/nohup as a blocked binary and pops
# the policy warning dialog every time a
# shell init file invokes it. Common offenders: zsh/bash init scripts
# that start an LLM server (mlx_lm, ollama, lm-studio) via
# `nohup <cmd> &`. The fix is `disown -h "$!"` — same nohup-immunity
# semantic (the shell won't send SIGHUP to that job on exit), no blocked
# binary. See dotfiles/home/zshrc.ai-tools history for the 2026-05-12
# regression-and-fix trail; the canonical doc lives in
# agentbrew/skill-plugins/local-llm-warmup/SKILL.md.
#
# The check scans the operator's actively-sourced zsh/bash init files
# for non-comment `nohup` invocations and surfaces them as RED.

_init_files_to_check=(
  "$HOME/.zshrc"
  "$HOME/.zshrc.ai-tools"
  "$HOME/.zshrc.local"
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.profile"
  "$HOME/.zshenv"
)

for init in "${_init_files_to_check[@]}"; do
  [ -f "$init" ] || continue
  # Strict regex: nohup must be the first word on the line (after optional
  # whitespace). This intentionally misses pipeline-tail invocations like
  # `cmd && nohup other &` — acceptable because such constructs are rare in
  # shell init files and false-positives on string literals like
  # `echo "the nohup command"` are worse than missing one edge-case.
  init_name="$(basename "$init")"
  check_advisory "security.no_nohup.$init_name" "$init_name does not invoke nohup (endpoint agent blocks it)" \
    "! grep -nE '^[[:space:]]*nohup[[:space:]]+' '$init' >/dev/null 2>&1" \
    "replace 'nohup <cmd> &' with '<cmd> &' followed by 'disown -h \"\$!\"' — see dotfiles/home/zshrc.ai-tools for the canonical pattern"
done

# ── endpoint agent: Homebrew bottles must be ad-hoc signed ──────
# Homebrew ships pre-built bottles UNSIGNED ("code object is not signed
# at all"). endpoint agent reads that as "unsigned" and fires the policy
# dialog on every spawn of jq, fd, atuin, chezmoi, ripgrep, etc. The
# bin/dotfiles-adhoc-sign-bottles script ad-hoc signs each, invoked from
# run_onchange_brew.sh.tmpl after `brew bundle`. This check detects
# drift (e.g. after a new brew install bypasses the chezmoi flow).
# See AGENTS.md rule #10 § "Homebrew bottles are unsigned".

if command -v brew >/dev/null 2>&1; then
  if declare -f dotfiles_brew_bottle_audit >/dev/null 2>&1; then
    dotfiles_brew_bottle_audit
    unsigned_brew="$DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED"
    total_brew="$DOTFILES_BREW_BOTTLE_AUDIT_TOTAL"
    unverified_brew="$DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED"
    cache_note=""
    [ "${DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT:-0}" = "1" ] && cache_note=", cached"

    if [ "$total_brew" -gt 0 ]; then
      check_advisory "security.brew_bottles_signed" \
        "Homebrew bottles ad-hoc signed ($unsigned_brew unsigned, $unverified_brew unverified of $total_brew$cache_note)" \
        "[ $unsigned_brew -eq 0 ] && [ $unverified_brew -eq 0 ]" \
        "$DOTFILES_DIR/bin/dotfiles-adhoc-sign-bottles  # idempotent; com.dotfiles.adhoc-sign-bottles runs daily"
    fi
  fi
fi

_adhoc_sign_la="$HOME/Library/LaunchAgents/com.dotfiles.adhoc-sign-bottles.plist"
check "security.adhoc_sign_launchagent" \
  "Daily adhoc-sign LaunchAgent installed (closes brew upgrade unsigned window)" \
  "[ -f '$_adhoc_sign_la' ]" \
  "chezmoi apply  # launchagents/com.dotfiles.adhoc-sign-bottles.plist.tmpl"
unset _adhoc_sign_la

# ── endpoint agent: framework python venvs ────────────────────────
# python.org .pkg installs leave a framework binary at
# /Library/Frameworks/Python.framework/ that endpoint agent flags on
# execution. Venvs created with that python will invoke the framework
# binary every time they run. This check finds venvs under ~/apps
# that resolve to the framework and offers to recreate them.

_framework="/Library/Frameworks/Python.framework"
if [ -d "$_framework" ]; then
  check_advisory "security.no_framework_python" "No python.org framework install (endpoint agent flags it)" \
    "[ ! -d '$_framework' ]" \
    "dotfiles-remove-framework-python (needs admin rights)"

  # Scan for venvs under ~/apps that resolve to the framework python
  if command -v fd >/dev/null 2>&1; then
    while IFS= read -r cfg; do
      [ -f "$cfg" ] || continue
      if grep -q "Library/Frameworks/Python" "$cfg" 2>/dev/null; then
        venv_dir="$(dirname "$cfg")"
        venv_name="${venv_dir#"$HOME"/}"
        check "security.framework_venv.${venv_name//\//_}" "$venv_name not using framework python" \
          "false" \
          "rm -rf '$venv_dir' && \"\$(uv python find 3.13 2>/dev/null || command -v python3)\" -m venv '$venv_dir' && '$venv_dir/bin/pip' install -r '$(dirname "$venv_dir")/requirements.txt' 2>/dev/null"
      fi
    done < <(fd -t f "pyvenv.cfg" "$HOME/apps" --max-depth 5 2>/dev/null)
  fi

  # Scan pipx venvs — mcpm and other tools launched by MCP servers
  if [ -d "$HOME/.local/pipx/venvs" ]; then
    while IFS= read -r cfg; do
      [ -f "$cfg" ] || continue
      if grep -q "Python.framework" "$cfg" 2>/dev/null; then
        venv_dir="$(dirname "$cfg")"
        pkg_name="$(basename "$venv_dir")"
        check "security.pipx_framework_venv.$pkg_name" "pipx $pkg_name not using Python.framework path" \
          "false" \
          "pipx uninstall $pkg_name && pipx install --python \$(uv python find 3.13) $pkg_name"
      fi
    done < <(fd -t f "pyvenv.cfg" "$HOME/.local/pipx/venvs" --max-depth 3 2>/dev/null)
  fi
fi

# ── pipx venv architecture drift (arm64 host, x86_64 venv) ──────
# On Apple Silicon, a pipx venv built with an x86_64 (Rosetta) python not
# only runs emulated — because pipx injects the NATIVE arm64 shared-pip venv
# into a cross-arch tool venv, `pipx upgrade-all` breaks with "No module named
# pip". That is exactly what failed a past `dotfiles upgrade` pipx step when
# all four venvs were x86_64. New installs go native
# (UV_PYTHON_PREFERENCE=only-managed + the aarch64 default python), so this is
# the regression net for leftovers / drift. Fix: rebuild on native python.
# Uses a glob (not fd) so it's independent of the framework block above and
# trivially testable. Matches uv-managed pythons' `...-macos-x86_64-none` path.
if [ "$(uname -m)" = "arm64" ] && [ -d "$HOME/.local/pipx/venvs" ]; then
  for cfg in "$HOME"/.local/pipx/venvs/*/pyvenv.cfg; do
    [ -f "$cfg" ] || continue
    if grep -q "macos-x86_64" "$cfg" 2>/dev/null; then
      pkg_name="$(basename "$(dirname "$cfg")")"
      check "security.pipx_venv_native_arch.$pkg_name" "pipx $pkg_name uses native arm64 python (not x86_64/Rosetta)" \
        "false" \
        "pipx reinstall $pkg_name --python \"\$(uv python find 3.13)\"  # or reinstall-all"
    fi
  done
fi

# ── Tool shims: curl, jq, grep, perl, find ───────────────────────
# Ensure dotfiles bin/ shims are present so scripts and doctor checks avoid
# /usr/bin/{curl,grep,jq} that endpoint agents flag on this fleet.
check "security.curl_shim" "curl shim in dotfiles/bin (symlink to adhoc-signed Homebrew curl)" \
  "[ -L '$DOTFILES_DIR/bin/curl' ] && [ -x '$DOTFILES_DIR/bin/curl' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-curl-shim'"

check "security.curl_shim_not_script" "curl shim is symlink not bash script (prevents unsigned)" \
  "[ -L '$DOTFILES_DIR/bin/curl' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-curl-shim'"

if [ -L "$DOTFILES_DIR/bin/curl" ] && command -v codesign >/dev/null 2>&1; then
  _curl_real="$(readlink "$DOTFILES_DIR/bin/curl" 2>/dev/null || true)"
  if [ -n "$_curl_real" ] && [ "${_curl_real#/}" = "$_curl_real" ]; then
    _curl_real="$DOTFILES_DIR/bin/$_curl_real"
  fi
  if [ -n "$_curl_real" ] && [ -x "$_curl_real" ]; then
    check "security.curl_shim_target_signed" "curl symlink target is adhoc-signed Mach-O" \
      "codesign -dvv \"\$_curl_real\" 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-curl  # or dotfiles-adhoc-sign-bottles; then dotfiles-link-curl-shim"
  fi
  unset _curl_real
fi

check "security.curl_not_bare_homebrew" "curl resolves via dotfiles/bin not bare Homebrew keg when PATH is correct" \
  "! command -v curl >/dev/null 2>&1 || [ \"\$(command -v curl)\" = '$DOTFILES_DIR/bin/curl' ]" \
  "chezmoi apply  # dotfiles-link-curl-shim; ensure dotfiles/bin precedes /opt/homebrew/opt/curl/bin in PATH"

check "security.curl_not_system" "curl does not resolve to /usr/bin/curl (endpoint agents may block system curl)" \
  "! command -v curl >/dev/null 2>&1 || [ \"\$(command -v curl)\" != '/usr/bin/curl' ]" \
  "chezmoi apply  # dotfiles-link-curl-shim + ~/.config/dotfiles/env.sh PATH"

check "security.network_watchdog_no_curl" "Recurring network watchdog uses signed Apple nc, not unsigned curl" \
  "! grep -vE '^[[:space:]]*#' '$DOTFILES_DIR/bin/network-watchdog' | grep -qE '(^|[[:space:]])curl([[:space:]]|$)'" \
  "upgrade dotfiles and chezmoi apply  # network-watchdog must use /usr/bin/nc"

check "security.local_ai_warmup_no_curl" "Recurring local-AI warmup uses publisher-signed clients, not unsigned curl" \
  "! grep -vE '^[[:space:]]*#' '$DOTFILES_DIR/bin/local-ai-warmup' | grep -qE '(^|[[:space:]])curl([[:space:]]|$)'" \
  "upgrade dotfiles and reload com.dotfiles.local-ai-warmup  # use /usr/bin/nc HTTP helper"

check "security.local_ai_no_model_spawn" "Recurring local-AI health check never spawns blocked model publishers" \
  "! grep -vE '^[[:space:]]*#' '$DOTFILES_DIR/bin/local-ai-warmup' | grep -qE 'api/generate|chat/completions|ollama (run|serve)|lms (load|server start)'" \
  "upgrade dotfiles and reload com.dotfiles.local-ai-warmup  # health checks must remain GET-only"

check "security.ollama_no_duplicate_supervisor" "Ollama LaunchAgent avoids duplicate serve retry loops" \
  "grep -q 'bin/ollama-launchagent' '$DOTFILES_DIR/launchagents/com.dotfiles.ollama.plist.tmpl' && ! grep -q '<string>serve</string>' '$DOTFILES_DIR/launchagents/com.dotfiles.ollama.plist.tmpl' && grep -A4 '<key>KeepAlive</key>' '$DOTFILES_DIR/launchagents/com.dotfiles.ollama.plist.tmpl' | grep -q '<key>SuccessfulExit</key>'" \
  "upgrade dotfiles and reload com.dotfiles.ollama  # probe :11434 before starting one server"

check "security.jq_shim" "jq shim in dotfiles/bin (symlink to adhoc-signed Homebrew jq)" \
  "[ -L '$DOTFILES_DIR/bin/jq' ] && [ -x '$DOTFILES_DIR/bin/jq' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-jq-shim'"

check "security.jq_shim_not_script" "jq shim is symlink not bash script (prevents unsigned)" \
  "[ -L '$DOTFILES_DIR/bin/jq' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-jq-shim'"

if [ -L "$DOTFILES_DIR/bin/jq" ] && command -v codesign >/dev/null 2>&1; then
  _jq_real="$(readlink "$DOTFILES_DIR/bin/jq" 2>/dev/null || true)"
  if [ -n "$_jq_real" ] && [ "${_jq_real#/}" = "$_jq_real" ]; then
    _jq_real="$DOTFILES_DIR/bin/$_jq_real"
  fi
  if [ -n "$_jq_real" ] && [ -x "$_jq_real" ]; then
    check_advisory "security.jq_shim_target_signed" "jq symlink target is adhoc-signed Mach-O" \
      "codesign -dvv \"\$_jq_real\" 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # then dotfiles-link-jq-shim"
  fi
  unset _jq_real
fi

check_advisory "security.local_bin_jq_shim" "\$HOME/.local/bin/jq symlink to adhoc-signed Homebrew jq (codeassist hook PATH)" \
  "[ -L \"\$HOME/.local/bin/jq\" ] && [ \"\$(readlink \"\$HOME/.local/bin/jq\" 2>/dev/null)\" != '' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-jq-shim'"

_dotfiles_endpoint_shims_signed() {
  local _shim _path _real _sig
  for _shim in curl jq grep ggrep perl find python3 python3.13; do
    _path="$DOTFILES_DIR/bin/$_shim"
    [ -f "$_path" ] || continue
    [ -x "$_path" ] || continue
    _real="$_path"
    if [ -L "$_path" ]; then
      _real="$(readlink "$_path" 2>/dev/null || true)"
      if [ -n "$_real" ] && [ "${_real#/}" = "$_real" ]; then
        _real="$DOTFILES_DIR/bin/$_real"
      fi
      [ -f "$_real" ] || continue
    fi
    _sig="$(codesign -dvv "$_real" 2>&1 || true)"
    case "$_sig" in
      *"code object is not signed at all"*|*"not signed"*) return 1 ;;
    esac
  done
  return 0
}

if command -v codesign >/dev/null 2>&1; then
  check "security.endpoint_shims_adhoc_signed" "dotfiles endpoint shims ad-hoc signed (prevents unsigned endpoint agent dialogs)" \
    "_dotfiles_endpoint_shims_signed" \
    "'$DOTFILES_DIR/bin/dotfiles-adhoc-sign-endpoint-shims' '$DOTFILES_DIR/bin'"
fi

# endpoint agent blocks Apple's /usr/bin/jq (system-signed, Description: jq).
# The shim must never be bypassed by PATH order in LaunchAgents or non-interactive shells.
check "security.jq_not_system" "jq does not resolve to /usr/bin/jq (endpoint agents may block Apple jq)" \
  "! command -v jq >/dev/null 2>&1 || [ \"\$(command -v jq)\" != '/usr/bin/jq' ]" \
  "chezmoi apply  # dotfiles-link-jq-shim + ~/.config/dotfiles/env.sh PATH"

check "security.jq_not_bare_homebrew" "jq resolves via dotfiles/bin not bare Homebrew when PATH is correct" \
  "! command -v jq >/dev/null 2>&1 || [ \"\$(command -v jq)\" = '$DOTFILES_DIR/bin/jq' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-jq-shim'  # then ensure dotfiles/bin precedes /opt/homebrew/bin in PATH"

if command -v brew >/dev/null 2>&1; then
  check_advisory "security.brew_jq_installed" "Homebrew jq installed (Brewfile / brew bundle)" \
    "brew list --formula 2>/dev/null | grep -qx jq" \
    "brew install jq  # then dotfiles-adhoc-sign-bottles"
  if [ -f /opt/homebrew/bin/ggrep ] && command -v codesign >/dev/null 2>&1; then
    check "security.brew_ggrep_adhoc_signed" "Homebrew ggrep at /opt/homebrew/bin/ggrep is adhoc-signed" \
      "codesign -dvv /opt/homebrew/bin/ggrep 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-ggrep  # or dotfiles-adhoc-sign-bottles after brew upgrade grep"
  fi
  if [ -f /opt/homebrew/bin/perl ] && command -v codesign >/dev/null 2>&1; then
    check "security.brew_perl_adhoc_signed" "Homebrew perl at /opt/homebrew/bin/perl is adhoc-signed" \
      "codesign -dvv /opt/homebrew/bin/perl 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # re-run after every brew upgrade perl"
  fi
  if [ -f /opt/homebrew/opt/curl/bin/curl ] && command -v codesign >/dev/null 2>&1; then
    check "security.brew_curl_adhoc_signed" "Homebrew curl at /opt/homebrew/opt/curl/bin/curl is adhoc-signed" \
      "codesign -dvv /opt/homebrew/opt/curl/bin/curl 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-curl  # or dotfiles-adhoc-sign-bottles after brew upgrade curl"
    _libcurl="$(/bin/realpath /opt/homebrew/opt/curl/lib/libcurl.4.dylib 2>/dev/null || true)"
    if [ -n "$_libcurl" ] && [ -f "$_libcurl" ]; then
      check "security.brew_libcurl_adhoc_signed" "Homebrew libcurl.4.dylib is adhoc-signed (mode-444; bottles +111 miss)" \
        "codesign -dvv '$_libcurl' 2>&1 | grep -q 'Signature=adhoc'" \
        "dotfiles-adhoc-sign-curl  # signs curl keg binary + libcurl*.dylib"
    fi
    unset _libcurl
  fi
fi

# ── Node.js Foundation publisher policy ──────────────────────────
# fnm already keeps Node in user space, but this endpoint policy matches the
# Developer ID TeamIdentifier itself. Path migration and re-signing therefore
# cannot help; unattended spawns must stop until the exception is approved.
_node_path="$(command -v node 2>/dev/null || true)"
_node_signature=""
if [ -n "$_node_path" ] && command -v codesign >/dev/null 2>&1; then
  _node_signature="$(codesign -dvv "$_node_path" 2>&1 || true)"
fi
if grep -q 'TeamIdentifier=HX7739G8FX' <<<"$_node_signature"; then
  check_advisory "security.node_publisher_exception" "Node.js Foundation publisher has a machine-scoped endpoint-policy exception" \
    "[ '${DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER:-0}' = '1' ]" \
    "file the Node.js Foundation (HX7739G8FX) exception; opt in only after approval"
fi

check "security.recurring_automation_no_blocked_node" "Recurring apply and doctor avoid blocked Node.js Foundation execution" \
  "[ -x '$DOTFILES_DIR/bin/dotfiles-disable-blocked-node-automation' ] && grep -q 'endpoint-node-publisher-blocked' '$DOTFILES_DIR/.chezmoiscripts/run_after_agentbrew-sync.sh' && grep -q 'endpoint-node-publisher-blocked' '$DOTFILES_DIR/bin/dotfiles-upgrade' && grep -q 'DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER' '$DOTFILES_DIR/bin/dotfiles-doctor'" \
  "upgrade dotfiles; agentbrew sync, weekly topgrade, and Node-dependent doctors must remain endpoint-policy gated"

_blocked_node_jobs_unloaded() {
  local plist label
  for plist in "$HOME"/Library/LaunchAgents/com.agentbrew.*.plist; do
    [ -f "$plist" ] || continue
    label="$(basename "$plist" .plist)"
    [ "$label" = "com.agentbrew.mcp-memory" ] && continue
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      return 1
    fi
  done
  label="com.dotfiles.dotfiles-upgrade"
  if [ -f "$HOME/Library/LaunchAgents/$label.plist" ]; then
    if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      return 1
    fi
  fi
  return 0
}

if grep -q 'TeamIdentifier=HX7739G8FX' <<<"$_node_signature" \
    && [ "${DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER:-0}" != "1" ]; then
  check "security.blocked_node_jobs_unloaded" "Node-backed recurring LaunchAgents are disabled while publisher is blocked" \
    "_blocked_node_jobs_unloaded" \
    "'$DOTFILES_DIR/bin/dotfiles-disable-blocked-node-automation'"
fi
unset _node_path _node_signature

check "security.ollama_publisher_safe_mode" "Ollama supervisor never starts the blocked publisher without exception opt-in" \
  "grep -q 'DOTFILES_ALLOW_BLOCKED_OLLAMA_PUBLISHER' '$DOTFILES_DIR/bin/ollama-launchagent' && grep -q 'TeamIdentifier=.*BLOCKED_TEAM_ID' '$DOTFILES_DIR/bin/ollama-launchagent'" \
  "upgrade dotfiles; keep Ollama startup publisher-gated until its machine-scoped exception is approved"

# ── Python shims: python3 / python3.13 ───────────────────────────
# uv ships python-build-standalone without publisher authority. Ad-hoc signing
# removes the completely-unsigned state but current endpoint policy can still
# report unsigned. Symlinks avoid an additional script-level code object;
# recurring automation must not execute this Python until an exception exists.
check "security.python3_shim" "python3 shim in dotfiles/bin (symlink to adhoc-signed uv python)" \
  "[ -L '$DOTFILES_DIR/bin/python3' ] && [ -x '$DOTFILES_DIR/bin/python3' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-python-shim'"

check "security.python3_13_shim" "python3.13 shim in dotfiles/bin (symlink to adhoc-signed uv python)" \
  "[ -L '$DOTFILES_DIR/bin/python3.13' ] && [ -x '$DOTFILES_DIR/bin/python3.13' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-python-shim'"

check "security.python3_shim_not_script" "python3 shim is symlink not an additional unsigned script" \
  "[ -L '$DOTFILES_DIR/bin/python3' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-python-shim'"

check "security.python3_13_shim_not_script" "python3.13 shim is symlink not an additional unsigned script" \
  "[ -L '$DOTFILES_DIR/bin/python3.13' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-python-shim'"

if [ -L "$DOTFILES_DIR/bin/python3" ] && command -v codesign >/dev/null 2>&1; then
  _py_real="$(readlink "$DOTFILES_DIR/bin/python3" 2>/dev/null || true)"
  if [ -n "$_py_real" ] && [ "${_py_real#/}" = "$_py_real" ]; then
    _py_real="$DOTFILES_DIR/bin/$_py_real"
  fi
  if [ -n "$_py_real" ] && [ -x "$_py_real" ]; then
    check_advisory "security.python3_shim_target_signed" "python3 symlink target is ad-hoc signed (still lacks publisher authority)" \
      "codesign -dvv \"\$_py_real\" 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-uv-pythons  # then dotfiles-link-python-shim"
    check_advisory "security.python3_publisher_authority" "python3 has publisher authority required by endpoint policy" \
      "codesign -dvv \"\$_py_real\" 2>&1 | grep -q '^Authority='" \
      "file the machine-scoped endpoint-policy exception for uv python-build-standalone; keep recurring automation in safe mode"
  fi
  unset _py_real
fi

check "security.recurring_automation_no_publisher_na_python" "Recurring apply and doctor avoid unsigned Python execution" \
  "grep -q 'AGENTBREW_MCPM_BIN=/nonexistent/' '$DOTFILES_DIR/.chezmoiscripts/run_after_agentbrew-sync.sh' && grep -q 'endpoint-policy safe mode' '$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-parity.sh' && ! grep -vE '^[[:space:]]*#' '$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh' | grep -qE '(^|[[:space:]])python3([[:space:]]|$)' && grep -q 'endpoint-policy safe mode' '$DOTFILES_DIR/.chezmoiscripts/run_after_install_local_llm.sh.tmpl' && grep -q 'DOTFILES_ALLOW_PUBLISHER_NA_PYTHON' '$DOTFILES_DIR/.chezmoiscripts/run_after_uv-tools.sh' && grep -q 'local-llm' '$DOTFILES_DIR/bin/dotfiles-doctor' && grep -q 'DOTFILES_ALLOW_PUBLISHER_NA_PYTHON' '$DOTFILES_DIR/bin/dotfiles-doctor'" \
  "upgrade dotfiles; recurring JSON edits must use /usr/bin/plutil and Python-dependent doctors must stay gated"

check "security.agent_hooks_no_publisher_na_python" "High-frequency agent hooks parse JSON with Apple plutil, not unsigned Python" \
  "grep -q '/usr/bin/plutil' '$DOTFILES_DIR/agent-hooks/prepend-endpoint-path.sh' && grep -q '/usr/bin/plutil' '$DOTFILES_DIR/agent-hooks/block-dangerous-git.sh' && ! grep -vE '^[[:space:]]*#' '$DOTFILES_DIR/agent-hooks/prepend-endpoint-path.sh' '$DOTFILES_DIR/agent-hooks/block-dangerous-git.sh' | grep -qE '(^|[[:space:]])python3([[:space:]]|$)'" \
  "upgrade dotfiles; pre-tool hooks must not execute Python before every agent command"

check "security.python3_not_system" "python3 does not resolve to /usr/bin/python3 (endpoint agent blocks system python)" \
  "! command -v python3 >/dev/null 2>&1 || [ \"\$(command -v python3)\" != '/usr/bin/python3' ]" \
  "chezmoi apply  # refreshes ~/.config/dotfiles/env.sh PATH; ensures uv python symlinks"

check "security.python3_13_not_system" "python3.13 does not resolve to /usr/bin/python3.13" \
  "! command -v python3.13 >/dev/null 2>&1 || [ \"\$(command -v python3.13)\" != '/usr/bin/python3.13' ]" \
  "chezmoi apply  # bin/python3.13 shim + ~/.local/bin symlinks"

# launchctl setenv PATH (com.dotfiles.gui-path) must prepend dotfiles shims before
# /usr/bin — GUI apps and agents that inherit launchctl PATH otherwise resolve
# python3 to Apple's tool-shim-public at /usr/bin/python3 (endpoint agent).
_lc_path="$(launchctl getenv PATH 2>/dev/null || echo "")"
if [ -n "$_lc_path" ]; then
  _lc_df_idx=""
  _lc_canonical_bin=""
  _git_common="$(git -C "$DOTFILES_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$_git_common" ]; then
    if [ "${_git_common#/}" = "$_git_common" ]; then
      _git_common="$(cd "$DOTFILES_DIR/$_git_common" && pwd -P 2>/dev/null || true)"
    fi
    _lc_canonical_bin="$(dirname "$_git_common")/bin"
  fi
  for _lc_df_candidate in "$DOTFILES_LINK_BIN" "$_lc_canonical_bin" "$DOTFILES_DIR/bin"; do
    [ -n "$_lc_df_candidate" ] || continue
    _lc_df_idx="$(echo "$_lc_path" | tr ':' '\n' | grep -n "^${_lc_df_candidate}\$" | head -1 | cut -d: -f1 || echo "")"
    [ -n "$_lc_df_idx" ] && break
  done
  _lc_ub_idx="$(echo "$_lc_path" | tr ':' '\n' | grep -n '^/usr/bin$' | head -1 | cut -d: -f1 || echo "")"
  check "security.launchctl_path_dotfiles_first" "launchctl PATH has dotfiles/bin before /usr/bin" \
    "[ -n \"\$_lc_df_idx\" ] && [ -n \"\$_lc_ub_idx\" ] && [ \"\$_lc_df_idx\" -lt \"\$_lc_ub_idx\" ]" \
    "chezmoi apply  # reloads com.dotfiles.gui-path; or launchctl kickstart gui/\$(id -u)/com.dotfiles.gui-path"
  unset _lc_df_candidate _lc_canonical_bin _git_common
fi

# Simulate LaunchAgent PATH (.chezmoitemplates/launchagent-path) — must not resolve
# endpoint tools to /usr/bin/* or bare Homebrew ggrep when dotfiles/bin is first.
_la_path="$DOTFILES_LINK_BIN"
if [ -d /opt/homebrew ]; then
  _la_path="${_la_path}:/opt/homebrew/opt/curl/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
fi
if [ -d "${HOME}/.local/bin" ]; then
  _la_path="${_la_path}:${HOME}/.local/bin"
fi
_la_path="${_la_path}:/usr/local/opt/curl/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
check "security.curl_launchagent_path" "curl under LaunchAgent PATH is dotfiles/bin/curl" \
  "PATH=\"\$_la_path\" command -v curl >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v curl)\" = '$DOTFILES_LINK_BIN/curl' ]" \
  "chezmoi apply  # dotfiles-link-curl-shim + launchagent-path template"

check "security.curl_launchagent_not_system" "curl under LaunchAgent PATH is not /usr/bin/curl" \
  "PATH=\"\$_la_path\" command -v curl >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v curl)\" != '/usr/bin/curl' ]" \
  "chezmoi apply  # dotfiles-link-curl-shim + launchagent-path template"
check "security.python3_launchagent_path" "python3 under LaunchAgent PATH is not /usr/bin/python3" \
  "PATH=\"\$_la_path\" command -v python3 >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v python3)\" != '/usr/bin/python3' ]" \
  "chezmoi apply  # ensures bin/python3 shim + ~/.local/bin symlinks; run dotfiles-adhoc-sign-uv-pythons"
check "security.python3_13_launchagent_path" "python3.13 under LaunchAgent PATH is dotfiles/bin/python3.13" \
  "PATH=\"\$_la_path\" command -v python3.13 >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v python3.13)\" = '$DOTFILES_LINK_BIN/python3.13' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-python-shim'  # + launchagent-path template; dotfiles-adhoc-sign-uv-pythons"
check "security.jq_launchagent_path" "jq under LaunchAgent PATH is dotfiles/bin/jq" \
  "PATH=\"\$_la_path\" command -v jq >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v jq)\" = '$DOTFILES_LINK_BIN/jq' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-jq-shim'  # + launchagent-path template; dotfiles-fix-launchagent-endpoint-path"

# Recurring endpoint agent trigger: minsky tick-loop historically test-executed /usr/bin/python3
# (Apple tool-shim-public, system-signed). Flag drift in sibling repo.
_minsky_tick="${HOME}/apps/tooling/minsky/distribution/systemd/run-tick-loop.sh"
_minsky_path_lib="${HOME}/apps/tooling/minsky/distribution/systemd/lib-launchd-path.sh"
if [ -f "$_minsky_tick" ]; then
  check_advisory "security.minsky_tick_loop_no_system_python" "minsky tick-loop does not reference /usr/bin/python3" \
    "! grep -vE '^[[:space:]]*#' '$_minsky_tick' | grep -q '/usr/bin/python3'" \
    "upgrade minsky: use ~/.local/share/uv/python in lib-launchd-path.sh; remove /usr/bin/python3 from run-tick-loop.sh"
  check_advisory "security.minsky_tick_loop_sources_launchd_path" "minsky tick-loop sources lib-launchd-path.sh (dotfiles shims before /usr/bin)" \
    "grep -q 'lib-launchd-path.sh' '$_minsky_tick'" \
    "upgrade minsky: run-tick-loop.sh must source lib-launchd-path.sh; then minsky install-daemon / launchctl kickstart com.minsky.tick-loop"
fi
if [ -f "$_minsky_path_lib" ]; then
  check_advisory "security.minsky_launchd_path_dotfiles_bin" "minsky lib-launchd-path.sh prepends dotfiles/bin" \
    "grep -q 'apps/tooling/dotfiles/bin' '$_minsky_path_lib'" \
    "upgrade minsky lib-launchd-path.sh; reload com.minsky.tick-loop and com.minsky.watchdog"
  check "security.minsky_launchd_path_no_uv_test_exec" "minsky lib-launchd-path.sh does not test-execute bare uv python3.13 (post-reboot endpoint agent)" \
    "! grep -qE '\"\\$_uv_py\" -c|\\.local/share/uv/python.*-c' '$_minsky_path_lib'" \
    "upgrade minsky lib-launchd-path.sh (remove uv python -c '' probe); kickstart -k gui/\$(id -u)/com.minsky.tick-loop"
  # Historical failure: uv-only PATH still resolved jq to /usr/bin/jq (endpoint agent popup every ~5–10s).
  _uv_bin=""
  for _uv_candidate in "${HOME}"/.local/share/uv/python/cpython-3.13*/bin; do
    [ -d "$_uv_candidate" ] && _uv_bin="$_uv_candidate" && break
  done
  if [ -n "$_uv_bin" ]; then
    _tick_sim_path="${_uv_bin}:/usr/bin:/bin"
    check_advisory "security.minsky_tick_loop_jq_via_dotfiles" "jq under uv-only launchd PATH is dotfiles/bin/jq when dotfiles/bin is prepended" \
      "PATH=\"$DOTFILES_LINK_BIN:$_tick_sim_path\" command -v jq >/dev/null 2>&1 && [ \"\$(PATH=\"$DOTFILES_LINK_BIN:$_tick_sim_path\" command -v jq)\" = '$DOTFILES_LINK_BIN/jq' ]" \
      "chezmoi apply; kickstart com.minsky.tick-loop after minsky lib-launchd-path.sh upgrade"
  fi
  unset _uv_bin _uv_candidate _tick_sim_path
fi
unset _minsky_tick _minsky_path_lib

if command -v python3.13 >/dev/null 2>&1; then
  check_advisory "security.python3_13_not_framework" "python3.13 path does not contain Python.framework" \
    "! command -v python3.13 | grep -q Python.framework" \
    "chezmoi apply  # symlinks ~/.local/bin/python3.13 → uv-managed; remove framework: dotfiles-remove-framework-python"
fi

# uv-managed pythons must stay ad-hoc signed (endpoint agent drift after
# `uv python install` / `uv python upgrade` re-extracts unsigned binaries).
# Also sign libpython*.dylib / lib-dynload/*.so — unsigned companions fire
# Description: python3.13 / unsigned even when the interpreter is signed.
_uv_python_root="$HOME/.local/share/uv/python"
if [ -d "$_uv_python_root" ]; then
  _uv_unsigned=0
  _uv_total=0
  while IFS= read -r _uv_py; do
    [ -f "$_uv_py" ] || continue
    [ -L "$_uv_py" ] && continue
    case "$(/usr/bin/file -b "$_uv_py" 2>/dev/null || true)" in
      Mach-O*) ;;
      *) continue ;;
    esac
    _uv_total=$((_uv_total + 1))
    _uv_sig="$(codesign -dvv "$_uv_py" 2>&1 | grep -E 'Signature=|not signed' | head -1 || true)"
    case "$_uv_sig" in
      *"not signed"*) _uv_unsigned=$((_uv_unsigned + 1)) ;;
    esac
  done < <("$_DOTFILES_FIND" "$_uv_python_root" -type f \( \
    -name 'python3.*' -o -name 'libpython*.dylib' -o -name '*.dylib' -o -name '*.so' \
  \) 2>/dev/null)
  check "security.uv_python_adhoc_signed" "All uv-managed Python Mach-O at least ad-hoc signed ($_uv_unsigned of $_uv_total unsigned; publisher exception still required)" \
    "[ $_uv_unsigned -eq 0 ]" \
    "'$DOTFILES_DIR/bin/dotfiles-adhoc-sign-uv-pythons'  # com.dotfiles.endpoint-bootstrap runs at login"
fi

_adhoc_sign_uv_la="$HOME/Library/LaunchAgents/com.dotfiles.endpoint-bootstrap.plist"
check "security.endpoint_bootstrap_la" "Login endpoint-bootstrap LaunchAgent installed (jq + uv sign before minsky RunAtLoad)" \
  "[ -f '$_adhoc_sign_uv_la' ]" \
  "chezmoi apply  # launchagents/com.dotfiles.endpoint-bootstrap.plist.tmpl"
check_advisory "security.endpoint_bootstrap_sentinel" "endpoint-bootstrap ready sentinel present after login" \
  "[ -f \"\$HOME/.local/state/dotfiles/endpoint-ready\" ]" \
  "launchctl kickstart -k gui/\$(id -u)/com.dotfiles.endpoint-bootstrap  # or: dotfiles-adhoc-sign-jq && dotfiles-link-jq-shim"
check_advisory "security.endpoint_bootstrap_before_minsky" "endpoint-bootstrap label sorts before com.minsky.* (launchd RunAtLoad hint)" \
  "printf '%s\\n' 'com.dotfiles.endpoint-bootstrap' 'com.minsky.tick-loop' | LC_ALL=C sort | head -1 | grep -qx 'com.dotfiles.endpoint-bootstrap'" \
  "chezmoi apply  # com.dotfiles.endpoint-bootstrap replaces com.dotfiles.adhoc-sign-uv-pythons"

# LaunchAgent plists with explicit PATH must prepend dotfiles shims (see .chezmoitemplates/launchagent-path).
if [ -d "$DOTFILES_DIR/launchagents" ]; then
  _la_path_bad=0
  while IFS= read -r _la_plist; do
    [ -f "$_la_plist" ] || continue
    grep -q '<key>PATH</key>' "$_la_plist" || continue
    if grep -A1 '<key>PATH</key>' "$_la_plist" | grep -q 'launchagent-path'; then
      continue
    fi
    if grep -A1 '<key>PATH</key>' "$_la_plist" | grep -q '{{ .dotfiles_dir }}/bin'; then
      continue
    fi
    _la_path_bad=1
  done < <(find "$DOTFILES_DIR/launchagents" -maxdepth 1 \( -name '*.plist.tmpl' -o -name '*.plist' \) 2>/dev/null)
  check "security.launchagent_path_shims" "LaunchAgent PATH keys use launchagent-path template or dotfiles bin" \
    "[ $_la_path_bad -eq 0 ]" \
    "Use {{ template \"launchagent-path\" . }} in launchagents/*.plist.tmpl — see .chezmoitemplates/launchagent-path"
fi

check "security.grep_shim" "grep shim in dotfiles/bin (symlink to adhoc-signed Homebrew ggrep)" \
  "[ -L '$DOTFILES_DIR/bin/grep' ] && [ -x '$DOTFILES_DIR/bin/grep' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-grep-shim'"

check "security.ggrep_shim" "ggrep shim in dotfiles/bin (symlink to adhoc-signed Homebrew ggrep)" \
  "[ -L '$DOTFILES_DIR/bin/ggrep' ] && [ -x '$DOTFILES_DIR/bin/ggrep' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-grep-shim'"

check "security.grep_shim_not_script" "grep shim is symlink not bash script (prevents unsigned)" \
  "[ -L '$DOTFILES_DIR/bin/grep' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-grep-shim'"

check "security.ggrep_shim_not_script" "ggrep shim is symlink not bash script (prevents unsigned)" \
  "[ -L '$DOTFILES_DIR/bin/ggrep' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-grep-shim'"

if [ -L "$DOTFILES_DIR/bin/ggrep" ] && command -v codesign >/dev/null 2>&1; then
  _grep_real="$(readlink "$DOTFILES_DIR/bin/ggrep" 2>/dev/null || true)"
  if [ -n "$_grep_real" ] && [ "${_grep_real#/}" = "$_grep_real" ]; then
    _grep_real="$DOTFILES_DIR/bin/$_grep_real"
  fi
  if [ -n "$_grep_real" ] && [ -x "$_grep_real" ]; then
    check_advisory "security.ggrep_shim_target_signed" "ggrep symlink target is adhoc-signed Mach-O" \
      "codesign -dvv \"\$_grep_real\" 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # then dotfiles-link-grep-shim"
  fi
  unset _grep_real
fi

check "security.grep_not_system" "grep does not resolve to /usr/bin/grep (endpoint agent blocks system grep)" \
  "! command -v grep >/dev/null 2>&1 || [ \"\$(command -v grep)\" != '/usr/bin/grep' ]" \
  "chezmoi apply  # dotfiles-link-grep-shim + ~/.config/dotfiles/env.sh PATH"

check "security.ggrep_not_bare_homebrew" "ggrep resolves via dotfiles/bin not bare Homebrew when PATH is correct" \
  "! command -v ggrep >/dev/null 2>&1 || [ \"\$(command -v ggrep)\" = '$DOTFILES_DIR/bin/ggrep' ]" \
  "chezmoi apply  # dotfiles-link-grep-shim; ensure dotfiles/bin precedes /opt/homebrew/bin in PATH"

check "security.ggrep_launchagent_path" "ggrep under LaunchAgent PATH is dotfiles/bin/ggrep" \
  "PATH=\"\$_la_path\" command -v ggrep >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v ggrep)\" = '$DOTFILES_DIR/bin/ggrep' ]" \
  "chezmoi apply  # dotfiles-link-grep-shim + launchagent-path template"

check "security.grep_launchagent_path" "grep under LaunchAgent PATH is not /usr/bin/grep" \
  "PATH=\"\$_la_path\" command -v grep >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v grep)\" != '/usr/bin/grep' ]" \
  "chezmoi apply  # dotfiles-link-grep-shim + launchagent-path template"

check "security.sed_shim" "sed shim in dotfiles/bin (symlink to adhoc-signed Homebrew gsed)" \
  "[ -L '$DOTFILES_DIR/bin/sed' ] && [ -x '$DOTFILES_DIR/bin/sed' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-sed-shim'"

check "security.sed_shim_not_script" "sed shim is symlink not bash script" \
  "[ -L '$DOTFILES_DIR/bin/sed' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-sed-shim'"

check "security.sed_not_system" "sed does not resolve to /usr/bin/sed (endpoint agent blocks system sed)" \
  "! command -v sed >/dev/null 2>&1 || [ \"\$(command -v sed)\" != '/usr/bin/sed' ]" \
  "chezmoi apply  # dotfiles-link-sed-shim + ~/.config/dotfiles/env.sh PATH"

check "security.sed_launchagent_path" "sed under LaunchAgent PATH is not /usr/bin/sed" \
  "PATH=\"\$_la_path\" command -v sed >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v sed)\" != '/usr/bin/sed' ]" \
  "chezmoi apply  # dotfiles-link-sed-shim + launchagent-path template"

check "security.awk_shim" "awk shim in dotfiles/bin (symlink to adhoc-signed Homebrew gawk)" \
  "[ -L '$DOTFILES_DIR/bin/awk' ] && [ -x '$DOTFILES_DIR/bin/awk' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-awk-shim'"

check "security.awk_shim_not_script" "awk shim is symlink not bash script" \
  "[ -L '$DOTFILES_DIR/bin/awk' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-awk-shim'"

check "security.awk_not_system" "awk does not resolve to /usr/bin/awk (endpoint agent blocks system awk)" \
  "! command -v awk >/dev/null 2>&1 || [ \"\$(command -v awk)\" != '/usr/bin/awk' ]" \
  "chezmoi apply  # dotfiles-link-awk-shim + ~/.config/dotfiles/env.sh PATH"

check "security.awk_launchagent_path" "awk under LaunchAgent PATH is not /usr/bin/awk" \
  "PATH=\"\$_la_path\" command -v awk >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v awk)\" != '/usr/bin/awk' ]" \
  "chezmoi apply  # dotfiles-link-awk-shim + launchagent-path template"

check "security.git_wrapper_present" "git push-guard wrapper exists in dotfiles/bin" \
  "[ -f '$DOTFILES_DIR/bin/git' ] && [ -x '$DOTFILES_DIR/bin/git' ] && [ ! -L '$DOTFILES_DIR/bin/git' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-git-shim'"

check "security.git_launchagent_not_system" "git under LaunchAgent PATH is not /usr/bin/git" \
  "PATH=\"\$_la_path\" command -v git >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v git)\" != '/usr/bin/git' ]" \
  "chezmoi apply  # launchagent-path template prepends dotfiles/bin"

# Deployed LaunchAgents (agentbrew, minsky, dotfiles, watchman, …) with stale PATH
# omit dotfiles/bin and resolve jq/ggrep/python3 to /usr/bin/* or bare Homebrew.
_la_endpoint_deploy_bad=0
# Deployed plists point at the applied checkout, even when this doctor runs
# from a development checkout.
_la_link_bin="$DOTFILES_LINK_BIN"
while IFS= read -r _la_deployed; do
  [ -f "$_la_deployed" ] || continue
  _deploy_path="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$_la_deployed" 2>/dev/null || true)"
  [ -n "$_deploy_path" ] || continue
  _la_endpoint_deploy_label="$(basename "$_la_deployed" .plist)"
  # The memory daemon invokes its pinned uvx executable by absolute path. Its
  # intentionally isolated PATH must not inherit dotfiles shims or Node; its
  # maintenance sibling remains covered because it runs AgentBrew through Node.
  [ "$_la_endpoint_deploy_label" = "com.agentbrew.mcp-memory" ] && continue
  _deploy_jq="$(PATH="$_deploy_path" command -v jq 2>/dev/null || true)"
  if [ -n "$_deploy_jq" ] && [ "$_deploy_jq" != "$_la_link_bin/jq" ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_jq.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH resolves jq via dotfiles/bin (not /usr/bin/jq)" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_ggrep="$(PATH="$_deploy_path" command -v ggrep 2>/dev/null || true)"
  if [ -n "$_deploy_ggrep" ] && [ "$_deploy_ggrep" != "$_la_link_bin/ggrep" ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_ggrep.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH resolves ggrep via dotfiles/bin (not bare Homebrew)" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_curl="$(PATH="$_deploy_path" command -v curl 2>/dev/null || true)"
  if [ -n "$_deploy_curl" ] && [ "$_deploy_curl" != "$_la_link_bin/curl" ]; then
    _la_endpoint_deploy_bad=1
    if [ "$_deploy_curl" = '/usr/bin/curl' ]; then
      check "security.deployed_la_curl.${_la_endpoint_deploy_label}" \
        "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve curl to /usr/bin/curl" \
        "false" \
        "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
    else
      check "security.deployed_la_curl.${_la_endpoint_deploy_label}" \
        "LaunchAgent $_la_endpoint_deploy_label PATH resolves curl via dotfiles/bin (not bare Homebrew keg)" \
        "false" \
        "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
    fi
  fi
  _deploy_perl="$(PATH="$_deploy_path" command -v perl 2>/dev/null || true)"
  if [ -n "$_deploy_perl" ] && [ "$_deploy_perl" != "$_la_link_bin/perl" ] && [ "$_deploy_perl" != '/usr/bin/perl' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_perl.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH resolves perl via dotfiles/bin (not bare Homebrew)" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  elif [ "$_deploy_perl" = '/usr/bin/perl' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_perl.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve perl to /usr/bin/perl" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_find="$(PATH="$_deploy_path" command -v find 2>/dev/null || true)"
  if [ "$_deploy_find" = '/usr/bin/find' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_find.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve find to /usr/bin/find" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_grep="$(PATH="$_deploy_path" command -v grep 2>/dev/null || true)"
  if [ "$_deploy_grep" = '/usr/bin/grep' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_grep.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve grep to /usr/bin/grep" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_sed="$(PATH="$_deploy_path" command -v sed 2>/dev/null || true)"
  if [ "$_deploy_sed" = '/usr/bin/sed' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_sed.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve sed to /usr/bin/sed" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_awk="$(PATH="$_deploy_path" command -v awk 2>/dev/null || true)"
  if [ "$_deploy_awk" = '/usr/bin/awk' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_awk.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve awk to /usr/bin/awk" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_py="$(PATH="$_deploy_path" command -v python3 2>/dev/null || true)"
  if [ -n "$_deploy_py" ] && [ "$_deploy_py" = '/usr/bin/python3' ]; then
    _la_endpoint_deploy_bad=1
    check "security.deployed_la_python3.${_la_endpoint_deploy_label}" \
      "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve python3 to /usr/bin/python3" \
      "false" \
      "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
  fi
  _deploy_py13="$(PATH="$_deploy_path" command -v python3.13 2>/dev/null || true)"
  if [ -n "$_deploy_py13" ] && [ "$_deploy_py13" != "$_la_link_bin/python3.13" ]; then
    _la_endpoint_deploy_bad=1
    if echo "$_deploy_py13" | grep -q '.local/share/uv/python'; then
      check "security.deployed_la_python3_13.${_la_endpoint_deploy_label}" \
        "LaunchAgent $_la_endpoint_deploy_label PATH must resolve python3.13 via dotfiles/bin (not bare uv path)" \
        "false" \
        "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'  # then dotfiles-link-python-shim"
    elif [ "$_deploy_py13" = '/usr/bin/python3.13' ]; then
      check "security.deployed_la_python3_13.${_la_endpoint_deploy_label}" \
        "LaunchAgent $_la_endpoint_deploy_label PATH must not resolve python3.13 to /usr/bin/python3.13" \
        "false" \
        "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
    fi
  fi
  case "$_deploy_path" in
    *"${HOME}/apps/dotfiles/bin"*)
      if ! echo "$_deploy_path" | grep -q "${_la_link_bin}"; then
        _la_endpoint_deploy_bad=1
        check "security.deployed_la_stale_dotfiles_path.${_la_endpoint_deploy_label}" \
          "LaunchAgent $_la_endpoint_deploy_label PATH has stale ~/apps/dotfiles/bin (missing tooling/dotfiles)" \
          "false" \
          "'$DOTFILES_DIR/bin/dotfiles-fix-launchagent-endpoint-path'"
      fi
      ;;
  esac
done < <("$_DOTFILES_FIND" "$HOME/Library/LaunchAgents" -maxdepth 1 -name '*.plist' 2>/dev/null | sort -u)
if [ "$_la_endpoint_deploy_bad" -eq 0 ]; then
  check "security.deployed_la_jq" "Deployed LaunchAgents resolve jq via dotfiles/bin" "true"
  check "security.deployed_la_ggrep" "Deployed LaunchAgents resolve ggrep via dotfiles/bin" "true"
  check "security.deployed_la_curl" "Deployed LaunchAgents resolve curl via dotfiles/bin (not /usr/bin/curl)" "true"
  check "security.deployed_la_perl" "Deployed LaunchAgents resolve perl via dotfiles/bin (not /usr/bin/perl)" "true"
  check "security.deployed_la_find" "Deployed LaunchAgents resolve find via dotfiles/bin (not /usr/bin/find)" "true"
  check "security.deployed_la_grep" "Deployed LaunchAgents do not resolve grep to /usr/bin/grep" "true"
  check "security.deployed_la_sed" "Deployed LaunchAgents do not resolve sed to /usr/bin/sed" "true"
  check "security.deployed_la_awk" "Deployed LaunchAgents do not resolve awk to /usr/bin/awk" "true"
  check "security.deployed_la_python3" "Deployed LaunchAgents do not resolve python3 to /usr/bin/python3" "true"
  check "security.deployed_la_python3_13" "Deployed LaunchAgents resolve python3.13 via dotfiles/bin (not bare uv)" "true"
fi
unset _la_endpoint_deploy_bad _la_endpoint_deploy_label _la_deployed _deploy_path _deploy_jq _deploy_ggrep _deploy_curl _deploy_perl _deploy_py _deploy_py13

# Cursor / CI sandboxes that run `bash -c` with PATH=/usr/bin:/bin bypass ~/.zshenv.
# zsh -c still loads ~/.zshenv and picks up dotfiles/bin — prefer zsh for agent shells.
check_advisory "security.zsh_minimal_path_endpoint" "zsh -c with minimal PATH resolves jq via dotfiles/bin (~/.zshenv)" \
  "env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" /bin/zsh -c 'command -v jq' 2>/dev/null | grep -q 'dotfiles/bin/jq'" \
  "chezmoi apply  # ~/.config/dotfiles/env.sh sourced from ~/.zshenv"

check_advisory "security.bash_minimal_path_endpoint" "bash -c with PATH=/usr/bin:/bin must not be used for jq/python (hits /usr/bin/*)" \
  "! env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" bash -c 'command -v jq' 2>/dev/null | grep -q '/usr/bin/jq'" \
  "Use zsh for non-login agent subshells; bash -c ignores BASH_ENV on macOS. See docs/troubleshooting.md § endpoint-security"

check_advisory "security.zsh_minimal_path_ggrep" "zsh -c with minimal PATH resolves ggrep via dotfiles/bin (~/.zshenv)" \
  "env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" /bin/zsh -c 'command -v ggrep' 2>/dev/null | grep -q 'dotfiles/bin/ggrep'" \
  "chezmoi apply  # ~/.config/dotfiles/env.sh sourced from ~/.zshenv"

check_advisory "security.bash_minimal_path_ggrep" "bash -c with PATH=/usr/bin:/bin must not resolve ggrep to bare Homebrew" \
  "! env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" bash -c 'command -v ggrep' 2>/dev/null | grep -q '/opt/homebrew/bin/ggrep'" \
  "Use zsh for non-login agent subshells; chezmoi apply installs cursor preToolUse prepend-endpoint-path hook"

check_advisory "security.zsh_minimal_path_perl" "zsh -c with minimal PATH resolves perl via dotfiles/bin (~/.zshenv)" \
  "env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" /bin/zsh -c 'command -v perl' 2>/dev/null | grep -q 'dotfiles/bin/perl'" \
  "chezmoi apply  # ~/.config/dotfiles/env.sh sourced from ~/.zshenv"

check_advisory "security.bash_minimal_path_perl" "bash -c with PATH=/usr/bin:/bin must not resolve perl to /usr/bin/perl (endpoint agents may block Apple perl)" \
  "! env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" bash -c 'command -v perl' 2>/dev/null | grep -q '/usr/bin/perl'" \
  "Use zsh for non-login agent subshells; chezmoi apply installs cursor preToolUse prepend-endpoint-path hook"

check_advisory "security.zsh_minimal_path_curl" "zsh -c with minimal PATH resolves curl via dotfiles/bin (~/.zshenv)" \
  "env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" /bin/zsh -c 'command -v curl' 2>/dev/null | grep -q 'dotfiles/bin/curl'" \
  "chezmoi apply  # ~/.config/dotfiles/env.sh sourced from ~/.zshenv"

check_advisory "security.bash_minimal_path_curl" "bash -c with PATH=/usr/bin:/bin must not resolve curl to /usr/bin/curl (endpoint agents may block system curl)" \
  "! env -i PATH=/usr/bin:/bin HOME=\"\$HOME\" bash -c 'command -v curl' 2>/dev/null | grep -q '/usr/bin/curl'" \
  "Use zsh for non-login agent subshells; chezmoi apply installs cursor preToolUse prepend-endpoint-path hook"

# Cursor agent tool shells often use PATH=/opt/homebrew/bin:/usr/bin:/bin (Homebrew
# sandbox) which omits dotfiles/bin — ggrep/perl hit bare Homebrew binaries
# (unsigned when unsigned); curl is keg-only and falls through to /usr/bin/curl
# on that PATH unless dotfiles/bin is prepended. LaunchAgent PATH was fixed in PR #241;
# this is the remaining invoker for recurring endpoint agent popups.
if [ -d /opt/homebrew/bin ]; then
  _sandbox_hb_path="/opt/homebrew/bin:/usr/bin:/bin"
  _sandbox_ggrep="$(PATH="$_sandbox_hb_path" command -v ggrep 2>/dev/null || true)"
  if [ -n "$_sandbox_ggrep" ] && [ "$_sandbox_ggrep" != "$DOTFILES_DIR/bin/ggrep" ]; then
    check_advisory "security.sandbox_homebrew_only_ggrep" \
      "Homebrew-only sandbox PATH resolves ggrep to bare Homebrew (not dotfiles/bin; Cursor agent subshells)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-adhoc-sign-ggrep; prefer zsh for agent shells"
    if command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_ggrep" ]; then
      check "security.sandbox_ggrep_signed" \
        "bare Homebrew ggrep is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
        "codesign -dvv '$_sandbox_ggrep' 2>&1 | grep -q 'Signature=adhoc'" \
        "dotfiles-adhoc-sign-ggrep  # ggrep must stay signed after every brew upgrade grep"
    fi
  fi
  _sandbox_perl="$(PATH="$_sandbox_hb_path" command -v perl 2>/dev/null || true)"
  if [ -n "$_sandbox_perl" ] && [ "$_sandbox_perl" != "$DOTFILES_DIR/bin/perl" ]; then
    check_advisory "security.sandbox_homebrew_only_perl" \
      "Homebrew-only sandbox PATH resolves perl to bare Homebrew (not dotfiles/bin; Cursor agent subshells)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-adhoc-sign-bottles; prefer zsh for agent shells"
    if command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_perl" ]; then
      check "security.sandbox_perl_signed" \
        "bare Homebrew perl is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
        "codesign -dvv '$_sandbox_perl' 2>&1 | grep -q 'Signature=adhoc'" \
        "dotfiles-adhoc-sign-bottles  # perl must stay signed after every brew upgrade"
    fi
  fi
  _sandbox_jq="$(PATH="$_sandbox_hb_path" command -v jq 2>/dev/null || true)"
  if [ -n "$_sandbox_jq" ] && [ "$_sandbox_jq" != "$DOTFILES_DIR/bin/jq" ]; then
    check_advisory "security.sandbox_homebrew_only_jq" \
      "Homebrew-only sandbox PATH resolves jq to bare Homebrew (not dotfiles/bin; Cursor agent subshells)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-adhoc-sign-bottles; prefer zsh for agent shells"
    if [ "$_sandbox_jq" = '/usr/bin/jq' ]; then
      check_advisory "security.sandbox_homebrew_only_jq_system" \
        "Homebrew-only sandbox PATH hits /usr/bin/jq (system-signed; prepend dotfiles/bin)" \
        "false" \
        "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-jq-shim"
    elif command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_jq" ]; then
      check "security.sandbox_jq_signed" \
        "bare Homebrew jq is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
        "codesign -dvv '$_sandbox_jq' 2>&1 | grep -q 'Signature=adhoc'" \
        "dotfiles-adhoc-sign-bottles  # jq must stay signed after every brew upgrade"
    fi
  fi
  _sandbox_curl="$(PATH="$_sandbox_hb_path" command -v curl 2>/dev/null || true)"
  if [ -n "$_sandbox_curl" ] && [ "$_sandbox_curl" != "$DOTFILES_DIR/bin/curl" ]; then
    check_advisory "security.sandbox_homebrew_only_curl" \
      "Homebrew-only sandbox PATH resolves curl without dotfiles/bin (often /usr/bin/curl; Cursor agent subshells)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-curl-shim; prefer zsh for agent shells"
    if [ "$_sandbox_curl" = '/usr/bin/curl' ]; then
      check_advisory "security.sandbox_homebrew_only_curl_system" \
        "Homebrew-only sandbox PATH hits /usr/bin/curl (endpoint policy; prepend dotfiles/bin)" \
        "false" \
        "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook prepends dotfiles/bin"
    elif command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_curl" ]; then
      check "security.sandbox_curl_signed" \
        "bare Homebrew curl keg is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
        "codesign -dvv '$_sandbox_curl' 2>&1 | grep -q 'Signature=adhoc'" \
        "dotfiles-adhoc-sign-bottles  # curl must stay signed after every brew upgrade curl"
    fi
  fi
  if [ -d /opt/homebrew/opt/curl/bin ]; then
    _sandbox_keg_path="/opt/homebrew/opt/curl/bin:/opt/homebrew/bin:/usr/bin:/bin"
    _sandbox_curl_keg="$(PATH="$_sandbox_keg_path" command -v curl 2>/dev/null || true)"
    if [ -n "$_sandbox_curl_keg" ] && [ "$_sandbox_curl_keg" != "$DOTFILES_DIR/bin/curl" ]; then
      check_advisory "security.sandbox_keg_curl_without_dotfiles" \
        "Keg curl PATH without dotfiles/bin resolves bare /opt/homebrew/opt/curl/bin/curl" \
        "false" \
        "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-curl-shim"
      if command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_curl_keg" ]; then
        check "security.sandbox_curl_signed" \
          "bare Homebrew curl keg is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
          "codesign -dvv '$_sandbox_curl_keg' 2>&1 | grep -q 'Signature=adhoc'" \
          "dotfiles-adhoc-sign-bottles  # curl must stay signed after every brew upgrade curl"
      fi
    fi
    unset _sandbox_keg_path _sandbox_curl_keg
  fi
  _sandbox_find="$(PATH="$_sandbox_hb_path" command -v find 2>/dev/null || true)"
  if [ "$_sandbox_find" = '/usr/bin/find' ]; then
    check "security.sandbox_homebrew_only_find_system" \
      "Homebrew-only sandbox PATH hits /usr/bin/find (system-signed; prepend dotfiles/bin)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-find-shim"
  elif [ -n "$_sandbox_find" ] && [ "$_sandbox_find" != "$DOTFILES_DIR/bin/find" ] && command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_find" ]; then
    check "security.sandbox_find_signed" \
      "bare Homebrew gfind is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
      "codesign -dvv '$_sandbox_find' 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # gfind must stay signed after every brew upgrade"
  fi
  _sandbox_grep_sys="$(PATH="$_sandbox_hb_path" command -v grep 2>/dev/null || true)"
  if [ "$_sandbox_grep_sys" = '/usr/bin/grep' ]; then
    check "security.sandbox_homebrew_only_grep_system" \
      "Homebrew-only sandbox PATH hits /usr/bin/grep (system-signed; prepend dotfiles/bin)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-grep-shim"
  fi
  _sandbox_sed="$(PATH="$_sandbox_hb_path" command -v sed 2>/dev/null || true)"
  if [ "$_sandbox_sed" = '/usr/bin/sed' ]; then
    check "security.sandbox_homebrew_only_sed_system" \
      "Homebrew-only sandbox PATH hits /usr/bin/sed (system-signed; prepend dotfiles/bin)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-sed-shim"
  elif [ -n "$_sandbox_sed" ] && [ "$_sandbox_sed" != "$DOTFILES_DIR/bin/sed" ] && command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_sed" ]; then
    check "security.sandbox_sed_signed" \
      "bare Homebrew gsed is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
      "codesign -dvv '$_sandbox_sed' 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # gsed must stay signed after every brew upgrade"
  fi
  _sandbox_awk="$(PATH="$_sandbox_hb_path" command -v awk 2>/dev/null || true)"
  if [ "$_sandbox_awk" = '/usr/bin/awk' ]; then
    check "security.sandbox_homebrew_only_awk_system" \
      "Homebrew-only sandbox PATH hits /usr/bin/awk (system-signed; prepend dotfiles/bin)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-awk-shim"
  elif [ -n "$_sandbox_awk" ] && [ "$_sandbox_awk" != "$DOTFILES_DIR/bin/awk" ] && command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_awk" ]; then
    check "security.sandbox_awk_signed" \
      "bare Homebrew gawk is adhoc-signed (endpoint-safe when sandbox PATH skips dotfiles/bin)" \
      "codesign -dvv '$_sandbox_awk' 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # gawk must stay signed after every brew upgrade"
  fi
  _sandbox_py="$(PATH="$_sandbox_hb_path" command -v python3 2>/dev/null || true)"
  if [ "$_sandbox_py" = '/usr/bin/python3' ]; then
    check "security.sandbox_homebrew_only_python3_system" \
      "Homebrew-only sandbox PATH hits /usr/bin/python3 (system-signed; prepend dotfiles/bin)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-python-shim"
  elif [ -n "$_sandbox_py" ] && [ "$_sandbox_py" != "$DOTFILES_DIR/bin/python3" ] && echo "$_sandbox_py" | grep -q '.local/share/uv/python' && command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_py" ]; then
    check "security.sandbox_python3_signed" \
      "bare uv python3 on sandbox PATH is ad-hoc signed (not publisher-authorized)" \
      "codesign -dvv '$_sandbox_py' 2>&1 | grep -q 'Signature=adhoc'" \
      "'$DOTFILES_DIR/bin/dotfiles-adhoc-sign-uv-pythons'"
  fi
  _sandbox_py13="$(PATH="$_sandbox_hb_path" command -v python3.13 2>/dev/null || true)"
  if [ -n "$_sandbox_py13" ] && [ "$_sandbox_py13" != "$DOTFILES_DIR/bin/python3.13" ]; then
    if echo "$_sandbox_py13" | grep -q '.local/share/uv/python' && command -v codesign >/dev/null 2>&1 && [ -f "$_sandbox_py13" ]; then
      check "security.sandbox_python3_13_signed" \
        "bare uv python3.13 on sandbox PATH is ad-hoc signed (not publisher-authorized)" \
        "codesign -dvv '$_sandbox_py13' 2>&1 | grep -q 'Signature=adhoc'" \
        "'$DOTFILES_DIR/bin/dotfiles-adhoc-sign-uv-pythons'"
    fi
  fi
  _sandbox_git="$(PATH="$_sandbox_hb_path" command -v git 2>/dev/null || true)"
  if [ "$_sandbox_git" = '/usr/bin/git' ]; then
    check_advisory "security.sandbox_homebrew_only_git_system" \
      "Homebrew-only sandbox PATH hits /usr/bin/git (system-signed; prepend dotfiles/bin for push-guard wrapper)" \
      "false" \
      "chezmoi apply  # cursor preToolUse prepend-endpoint-path hook; dotfiles-link-git-shim adhoc-signs wrapper"
  fi
  unset _sandbox_hb_path _sandbox_ggrep _sandbox_perl _sandbox_jq _sandbox_curl _sandbox_find \
    _sandbox_grep_sys _sandbox_sed _sandbox_awk _sandbox_py _sandbox_py13 _sandbox_git
fi

# fnm node/npm/npx on sandbox PATH when .node-version exists (MCP + npx hooks).
if [ -f "${HOME}/.node-version" ] && [ -d /opt/homebrew/bin ]; then
  _sandbox_node_path="/opt/homebrew/bin:/usr/bin:/bin"
  _fnm_bin="$(dotfiles_resolve_fnm_node_bin "$HOME" 2>/dev/null || true)"
  if [ -n "$_fnm_bin" ]; then
    _sandbox_node="$(PATH="${_fnm_bin}:$_sandbox_node_path" command -v node 2>/dev/null || true)"
    check "security.sandbox_node_resolves" "node resolves via fnm when .node-version present (sandbox + fnm PATH)" \
      "[ -n \"\$_sandbox_node\" ] && [ \"\$_sandbox_node\" != '/usr/bin/node' ]" \
      "chezmoi apply  # bootstrap-endpoint-path.sh prepends fnm; ensure fnm node installed for .node-version"
    _sandbox_npx="$(PATH="${_fnm_bin}:$_sandbox_node_path" command -v npx 2>/dev/null || true)"
    check_advisory "security.sandbox_npx_resolves" "npx resolves via fnm when .node-version present" \
      "[ -n \"\$_sandbox_npx\" ]" \
      "fnm install \$(cat ~/.node-version); chezmoi apply"
  else
    check_advisory "security.sandbox_node_resolves" "fnm node bin missing for .node-version (npx/MCP hooks may fail)" \
      "false" \
      "fnm install \$(sed 's/^v//' ~/.node-version); chezmoi apply"
  fi
  unset _sandbox_node_path _fnm_bin _sandbox_node _sandbox_npx
fi

# Deployed Cursor/agent hook scripts must source endpoint PATH bootstrap.
_hooks_bootstrap_bad=0
for _hooks_scan_dir in \
  "$DOTFILES_DIR/agent-hooks" \
  "${HOME}/.config/dotfiles/hooks"; do
  [ -d "$_hooks_scan_dir" ] || continue
  while IFS= read -r _hook_script; do
    [ -f "$_hook_script" ] || continue
    case "$_hook_script" in
      *bootstrap-endpoint-path.sh|*with-endpoint-path.sh|*prepend-endpoint-path.sh|*session-endpoint-path.sh) continue ;;
    esac
    head -1 "$_hook_script" 2>/dev/null | grep -q '^#!' || continue
    grep -qE 'bootstrap-endpoint-path|with-endpoint-path|prepend-endpoint-path|dotfiles_prepend_endpoint_tool_paths' "$_hook_script" && continue
    grep -qE '\bjq\b|\bggrep\b|\bgrep\b|\bfind\b|\bcurl\b|\bawk\b|\bsed\b|\bpython3\b|\bnpx\b|\bnode\b' "$_hook_script" || continue
    _hooks_bootstrap_bad=1
    _hook_rel="${_hook_script#"$DOTFILES_DIR"/}"
    [ "$_hook_rel" = "$_hook_script" ] && _hook_rel="${_hook_script#"$HOME"/}"
    check "security.hooks_use_bootstrap.${_hook_rel//\//_}" \
      "Hook $_hook_rel invokes endpoint tools without bootstrap-endpoint-path" \
      "false" \
      "Wrap with with-endpoint-path.sh or source bootstrap-endpoint-path.sh"
  done < <("$_DOTFILES_FIND" "$_hooks_scan_dir" -maxdepth 1 -type f \( -name '*.sh' -o -perm -111 \) 2>/dev/null)
done
if [ "$_hooks_bootstrap_bad" -eq 0 ]; then
  check "security.hooks_use_bootstrap" "Agent hook scripts source endpoint PATH bootstrap when invoking shims" "true"
fi
unset _hooks_bootstrap_bad _hooks_scan_dir _hook_script _hook_rel

_bash_env_path="${HOME}/.config/dotfiles/bash-env.sh"
if [ -f "$_bash_env_path" ]; then
  _lc_bash_env="$(launchctl getenv BASH_ENV 2>/dev/null || echo "")"
  check_advisory "security.launchctl_bash_env" "launchctl BASH_ENV points at dotfiles bash-env.sh (non-interactive bash scripts)" \
    "[ \"\$_lc_bash_env\" = \"\$_bash_env_path\" ]" \
    "chezmoi apply  # com.dotfiles.gui-path; or '$DOTFILES_DIR/bin/dotfiles-ensure-gui-path'"
fi
unset _bash_env_path _lc_bash_env

check "security.perl_shim" "perl shim in dotfiles/bin (symlink to adhoc-signed Homebrew perl)" \
  "[ -L '$DOTFILES_DIR/bin/perl' ] && [ -x '$DOTFILES_DIR/bin/perl' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-perl-shim'"

check "security.perl_shim_not_script" "perl shim is symlink not bash script (prevents unsigned)" \
  "[ -L '$DOTFILES_DIR/bin/perl' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-perl-shim'"

if [ -L "$DOTFILES_DIR/bin/perl" ] && command -v codesign >/dev/null 2>&1; then
  _perl_real="$(readlink "$DOTFILES_DIR/bin/perl" 2>/dev/null || true)"
  if [ -n "$_perl_real" ] && [ "${_perl_real#/}" = "$_perl_real" ]; then
    _perl_real="$DOTFILES_DIR/bin/$_perl_real"
  fi
  if [ -n "$_perl_real" ] && [ -x "$_perl_real" ]; then
    check_advisory "security.perl_shim_target_signed" "perl symlink target is adhoc-signed Mach-O" \
      "codesign -dvv \"\$_perl_real\" 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles  # then dotfiles-link-perl-shim"
  fi
  unset _perl_real
fi

check "security.perl_not_bare_homebrew" "perl resolves via dotfiles/bin not bare Homebrew when PATH is correct" \
  "! command -v perl >/dev/null 2>&1 || [ \"\$(command -v perl)\" = '$DOTFILES_DIR/bin/perl' ]" \
  "chezmoi apply  # dotfiles-link-perl-shim; ensure dotfiles/bin precedes /opt/homebrew/bin in PATH"

check "security.perl_not_system" "perl does not resolve to /usr/bin/perl (endpoint agent blocks Apple perl)" \
  "! command -v perl >/dev/null 2>&1 || [ \"\$(command -v perl)\" != '/usr/bin/perl' ]" \
  "chezmoi apply  # dotfiles-link-perl-shim + ~/.config/dotfiles/env.sh PATH"

check "security.perl_launchagent_path" "perl under LaunchAgent PATH is dotfiles/bin/perl" \
  "PATH=\"\$_la_path\" command -v perl >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v perl)\" = '$DOTFILES_DIR/bin/perl' ]" \
  "chezmoi apply  # dotfiles-link-perl-shim + launchagent-path template"

check "security.perl_launchagent_not_system" "perl under LaunchAgent PATH is not /usr/bin/perl" \
  "PATH=\"\$_la_path\" command -v perl >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v perl)\" != '/usr/bin/perl' ]" \
  "chezmoi apply  # dotfiles-link-perl-shim + launchagent-path template"

check "security.find_shim" "find shim in dotfiles/bin (symlink to adhoc-signed Homebrew gfind)" \
  "[ -L '$DOTFILES_DIR/bin/find' ] && [ -x '$DOTFILES_DIR/bin/find' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-find-shim'"

check "security.find_shim_not_script" "find shim is symlink not bash script" \
  "[ -L '$DOTFILES_DIR/bin/find' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-find-shim'"

check "security.find_not_system" "find does not resolve to /usr/bin/find" \
  "! command -v find >/dev/null 2>&1 || [ \"\$(command -v find)\" != '/usr/bin/find' ]" \
  "chezmoi apply  # dotfiles-link-find-shim"

check "security.otool_shim" "otool shim in dotfiles/bin (symlink to Xcode/CLT llvm-otool)" \
  "[ -L '$DOTFILES_DIR/bin/otool' ] && [ -x '$DOTFILES_DIR/bin/otool' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-otool-shim'"

check "security.otool_shim_not_script" "otool shim is symlink not bash script" \
  "[ -L '$DOTFILES_DIR/bin/otool' ]" \
  "'$DOTFILES_DIR/bin/dotfiles-link-otool-shim'"

check "security.otool_not_system" "otool does not resolve to /usr/bin/otool (endpoint agent blocks tool-shim-public)" \
  "! command -v otool >/dev/null 2>&1 || [ \"\$(command -v otool)\" != '/usr/bin/otool' ]" \
  "chezmoi apply  # dotfiles-link-otool-shim + ~/.config/dotfiles/env.sh PATH"

check "security.otool_not_tool_shim_public" "otool shim target is not Apple tool-shim-public" \
  "[ ! -L '$DOTFILES_DIR/bin/otool' ] || ! codesign -dvv '$DOTFILES_DIR/bin/otool' 2>&1 | grep -q 'tool-shim-public'" \
  "'$DOTFILES_DIR/bin/dotfiles-link-otool-shim'"

check "security.otool_launchagent_path" "otool under LaunchAgent PATH is not /usr/bin/otool" \
  "PATH=\"\$_la_path\" command -v otool >/dev/null 2>&1 && [ \"\$(PATH=\"\$_la_path\" command -v otool)\" != '/usr/bin/otool' ]" \
  "chezmoi apply  # dotfiles-link-otool-shim + launchagent-path template"

if command -v brew >/dev/null 2>&1; then
  # On Apple Silicon with a native arm64 shell, brew --prefix must be /opt/homebrew.
  # Intel Homebrew at /usr/local forces Rosetta for every brew-installed tool.
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] && [ "$(uname -m)" = "arm64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != "1" ]; then
    check_advisory "security.homebrew_native_prefix" "Homebrew prefix is /opt/homebrew on native Apple Silicon shell" \
      "[ \"\$(brew --prefix 2>/dev/null)\" = '/opt/homebrew' ]" \
      "Install native arm64 Homebrew (https://brew.sh). See docs/troubleshooting.md#shell-running-under-rosetta"
  fi

  check_advisory "security.brew_grep_installed" "Homebrew grep installed (GNU ggrep for bin/grep shim)" \
    "brew list --formula 2>/dev/null | grep -qx grep" \
    "brew install grep  # then dotfiles-adhoc-sign-bottles"

  check_advisory "security.brew_gnu_sed_installed" "Homebrew gnu-sed installed (GNU gsed for bin/sed shim)" \
    "brew list --formula 2>/dev/null | grep -qx gnu-sed" \
    "brew install gnu-sed  # then dotfiles-adhoc-sign-bottles"

  check_advisory "security.brew_gawk_installed" "Homebrew gawk installed (GNU gawk for bin/awk shim)" \
    "brew list --formula 2>/dev/null | grep -qx gawk" \
    "brew install gawk  # then dotfiles-adhoc-sign-bottles"

  check_advisory "security.brew_findutils_installed" "Homebrew findutils installed (GNU gfind for bin/find shim)" \
    "brew list --formula 2>/dev/null | grep -qx findutils" \
    "brew install findutils"
  if [ -f /opt/homebrew/bin/gfind ] && command -v codesign >/dev/null 2>&1; then
    check "security.brew_gfind_adhoc_signed" "Homebrew gfind is adhoc-signed" \
      "codesign -dvv /opt/homebrew/bin/gfind 2>&1 | grep -q 'Signature=adhoc'" \
      "dotfiles-adhoc-sign-bottles"
  fi

  check_advisory "security.brew_findutils_installed" "Homebrew findutils installed" \
    "brew list --formula 2>/dev/null | grep -qx findutils" \
    "brew install findutils"

  check_advisory "security.brew_perl_installed" "Homebrew perl installed (bin/perl shim)" \
    "brew list --formula 2>/dev/null | grep -qx perl" \
    "brew install perl  # then dotfiles-adhoc-sign-bottles"

  check_advisory "security.brew_curl_installed" "Homebrew curl installed (keg-only patched curl for bin/curl shim)" \
    "brew list --formula 2>/dev/null | grep -qx curl" \
    "brew install curl  # then dotfiles-adhoc-sign-bottles"
fi

# ── No /usr/bin/env shebangs in dotfiles executables ───────────────
# endpoint agent blocks /usr/bin/env (system-signed) when
# high-churn bin/* scripts run. Use #!/bin/bash or re-exec Homebrew bash
# directly — never `#!/usr/bin/env bash`.
_env_shebang_count=0
if [ -d "$DOTFILES_DIR/bin" ]; then
  while IFS= read -r _env_script; do
    [ -n "$_env_script" ] || continue
    _env_rel="${_env_script#"$DOTFILES_DIR"/}"
    check "security.no_env_shebang.${_env_rel//\//_}" "$_env_rel must not use #!/usr/bin/env (endpoint agents may block env)" \
      "false" \
      "sed -i '' '1s|^#!/usr/bin/env bash|#!/bin/bash|' '$_env_script'"
    _env_shebang_count=$((_env_shebang_count + 1))
  done < <(grep -rl '^#!/usr/bin/env' "$DOTFILES_DIR/bin" 2>/dev/null || true)
fi
if [ "$_env_shebang_count" -eq 0 ]; then
  check "security.no_env_shebangs" "No #!/usr/bin/env shebangs in dotfiles/bin" "true"
fi

# Global git hooks (core.hooksPath) run on every commit/push — env shebangs
# here are a top recurring endpoint agent trigger.
_env_hook_count=0
if [ -d "$DOTFILES_DIR/git-hooks" ]; then
  while IFS= read -r _env_hook; do
    [ -n "$_env_hook" ] || continue
    _env_hook_rel="${_env_hook#"$DOTFILES_DIR"/}"
    check "security.no_env_shebang.${_env_hook_rel//\//_}" "$_env_hook_rel must not use #!/usr/bin/env (endpoint agents may block env)" \
      "false" \
      "sed -i '' '1s|^#!/usr/bin/env bash|#!/opt/homebrew/bin/bash|' '$_env_hook'"
    _env_hook_count=$((_env_hook_count + 1))
  done < <(grep -rl '^#!/usr/bin/env' "$DOTFILES_DIR/git-hooks" 2>/dev/null || true)
fi
if [ "$_env_hook_count" -eq 0 ]; then
  check "security.no_env_shebangs_git_hooks" "No #!/usr/bin/env shebangs in dotfiles/git-hooks" "true"
fi

# Minsky bin/ scripts are invoked directly by operators and the tick-loop
# maintenance path; env shebangs pop endpoint agent on every spawn.
_minsky_home="${HOME}/apps/tooling/minsky"
_env_minsky_count=0
if [ -d "$_minsky_home/bin" ]; then
  while IFS= read -r _env_minsky; do
    [ -n "$_env_minsky" ] || continue
    _env_minsky_rel="${_env_minsky#"$_minsky_home"/}"
    check "security.no_env_shebang.minsky_${_env_minsky_rel//\//_}" "minsky/$_env_minsky_rel must not use #!/usr/bin/env (endpoint agents may block env)" \
      "false" \
      "sed -i '' '1s|^#!/usr/bin/env bash|#!/opt/homebrew/bin/bash|' '$_env_minsky'"
    _env_minsky_count=$((_env_minsky_count + 1))
  done < <(grep -rl '^#!/usr/bin/env' "$_minsky_home/bin" 2>/dev/null || true)
fi
if [ "$_env_minsky_count" -eq 0 ]; then
  check "security.no_env_shebangs_minsky_bin" "No #!/usr/bin/env shebangs in minsky/bin" "true"
fi
unset _minsky_home _env_minsky_count _env_minsky _env_minsky_rel _env_hook_count _env_hook _env_hook_rel

# LaunchAgent ProgramArguments must not invoke /usr/bin/env directly — use
# /bin/bash + run-*.sh wrappers (see minsky distribution/systemd/run-watchdog.sh).
_la_env_bad=0
_la_env_plist=""
while IFS= read -r _la_env_plist; do
  [ -f "$_la_env_plist" ] || continue
  if grep -q '<string>/usr/bin/env</string>' "$_la_env_plist"; then
    _la_env_bad=1
    _la_env_rel="${_la_env_plist#"$DOTFILES_DIR"/}"
    [ "$_la_env_rel" = "$_la_env_plist" ] && _la_env_rel="${_la_env_plist#"$HOME"/}"
    check "security.launchagent_no_env.${_la_env_rel//\//_}" "LaunchAgent $_la_env_rel must not use /usr/bin/env in ProgramArguments" \
      "false" \
      "Replace /usr/bin/env with /bin/bash + a run-*.sh wrapper; then launchctl bootstrap gui/\$(id -u) '$_la_env_plist'"
  fi
done < <({
  "$_DOTFILES_FIND" "$DOTFILES_DIR/launchagents" -maxdepth 1 \( -name '*.plist.tmpl' -o -name '*.plist' \) 2>/dev/null
  "$_DOTFILES_FIND" "${HOME}/apps/tooling/minsky/distribution/launchd" -maxdepth 1 -name '*.plist' 2>/dev/null
  "$_DOTFILES_FIND" "$HOME/Library/LaunchAgents" -maxdepth 1 \( -name 'com.dotfiles.*.plist' -o -name 'com.minsky.*.plist' -o -name 'com.agentbrew.*.plist' \) 2>/dev/null
} | sort -u)
if [ "$_la_env_bad" -eq 0 ]; then
  check "security.launchagent_no_env" "No LaunchAgent plists invoke /usr/bin/env" "true"
fi
unset _la_env_bad _la_env_plist _la_env_rel

# ── Hung git-upload-pack / GHE SSH (stuck Cursor extension-host git) ─
# shellcheck source=../../lib/heal-stuck-agents.sh
source "$DOTFILES_MODULE_DIR/lib/heal-stuck-agents.sh"

check "security.git_ssh_hung_upload_pack" \
  "No hung git-upload-pack or GHE SSH sessions (>30 min, excluding mux master)" \
  "[ \"\$(dotfiles_heal_count_hung_git_sessions)\" -eq 0 ]" \
  "'$DOTFILES_DIR/bin/dotfiles-heal-stuck-agents' --fix --quiet"

# ── Plaintext bearer tokens in agent-config backups ──────────────
# A redacted copy does not revoke the token: rotate it at its issuer too.
check "security.agent_config_backup_bearer" \
  "No plaintext bearer tokens in ~/.claude.json backups (after repair, rotate the token at its issuer)" \
  "[ -z \"\$(dotfiles_agent_config_bearer_leaks)\" ]" \
  "dotfiles_redact_agent_config_bearer_leaks"

DOTFILES_DIR="$DOTFILES_MODULE_DIR"
unset DOTFILES_MODULE_DIR
