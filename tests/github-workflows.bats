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

# ── Safety contract for hosted runs (docs/ci-setup.md) ──────────────
# A public repo runs code from strangers' pull requests, so each rule
# closes one way a workflow could leak a token or get more rights than
# it needs.

workflow_code() {
  # Print a workflow without its YAML comment lines.
  grep -v '^[[:space:]]*#' "$1"
}

@test "workflow files: every action is pinned to a full commit SHA" {
  local wf line
  for wf in "$REPO_ROOT"/.github/workflows/*.yml; do
    while IFS= read -r line; do
      [[ "$line" =~ uses:\ (actions|github)/[A-Za-z0-9._/-]+@[0-9a-f]{40}\ \#\ v[0-9] ]] || {
        echo "$(basename "$wf"): not a GitHub-owned action pinned to a SHA: $line"
        return 1
      }
    done < <(workflow_code "$wf" | grep -E '^[[:space:]]*(-[[:space:]]*)?uses:')
  done
}

@test "workflow files: every workflow sets top-level permissions" {
  local wf
  for wf in "$REPO_ROOT"/.github/workflows/*.yml; do
    workflow_code "$wf" | grep -q '^permissions:' || {
      echo "$(basename "$wf") has no top-level permissions block"
      return 1
    }
  done
}

@test "workflow files: no fork code runs with repo rights or secrets" {
  local wf
  for wf in "$REPO_ROOT"/.github/workflows/*.yml; do
    ! workflow_code "$wf" | grep -q 'pull_request_target' || {
      echo "$(basename "$wf") uses pull_request_target"
      return 1
    }
    ! workflow_code "$wf" | grep -qE '\$\{\{[[:space:]]*secrets\.' || {
      echo "$(basename "$wf") reads a secret"
      return 1
    }
    # A step that prints the environment could expose values in a public log.
    ! workflow_code "$wf" | grep -qE '^[[:space:]]*(-[[:space:]]*)?run:[[:space:]]*(env|printenv|set)[[:space:]]*$' || {
      echo "$(basename "$wf") prints the environment"
      return 1
    }
  done
}

@test "workflow files: ci.yml is read-only, keeps no credentials, cancels stale runs" {
  local file="$REPO_ROOT/.github/workflows/ci.yml"
  ! workflow_code "$file" | grep -qE ':[[:space:]]*write\b' || {
    echo "ci.yml grants a write permission"
    return 1
  }
  grep -q 'cancel-in-progress:' "$file"
  [ "$(grep -c 'persist-credentials: false' "$file")" -eq "$(workflow_code "$file" | grep -c 'uses: actions/checkout@')" ]
}

@test "workflow files: ci.yml test job runs the local gate on macOS" {
  local file="$REPO_ROOT/.github/workflows/ci.yml"
  grep -qE '^[[:space:]]*run: make check$' "$file"
  awk '/^  test:/ { in_job = 1; next } in_job && /^  [a-z]+:/ { exit } in_job' "$file" | grep -q 'runs-on: macos-latest'
}
