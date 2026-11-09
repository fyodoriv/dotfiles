---
description: Show remaining Kimi Code subscription quota
allowed-tools: Bash(kimi-usage:*)
---

**Agent contract:** Claude Code + ChatGPT Work/Codex; shared memory required when configured; regression: tests/user-stories.bats.

**Portable agent acceptance:** Use the same CLI handler in Claude Code and ChatGPT Work/Codex. Before context-dependent work, use configured shared memory: `get_bootstrap_profile`, then semantic `memory_search`. If configured recall fails, report **shared memory unavailable** and the failed tool. Do not claim context-dependent readiness. If memory is unconfigured, state that scope. This is a deterministic read-only command and needs no model. Do not read credential files or print an API key. Do not copy OAuth, credentials, privacy choices, schedules, or private records between hosts.

Run `kimi-usage` and show its output verbatim. It uses the existing environment or macOS Keychain credential to read `https://api.kimi.com/coding/v1/usages`.

- If Kimi reports a weekly window, show its remaining quota and reset time.
- If Kimi reports no weekly limit, say so plainly and show the actual 5-hour and monthly windows instead of inventing a weekly total.
- On failure, show the command's error and do not retry with a different credential or endpoint.
- For `/kimi-usage forecast`, run `kimi-usage --forecast`. It compares the current 5-hour average burn rate with the reset time and says whether exhaustion is estimated before reset. State that the forecast is only an estimate from current usage, not a guarantee. Do not invent a monthly forecast without a precise elapsed window.
