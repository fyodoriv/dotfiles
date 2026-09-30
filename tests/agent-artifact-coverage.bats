#!/usr/bin/env bats

load test_helper

repo_root() {
  printf '%s\n' "$BATS_TEST_DIRNAME/.."
}

agentfile_block_items() {
  local block="$1" file="$2"
  awk -v block="$block" '
    $0 == block ":" { in_block = 1; next }
    in_block && /^[^[:space:]#][^:]*:/ { exit }
    in_block && /^[[:space:]]*-[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)
      if (line ~ /^name:/) {
        sub(/^name:[[:space:]]*/, "", line)
      }
      sub(/[[:space:]]+#.*$/, "", line)
      gsub(/^"|"$/, "", line)
      print line
    }
  ' "$file"
}

command_has_eval() {
  local root="$1" name="$2" eval_file="$root/commands/evals/$name.evals.json"
  [ -f "$eval_file" ] || return 1
  jq -e --arg name "$name" '.command_name == $name and (.evals | type == "array") and (.evals | length > 0)' "$eval_file" >/dev/null
}

command_has_static_bats_coverage() {
  local root="$1" name="$2"
  grep -R -F -q "commands/$name.md" "$root/tests" 2>/dev/null ||
    grep -R -F -q "$name command" "$root/tests" 2>/dev/null ||
    grep -R -F -q "$name.evals.json" "$root/tests" 2>/dev/null
}

check_command_coverage() {
  local root="$1" status=0 command_file name
  shopt -s nullglob
  for command_file in "$root"/commands/*.md; do
    name="$(basename "$command_file" .md)"
    if ! command_has_eval "$root" "$name" && ! command_has_static_bats_coverage "$root" "$name"; then
      printf 'uncovered command: %s (add commands/evals/%s.evals.json or a literal Bats assertion)\n' "$name" "$name"
      status=1
    fi
  done
  shopt -u nullglob
  return "$status"
}

@test "all dotfiles commands have evals or static Bats coverage" {
  run check_command_coverage "$(repo_root)"

  [ "$status" -eq 0 ]
}

@test "coverage gate fails for a new command without eval or static coverage" {
  local fixture="$TEST_DIR/fixture"
  mkdir -p "$fixture"
  cp -R "$(repo_root)/commands" "$fixture/commands"
  mkdir -p "$fixture/tests"
  cp "$(repo_root)/tests/agentbrew-command-sources.bats" "$fixture/tests/agentbrew-command-sources.bats"
  cat > "$fixture/commands/uncovered-tool.md" <<'EOF'
---
description: Uncovered fixture command
---

# Uncovered fixture command
EOF

  run check_command_coverage "$fixture"

  [ "$status" -eq 1 ]
  [[ "$output" == *"uncovered command: uncovered-tool"* ]]
}

@test "command eval files are valid and point at existing commands" {
  local root eval_file filename_name json_name
  root="$(repo_root)"
  shopt -s nullglob
  for eval_file in "$root"/commands/evals/*.evals.json; do
    filename_name="$(basename "$eval_file" .evals.json)"
    json_name="$(jq -r '.command_name' "$eval_file")"

    [ "$json_name" = "$filename_name" ]
    [ -f "$root/commands/$json_name.md" ]
    jq -e '.evals | type == "array" and length > 0' "$eval_file" >/dev/null
  done
  shopt -u nullglob
}

@test "Agentfile command source entries resolve to dotfiles-owned command dirs" {
  local root agentfile items item path command_files
  root="$(repo_root)"
  agentfile="$root/Agentfile.yaml"
  items="$(agentfile_block_items commands "$agentfile")"

  [[ "$items" == *"./commands"* ]]
  shopt -s nullglob
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    [[ "$item" == ./* ]]
    path="$root/${item#./}"
    [ -d "$path" ]
    command_files=("$path"/*.md)
    [ "${#command_files[@]}" -gt 0 ]
  done <<< "$items"
  shopt -u nullglob
}

@test "Agentfile skill and source artifacts stay explicit and safe" {
  local agentfile skills sources
  agentfile="$(repo_root)/Agentfile.yaml"
  skills="$(agentfile_block_items skills "$agentfile")"
  sources="$(agentfile_block_items sources "$agentfile")"

  [[ "$skills" == *"verification-before-completion"* ]]
  [[ "$skills" == *"debug"* ]]
  [[ "$skills" == *"review"* ]]
  [[ "$skills" == *"test-driven-development"* ]]
  [[ "$sources" == *"anthropics/skills"* ]]
  [[ "$sources" == *"modelcontextprotocol/ext-apps"* ]]
  [[ "$skills$sources" != *"~/.claude"* ]]
  [[ "$skills$sources" != *"~/.cursor"* ]]
  [[ "$skills$sources" != *"~/.config/devin"* ]]
  [[ "$skills$sources" != *"~/.codeium"* ]]
}

@test "Agentfile inline rules cover delivery safety invariants" {
  local agentfile
  agentfile="$(repo_root)/Agentfile.yaml"

  grep -q "No completion claims without fresh verification evidence" "$agentfile"
  grep -q "generated agent config is owned by agentbrew" "$agentfile"
  grep -q "approved repo families" "$agentfile"
  grep -q "never bypass-merge someone else's PR" "$agentfile"
  grep -q "Every PR needs uncommitted visual proof" "$agentfile"
}

@test "Agentfile inline rules use task-aware structured memory lifecycle calls" {
  local agentfile
  agentfile="$(repo_root)/Agentfile.yaml"

  grep -q "get_bootstrap_profile.*task_summary" "$agentfile"
  grep -q "search ranked memory and mistake notes" "$agentfile"
  grep -q "decisions as {what, why}" "$agentfile"
  grep -q "errors as {error, tool, resolution}" "$agentfile"
  grep -q "user corrections as {original, corrected_to}" "$agentfile"
}

@test "AGENTS and CLAUDE stay mirrored for delivery-critical guidance" {
  local root
  root="$(repo_root)"

  cmp -s "$root/AGENTS.md" "$root/CLAUDE.md"
  grep -q "Hook-based enforcement" "$root/AGENTS.md"
  grep -q "generated agent config" "$root/AGENTS.md"
  grep -q "Approved-family standing approval" "$root/AGENTS.md"
  grep -q "admin/bypass PR merges" "$root/AGENTS.md"
  grep -q "someone else's PR" "$root/AGENTS.md"
}
