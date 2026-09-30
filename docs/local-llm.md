# Local-LLM Stack

A self-hosted code-LLM fallback so Minsky (and any other agent loop)
can keep working when claude-code tokens are exhausted, rate-limited,
or the operator wants zero cloud-side traffic for a session.

## What it gives you

| Component | Purpose |
|---|---|
| **pipx** | Sandboxed Python tool installs (huggingface CLI, aider) |
| **`huggingface_hub[cli]`** | `hf download <repo>` — fetches model weights |
| **`aider-chat`** | Terminal-driven coding agent that can talk to any OpenAI-compatible endpoint (including local mlx-lm) |
| **`mlx-lm`** (Apple Silicon only) | Metal-accelerated inference engine; ships `mlx_lm.server` (OpenAI-compatible) |
| **Model weights** | `Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit` (~30 GB) by default; override via `$LOCAL_LLM_MODEL_REPO` |

`dotfiles-doctor --module local-llm` reports the current state of
every piece; this doc covers when and how to install them.

## When to enable

Enable if any of the following apply:

- You hit Claude rate limits regularly and want a same-host fallback.
- Your workflow tolerates 30B-class code completion (Qwen3-Coder-30B
  is the default; lighter and heavier models work via the env var).
- You have ≥ 64 GB unified memory and an Apple Silicon Mac.
  mlx-lm requires native arm64 — the chezmoi script skips cleanly on
  x86 Macs and Linux, so opting in there only installs pipx + aider.
- You want Minsky's auto-bootstrap pre-flight to succeed without
  asking you to install anything mid-session.

Skip if you have none of the above. The stack costs ~30 GB on disk
when fully bootstrapped and runs no background services (the server
starts on demand).

## How to enable

Two opt-ins, by design — the pipx step is cheap (~50 MB), the model
download is the big commitment.

### Opt-in 1: `use_local_ai` chezmoi data flag

Set during `chezmoi init` or by editing `~/.config/chezmoi/chezmoi.yaml`:

```yaml
data:
  use_local_ai: true
```

Then re-apply:

```bash
dotfiles apply
```

After this:

- `brew bundle` installs `pipx` (always — small, broadly useful).
- On native Apple Silicon (`uname -m = arm64` and not under Rosetta),
  `brew install mlx-lm` runs.
- `run_after_install_local_llm.sh` does `pipx install huggingface_hub[cli]`
  and `pipx install aider-chat` (both via uv-managed python 3.13 — never
  Homebrew or python.org python; see dotfiles rule #10).
- The model download is still gated behind the sentinel below.

### Opt-in 2: Sentinel file (model download)

The ~30 GB model download is gated separately so you can install the
runtime first, decide later. When ready:

```bash
mkdir -p ~/.config/dotfiles
touch ~/.config/dotfiles/.local-llm-bootstrap-confirmed
dotfiles apply
```

The chezmoi script then runs `hf download $LOCAL_LLM_MODEL_REPO`
(resumable — interrupt + re-run is safe). On completion the weights
live at `~/.cache/huggingface/hub/models--Qwen--Qwen3-Coder-30B...`.
Subsequent `dotfiles apply` runs skip the download when that cache
directory already exists.

To use a different model, set the env var before applying:

```bash
LOCAL_LLM_MODEL_REPO=mlx-community/Qwen3-Coder-14B-A1.5B-Instruct-MLX-4bit dotfiles apply
```

## Running the server

After bootstrap, start the mlx-lm server on demand:

```bash
arch -arm64 mlx_lm.server \
  --model "$LOCAL_LLM_MODEL_REPO" \
  --port 8080
```

`arch -arm64` is belt-and-braces — mlx-lm only loads under native arm64,
and the explicit prefix surfaces a clear error if the shell happens to
be running under Rosetta.

Probe reachability:

```bash
curl -s http://127.0.0.1:8080/v1/models | jq .
```

`dotfiles-doctor --module local-llm` does this for you and reports
`local-llm.server.reachable` as ✓ when the endpoint responds.

## Integrating with aider

```bash
aider \
  --openai-api-base http://127.0.0.1:8080/v1 \
  --openai-api-key NONE \
  --model openai/$LOCAL_LLM_MODEL_REPO
```

Or pin in `~/.aider.conf.yml`:

```yaml
openai-api-base: http://127.0.0.1:8080/v1
openai-api-key: NONE
model: openai/Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit
```

## Composition with Minsky

Minsky's `--local` mode + `~/.minsky/config.json` `local_agent: aider`
pointing at this stack is the supported flow. The pre-flight in
`novel/tick-loop/src/local-llm-bootstrap.ts` defers to dotfiles for
install and only handles the "is the server running right now" check
itself. Minsky's bootstrap should stay detect-and-prompt only.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---|---|---|
| `mlx_lm.server: command not found` after `dotfiles apply` | Not native arm64 | `arch -arm64 zsh` then re-run; or accept that mlx-lm is Apple-Silicon-only and use a remote endpoint instead. |
| `pipx install --python <uv-python> aider-chat` fails | uv python 3.13 not installed | `uv python install 3.13`, then re-run `dotfiles apply` |
| `hf download` hangs | Slow HF mirror or network | Resume-safe — kill + re-run. To use a mirror, set `HF_ENDPOINT=https://hf-mirror.com` |
| pipx venv shows `Python.framework` in `pyvenv.cfg` | Old pipx install used Homebrew python | `pipx uninstall <pkg> && pipx install --python "$(uv python find 3.13)" <pkg>` |
| Model loaded but inference is 5 tokens/sec | Wrong quantisation for your RAM | Switch to a smaller 4-bit model or upgrade hardware. 30B-A3B fits comfortably on 64 GB; tight on 32 GB. |
| `dotfiles-doctor --module local-llm` shows `✗ local-llm.aider` after install | pipx PATH not picked up by current shell | `exec zsh` or open a new terminal |

## Reversal

To remove the stack without uninstalling dotfiles:

```bash
# Disable the data flag
chezmoi data use_local_ai=false   # or edit ~/.config/chezmoi/chezmoi.yaml

# Remove the sentinel
rm -f ~/.config/dotfiles/.local-llm-bootstrap-confirmed

# Uninstall the pipx packages
pipx uninstall aider-chat
pipx uninstall huggingface_hub

# Uninstall mlx-lm (Apple Silicon)
brew uninstall mlx-lm

# Free the model weights (~30 GB)
rm -rf ~/.cache/huggingface/hub/models--*Qwen*
```

`pipx` itself stays (it's broadly useful beyond this stack).
