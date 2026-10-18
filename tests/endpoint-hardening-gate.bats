#!/usr/bin/env bats
# The endpoint-hardening scripts sign Homebrew bottles and link shims into the
# Homebrew prefix, outside $HOME. They exist for a managed endpoint-security
# agent, so they run only where `managed_endpoint` is true. It defaults to
# owner_machine: the owner's Macs keep signing, a new user's Mac skips it.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
SCRIPTS=(run_after_endpoint-security.sh run_at_login_endpoint-bootstrap.sh run_at_login_sign-uv-python.sh)

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  SRC="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$SRC/bin" "$SRC/.chezmoiscripts"
  CALLS="$TEST_DIR/calls.log"
  : > "$CALLS"
  # Every helper the scripts call logs its name and succeeds.
  for helper in adhoc-sign-jq adhoc-sign-curl adhoc-sign-ggrep adhoc-sign-uv-pythons \
      adhoc-sign-bottles adhoc-sign-endpoint-shims link-jq-shim link-curl-shim \
      link-grep-shim link-python-shim; do
    printf '#!/bin/bash\necho %s >> "%s"\n' "$helper" "$CALLS" > "$SRC/bin/dotfiles-$helper"
    chmod +x "$SRC/bin/dotfiles-$helper"
  done
  for s in "${SCRIPTS[@]}"; do
    cp "$REPO_ROOT/.chezmoiscripts/$s" "$SRC/.chezmoiscripts/$s"
  done
}

teardown() { rm -rf "$TEST_DIR"; }

_init_config() {
  local email="$1"
  mkdir -p "$TEST_DIR/src"
  cp "$REPO_ROOT/.chezmoi.yaml.tmpl" "$TEST_DIR/src/"
  HOME="$TEST_HOME" chezmoi init --source "$TEST_DIR/src" --config-path "$TEST_DIR/cfg.yaml" \
    --promptDefaults \
    --promptString "Git commit name for work/default identity=Alex Example" \
    --promptString "Git commit email for work/default identity=$email" >/dev/null 2>&1
}

@test "new user's config turns endpoint hardening off for chezmoi scripts" {
  _init_config alex@example.com
  grep -q '^  managed_endpoint: false' "$TEST_DIR/cfg.yaml"
  grep -qE '^  DOTFILES_MANAGED_ENDPOINT: "0"' "$TEST_DIR/cfg.yaml"
}

@test "owner's config keeps endpoint hardening on" {
  _init_config fyodor@sent.com
  grep -q '^  managed_endpoint: true' "$TEST_DIR/cfg.yaml"
  grep -qE '^  DOTFILES_MANAGED_ENDPOINT: "1"' "$TEST_DIR/cfg.yaml"
}

@test "managed_endpoint override wins over owner_machine" {
  # A new user on a Mac with an endpoint agent sets the key by hand.
  printf 'data:\n  managed_endpoint: true\n' > "$TEST_DIR/cfg.yaml"
  mkdir -p "$TEST_DIR/src"
  cp "$REPO_ROOT/.chezmoi.yaml.tmpl" "$TEST_DIR/src/"
  HOME="$TEST_HOME" chezmoi init --source "$TEST_DIR/src" --config "$TEST_DIR/cfg.yaml" \
    --config-path "$TEST_DIR/cfg.yaml" --promptDefaults \
    --promptString "Git commit email for work/default identity=alex@example.com" >/dev/null 2>&1
  grep -q '^  owner_machine: false' "$TEST_DIR/cfg.yaml"
  grep -qE '^  DOTFILES_MANAGED_ENDPOINT: "1"' "$TEST_DIR/cfg.yaml"
}

@test "scripts skip all signing and linking when DOTFILES_MANAGED_ENDPOINT=0" {
  for s in "${SCRIPTS[@]}"; do
    run env HOME="$TEST_HOME" DOTFILES_DIR="$SRC" CHEZMOI_SOURCE_DIR="$SRC" DOTFILES_MANAGED_ENDPOINT=0 \
      bash "$SRC/.chezmoiscripts/$s"
    [ "$status" -eq 0 ] || { echo "$s: $output"; return 1; }
    [[ "$output" == *"Skipping endpoint hardening"* ]] || { echo "$s: $output"; return 1; }
  done
  [ ! -s "$CALLS" ] || { cat "$CALLS"; return 1; }
  [ ! -e "$TEST_HOME/.local/state/dotfiles/endpoint-ready" ]
}

@test "owner's apply (DOTFILES_MANAGED_ENDPOINT=1) still signs bottles" {
  run env HOME="$TEST_HOME" DOTFILES_DIR="$SRC" CHEZMOI_SOURCE_DIR="$SRC" DOTFILES_MANAGED_ENDPOINT=1 \
    bash "$SRC/.chezmoiscripts/run_after_endpoint-security.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx adhoc-sign-bottles "$CALLS"
  grep -qx adhoc-sign-uv-pythons "$CALLS"
}

@test "a config without the key (written before the gate) keeps signing" {
  run env -u DOTFILES_MANAGED_ENDPOINT HOME="$TEST_HOME" DOTFILES_DIR="$SRC" CHEZMOI_SOURCE_DIR="$SRC" \
    bash "$SRC/.chezmoiscripts/run_at_login_endpoint-bootstrap.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx adhoc-sign-jq "$CALLS"
  [ -f "$TEST_HOME/.local/state/dotfiles/endpoint-ready" ]
}

@test "the login LaunchAgent is skipped where managed_endpoint is false" {
  local tmpl="$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  grep -q 'MANAGED_ENDPOINT="{{ dig "managed_endpoint" true . }}"' "$tmpl"
  grep -A2 -E '^    endpoint-bootstrap\)' "$tmpl" | grep -q 'MANAGED_ENDPOINT'
}

@test "the install e2e needs no endpoint-hardening skip variable" {
  run grep -n 'DOTFILES_SKIP_ENDPOINT_HARDENING' "$REPO_ROOT"/tests/e2e/*.sh "$REPO_ROOT"/.chezmoiscripts/*
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
}
