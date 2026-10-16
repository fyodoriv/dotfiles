# Spotlight `mdworker` CPU after a busy worktree session (#83 acceptance)

- **Task**: spotlight-wt-noindex-mdworker-measurement
- **Date**: 2026-10-16, during a parallel agent session
- **Change under test**: #83 (714cab5) moved agent worktrees to `~/apps/tooling/wt.noindex`.
- **Pre-registered success**: `mdworker` total CPU stays under 50% in all three samples.

## Method

No polling loop. Three samples, 5 minutes apart, from one background shell:

```bash
ps -axo pcpu=,comm= | awk '$2 ~ /mdworker/ {w+=$1} $2 ~ /mds_stores/ {s+=$1} END {print w, s}'
sysctl -n vm.loadavg
ls ~/apps/tooling/wt.noindex | wc -l
```

## Result

| Minute | Time (local) | load1 | Worktrees | `mdworker` CPU % | `mdworker` procs | `mds_stores` CPU % |
|---|---|---|---|---|---|---|
| 0 | 08:26:39 | 81.51 | 16 | 0.0 | 0 | 16.1 |
| 5 | 08:31:39 | 21.92 | 19 | 0.0 | 12 | 1.1 |
| 10 | 08:36:39 | 16.03 | 20 | 0.0 | 8 | 39.5 |

A `top -l 2` cross-check right after showed every `mdworker_shared` at 0.0%.

**Verdict**: success. `mdworker` stayed at 0% in all three samples with 16-20
worktrees under `wt.noindex`, so #83 holds on a busy Mac.

## Side finding

`mds_stores` reached 39.5% CPU. The worktrees are not the cause (their
index count is 0). `~/apps` itself is still indexed: `mdfind -onlyin ~/apps
-count "kMDItemDisplayName == '*'"` returned 188,491 items, although it has
a `.metadata_never_index` marker. The `spotlight.apps` doctor check now
reports this (#100). The manual fix is System Settings → Spotlight → Search
Privacy.
