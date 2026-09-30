#!/usr/bin/env bats
# Docs must not carry counts that go stale. `make count` prints live numbers.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
# shellcheck source=verify-counts-doc-paths.sh
source "$BATS_TEST_DIRNAME/verify-counts-doc-paths.sh"
# shellcheck source=verify-counts-exemptions.sh
source "$BATS_TEST_DIRNAME/verify-counts-exemptions.sh"

# Primary inventory: N(+)? <noun>
COUNT_PATTERN='(^|[^[:alnum:]])(~)?[0-9][0-9,]*\+? (more )?(doctor checks|health checks|tests|test files|bats files|modules|checks|launchagents|scripts|aliases|settings|defaults|agents|skills|commands|servers|tools|files|lines|entries|surfaces|packages|repos)([^[:alnum:]]|$)'
# Multi-word inventory nouns
COUNT_PATTERN_PHRASE='(^|[^[:alnum:]])(~)?[0-9][0-9,]*\+? (agent surfaces|workspace folders|standalone repos)([^[:alnum:]]|$)'
# Profile comparison tables: approximate Homebrew package totals (not benchmark timing columns).
COUNT_PATTERN_BREW_PROFILE='(Brew packages|Homebrew packages).*~[0-9]'

DOC_FILES=("${VERIFY_COUNTS_DOC_FILES[@]}")

collect_volatile_count_hits() {
  local -a files=("$@")
  local -a hits=()
  local line pattern
  for pattern in "$COUNT_PATTERN" "$COUNT_PATTERN_PHRASE" "$COUNT_PATTERN_BREW_PROFILE"; do
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if is_verify_counts_exemption "$line"; then
        continue
      fi
      hits+=("$line")
    done < <(grep -n -i -E "$pattern" "${files[@]}" 2>/dev/null || true)
  done
  printf '%s\n' "${hits[@]}" | sort -u
}

@test "guard doc list includes ARCHITECTURE.md and docs/team-onboarding.md" {
  local found=0
  for doc in "${VERIFY_COUNTS_DOC_FILES[@]}"; do
    case "$doc" in
      ARCHITECTURE.md|docs/team-onboarding.md) found=$((found + 1)) ;;
    esac
  done
  [ "$found" -eq 2 ]
}

@test "patterns catch doctor or health check totals and brew profile tilde counts" {
  run grep -n -E "$COUNT_PATTERN" <<< 'VISION has 145+ doctor checks in prose.'
  [ "$status" -eq 0 ]
  run grep -n -E "$COUNT_PATTERN" <<< 'dotfiles doctor runs 145+ health checks on first apply.'
  [ "$status" -eq 0 ]
  run grep -n -E "$COUNT_PATTERN_BREW_PROFILE" <<< '| Brew packages | ~47 (essentials) | ~67 (+tools) |'
  [ "$status" -eq 0 ]
  run grep -n -E "$COUNT_PATTERN_BREW_PROFILE" <<< '| **Homebrew packages** | ~47 | ~67 |'
  [ "$status" -eq 0 ]
}

@test "docs and user stories carry no volatile inventory counts" {
  cd "$DOTFILES_DIR"
  shopt -s nullglob
  human_blocked=(docs/human-blocked-actions/*.md)
  user_stories=(docs/user-stories/*.md)
  plan_docs=(docs/plans/*.md)
  shopt -u nullglob
  local -a scan_files=("${DOC_FILES[@]}" TASKS.md CHANGELOG.md Agentfile.yaml "${human_blocked[@]}" "${user_stories[@]}" "${plan_docs[@]}")
  local -a hits=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hits+=("$line")
  done < <(collect_volatile_count_hits "${scan_files[@]}")
  if ((${#hits[@]} > 0)); then
    echo "volatile counts found — delete them; do not update them:"
    printf '%s\n' "${hits[@]}"
    return 1
  fi
}

@test "count prints live stats" {
  run make -C "$DOTFILES_DIR" count
  [ "$status" -eq 0 ]
  [[ "$output" == *"Modules:"* ]]
  [[ "$output" == *"macOS defaults:"* ]]
}
