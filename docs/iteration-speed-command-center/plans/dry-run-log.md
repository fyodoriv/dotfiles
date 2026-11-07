# Dry-run log

2026-11-07: A separate scratch checkout used a temporary synthetic Git repository. It compared working bytes, staged tree, and revision; it also tested an unmerged index. The first fixture did not supply input to `git hash-object`; rerunning with explicit synthetic bytes fixed the fixture.

```text
synthetic cache dry run: 4/4 controls passed
```

This is a bounded design check. It does not prove a production cache or runtime speedup.
