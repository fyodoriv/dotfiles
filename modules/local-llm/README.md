# `local-llm` doctor module

Detects the local-LLM stack that Minsky and other agent loops fall
back to when claude-code tokens are exhausted. Install paths live in
the brew + local-LLM chezmoi scripts.

Each check is one of:

| State | Meaning |
|-------|---------|
| ✓ | present + working |
| ✗ | missing — operator should install |
| ⚠ | present but stale / wrong-arch / endpoint unreachable — advisory |

## Checks emitted

| ID | What it probes |
|----|-----------------|
| `local-llm.arch.arm64_native` | (Apple Silicon machines only) shell is running native arm64, not under x86_64 Rosetta. mlx-lm requires native arm64. |
| `local-llm.pipx` | `pipx` on `PATH`. Backbone for `aider-chat` + `huggingface_hub[cli]`. |
| `local-llm.aider` | `aider` binary on `PATH`, or `aider-chat` listed by `pipx list --short`. |
| `local-llm.huggingface_cli` | `hf` (new name in `huggingface-hub ≥0.23`) OR `huggingface-cli` (legacy) on `PATH`. |
| `local-llm.mlx_lm` | (Apple Silicon only) `mlx_lm.server` console script on `PATH`. |
| `local-llm.server.reachable` | (Apple Silicon only, advisory) HTTP GET on `$LOCAL_LLM_ENDPOINT` (default `http://127.0.0.1:8080/v1/models`) returns 2xx within 2s. |
| `local-llm.bootstrap.sentinel` | (advisory) operator opt-in sentinel at `~/.config/dotfiles/.local-llm-bootstrap-confirmed`. Absence is the DEFAULT; create it to allow the ~30 GB model download. |
| `local-llm.model.weights_cached` | (advisory) any `models--*qwen*` folder under `~/.cache/huggingface/hub/`. |

Non-Apple-Silicon machines (Intel Macs, Linux without arm64) skip
the arch + mlx-lm + reachability checks entirely — mlx-lm is
Metal-only.

## Environment overrides

All paths are configurable for testing / multi-machine use:

| Variable | Default |
|----------|---------|
| `LOCAL_LLM_LOCAL_DIR` | `~/.local/share/dotfiles-local-llm` |
| `LOCAL_LLM_SENTINEL` | `~/.config/dotfiles/.local-llm-bootstrap-confirmed` |
| `LOCAL_LLM_ENDPOINT` | `http://127.0.0.1:8080/v1/models` |
| `LOCAL_LLM_MODEL_REPO` | `Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit` |

## Install path

The small dependencies are self-healing; the ~30 GB model weights
download still requires explicit operator opt-in.

- `.chezmoiscripts/run_onchange_brew.sh.tmpl` installs `pipx` and,
  when `use_local_ai: true` on native Apple Silicon, `mlx-lm`.
- `.chezmoiscripts/run_after_install_local_llm.sh.tmpl` installs
  `huggingface_hub[cli]` and `aider-chat` with uv-managed Python
  3.13, then downloads model weights only when the sentinel exists.
- `docs/local-llm.md` is the operator-facing runbook.

## Manual equivalent commands

```bash
# 1. pipx (already on the Brewfile, should be ✓ out of the box)
brew install pipx

# 2. aider (uses claude/openai/local — local-LLM-compatible)
pipx install aider-chat

# 3. huggingface CLI (for model downloads)
pipx install 'huggingface_hub[cli]'

# 4. mlx-lm (Apple Silicon ONLY — run under arch -arm64 if shell is Rosetta)
arch -arm64 brew install mlx-lm

# 5. Download model weights (~30 GB, ~30 min on a fast link)
hf download Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit

# 6. Start the server (background, OpenAI-compatible at :8080)
arch -arm64 mlx_lm.server \
  --model Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit \
  --port 8080 &
```

Re-run `dotfiles-doctor --module local-llm` after each step to watch
the state flip.

## Coordination with Minsky

Minsky's local-LLM bootstrap path should detect-and-prompt only — the
actual install code lives in this dotfiles module. The boundary is
documented in `AGENTS.md`
Ownership Boundary table: system-level Python tooling + brew
packages + `~/Library` agents are dotfiles' concern; Minsky just
detects whether the stack is healthy and prompts the operator to
run `dotfiles apply` when it isn't.

## Tests

`tests/module-local-llm.bats` — 15 cases covering each detection
branch: fresh machine, pipx-only, aider via PATH, aider via pipx
list, hf (new) vs huggingface-cli (legacy), Apple Silicon native /
Rosetta / non-Apple-Silicon arch detection, sentinel present /
missing, Qwen weights cached / not, server reachability timeout, and
doctor auto-fix command surfacing.
