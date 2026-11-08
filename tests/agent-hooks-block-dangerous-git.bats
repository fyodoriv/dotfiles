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

_check_command_text() {
  local payload
  payload=$(jq -n --arg command "$1" '{tool_input: {command: $command}}')
  run bash -c 'printf "%s" "$1" | ./agent-hooks/block-dangerous-git.sh' _ "$payload"
}

@test "allows verbose branch listing" {
  _check_command_text 'git branch -vv'
  [ "$status" -eq 0 ]
}

@test "ignores inert quoted heredoc prose" {
  local text
  text=$(printf "cat <<'NOTE'\ngit branch -D topic\nNOTE\n")
  _check_command_text "$text"
  [ "$status" -eq 0 ]
}

@test "still blocks a destructive command after an inert heredoc" {
  local text
  text=$(printf "cat <<'NOTE'\nexample text\nNOTE\ngit reset --hard\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "a here-string must not hide following commands" {
  local text
  text=$(printf "cat <<<'NOTE'\ngit reset --hard\nNOTE\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "heredoc-like text in a quoted argument must not hide commands" {
  local text
  text=$(printf "echo \"<<'NOTE'\"\ngit reset --hard\nNOTE\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "unquoted heredoc substitutions remain visible to the guard" {
  local text
  text=$(printf 'cat <<NOTE\n$(git reset --hard)\nNOTE\n')
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "nested quotes in substitutions cannot hide a following command" {
  local text
  text=$(printf 'echo "$(printf "<<\047NOTE\047")"\ngit reset --hard\nNOTE\n')
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "a nested heredoc spelling inside an unquoted body cannot hide a command" {
  local text
  text=$(printf 'cat <<PLAIN\ncat <<\047NOTE\047\nPLAIN\ngit reset --hard\nNOTE\n')
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "comments cannot open a heredoc that hides a command" {
  local text
  text=$(printf '# cat <<\047NOTE\047\ngit reset --hard\nNOTE\n')
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "multiple quoted heredocs leave later executable commands visible" {
  local text
  text=$(printf 'cat <<\047FIRST\047 <<"SECOND"\ngit branch -D prose\nFIRST\ngit reset --hard\nSECOND\n')
  _check_command_text "$text"
  [ "$status" -eq 0 ]
}

@test "deployed git guard links its inert-text helper" {
  local scratch="$BATS_TEST_TMPDIR/deployed-home" payload text
  mkdir -p "$scratch"
  run env HOME="$scratch" CHEZMOI_SOURCE_DIR="$BATS_TEST_DIRNAME/.." \
    bash .chezmoiscripts/run_after_agent-hooks.sh
  [ "$status" -eq 0 ]
  [ -L "$scratch/.config/dotfiles/hooks/plain-document-write.jq" ]
  text=$(printf "cat <<'NOTE'\ngit branch -D topic\nNOTE\n")
  payload=$(jq -n --arg command "$text" '{tool_input: {command: $command}}')
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$scratch/.config/dotfiles/hooks/block-dangerous-git.sh"
  [ "$status" -eq 0 ]
}

@test "quoted heredoc input to a shell remains executable" {
  local text
  text=$(printf "bash <<'NOTE'\ngit reset --hard\nNOTE\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "quoted heredoc piped to a shell remains executable" {
  local text
  text=$(printf "cat <<'NOTE' | bash\ngit reset --hard\nNOTE\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "arithmetic shifts cannot masquerade as heredocs" {
  local text
  text=$(printf "(( 1 << 'NOTE' ))\ngit reset --hard\nNOTE\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "an emoji before a following executable command cannot shift the filter" {
  local text
  text=$(printf "cat <<'NOTE'\n📄 safe text\nNOTE\ngit reset --hard\n")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "plain document output may contain an otherwise blocked example" {
  local text
  text=$(printf "cat > %s/notes.md <<'NOTE'\ngit reset --hard\nNOTE\n" "$BATS_TEST_TMPDIR")
  _check_command_text "$text"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/notes.md" ]
}

@test "document output to a named pipe keeps the conservative check" {
  local text
  mkfifo "$BATS_TEST_TMPDIR/notes.md"
  text=$(printf "cat > %s/notes.md <<'NOTE'\ngit reset --hard\nNOTE\n" "$BATS_TEST_TMPDIR")
  _check_command_text "$text"
  [ "$status" -eq 2 ]
}

@test "an unavailable parser keeps the conservative check" {
  local text
  shfmt() { return 1; }
  export -f shfmt
  text=$(printf "cat <<'NOTE'\ngit reset --hard\nNOTE\n")
  _check_command_text "$text"
  unset -f shfmt
  [ "$status" -eq 2 ]
}

# Issue #502: with a shell expansion, "branch" and a delete-like flag count only
# inside one git invocation, not anywhere in the command.
@test "#502 allows a commit message with prose next to a shell expansion" {
  _check_command_text 'd=$(mktemp -d) && git commit -m "keep the branch head" -q'
  [ "$status" -eq 0 ]
}

@test "#502 allows a branch create next to an unrelated substitution and -m" {
  _check_command_text 'git commit -q -m init && git branch tmpx && tool run -m x "$(cat p.txt)"'
  [ "$status" -eq 0 ]
}

@test "#502 allows a search over the hook whose pattern mentions branch and -D" {
  _check_command_text 'rg -n "branch" ${HOOK_DIR}/block.sh -D'
  [ "$status" -eq 0 ]
}

@test "#502 still blocks a force delete next to a substitution" {
  _check_command_text 'x=$(pwd) && git branch -D topic'
  [ "$status" -eq 2 ]
}

@test "#502 still blocks a substituted git word" {
  _check_command_text '$(command -v git) branch -D topic'
  [ "$status" -eq 2 ]
}

@test "#502 still blocks a substituted branch word" {
  _check_command_text 'git $(echo branch) -D topic'
  [ "$status" -eq 2 ]
}

@test "#502 still blocks git -C with a substituted dir" {
  _check_command_text 'git -C "$(pwd)" branch --delete --force topic'
  [ "$status" -eq 2 ]
}

@test "#502 still blocks a rewritten flag after branch" {
  _check_command_text 'git branch ${FLAG} topic'
  [ "$status" -eq 2 ]
}
