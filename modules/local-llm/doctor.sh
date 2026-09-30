#!/bin/bash
# Doctor checks for the local-llm module.
#
# Detects the local-LLM stack that Minsky and other agent loops fall
# back to when claude-code tokens are exhausted: pipx, mlx-lm, aider,
# huggingface-cli, the mlx-lm.server endpoint, and Apple Silicon arch
# handling. Install paths live in the brew + local-LLM chezmoi scripts.
#
# See: docs/local-llm.md and Minsky README → "auto-bootstrap pre-flight"
#
# Each check has three terminal states:
#   ✓  pass — present + working
#   ✗  fail — missing
#   ⚠  warn (via check_advisory) — present but stale / wrong-arch /
#      unreachable. Advisory because the operator may have deliberately
#      not installed it (e.g. on a non-Apple-Silicon machine).
#
# The ~30 GB model weights download is gated by explicit operator opt-in
# (sentinel file at ~/.config/dotfiles/.local-llm-bootstrap-confirmed).

_LL_LOCAL="${LOCAL_LLM_LOCAL_DIR:-$HOME/.local/share/dotfiles-local-llm}"
_LL_SENTINEL="${LOCAL_LLM_SENTINEL:-$HOME/.config/dotfiles/.local-llm-bootstrap-confirmed}"
_LL_ENDPOINT="${LOCAL_LLM_ENDPOINT:-http://127.0.0.1:8080/v1/models}"
_LL_MODEL_REPO="${LOCAL_LLM_MODEL_REPO:-Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit}"

# ── Apple Silicon arch (advisory) ────────────────────────────────────
# mlx-lm requires native arm64 (Metal). If the operator is on an
# Apple Silicon machine but running under x86_64 Rosetta, mlx-lm
# install via brew will silently install the wrong arch and fail at
# import time. Warn rather than fail because a non-AS machine is a
# legitimate "no local LLM" state.
_ll_is_apple_silicon_native() {
  local cpu_brand uname_m proc_translated
  cpu_brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")"
  uname_m="$(uname -m 2>/dev/null || echo "")"
  proc_translated="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo "")"
  # Native arm64: uname=arm64 AND not under Rosetta.
  [[ "$uname_m" = "arm64" ]] && [[ "$proc_translated" != "1" ]]
}
_ll_is_apple_silicon_machine() {
  local cpu_brand
  cpu_brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")"
  [[ "$cpu_brand" == "Apple "* ]]
}

if _ll_is_apple_silicon_machine; then
  check_advisory "local-llm.arch.arm64_native" \
    "shell is running native arm64 (mlx-lm requires it)" \
    "_ll_is_apple_silicon_native" \
    "Open Terminal in 'Open in Rosetta' OFF mode, or invoke arch -arm64 zsh; see docs/local-llm.md."
fi

# ── pipx (the install backbone for aider + huggingface_hub[cli]) ────
check "local-llm.pipx" \
  "pipx installed" \
  "command -v pipx >/dev/null 2>&1" \
  "brew install pipx"

# ── aider (the editor agent) ─────────────────────────────────────────
# pipx-managed; check both the `aider` binary on PATH and the pipx
# venv presence. Either is sufficient.
_ll_check_aider() {
  command -v aider >/dev/null 2>&1 && return 0
  command -v pipx >/dev/null 2>&1 \
    && pipx list --short 2>/dev/null | grep -q '^aider-chat\b'
}
check "local-llm.aider" \
  "aider installed (pipx aider-chat)" \
  "_ll_check_aider" \
  "dotfiles apply"

# ── huggingface CLI (model download) ─────────────────────────────────
# Renamed from `huggingface-cli` to `hf` in huggingface-hub >=0.23.
# Accept either binary name; both ship from the same `huggingface_hub`
# wheel.
_ll_check_hf_cli() {
  command -v hf >/dev/null 2>&1 \
    || command -v huggingface-cli >/dev/null 2>&1
}
check "local-llm.huggingface_cli" \
  "huggingface CLI installed (hf or huggingface-cli)" \
  "_ll_check_hf_cli" \
  "dotfiles apply"

# ── mlx-lm (the inference engine) ────────────────────────────────────
# Skip on non-Apple-Silicon machines — mlx is Metal-only.
if _ll_is_apple_silicon_machine; then
  _ll_check_mlx_lm() {
    command -v mlx_lm.server >/dev/null 2>&1 && return 0
    # mlx-lm may be installed as a brew formula or via pipx; either
    # exposes the `mlx_lm.server` console script on PATH.
    return 1
  }
  check "local-llm.mlx_lm" \
    "mlx-lm installed (mlx_lm.server on PATH)" \
    "_ll_check_mlx_lm" \
    "brew install mlx-lm"

  # mlx-lm.server reachability — advisory because the server isn't
  # expected to always be running; the bootstrap script starts it
  # on-demand. Reaching the endpoint is just a "is the local LLM
  # ready for inference RIGHT NOW" signal.
  check_advisory "local-llm.server.reachable" \
    "mlx-lm.server reachable at $_LL_ENDPOINT" \
    "curl -fsS --max-time 2 '$_LL_ENDPOINT' >/dev/null 2>&1" \
    "Start with: arch -arm64 mlx_lm.server --model $_LL_MODEL_REPO --port 8080. See docs/local-llm.md."
fi

# ── Bootstrap sentinel (operator opt-in for model-weights download) ──
# The operator creates the sentinel before `run_after_install_local_llm.sh`
# is allowed to start the ~30 GB download. Until it exists, the doctor
# reports `?` advisory rather than `✗`: a missing sentinel is the
# DEFAULT, not an error.
check_advisory "local-llm.bootstrap.sentinel" \
  "local-LLM bootstrap confirmed by operator (sentinel at ~/.config/dotfiles/.local-llm-bootstrap-confirmed)" \
  "[ -f '$_LL_SENTINEL' ]" \
  "To opt into the ~30 GB model download: mkdir -p ~/.config/dotfiles && touch ~/.config/dotfiles/.local-llm-bootstrap-confirmed && dotfiles apply"

# ── Model weights present (best-effort) ──────────────────────────────
# Probe the huggingface cache for the configured model. Advisory:
# the model may live elsewhere if the operator overrode HF_HOME.
if [ -d "$HOME/.cache/huggingface/hub" ]; then
  _ll_model_slug="$(printf '%s' "$_LL_MODEL_REPO" | tr '/' '-' | tr '[:upper:]' '[:lower:]')"
  check_advisory "local-llm.model.weights_cached" \
    "$_LL_MODEL_REPO weights cached at ~/.cache/huggingface/hub" \
    "find '$HOME/.cache/huggingface/hub' -maxdepth 1 -type d -iname 'models--*qwen*' 2>/dev/null | grep -q ." \
    "Download with: touch ~/.config/dotfiles/.local-llm-bootstrap-confirmed && dotfiles apply. ~30 GB. See docs/local-llm.md."
fi
