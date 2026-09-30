# Paths scanned by tests/verify-counts.bats for volatile count patterns.
# Sourced by tests/verify-counts.bats and bin/bats-affected — keep in sync.
VERIFY_COUNTS_DOC_FILES=(
  README.md
  AGENTS.md
  ARCHITECTURE.md
  ROADMAP.md
  VISION.md
  CONTRIBUTING.md
  tests/README.md
  docs/architecture.md
  docs/faq.md
  docs/module-reference.md
  docs/what-gets-changed.md
  docs/security-model.md
  docs/team-onboarding.md
  docs/onboarding.md
  docs/forking-guide.md
)

is_verify_counts_doc_path() {
  local file="$1"
  case "$file" in
    TASKS.md|CHANGELOG.md|Agentfile.yaml) return 0 ;;
    docs/plans/*.md) return 0 ;;
    docs/human-blocked-actions/*.md|docs/user-stories/*.md) return 0 ;;
  esac

  local doc
  for doc in "${VERIFY_COUNTS_DOC_FILES[@]}"; do
    if [[ "$file" == "$doc" ]]; then
      return 0
    fi
  done
  return 1
}
