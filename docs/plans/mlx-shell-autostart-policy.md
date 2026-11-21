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

## Check the launcher interpreter and keep startup offline

- **Hypothesis**: A stale interpreter or a package for a different
  Python version leaves the startup idle. With no usable local
  model, an eligible cold shell also leaves the server alone.
- **Measurement**: Run the hosted shell controls with an installed
  entry point and each missing or mismatched file. Use a recognized
  virtual environment, a local model, and a cached revision fixture
  with an inert launcher. Record the model argument and offline value.
- **Success**: 0 service probes for the two broken launchers.
  An eligible cold shell without weights makes 0 launch calls. Each
  offline positive case starts once with a local model path.
- **Pivot**: Any startup with a broken launcher or missing weights,
  any direct remote model argument, or a missed valid start rejects.
- **Anchor**: The [Homebrew MLX formula](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/m/mlx-lm.rb)
  and [upstream model loading](https://github.com/ml-explore/mlx-lm/blob/v0.32.2/mlx_lm/utils.py).

The upstream server can load the default model during startup. Keep
the separately approved bootstrap as the path that downloads weights.
Respect `use_local_ai` in the shell as Doctor already does.

The [follow-up baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44881741060/job/136778385380)
accepted a missing interpreter and a package for another Python
version. It attempted a launch with no cached model and passed a
remote model ID for a cached revision. The generated shell setting
also allowed startup with local AI off. The other eight controls passed.

## Require all indexed weight shards

- **Hypothesis**: A partial sharded snapshot leaves the shell idle
  after its loopback check. A complete indexed snapshot starts once.
- **Measurement**: Give the local model fixture an index with two
  shard names. Run startup with one file and then with both files.
- **Success**: 0 launch calls for the partial snapshot and 1 offline
  launch for the complete snapshot. A nonempty unsharded model
  continues to pass the original control.
- **Pivot**: Any launch with a missing listed shard, malformed index,
  or empty weight file rejects the check.
- **Anchor**: [MLX weight loading](https://github.com/ml-explore/mlx-lm/blob/v0.32.2/mlx_lm/utils.py#L409-L419).

The [partial-shard baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44882595650/job/136780935396)
contacted the startup path after the loopback check. It had only one of
two indexed files. The thirteen other controls passed.
