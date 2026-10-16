#!/usr/bin/env bats
# Functional tests for modules/enterprise/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  # Create mock enterprise tool binaries
  mkdir -p "$TEST_DIR/bin"
  for tool in kubectl gradle java node docker gh jq; do
    echo '#!/bin/bash' > "$TEST_DIR/bin/$tool"
    chmod +x "$TEST_DIR/bin/$tool"
  done
  # aws and gcloud are user-dir installs under ~/.local/bin.
  mkdir -p "$TEST_HOME/.local/bin"
  for tool in aws gcloud; do
    echo '#!/bin/bash' > "$TEST_HOME/.local/bin/$tool"
    chmod +x "$TEST_HOME/.local/bin/$tool"
  done
  ln -s "$TEST_HOME/.local/bin/aws" "$TEST_DIR/bin/aws"
  export PATH="$TEST_HOME/.local/bin:$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "enterprise: passes when all tools installed" {
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [ "$pass_count" -eq 10 ]
  [ "$fail_count" -eq 0 ]
}

@test "enterprise: fails when tools missing" {
  rm -f "$TEST_HOME/.local/bin/aws" "$TEST_DIR/bin/kubectl"
  # Include /bin and /usr/bin for shell builtins but not tool-specific paths
  export PATH="$TEST_DIR/bin:/bin:/usr/bin"
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [ "$fail_count" -ge 2 ]
}

@test "enterprise: overrides skip checks" {
  echo "enterprise.aws" >> "$OVERRIDES_FILE"
  echo "enterprise.kubectl" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [ "$skip_count" -ge 2 ]
}

@test "enterprise: individual tool missing fails only that check" {
  rm -f "$TEST_DIR/bin/gradle"
  export PATH="$TEST_HOME/.local/bin:$TEST_DIR/bin:/bin:/usr/bin"
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [ "$pass_count" -ge 7 ]
  [ "$fail_count" -eq 1 ]
}

@test "enterprise: all tools missing fails all checks" {
  rm -f "$TEST_HOME/.local/bin/aws" "$TEST_DIR/bin/kubectl" "$TEST_DIR/bin/gradle" "$TEST_DIR/bin/java" "$TEST_DIR/bin/node" "$TEST_DIR/bin/docker" "$TEST_DIR/bin/gh" "$TEST_DIR/bin/jq"
  export PATH="$TEST_DIR/bin:/bin:/usr/bin"
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  # At least 6 fail (java and jq may exist at /usr/bin on some systems)
  [ "$fail_count" -ge 6 ]
}

@test "enterprise: LIST_MODE suppresses all checks" {
  LIST_MODE=true
  rm -f "$TEST_DIR/bin/aws"
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "enterprise: aws outside ~/.local/bin fails the user-dir check with the installer fix" {
  rm -f "$TEST_HOME/.local/bin/aws" "$TEST_DIR/bin/aws"
  echo '#!/bin/bash' > "$TEST_DIR/bin/aws"
  chmod +x "$TEST_DIR/bin/aws"
  export PATH="$TEST_HOME/.local/bin:$TEST_DIR/bin:/bin:/usr/bin"
  failed_ids=""
  fixes=""
  check() {
    if eval "$3" >/dev/null 2>&1; then pass "$2"; else fail "$2"; failed_ids="$failed_ids $1"; fixes="$fixes|$4"; fi
  }
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [ "$failed_ids" = " enterprise.aws_user_dir" ]
  [[ "$fixes" == *"dotfiles-install-aws-gcloud --aws"* ]]
}

@test "enterprise: missing aws and gcloud point at the user-dir installer, not brew" {
  rm -f "$TEST_HOME/.local/bin/aws" "$TEST_HOME/.local/bin/gcloud" "$TEST_DIR/bin/aws"
  export PATH="$TEST_HOME/.local/bin:$TEST_DIR/bin:/bin:/usr/bin"
  fixes=""
  check() {
    case "$1" in enterprise.aws|enterprise.aws_user_dir|enterprise.gcloud_user_dir) fixes="$fixes|$1=$4" ;; esac
  }
  source "$BATS_TEST_DIRNAME/../modules/enterprise/doctor.sh"
  [[ "$fixes" == *"enterprise.aws=dotfiles-install-aws-gcloud --aws"* ]]
  [[ "$fixes" == *"enterprise.gcloud_user_dir=dotfiles-install-aws-gcloud --gcloud"* ]]
  [[ "$fixes" != *"awscli"* ]]
}
