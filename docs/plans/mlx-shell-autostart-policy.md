# Start MLX only when the shell and package are eligible

[Issue #639](https://github.com/fyodoriv/dotfiles/issues/639) reports
repeated MLX starts from interactive shells on a managed Mac. An open
local port currently decides whether to start. The startup does not
first check endpoint policy or the selected Python installation.

- **Hypothesis**: Read the shell startup setting and endpoint policy
  before probing the local service. Use the installed package entry
  point only when its package files are present.
- **Measurement**: Run hosted Bats in a disposable home with a real
  interactive zsh and inert curl, MLX, uv and Python commands. Exercise
  managed, hardened, disabled, absent, stale, ready-service and
  valid cold-start cases. Render both setting values. Read the local
  LLM Doctor result for an eligible shell with a missing package.
- **Success**: 0 Python/uv or MLX commands in the managed, hardened,
  disabled, absent and stale cases. 0 starts when the service is already
  ready. One valid cold start uses the package entry point and preserves
  the loopback address and port. One advisory names the missing package.
- **Pivot**: Any prohibited process or service probe, a wrong startup
  destination, a second recorded cold-start call in its fixture,
  or a missed readiness advisory rejects the candidate.
- **Anchor**: Issue #639 and the
  [upstream MLX package entry point](https://github.com/ml-explore/mlx-lm/blob/main/pyproject.toml).

Use the existing endpoint configuration and operator policy. A shell
startup override for CPU architecture must not override endpoint policy.
The fixtures start no real inference server and download no weights.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44881105374/job/136776356487)
recorded curl, uv and Python calls in the hardened case. The managed,
disabled, missing-package and installed-package entry point controls
also failed. The already-ready service case passed.
