#!/usr/bin/env bats

load test_helper

@test "dotfiles_agent_path_prefix includes fnm node before dotfiles bin" {
  mkdir -p "$TEST_DOTFILES/bin" "$TEST_HOME/.local/share/fnm/node-versions/v22.22.0/installation/bin"
  echo "v22.22.0" > "$TEST_HOME/.node-version"
  run bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_agent_path_prefix '$TEST_DOTFILES' '$TEST_HOME'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node-versions/v22.22.0/installation/bin"* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
  node_pos="${output%%:*}"
  [[ "$node_pos" == *"fnm"* ]]
}

@test "dotfiles-agent-session-env.py builds PATH with prefix" {
  mkdir -p "$TEST_DOTFILES/bin"
  run python3 ./lib/dotfiles-agent-session-env.py "$TEST_DOTFILES" "$TEST_HOME" "$TEST_DOTFILES/bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"PATH"'* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
}

@test "corporate Node CA falls back to the local combined bundle" {
  mkdir -p "$TEST_HOME/.config/ssl"
  touch "$TEST_HOME/.config/ssl/corporate-combined-ca.pem" "$TEST_HOME/.config/ssl/macos-trust-bundle.pem"
  run bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_corporate_node_ca '$TEST_HOME'"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/.config/ssl/corporate-combined-ca.pem" ]
}

@test "dotfiles-agent-session-env.py sets NODE_EXTRA_CA_CERTS from the local bundle" {
  mkdir -p "$TEST_DOTFILES/bin" "$TEST_HOME/.config/ssl"
  touch "$TEST_HOME/.config/ssl/macos-trust-bundle.pem"
  run env -u NODE_EXTRA_CA_CERTS python3 ./lib/dotfiles-agent-session-env.py "$TEST_DOTFILES" "$TEST_HOME" "$TEST_DOTFILES/bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"NODE_EXTRA_CA_CERTS\": \"$TEST_HOME/.config/ssl/macos-trust-bundle.pem\""* ]]
}

@test "corporate Node CA reports nothing when no bundle exists" {
  run bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_corporate_node_ca '$TEST_HOME'"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "corporate Node CA prefers DOTFILES_CORPORATE_CA_BUNDLES entries" {
  mkdir -p "$TEST_HOME/.config/ssl"
  touch "$TEST_HOME/extra-ca.pem" "$TEST_HOME/.config/ssl/macos-trust-bundle.pem"
  DOTFILES_CORPORATE_CA_BUNDLES="$TEST_HOME/missing.pem:$TEST_HOME/extra-ca.pem" \
    run bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_corporate_node_ca '$TEST_HOME'"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/extra-ca.pem" ]
}

@test "dotfiles_managed_endpoint is false by default" {
  run env -u DOTFILES_MANAGED_ENDPOINT -u DOTFILES_ENDPOINT_AGENT_APPS bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_managed_endpoint"
  [ "$status" -eq 1 ]
}

@test "dotfiles_managed_endpoint is true with DOTFILES_MANAGED_ENDPOINT=1" {
  run env DOTFILES_MANAGED_ENDPOINT=1 bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_managed_endpoint"
  [ "$status" -eq 0 ]
}

@test "dotfiles_managed_endpoint is true when a listed app path exists" {
  mkdir -p "$TEST_HOME/Apps/Agent.app"
  run env -u DOTFILES_MANAGED_ENDPOINT DOTFILES_ENDPOINT_AGENT_APPS="$TEST_HOME/Apps/None.app:$TEST_HOME/Apps/Agent.app" \
    bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_managed_endpoint"
  [ "$status" -eq 0 ]
}

@test "dotfiles_managed_endpoint is false when no listed app path exists" {
  run env -u DOTFILES_MANAGED_ENDPOINT DOTFILES_ENDPOINT_AGENT_APPS="$TEST_HOME/Apps/None.app:$TEST_HOME/Apps/Other.app" \
    bash -c "source ./lib/dotfiles-endpoint-paths.sh; dotfiles_managed_endpoint"
  [ "$status" -eq 1 ]
}
