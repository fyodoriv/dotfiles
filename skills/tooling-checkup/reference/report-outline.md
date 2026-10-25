# Checkup report outline

The Phase 10 page of the tooling checkup follows this outline, verdict first.

```markdown
## Tooling checkup <YYYY-MM-DD>

**Verdict:** <healthy | healthy with gaps | broken: <what>>
**Since last run (<age>):** <changed versions and heads, or "nothing changed">

### Shipped
- <PR or commit>: <what it delivers> (<evidence>)

### Updated
- <tool>: <old> → <new> | skipped: <reason> | failed: <log line>
- Claude Code: <old> → <new>; doctor: <OK or findings>

### Background processes
- Removed: <label> (<why>) · Kept for you to decide: <label>
- Heavy: <process> <cpu>% <mem> MB → <cause or lead>

### Machine metrics (24 h)
- act: <metric> <value> → <fix, task, or question> · warn: <metric> <value> · rest ok
- Input latency: skipped (no trigger) | claude p95 <before> → <after> ms (<trigger>)

### Config audit
- <n> errors, <n> warnings · fixed: <list> · open: <list with owner>
- Requirements (monthly): <repo> <score> (<change>) · waived: <n> · not due: <repos>
- Repo health (monthly): doctor <n> failing · gate <pass/fail> · stories broken: <USNN list or none> · gate <median> s (goal 120, pivot 300)

### Agent time (7 days)
- Tool time: <h> (<change> vs last run) · active <h> · output <n>M tokens
- Slowest recurring: <key> <total> (<n>x, p95 <s>) · <key> … · <key> …
- Per project: <project>: <top key> <total> · …
- Speedups: filed <repo>/<task-id> (<min/day>) · fixed: <what> · none

### AI-work research
- Scanned: <n> new items from <n> feeds (<errors>) · searches: <queries>
- Adopt/try: <idea> (<lens>) → <task, PR, or question> · skipped: <n>

### Needs you
- <item> → <the exact question or command>

### Next: stability
1. `<repo>/<task-id>` (<priority>): <why now>

### Next: features
1. `<repo>/<task-id>` (<priority>): <why now>
```

Rules: "Shipped" lists only work that reached `origin`. Keep stability and
feature work in separate lists, up to three each. Recommend from the refreshed
`TASKS.md` queues of the tooling repositories. A gap with no task gets
`new: <kebab-case-id>` and one line on why.
