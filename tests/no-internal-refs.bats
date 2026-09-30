#!/usr/bin/env bats

REPO_ROOT="$BATS_TEST_DIRNAME/.."
# shellcheck source=../lib/oss-readiness.sh
source "$REPO_ROOT/lib/oss-readiness.sh"
oss_readiness_load_private_env dotfiles >/dev/null 2>&1 || true

@test "no configured private references in tracked text files" {
  cd "$REPO_ROOT"
  [ -n "${OSS_READINESS_INTERNAL_PATTERN:-}" ] || skip "no private reference pattern configured"

  local hits=()
  while IFS= read -r -d '' rel; do
    [ -z "$rel" ] && continue
    [ -f "$rel" ] || continue
    grep -Iq . "$rel" 2>/dev/null || continue
    if ! grep -qiE -- "$OSS_READINESS_INTERNAL_PATTERN" "$rel" 2>/dev/null; then
      continue
    fi
    hits+=("$rel")
  done < <(git ls-files -z)

  if [ ${#hits[@]} -gt 0 ]; then
    echo "Files mentioning configured private identifiers:"
    printf '  %s\n' "${hits[@]}"
    echo "Move those references to the private overlay or generalize the base repo."
    return 1
  fi
}
