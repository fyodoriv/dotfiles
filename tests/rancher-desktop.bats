#!/usr/bin/env bats
# Tests for rancher-desktop startup script

load test_helper

RANCHER_CMD="$BATS_TEST_DIRNAME/../bin/rancher-desktop"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  STUB_DIR="$TEST_DIR/stubs"
  mkdir -p "$TEST_HOME/.rd/bin" "$STUB_DIR"

  export ORIG_HOME="$HOME"
  export HOME="$TEST_HOME"
  export PATH="$STUB_DIR:$PATH"

  # Docker API answers whenever the socket exists, unless a test overrides it.
  cat > "$STUB_DIR/curl" << 'STUB'
#!/bin/bash
[ -S "$HOME/.rd/docker.sock" ]
STUB
  chmod +x "$STUB_DIR/curl"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

# ── Static analysis ──

@test "rancher-desktop script exists and is executable" {
  [ -f "$RANCHER_CMD" ]
  [ -x "$RANCHER_CMD" ]
}

@test "rancher-desktop script has correct shebang" {
  head -1 "$RANCHER_CMD" | grep -q '#!/bin/bash'
}

@test "rancher-desktop script uses strict mode" {
  grep -q 'set -euo pipefail' "$RANCHER_CMD"
}

@test "rancher-desktop checks for rdctl binary" {
  grep -q 'RDCTL=.*rdctl' "$RANCHER_CMD"
  grep -q '! -x.*RDCTL' "$RANCHER_CMD"
}

@test "rancher-desktop exits 1 when rdctl is missing" {
  # Script checks [ ! -x "$RDCTL" ] and exits 1
  grep -q 'exit 1' "$RANCHER_CMD"
  grep -q 'is Rancher Desktop installed' "$RANCHER_CMD"
}

@test "rancher-desktop waits for the Docker API, not only the socket file" {
  grep -q 'SOCKET=.*docker.sock' "$RANCHER_CMD"
  grep -q 'unix-socket "\$SOCKET" http://localhost/_ping' "$RANCHER_CMD"
  grep -q 'while ! docker_ready' "$RANCHER_CMD"
}

@test "rancher-desktop has a timeout for socket wait" {
  grep -q 'TIMEOUT=' "$RANCHER_CMD"
  grep -q 'elapsed.*-ge.*TIMEOUT' "$RANCHER_CMD"
}

@test "rancher-desktop starts in background mode" {
  grep -q 'start --application.start-in-background' "$RANCHER_CMD"
}

@test "rancher-desktop reports elapsed time on success" {
  grep -q 'Docker socket ready after' "$RANCHER_CMD"
}

# ── Functional: rdctl missing ──

@test "exits 1 with error when rdctl binary is missing" {
  # Don't create rdctl at all
  rm -f "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rdctl not found"* ]]
  [[ "$output" == *"is Rancher Desktop installed"* ]]
}

@test "exits 1 when rdctl exists but is not executable" {
  touch "$TEST_HOME/.rd/bin/rdctl"
  chmod -x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rdctl not found"* ]]
}

# ── Functional: --help ──

@test "--help shows usage and exits 0" {
  run bash "$RANCHER_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rancher Desktop"* ]] || [[ "$output" == *"Docker socket"* ]]
}

# ── Functional: socket ready immediately ──

@test "succeeds when Docker socket exists before start" {
  # Create rdctl stub that creates the socket immediately
  cat > "$TEST_HOME/.rd/bin/rdctl" << 'STUB'
#!/bin/bash
# Create a Unix socket at the expected path
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock_path = os.path.expanduser('~/.rd/docker.sock')
os.makedirs(os.path.dirname(sock_path), exist_ok=True)
s.bind(sock_path)
s.listen(1)
" &
for _i in $(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker socket ready after"* ]]
}

@test "reports 0s elapsed when socket appears immediately" {
  # Pre-create the socket so it exists before the while loop runs
  python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock_path = os.path.expanduser('~/.rd/docker.sock')
os.makedirs(os.path.dirname(sock_path), exist_ok=True)
s.bind(sock_path)
s.listen(1)
" &
  local socket_pid=$!
  # Wait until the socket file is actually present
  while [ ! -S "$TEST_HOME/.rd/docker.sock" ]; do sleep 0.01; done

  # rdctl stub: no-op since socket already exists
  cat > "$TEST_HOME/.rd/bin/rdctl" << 'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  kill "$socket_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker socket ready after 0s"* ]]
}

# ── Functional: rdctl start called ──

@test "calls rdctl start with background flag" {
  # rdctl that logs the command and creates socket
  cat > "$TEST_HOME/.rd/bin/rdctl" << STUB
#!/bin/bash
echo "\$*" >> "$TEST_DIR/rdctl.log"
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock_path = os.path.expanduser('~/.rd/docker.sock')
os.makedirs(os.path.dirname(sock_path), exist_ok=True)
s.bind(sock_path)
s.listen(1)
" &
for _i in \$(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  bash "$RANCHER_CMD"

  [ -f "$TEST_DIR/rdctl.log" ]
  grep -q "start --application.start-in-background" "$TEST_DIR/rdctl.log"
}

# ── Functional: timeout behavior ──

@test "times out when socket never appears" {
  # rdctl that does nothing (no socket created)
  cat > "$TEST_HOME/.rd/bin/rdctl" << 'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  # Override TIMEOUT to 2s to make test fast
  # We modify the script inline via env — but since the script hardcodes TIMEOUT,
  # we need to use sed to create a modified copy
  local test_script="$TEST_DIR/rancher-desktop-fast"
  sed 's/TIMEOUT=120/TIMEOUT=2/' "$RANCHER_CMD" > "$test_script"
  chmod +x "$test_script"

  run bash "$test_script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timed out"* ]]
  [[ "$output" == *"Docker socket"* ]]
}

@test "timeout error goes to stderr" {
  cat > "$TEST_HOME/.rd/bin/rdctl" << 'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  local test_script="$TEST_DIR/rancher-desktop-fast"
  sed 's/TIMEOUT=120/TIMEOUT=2/' "$RANCHER_CMD" > "$test_script"
  chmod +x "$test_script"

  # Capture stderr separately
  run bash -c "bash '$test_script' 2>'$TEST_DIR/stderr.txt'"
  # Verify timeout message went to stderr
  [ -f "$TEST_DIR/stderr.txt" ]
  grep -q "Timed out" "$TEST_DIR/stderr.txt"
}

# ── Functional: dead engine behind a live socket ──

@test "restarts Rancher Desktop once when the socket exists but Docker does not answer" {
  python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(os.path.expanduser('~/.rd/docker.sock'))
s.listen(1)
import time; time.sleep(30)
" &
  local socket_pid=$!
  while [ ! -S "$TEST_HOME/.rd/docker.sock" ]; do sleep 0.01; done

  printf '#!/bin/bash\nexit 7\n' > "$STUB_DIR/curl"
  chmod +x "$STUB_DIR/curl"
  cat > "$TEST_HOME/.rd/bin/rdctl" << STUB
#!/bin/bash
echo "\$*" >> "$TEST_DIR/rdctl.log"
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  local test_script="$TEST_DIR/rancher-desktop-fast"
  sed 's/TIMEOUT=120/TIMEOUT=2/' "$RANCHER_CMD" > "$test_script"

  run bash "$test_script"
  kill "$socket_pid" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"restarting Rancher Desktop once"* ]]
  [ "$(grep -c '^start --application.start-in-background' "$TEST_DIR/rdctl.log")" -eq 2 ]
  grep -qx 'shutdown' "$TEST_DIR/rdctl.log"
}

# ── Functional: Kubernetes guard ──

@test "disables Kubernetes when Rancher Desktop has it enabled" {
  cat > "$TEST_HOME/.rd/bin/rdctl" << STUB
#!/bin/bash
echo "\$*" >> "$TEST_DIR/rdctl.log"
case "\$1" in
  list-settings) echo '{"kubernetes":{"enabled":true}}' ;;
  start) python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(os.path.expanduser('~/.rd/docker.sock'))
s.listen(1)
import time; time.sleep(5)
" & for _i in \$(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done ;;
esac
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 0 ]
  grep -qx 'set --kubernetes.enabled=false' "$TEST_DIR/rdctl.log"
}

@test "switches PATH management from rcfiles to manual" {
  cat > "$TEST_HOME/.rd/bin/rdctl" << STUB
#!/bin/bash
echo "\$*" >> "$TEST_DIR/rdctl.log"
case "\$1" in
  list-settings) echo '{"application":{"pathManagementStrategy":"rcfiles"},"kubernetes":{"enabled":false}}' ;;
  start) python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(os.path.expanduser('~/.rd/docker.sock'))
s.listen(1)
import time; time.sleep(5)
" & for _i in \$(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done ;;
esac
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 0 ]
  grep -qx 'set --application.path-management-strategy manual' "$TEST_DIR/rdctl.log"
  ! grep -q 'kubernetes.enabled=false' "$TEST_DIR/rdctl.log"
}

@test "keeps Kubernetes when DOTFILES_RANCHER_KUBERNETES=1" {
  cat > "$TEST_HOME/.rd/bin/rdctl" << STUB
#!/bin/bash
echo "\$*" >> "$TEST_DIR/rdctl.log"
case "\$1" in
  list-settings) echo '{"kubernetes":{"enabled":true}}' ;;
  start) python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(os.path.expanduser('~/.rd/docker.sock'))
s.listen(1)
import time; time.sleep(5)
" & for _i in \$(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done ;;
esac
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  DOTFILES_RANCHER_KUBERNETES=1 run bash "$RANCHER_CMD"
  [ "$status" -eq 0 ]
  ! grep -q 'kubernetes.enabled=false' "$TEST_DIR/rdctl.log"
}

# ── Functional: output messages ──

@test "shows waiting message with socket path" {
  cat > "$TEST_HOME/.rd/bin/rdctl" << 'STUB'
#!/bin/bash
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock_path = os.path.expanduser('~/.rd/docker.sock')
os.makedirs(os.path.dirname(sock_path), exist_ok=True)
s.bind(sock_path)
s.listen(1)
" &
for _i in $(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Waiting for Docker socket"* ]]
  [[ "$output" == *"docker.sock"* ]]
}

@test "shows timeout value in waiting message" {
  cat > "$TEST_HOME/.rd/bin/rdctl" << 'STUB'
#!/bin/bash
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock_path = os.path.expanduser('~/.rd/docker.sock')
os.makedirs(os.path.dirname(sock_path), exist_ok=True)
s.bind(sock_path)
s.listen(1)
" &
for _i in $(seq 1 50); do [ -S ~/.rd/docker.sock ] && break; sleep 0.01; done
STUB
  chmod +x "$TEST_HOME/.rd/bin/rdctl"

  run bash "$RANCHER_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"timeout 120s"* ]]
}
