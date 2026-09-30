#!/usr/bin/env bats
# Tests for .github/workflows/* — pin the OSS-readiness rewrite.
#
# Before the OSS migration these workflows had a `validation` job that
# uses an enterprise-only GHE composite action and gated every other
# job on it via `needs: validation` + `if: ${{ !cancelled() }}`. The
# rewrite drops the validation job entirely; this file pins that
# structural change so a future "fixup" cannot silently re-introduce
# the enterprise-only dependency on a public GitHub.com fork.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
WORKFLOWS=(
  ci.yml
  release.yml
  brew-audit.yml
)

@test "workflow files: no jobs depend on a validation job" {
  for wf in "${WORKFLOWS[@]}"; do
    ! grep -q '^[[:space:]]*needs: validation[[:space:]]*$' \
      "$REPO_ROOT/.github/workflows/$wf" || {
      echo "$wf still has 'needs: validation'"
      return 1
    }
  done
}

@test "workflow files: no validation job is declared" {
  for wf in "${WORKFLOWS[@]}"; do
    ! grep -q '^[[:space:]]*validation:[[:space:]]*$' \
      "$REPO_ROOT/.github/workflows/$wf" || {
      echo "$wf still declares a 'validation:' job"
      return 1
    }
  done
}

@test "workflow files: no '!cancelled()' bypass guard remains" {
  # The `!cancelled()` guard only made sense to keep jobs running when
  # the upstream validation job failed. With the validation job gone,
  # leaving the guard would mute legitimate cancellations.
  for wf in "${WORKFLOWS[@]}"; do
    ! grep -qF '!cancelled()' "$REPO_ROOT/.github/workflows/$wf" || {
      echo "$wf still has '!cancelled()' guard"
      return 1
    }
  done
}

@test "workflow files: ci.yml jobs are still defined" {
  # Pin the existing job names so removing the validation job doesn't
  # accidentally take the real CI jobs with it.
  local file="$REPO_ROOT/.github/workflows/ci.yml"
  for job in lint test doctor audit coverage; do
    grep -qE "^[[:space:]]*${job}:[[:space:]]*$" "$file" || {
      echo "ci.yml is missing the '$job' job"
      return 1
    }
  done
}

@test "workflow files: release.yml release job is still defined" {
  grep -qE '^[[:space:]]*release:[[:space:]]*$' \
    "$REPO_ROOT/.github/workflows/release.yml"
}

@test "workflow files: brew-audit.yml audit-manifest job is still defined" {
  grep -qE '^[[:space:]]*audit-manifest:[[:space:]]*$' \
    "$REPO_ROOT/.github/workflows/brew-audit.yml"
}
