#!/usr/bin/env bats
# Tests for bin/dotfiles-install-aws-gcloud: AWS CLI v2 and the Google Cloud
# SDK as user-dir installs. curl, pkgutil, tar, and uname are stubs, so no
# test downloads or installs anything.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-install-aws-gcloud"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  STUB_BIN="$TEST_DIR/stub"
  mkdir -p "$STUB_BIN"
  export CALLS="$TEST_DIR/calls.log"
  : > "$CALLS"
  export STUB_SIGNER="Developer ID Installer: Amazon.com Services LLC"

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/bash
case "$1" in -s) echo "${STUB_OS:-Darwin}" ;; -m) echo arm64 ;; esac
EOF
  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/bash
out=""; url=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; -*) ;; *) url="$1" ;; esac
  shift
done
echo "curl $url" >> "$CALLS"
echo fake > "$out"
EOF
  cat > "$STUB_BIN/pkgutil" <<'EOF'
#!/bin/bash
echo "pkgutil $1" >> "$CALLS"
case "$1" in
  --check-signature) echo "   1. $STUB_SIGNER" ;;
  --expand-full)
    payload="$3/aws-cli.pkg/Payload/aws-cli"
    mkdir -p "$payload"
    printf '#!/bin/bash\necho "aws-cli/2.99.0 test"\n' > "$payload/aws"
    printf '#!/bin/bash\n' > "$payload/aws_completer"
    chmod +x "$payload/aws" "$payload/aws_completer"
    ;;
esac
EOF
  cat > "$STUB_BIN/tar" <<'EOF'
#!/bin/bash
echo "tar $*" >> "$CALLS"
dest="${@: -1}"
sdk="$dest/google-cloud-sdk"
mkdir -p "$sdk/bin"
for t in gcloud gsutil bq; do printf '#!/bin/bash\necho %s\n' "$t" > "$sdk/bin/$t"; done
printf '#!/bin/bash\necho "install.sh $*" >> "$CALLS"\n' > "$sdk/install.sh"
chmod +x "$sdk/bin/"* "$sdk/install.sh"
EOF
  chmod +x "$STUB_BIN"/*
  export PATH="$STUB_BIN:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "fresh home: installs aws and gcloud under user dirs and links them" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.local/bin/aws")" = "$HOME/.local/aws-cli/aws" ]
  [ "$(readlink "$HOME/.local/bin/aws_completer")" = "$HOME/.local/aws-cli/aws_completer" ]
  for t in gcloud gsutil bq; do
    [ "$(readlink "$HOME/.local/bin/$t")" = "$HOME/google-cloud-sdk/bin/$t" ]
  done
  run "$HOME/.local/bin/aws" --version
  [[ "$output" == aws-cli/2.* ]]
  grep -q "curl https://awscli.amazonaws.com/AWSCLIV2.pkg" "$CALLS"
  grep -q "curl https://dl.google.com/.*google-cloud-cli-darwin-arm.tar.gz" "$CALLS"
}

@test "gcloud install.sh runs without prompts, PATH edits, or rc edits" {
  run "$SCRIPT" --gcloud

  [ "$status" -eq 0 ]
  grep -q "install.sh --quiet --usage-reporting false --path-update false --command-completion false" "$CALLS"
}

@test "second run is a no-op: no downloads, no new links" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  : > "$CALLS"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [[ "$output" != *"linked"* ]]
  [[ "$output" == *"aws already at"* ]]
  [[ "$output" == *"gcloud SDK already at"* ]]
}

@test "an unsigned AWS pkg is refused and nothing is installed" {
  export STUB_SIGNER="Developer ID Installer: Someone Else"

  run "$SCRIPT" --aws

  [ "$status" -eq 1 ]
  [[ "$output" == *"AWS CLI v2 install failed"* ]]
  [ ! -e "$HOME/.local/aws-cli" ]
  [ ! -e "$HOME/.local/bin/aws" ]
}

@test "--aws installs only the AWS CLI" {
  run "$SCRIPT" --aws

  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/aws" ]
  ! grep -q "google-cloud" "$CALLS"
  [ ! -e "$HOME/google-cloud-sdk" ]
}

@test "--dry-run downloads and writes nothing" {
  run "$SCRIPT" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry running"* ]]
  [ ! -s "$CALLS" ]
  [ ! -e "$HOME/.local" ]
}

@test "non-macOS host skips cleanly" {
  STUB_OS=Linux run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"not macOS"* ]]
  [ ! -s "$CALLS" ]
}
