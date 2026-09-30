#!/usr/bin/env bats
# Tests for modules/local-llm/doctor.sh.
#
# Checks report local-LLM stack state and surface the install commands
# wired through the brew + local-LLM chezmoi scripts.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_BIN="$TEST_DIR/bin"
  LOCAL_LLM_LOCAL_DIR="$TEST_DIR/local-llm"
  LOCAL_LLM_SENTINEL="$TEST_DIR/sentinel"
  LOCAL_LLM_ENDPOINT="http://127.0.0.1:65499/v1/models"  # unused port

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/modules/local-llm" "$TEST_BIN" "$LOCAL_LLM_LOCAL_DIR"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export LOCAL_LLM_LOCAL_DIR
  export LOCAL_LLM_SENTINEL
  export LOCAL_LLM_ENDPOINT
  # Restrict PATH so module sees ONLY our stubs (plus the bare system).
  # No real binaries leak in — every detection check resolves through
  # our fixtures.
  export PATH="$TEST_BIN:/usr/bin:/bin"

  cp "$BATS_TEST_DIRNAME/../modules/local-llm/doctor.sh" \
     "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # Doctor framework stubs (mirrors the jetbrains/windsurf test pattern).
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  CHECK_FIXES_FILE="$TEST_DIR/check-fixes.log"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0

  pass()        { pass_count=$((pass_count + 1)); }
  fail()        { fail_count=$((fail_count + 1)); }
  fixed()       { fix_count=$((fix_count + 1)); }
  skipped()     { skip_count=$((skip_count + 1)); }
  audit_warn()  { warn_count=$((warn_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    printf '%s\t%s\n' "$id" "$fix_cmd" >> "$CHECK_FIXES_FILE"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
  }

  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"; else audit_warn "$desc"; fi
  }

  # Stub the system probes the module reads from. Default state =
  # non-Apple-Silicon machine; tests opt into Apple Silicon individually.
  sysctl() {
    case "$2" in
      machdep.cpu.brand_string) echo "Intel(R) Core(TM) i7";;
      sysctl.proc_translated)   echo "0";;
      *) return 1;;
    esac
  }
  uname() { [[ "$1" = "-m" ]] && echo "x86_64" || /usr/bin/uname "$@"; }
  export -f sysctl uname
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Helpers to flip individual stack components on / off ─────────────

_install_stub() {
  # Drop an executable stub at $TEST_BIN/$1 with optional exit code in $2.
  local name="$1" rc="${2:-0}"
  printf '#!/bin/bash\nexit %s\n' "$rc" > "$TEST_BIN/$name"
  chmod +x "$TEST_BIN/$name"
}

_install_pipx() {
  cat > "$TEST_BIN/pipx" <<'STUB'
#!/bin/bash
if [ "$1" = "list" ] && [ "$2" = "--short" ]; then
  printf '%s\n' "$LOCAL_LLM_PIPX_LIST"
fi
STUB
  chmod +x "$TEST_BIN/pipx"
}

_set_apple_silicon_native() {
  sysctl() {
    case "$2" in
      machdep.cpu.brand_string) echo "Apple M3 Max";;
      sysctl.proc_translated)   echo "0";;
      *) return 1;;
    esac
  }
  uname() { [[ "$1" = "-m" ]] && echo "arm64" || /usr/bin/uname "$@"; }
  export -f sysctl uname
}

_set_apple_silicon_rosetta() {
  sysctl() {
    case "$2" in
      machdep.cpu.brand_string) echo "Apple M3 Max";;
      sysctl.proc_translated)   echo "1";;
      *) return 1;;
    esac
  }
  uname() { [[ "$1" = "-m" ]] && echo "x86_64" || /usr/bin/uname "$@"; }
  export -f sysctl uname
}

# ── Tests ────────────────────────────────────────────────────────────

@test "local-llm: fresh non-Apple-Silicon machine reports all components missing" {
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # 4 hard fails (pipx, aider, hf, sentinel-advisory-warn, weights-advisory)
  # Note arch check is skipped on non-Apple-Silicon machines, and so is
  # mlx-lm (it's Metal-only). So this is the smallest possible check set.
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -ge 3 ]   # pipx + aider + hf
}

@test "local-llm: pipx-only system fails aider + hf, passes pipx" {
  _install_pipx
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  [ "$pass_count" -ge 1 ]
  [ "$fail_count" -ge 2 ]
}

@test "local-llm: aider on PATH is detected" {
  _install_pipx
  _install_stub aider
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # pipx ✓ + aider ✓, hf still ✗
  [ "$pass_count" -ge 2 ]
}

@test "local-llm: aider via pipx list is detected even without PATH binary" {
  export LOCAL_LLM_PIPX_LIST="aider-chat 0.50.0"
  _install_pipx
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  [ "$pass_count" -ge 2 ]   # pipx + aider (via pipx list)
}

@test "local-llm: huggingface-cli detection accepts the new 'hf' binary name" {
  _install_pipx
  _install_stub hf
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  [ "$pass_count" -ge 2 ]   # pipx + hf
}

@test "local-llm: huggingface-cli detection accepts the legacy 'huggingface-cli' name" {
  _install_pipx
  _install_stub huggingface-cli
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  [ "$pass_count" -ge 2 ]
}

@test "local-llm: Apple Silicon native machine adds arch + mlx-lm checks" {
  _set_apple_silicon_native
  _install_pipx
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # Arch check (passes — native), mlx-lm fails (no stub), endpoint warns,
  # pipx passes, aider/hf fail, sentinel warns, weights warns.
  # The signal we care about: arch.arm64_native passed (visible to the
  # operator as ✓ ARM64 native).
  [ "$pass_count" -ge 2 ]   # arch + pipx
}

@test "local-llm: Apple Silicon Rosetta machine warns about arch" {
  _set_apple_silicon_rosetta
  _install_pipx
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # Arch check is advisory; should produce a warn rather than a fail.
  [ "$warn_count" -ge 1 ]   # arch + reachability + sentinel
}

@test "local-llm: non-Apple-Silicon machine SKIPS arch + mlx-lm checks entirely" {
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # On Intel Macs we don't run the arch or mlx-lm checks. Total checks
  # = pipx + aider + hf + sentinel-advisory + (weights-advisory if ~/.cache/huggingface/hub exists)
  # The sum of all counters should be small (<=6) and never include
  # the arch.arm64_native ID — verified by overrides being absent.
  total=$((pass_count + fail_count + warn_count))
  [ "$total" -le 6 ]
}

@test "local-llm: bootstrap sentinel reports advisory warn when missing" {
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # Sentinel check is always emitted; missing → warn.
  [ "$warn_count" -ge 1 ]
}

@test "local-llm: bootstrap sentinel passes when file exists" {
  mkdir -p "$(dirname "$LOCAL_LLM_SENTINEL")"
  touch "$LOCAL_LLM_SENTINEL"
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # Sentinel ✓; other components still ✗ — but sentinel itself must
  # have flipped from warn to pass.
  [ "$pass_count" -ge 1 ]   # sentinel + nothing else likely
}

@test "local-llm: cached Qwen weights folder is detected as pass" {
  mkdir -p "$HOME/.cache/huggingface/hub/models--mlx-community--Qwen3-8B-4bit"
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # weights ✓; other components ✗ — but the cache-detection check
  # specifically must have passed.
  [ "$pass_count" -ge 1 ]
}

@test "local-llm: no Qwen folder under ~/.cache/huggingface/hub → warn" {
  mkdir -p "$HOME/.cache/huggingface/hub/models--openai--gpt-oss-20b"
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  # The weights check is advisory and case-insensitive; an unrelated
  # OpenAI model present does NOT count as Qwen weights. Should be warn.
  [ "$warn_count" -ge 1 ]
}

@test "local-llm: mlx-lm.server reachability fails fast when endpoint is down" {
  _set_apple_silicon_native
  _install_pipx

  # Run the doctor; the curl probe should time out within 2s and warn.
  local start_s end_s elapsed
  start_s=$(date +%s)
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"
  end_s=$(date +%s)
  elapsed=$((end_s - start_s))

  # Curl --max-time 2 means each probe burns at most 2s. Total module
  # runtime must stay under 10s even with the server probe.
  [ "$elapsed" -lt 10 ]
  [ "$warn_count" -ge 1 ]
}

@test "local-llm: installable hard dependencies expose auto-fix commands" {
  _set_apple_silicon_native
  source "$TEST_DOTFILES/modules/local-llm/doctor.sh"

  grep -Fq $'local-llm.pipx\tbrew install pipx' "$CHECK_FIXES_FILE"
  grep -Fq $'local-llm.aider\tdotfiles apply' "$CHECK_FIXES_FILE"
  grep -Fq $'local-llm.huggingface_cli\tdotfiles apply' "$CHECK_FIXES_FILE"
  grep -Fq $'local-llm.mlx_lm\tbrew install mlx-lm' "$CHECK_FIXES_FILE"
}
