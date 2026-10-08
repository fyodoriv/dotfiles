#!/usr/bin/env bats

@test "Agentfile registers dotfiles command source directory" {
  run grep -A2 '^commands:' "$BATS_TEST_DIRNAME/../Agentfile.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"- ./commands"* ]]
}

@test "learn-repos command is incremental, safe, and retrieval-validated" {
  local command_file="$BATS_TEST_DIRNAME/../commands/learn-repos.md"
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/learn-repos.evals.json"
  local golden_file="$BATS_TEST_DIRNAME/../commands/evals/learn-repos.golden.json"
  local reference_file="$BATS_TEST_DIRNAME/../docs/learn-repos-reference.md"
  local fingerprint_helper="$BATS_TEST_DIRNAME/../bin/learn-repos-source-fingerprint"
  local inventory_helper="$BATS_TEST_DIRNAME/../bin/learn-repos-inventory"
  local chars

  [ -f "$command_file" ]
  [ -f "$eval_file" ]
  [ -f "$golden_file" ]
  [ -f "$reference_file" ]
  [ -x "$fingerprint_helper" ]
  [ -x "$inventory_helper" ]
  chars=$(wc -c < "$command_file" | tr -d ' ')
  [ "$chars" -le 8000 ]
  ! grep -q '^argument-hint:' "$command_file"
  grep -q "The command takes no arguments" "$command_file"
  grep -q "five lanes" "$command_file"
  ! grep -q 'focus=' "$command_file"
  grep -q "progress manifest" "$command_file"
  grep -q "git pull --ff-only" "$command_file"
  grep -q "repo-procedure" "$command_file"
  grep -q "Never delete by" "$command_file"
  grep -q 'repo-docs` alone' "$command_file"
  grep -q "Standing healing approval" "$command_file"
  grep -q "docs/ship-it-reference.md" "$command_file"
  grep -q "docs/learn-repos-reference.md" "$command_file"
  grep -q "include_superseded: false" "$command_file"
  grep -q "source-fingerprint" "$command_file"
  grep -q "learn-repos-inventory" "$command_file"
  grep -q "tag_match: all" "$command_file"
  grep -q "default/any matching is unsafe" "$command_file"
  grep -q "tag_match: all" "$reference_file"
  grep -q "default or \`any\` matching is unsafe" "$reference_file"
  grep -q "Re-index merged revision" "$reference_file"
  grep -q "Memory layers (logical" "$reference_file"
  grep -q "Forbidden recall paths" "$reference_file"
  grep -q "Quality cannot override freshness" "$reference_file"
  grep -q "Dead-end recovery" "$reference_file"
  grep -q "Cross-repo isolation" "$reference_file"
  grep -q "learn-repos-source-fingerprint <repo>" "$reference_file"
  grep -q "learn-repos-inventory discover" "$reference_file"
  grep -q "select-batch --root ~/apps" "$reference_file"
  grep -q "fewer than \*\*three\*\* fresh" "$reference_file"
  grep -q "timeout-bounded" "$reference_file"
  grep -q "Subagents are read-only with respect to shared memory" "$reference_file"
  grep -q "parent calls \`commit_session_legacy\` exactly once" "$reference_file"
  grep -q "Subagents are forbidden from calling \`commit_session_legacy\`" "$command_file"
  grep -q "tag_match all" "$eval_file"
  grep -q "Top-level defaults inherit to every question" "$reference_file"
  jq -e '.questions | type == "array" and length == 20' "$golden_file" >/dev/null
  jq -e '
    .schema == "learn-repos-golden-v1"
    and (.required_runtime_fields | type == "array" and length >= 6)
    and (.freshness_required_tags.templates | type == "array" and length == 3)
    and .authoritative_search.tag_match == "all"
    and .authoritative_search.include_superseded == false
    and .authoritative_search.query_requirement != ""
    and (.authoritative_search.modes_allowed | index("hybrid"))
    and (.required_source_citation.fields | index("source_paths"))
    and (.required_source_citation.fields | index("git_revision"))
    and (.questions | all(
      has("id") and has("category") and has("repo_relative_path")
      and has("question") and has("pass_criteria")
      and (has("expected_metadata") | not)
    ))
  ' "$golden_file" >/dev/null
  grep -q '"command_name": "learn-repos"' "$eval_file"
  grep -q '"prompt": "/learn-repos"' "$eval_file"
  grep -q 'uses /ship-it through PR, CI, merge, machine refresh, and re-indexing' "$eval_file"
  grep -q "stale-revision candidate" "$eval_file"
  grep -q "fingerprint drift at the same revision" "$eval_file"
  grep -q "quality cannot override freshness" "$eval_file"
  grep -q "dead-end recovery" "$eval_file"
  grep -q "sibling-prefix repositories do not pollute" "$eval_file"
  grep -q "mandatory source citation" "$eval_file" || grep -q "source_paths and git_revision" "$eval_file"
  grep -q "four parallel repository-reading subagents" "$eval_file"
  grep -q "canonical learn-repos-source-fingerprint helper" "$eval_file"
  grep -q "bin/learn-repos-inventory" "$eval_file"
  ! grep -q 'focus=' "$eval_file"
}

@test "learn-repos eval and golden JSON files are valid" {
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/learn-repos.evals.json"
  local golden_file="$BATS_TEST_DIRNAME/../commands/evals/learn-repos.golden.json"

  jq -e '.command_name == "learn-repos" and (.evals | type == "array") and (.evals | length >= 16)' "$eval_file" >/dev/null
  jq -e '
    .schema == "learn-repos-golden-v1"
    and (.questions | length == 20)
    and (.questions | all(has("pass_criteria") and (.pass_criteria | length > 0)))
    and (.required_runtime_fields | index("source_fingerprint"))
    and (.freshness_required_tags.templates | index("repo:{repo_relative_path}"))
    and (.authoritative_search.modes_forbidden | index("exact"))
    and (.forbidden_recall | index("tag_match:omitted"))
  ' "$golden_file" >/dev/null
}

@test "Agentfile automatically retrieves grounded repository procedures" {
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"

  grep -q "automatically search memory" "$agentfile"
  grep -q "current-revision repo-procedure" "$agentfile"
  grep -q "store the reusable correction with source paths and revision" "$agentfile"
}

@test "research-url command accepts URLs, text, and product names" {
  local command_file="$BATS_TEST_DIRNAME/../commands/research-url.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/research-url-reference.md"

  [ -f "$command_file" ]
  [ -f "$reference_file" ]
  grep -q 'argument-hint: "<url | product name | text>"' "$command_file"
  grep -q "a product, library, tool, paper, or technique name with no URL" "$command_file"
  grep -q "Extract URLs from the input" "$reference_file"
}

@test "research-url command stays under agent-bloat hard cap" {
  local command_file="$BATS_TEST_DIRNAME/../commands/research-url.md"
  local chars

  [ -f "$command_file" ]
  chars=$(wc -c < "$command_file" | tr -d ' ')
  [ "$chars" -le 8000 ]
}

@test "research-url command links to full workflow reference" {
  local command_file="$BATS_TEST_DIRNAME/../commands/research-url.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/research-url-reference.md"

  [ -f "$command_file" ]
  [ -f "$reference_file" ]
  grep -q "docs/research-url-reference.md" "$command_file"
  grep -q "## Phase 4 — Optional commit / delivery" "$reference_file"
}

@test "research-url command encodes standing delivery approval" {
  local command_file="$BATS_TEST_DIRNAME/../commands/research-url.md"

  [ -f "$command_file" ]
  grep -q "Standing delivery approval for this command" "$command_file"
  grep -q "commit, push, open PRs, merge, and deploy/sync" "$command_file"
  grep -Eq 'TASKS\.md.*task-filing output' "$command_file"
  grep -q "protected-branch direct pushes" "$command_file"
}

@test "research-url command has eval coverage" {
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/research-url.evals.json"

  [ -f "$eval_file" ]
  grep -q '"command_name": "research-url"' "$eval_file"
  grep -q '"prompt": "/research-url https://example.com/new-mcp-tool"' "$eval_file"
  grep -q "aggregator/newsletter" "$eval_file"
  grep -q "standing approval" "$eval_file"
  grep -q "push/PR/merge/deploy" "$eval_file"
}

@test "ship-it command stays under agent-bloat hard cap" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local chars

  [ -f "$command_file" ]
  chars=$(wc -c < "$command_file" | tr -d ' ')
  [ "$chars" -le 8000 ]
}

@test "ship-it command declares session auto-ship as default" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  grep -q "## Session auto-ship (default)" "$command_file"
  grep -q "Do not ask" "$command_file"
  grep -q "Dangerous — stop and report" "$command_file"
  grep -q "Dangerous blocker output" "$command_file"
  grep -q "## Session auto-ship (default)" "$reference_file"
  grep -q "SHIP-IT BLOCKED (dangerous)" "$reference_file"
  grep -q "/ship-it fix lint errors" "$reference_file"
}

@test "ship-it cleanup researches every local branch and stash" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
  local skill_file="$BATS_TEST_DIRNAME/../skills/update-tooling/SKILL.md"
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/ship-it.evals.json"

  grep -q "## 9. Clean up shipped/redundant worktrees, branches, and stashes" "$reference_file"
  grep -q "### Local branches and stashes" "$reference_file"
  grep -q "git bundle create" "$reference_file"
  grep -q "git apply --check -R" "$reference_file"
  grep -q "every local branch and stash" "$command_file"
  grep -q "Clean up local branches and stashes" "$skill_file"
  jq -e '.evals | any(.id == 11 and (.prompt | contains("stale local branches")))' "$eval_file" >/dev/null
}

@test "ship-it keeps a linked Jira ticket aligned with final delivery" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/ship-it.evals.json"

  grep -q "final non-draft PR open/ready" "$command_file"
  grep -q "### Jira delivery lifecycle" "$reference_file"
  grep -q "In Review" "$reference_file"
  grep -q "resolution: Done" "$reference_file"
  grep -q "get_available_transitions" "$reference_file"
  grep -q "transition_issue" "$reference_file"
  jq -e '.evals | any(.id == 10 and (.prompt | contains("linked Jira ticket")))' "$eval_file" >/dev/null
}

@test "ship-it requires uncommitted visual proof for every PR" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/ship-it.evals.json"
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"
  local agents_file="$BATS_TEST_DIRNAME/../AGENTS.md"
  local claude_file="$BATS_TEST_DIRNAME/../CLAUDE.md"

  grep -q "## Visual proof for every PR" "$command_file"
  grep -q "Drag and drop the images into the PR description" "$command_file"
  grep -q "Never commit proof images" "$command_file"
  grep -q "## 5a. Capture visual proof for every PR" "$reference_file"
  grep -q "This rule applies to every PR" "$reference_file"
  grep -q "terminal validation result" "$reference_file"
  grep -q "Every PR needs uncommitted visual proof" "$agentfile"
  grep -q "Visual proof for every PR" "$agents_file"
  cmp -s "$agents_file" "$claude_file"
  jq -e '.evals | any(.id == 9 and (.prompt | contains("backend-only fix")))' "$eval_file" >/dev/null
}

@test "non-UI proof accepts a pasted terminal transcript" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"

  # A transcript is copyable, diffable, and searchable, so it is the preferred
  # non-UI proof. Requiring an image there forced GUI automation for CLI work.
  grep -q "pasted terminal transcript" "$command_file"
  grep -q "pasted terminal transcript" "$reference_file"
  grep -q "pasted terminal transcript" "$agentfile"
}

@test "visual proof forbids GUI automation to manufacture a terminal image" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  # Driving AppleScript/keystrokes at a terminal window steals focus from the
  # user's apps and can type into whatever is frontmost.
  grep -q "Never drive AppleScript, keystrokes, or window activation" "$command_file"
  grep -q "Never drive AppleScript, keystrokes, or window activation" "$reference_file"
  grep -q "screencapture" "$reference_file"
}

@test "Agentfile requires explicit mutable-state scopes" {
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"

  grep -q "Name the lifecycle scope of mutable state" "$agentfile"
  grep -q 'provider-instance, Redux-store' "$agentfile"
  grep -q 'Do not use unqualified terms such as `globalState`' "$agentfile"
  grep -q 'Access `globalThis` or `Symbol.for` in one named owner module only' "$agentfile"
  grep -q "lifecycle, cleanup, and deletion condition" "$agentfile"
}

@test "Agentfile protects live auth and customer data" {
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"
  local readme="$BATS_TEST_DIRNAME/../README.md"

  grep -q "live authentication material" "$agentfile"
  grep -q "customer payload snapshots" "$agentfile"
  grep -q "tests," "$agentfile"
  grep -q "logs, screenshots" "$agentfile"
  grep -q "placeholders and fixtures" "$agentfile"
  grep -q "live authentication material" "$readme"
  grep -q "customer payload snapshots" "$readme"
}

@test "ship-it command links to full delivery reference" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  [ -f "$command_file" ]
  [ -f "$reference_file" ]
  grep -q "docs/ship-it-reference.md" "$command_file"
  grep -q "## 1. Inventory fast" "$reference_file"
  grep -q "## 13. Post-delivery verification loop" "$reference_file"
}

@test "ship-it routes planning requests through the source-backed plan workflow" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/ship-it.evals.json"
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"
  local plan_template="$BATS_TEST_DIRNAME/../docs/templates/plan-template.md"

  grep -q "## Planning requests" "$command_file"
  grep -q "writing-plans" "$command_file"
  grep -q "implementation-plan-template.md" "$command_file"
  grep -q "HostBootstrapPayload" "$command_file"
  grep -q -- "- task-command-center" "$agentfile"
  grep -q -- "- writing-plans" "$agentfile"
  grep -q "## Planning requests" "$reference_file"
  grep -q "fact.*proposals" "$reference_file"
  grep -q "unit/contract/integration/end-to-end" "$reference_file"
  grep -q "sandbox extension" "$plan_template"
  grep -q "scoped context" "$plan_template"
  grep -q "preloadedState" "$plan_template"
  grep -q "explicit store-prop" "$plan_template"
  jq -e '.evals | any(.id == 8 and (.prompt | contains("cross-platform host-state bridge")))' "$eval_file" >/dev/null
}

@test "ship-it command forbids bypass-merging other people's PRs" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  [ -f "$command_file" ]
  grep -q "someone else's PR" "$command_file"
  grep -q "admin/bypass merge of someone else's PR" "$reference_file"
  grep -q "gh pr view --json author,headRepositoryOwner,headRefName" "$reference_file"
  grep -q "PR author/head branch owner is you or the agent-created branch" "$reference_file"
}

@test "ship-it command releases own tools automatically" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  [ -f "$command_file" ]
  grep -q "Own-tool release automation is explicitly enabled" "$command_file"
  grep -q "\`agentbrew\`" "$command_file"
  grep -q "\`dotfiles\`" "$command_file"
  grep -q "\`tasks.md\` / \`tasks-md\`" "$command_file"
  grep -q "\`minsky\`" "$command_file"
  grep -q "npm run publish-latest" "$reference_file"
  grep -q "gh release create vX.Y.Z --generate-notes" "$reference_file"
  grep -q "semantic-release" "$reference_file"
}

@test "ship-it command approval persists for the current session" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"

  [ -f "$command_file" ]
  grep -q "remains active for the rest of the conversation/session" "$command_file"
  grep -q "If the user has invoked \`/ship-it\` earlier in this conversation/session" "$command_file"
  grep -q "until the user explicitly disables ship-it mode" "$command_file"
}

@test "ship-it command scopes broad delivery while approving owned current-task rebases" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  [ -f "$command_file" ]
  grep -q "## Approved repo families" "$command_file"
  grep -q "tooling repos whose real path is under \`~/apps/tooling/\\*\\*\`" "$command_file"
  grep -q "explicitly named by the active request" "$command_file"
  grep -q "Rebasing owned work is always approved" "$command_file"
  grep -q "explicitly named current-task repo" "$reference_file"
  grep -q "Rebasing owned work is always approved under \`/ship-it\`" "$reference_file"
  grep -q "They are not added to the bypass/release allowlist" "$command_file"
}

@test "ship-it command prefers reviewed duplicate PRs" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  grep -q "prefer reviewed PR on duplicates" "$command_file"
  grep -q "Prefer the PR that already has human" "$reference_file"
  grep -q "review history, comments, or approvals" "$reference_file"
  grep -q "Move the newer branch's intended content" "$reference_file"
  grep -q "Override this only when the user explicitly" "$reference_file"
  grep -q "says to prefer a different PR" "$reference_file"
}

@test "ship-it command salvages useful worktrees before cleanup" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  grep -q "salvage useful work from local worktrees before deleting anything" "$command_file"
  grep -q "git worktree list --porcelain" "$reference_file"
  grep -q "Classify each worktree" "$reference_file"
  grep -Fq "For **ship** worktrees" "$reference_file"
  grep -Fq "For **already represented** worktrees" "$reference_file"
  grep -Fq "For **unknown/owned elsewhere** worktrees" "$reference_file"
  grep -q "git worktree remove <path>" "$reference_file"
}

@test "Agentfile broad delivery mandate remains limited to approved repo families" {
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  grep -q "Approved-family /ship-it delivery" "$agentfile"
  grep -q "shared-rules.md sections \"Git and delivery\"" "$agentfile"
  grep -q "~/apps/tooling/\\*\\*" "$command_file"
  grep -q "approved repo families" "$command_file"
  grep -q "Prefer the PR that already has human" "$reference_file"
  grep -q "admin/bypass merge of someone else's PR" "$reference_file"
  grep -q "gh pr view --json author,headRepositoryOwner,headRefName" "$reference_file"
  grep -q "Own-tool release automation is explicitly enabled" "$command_file"
  grep -q "\`agentbrew\`" "$command_file"
  grep -q "\`dotfiles\`" "$command_file"
  grep -q "\`tasks.md\` / \`tasks-md\`" "$command_file"
  grep -q "\`minsky\`" "$command_file"
  grep -q "agentbrew sync --pull" "$command_file"
  grep -q "recommended updates" "$reference_file"
}

@test "ship-it command refreshes recommended updates after tooling delivery" {
  local command_file="$BATS_TEST_DIRNAME/../commands/ship-it.md"
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  grep -q "agentbrew sync --pull" "$command_file"
  grep -q "## 12. Apply latest recommended updates (tooling repos)" "$reference_file"
  grep -q "dotfiles apply" "$reference_file"
  grep -q "without a project Agentfile" "$reference_file"
  grep -q "merged-but-not-applied tooling work leaves the machine running stale config" "$reference_file"
}

@test "ship-it command includes post-delivery verification loop" {
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  grep -q "## 13. Post-delivery verification loop (tooling repos)" "$reference_file"
  grep -q "dotfiles doctor --module security --module cursor --module terminal --module agent-browser --module chrome --module resilience --fix" "$reference_file"
  grep -q "agentbrew status --ci" "$reference_file"
  grep -q "bin/dotfiles-reload-launchagents" "$reference_file"
  grep -q "Apply and reload LaunchAgents (mandatory)" "$reference_file"
  grep -q "bin/dotfiles-reload-launchagents --kickstart" "$reference_file"
  grep -q "com.dotfiles.gui-path" "$reference_file"
  grep -q "launchctl getenv UV_PYTHON_PREFERENCE" "$reference_file"
  grep -q "9223/json/version" "$reference_file"
  grep -q "DOTFILES_DOCTOR_NOTIFY=1" "$reference_file"
  grep -q "Non-blocking / pre-existing env failures" "$reference_file"
  grep -q "Fix-and-re-ship loop" "$reference_file"
}

@test "README documents approved-family ship-it delivery mandate" {
  local readme="$BATS_TEST_DIRNAME/../README.md"

  grep -q "Approved-family delivery mandate" "$readme"
  grep -q "approved repo families" "$readme"
  grep -q "the reviewed PR wins by default" "$readme"
  grep -q "For the four own-tool repos" "$readme"
  grep -q "If sibling worktrees exist" "$readme"
  grep -q "safe cleanup of shipped/redundant current-session worktrees" "$readme"
  grep -q "agentbrew's auto-release plus" "$readme"
  grep -q "tasks.md's GitHub Release-triggered npm publish workflow" "$readme"
  grep -q "Minsky's semantic-release workflow" "$readme"
  grep -q "applies the machine's latest recommended updates" "$readme"
  grep -q "git push --force-with-lease" "$readme"
}

@test "ship-it command reconciles clean local default branch commits" {
  local reference_file="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"

  [ -f "$reference_file" ]
  grep -q "clean working tree but local-only commits" "$reference_file"
  grep -q "short-lived branch at the current HEAD" "$reference_file"
  grep -q "Do not push the default/protected branch directly" "$reference_file"
  grep -q "refs/ship-it-preserved" "$reference_file"
  grep -q "git reset --keep" "$reference_file"
}
