# AI-work research

The checkup looks for new ways to work with AI on its own, every run. It
finds candidates, judges them, and turns the good ones into tasks or
questions. It never installs or changes anything from a post by itself.

The lenses come from shared-rules **## Ambition with models** (from Felix
Rieseberg, "How to be more ambitious: a tutorial for humans with models",
2026-10-13).

## 1. Collect candidates

Run the feed scan outside the agent sandbox. The sandbox proxy cuts large
feeds short (`IncompleteRead`), even after the script's one retry.

```bash
python3 <skill-dir>/scripts/ai_research.py scan
```

- It prints `source:` lines (one per feed, `ok` or `error`), then one
  `new: <date> <source> | <title> | <link>` line per unseen item, at most 5
  per feed, from the last 21 days.
- Feeds: the Claude Code releases, Simon Willison, Felix Rieseberg, and
  Latent Space. The owner adds feeds in `~/.config/dotfiles/ai-research-feeds`
  (one `name url` pair per line).
- Then run up to two web searches for what feeds miss. Good queries: the
  Anthropic news and engineering blogs from the last two weeks, and "Claude
  Code workflow" or "agent workflow" posts with high discussion.
- One more source is local: take the top recurring step from Phase 8 and ask
  the Altitude question about it (see step 2).

## 2. Judge each candidate

Skim the title first. Open a post only when it may change how the owner
works with agents. For each one you open, write one line:

`<link> → <lens> → <idea in one sentence> → <adopt | try | skip>: <why>`

The lenses:

| Lens | Question |
|---|---|
| Speed | Does it do the same work in less time or fewer tokens? |
| Altitude | Does it let an agent own an outcome instead of a task (for example, "keep the tooling healthy" instead of "fix this job")? What access would that loop need? |
| Depth | Does it bring raw data, an expert's instrument, or an outside judge into a workflow that lacks one? |
| Range | Does it borrow a method from another field that fits a tooling workflow? |

Skip news with no change to how the owner works: funding, launches of
products the owner does not use, and benchmark gossip. Skip any xAI or
Musk-affiliated product (owner rule). Prefer local or free options first.

## 3. Turn adoptions into work

An `adopt` or `try` needs an outside judge before it becomes work: name the
metric, its baseline, and the command that measures it.

- Small and inside a tooling repo: ship it with `/ship-it`.
- Bigger, or it needs a choice: a task in that repo's `TASKS.md` with the
  P0/P1 fields (Hypothesis, Success, Pivot, Measurement, Anchor; the post is
  the Anchor), or a Phase 11 question.
- An idea seen in two runs that still has no home: a Phase 11 question.

## 4. Record

After Phase 11, mark this run's items as seen, so the next run shows only
new ones:

```bash
python3 <skill-dir>/scripts/ai_research.py record
```

State: `~/.local/state/tooling-checkup/ai-research-seen.json` (kept 365 days)
and `ai-research-pending.json`.
