# Power Protect readiness instrumentation

Goal: expose missing readiness files without claiming a measured uptime
improvement. The physical closed-display experiment is separate.
Prediction committed in TASKS.md as 9563137 before tests.

1. Reproduce missing registration with actual resilience-module tests.
2. Reuse `dotfiles_is_apple_silicon` and the existing Amphetamine app-path
   seam. Add one advisory that requires both upstream file markers only
   when keep-awake tools are on and Amphetamine is installed.
3. Test each absent file, both present, Intel, absent app, opted-out tools,
   and list-mode discovery. All writes stay under each test's scratch HOME
   or its explicit administrator-file fixture path.
4. Run `bats tests/power-protect-readiness.bats`, `heavy-run make check`, and
   independent review. Keep only with zero failed assertions. Any false
   presence pass or unexpected host write abandons presence-only inference.

The check never installs a helper, changes sudo policy, or claims physical
agent continuity. Official paths:
https://github.com/x74353/Amphetamine-Power-Protect . Metric method:
Basili, Caldiera, Rombach (1994), Goal Question Metric.
