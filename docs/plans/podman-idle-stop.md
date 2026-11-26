# Stop an idle Podman VM on macOS

Dotfiles #835 asks for automatic release of memory used by idle container
VMs. Docker Desktop already releases its Linux VM through Resource Saver.
Document the native setting and its automatic wake. Podman will get an
optional LaunchAgent for one named, local machine.

The LaunchAgent checks every ten minutes. It accepts a minimum idle window
of 30 minutes by default. The stop command requires the same running VM
before and after the probe. The probe checks the managed user and root
Podman stores for active containers and recent container events. Both must
use the stock journald backend. The current boot journal must reach the
start of the window. Missing evidence leaves the machine running.

The dedicated lock covers one local invocation. Idle evidence comes from
the guest on each check. Podman exposes the probe and stop as separate
operations, so use this only with a machine you control. The scheduler
stays disabled when no machine is selected.

## Prediction

- **Hypothesis**: A named Podman VM stops once after a verified idle window.
  Busy, disabled, down, or unverified machines receive zero stop calls.
- **Measurement**: `bats tests/podman-idle-stop.bats` in hosted macOS CI.
  Fixtures run the production entry point against synthetic named
  machines and check the exact stop count and scheduler configuration.
- **Success**: One stop in the idle case. Zero stops when disabled, busy,
  paused, recently active, down, missing history, or restarted mid-check.
  No Docker polling helper and no scheduled job in the default config.
- **Pivot**: Stop delivery if 1 unsafe fixture invokes the stop command
  or the helper cannot prove it selected the requested local machine.
- **Anchor**: [Dotfiles #835](https://github.com/fyodoriv/dotfiles/issues/835),
  [Docker Resource Saver](https://docs.docker.com/desktop/use-desktop/resource-saver/),
  [Podman machine inspection](https://docs.podman.io/en/latest/markdown/podman-machine-inspect.1.html),
  and [Podman events](https://docs.podman.io/en/latest/markdown/podman-events.1.html).
