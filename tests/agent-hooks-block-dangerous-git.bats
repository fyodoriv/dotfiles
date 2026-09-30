#!/usr/bin/env bats

@test "blocks git reset --hard" {
  run bash -c "echo '{\"tool_input\": {\"command\": \"git reset --hard\"}}' | ./agent-hooks/block-dangerous-git.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "BLOCKED: 'git reset --hard' is not permitted. Ask the user to run it manually." ]
}

@test "blocks git clean -f" {
  run bash -c "echo '{\"tool_input\": {\"command\": \"git clean -f\"}}' | ./agent-hooks/block-dangerous-git.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "BLOCKED: 'git clean -f' is not permitted. Ask the user to run it manually." ]
}

@test "blocks git branch -D" {
  run bash -c "echo '{\"tool_input\": {\"command\": \"git branch -D\"}}' | ./agent-hooks/block-dangerous-git.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "BLOCKED: 'git branch -D' is not permitted. Ask the user to run it manually." ]
}

@test "blocks git checkout ." {
  run bash -c "echo '{\"tool_input\": {\"command\": \"git checkout .\"}}' | ./agent-hooks/block-dangerous-git.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "BLOCKED: 'git checkout .' is not permitted. Ask the user to run it manually." ]
}

@test "blocks git restore ." {
  run bash -c "echo '{\"tool_input\": {\"command\": \"git restore .\"}}' | ./agent-hooks/block-dangerous-git.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "BLOCKED: 'git restore .' is not permitted. Ask the user to run it manually." ]
}

@test "allows other commands" {
  run bash -c "echo '{\"tool_input\": {\"command\": \"git status\"}}' | ./agent-hooks/block-dangerous-git.sh"
  [ "$status" -eq 0 ]
}

@test "parses hook JSON without Python" {
  grep -q '/usr/bin/plutil' agent-hooks/block-dangerous-git.sh
  ! grep -vE '^[[:space:]]*#' agent-hooks/block-dangerous-git.sh \
    | grep -qE '(^|[[:space:]])python3([[:space:]]|$)'
}
