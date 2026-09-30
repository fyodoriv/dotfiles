# Learn Repositories — workflow reference

Canonical detail for `/learn-repos`. The command file stays concise; follow this
reference end-to-end during execution.

## Memory layers (logical, same SQLite backend)

| Layer | Purpose | Typical tags / types | Authoritative for repo answers? |
| --- | --- | --- | --- |
| **Source-backed** | Repository dossiers and procedures distilled from committed docs | `repo-docs`, `repo-procedure`, `repo:<path>`, `revision:<sha>`, `source-fingerprint:<prefix>`, `domain:<topic>`; types `reference`, `pattern` | **Yes** — when freshness passes |
| **Durable decisions** | Reusable preferences and decisions from `commit_session_legacy` | project/topic/agent tags; structured `{what, why}` | No — context only |
| **Episodic** | Progress notes, failure notes, mistake notes, eval corrections | mistake/progress tags from bootstrap search | No — never substitute for source-backed answers |

**Never store:** raw logs, secrets, credentials, transient tool output, full
AGENTS.md/CLAUDE.md copies, or anything whose source of truth is already in repo
docs (link paths instead).

## Required metadata on every dossier and procedure

Every write must include these fields in content **and** mirrored tags where noted:

| Field | Content | Tag mirror |
| --- | --- | --- |
| `writer` | Agent ID from bootstrap | — |
| `written_at_utc` | ISO-8601 UTC timestamp | — |
| `source_paths` | Ordered repo-relative paths actually read | — |
| `git_revision` | Short HEAD SHA (`unknown` when detached/unavailable) | `revision:<short-sha>` |
| `confidence` | `high`, `medium`, or `low` from doc clarity | — |
| `source_fingerprint` | Full SHA-256 hex of the source-document set | `source-fingerprint:<first-16-hex>` |

**Conversation ID** (dedup key):
`learn-repos:<repo-relative-path>:<git_revision>:<source_fingerprint_prefix>`

Derive from repo path + revision + fingerprint — never from title alone.

### Source-document fingerprint

Run `~/apps/tooling/dotfiles/bin/learn-repos-source-fingerprint <repo>`; do not
reimplement this inventory in prompts or ad hoc scripts. It emits the full fingerprint,
16-character prefix, and sorted `source_path` rows. The canonical set is:

- human-authored root Markdown/MDX/RST/AsciiDoc files and extensionless
  README/AGENTS/CLAUDE/VISION/ROADMAP/MILESTONES/ARCHITECTURE/TASKS/CONTRIBUTING/
  CHANGELOG/SECURITY files;
- recursive text documents under `docs/`, `doc/`, `runbooks/`, `skills/`,
  `.agents/skills/`, and `.claude/skills/`;
- tracked and untracked non-ignored files, so same-revision working-tree doc edits change
  the fingerprint; Git metadata, ignored dependencies, generated output, caches, logs,
  and transcripts are excluded.

Then:

1. Fully read every emitted `source_path`. Store exactly that sorted set as
   `source_paths`; partial or agent-chosen subsets are invalid.
2. For each path: `path + "\0" + git blob hash or file sha256 + "\0" + size`.
3. Sort lines lexicographically; join with `\n`; SHA-256 the result →
   `source_fingerprint`.
4. Tag prefix = first 16 hex chars (`source-fingerprint:abc123…`).

**Stale** when any of: missing dossier; `git_revision` ≠ current HEAD;
`source_fingerprint` ≠ current computed fingerprint (even at same revision after doc
edits); procedure count below threshold; eval failure on last indexed revision.

## Freshness gate (authoritative retrieval)

Repository answers **must** pass freshness before quality ranking applies.

### Required search shape

Use `memory_search` with **all** of:

- non-empty semantic query (architecture fact, operation, or troubleshooting symptom);
- mode `semantic`, `ranked`, or `hybrid` — **never `exact`** for authoritative answers;
- `include_superseded: false`;
- **`tag_match: all`** — mandatory whenever combining `repo:` + `revision:` +
  `source-fingerprint:` tags; default or `any` matching is unsafe (partial tag hits
  can bypass freshness);
- exact tag `repo:<relative-path>`;
- exact tag `revision:<current-short-sha>`;
- exact tag `source-fingerprint:<current-prefix>`.

Optional: add `repo-procedure` or `repo-docs` to narrow tier.

### Forbidden recall paths

- **`exact` mode** for authoritative answers — mcp-memory-service 11.7.0 bypasses
  supersession filtering in exact mode.
- **Tag-only recall** (empty or whitespace query, tags alone) — same bypass risk.
- **`tag_match: any` or omitted `tag_match`** when repo + revision + fingerprint tags
  are combined — partial matches are unsafe.
- Any candidate missing **current** `revision:` or `source-fingerprint:` tags.

### Candidate selection

1. Compute current HEAD and source fingerprint for the repo.
2. Run the required search; discard non-matching revision/fingerprint hits even if
   top-ranked or high quality.
3. Among freshness-passing candidates only, prefer `repo-procedure` over `repo-docs`;
   then rank by hybrid/semantic score.
4. **Quality cannot override freshness** — a score-5 stale memory is rejected; read
   current docs, re-index, then answer.

### Mandatory source citation

Every authoritative answer cites `source_paths` and `git_revision` from the winning
memory (or from live docs when re-indexing). No citation → treat as dead-end, re-read
docs, store correction, rerun eval.

## Lane 1 — Bootstrap and inventory

1. `get_bootstrap_profile` with agent ID and task summary; search ranked memory and
   mistake notes.
2. Verify memory MCP discovery + protocol `initialize` (`Accept: application/json,
   text/event-stream`) and `get_bootstrap_profile`. On failure: `agentbrew memory
   doctor`, `agentbrew memory fix`, `agentbrew memory enable`, then `agentbrew sync
   --pull` outside a project Agentfile and retry. Streamable HTTP fallback is allowed
   only against the same configured endpoint when Cursor's live MCP binding remains
   stale and the endpoint exposes bootstrap, search, write/update, and session-commit.
   Never create a fallback store.
3. Run
   `~/apps/tooling/dotfiles/bin/learn-repos-inventory discover --root ~/apps`.
   It detects `.git` directories and worktree `.git` files before pruning dependency,
   build, cache, and metadata directories, then emits sorted, deduplicated relative
   paths. It never mutates a repository.
4. Page the active `repo-docs` and `repo-procedure` records returned by
   `memory_list`; pass the records as JSON to
   `learn-repos-inventory select-batch --root ~/apps --memory-index <outside-repo-json>`.
   The selector indexes dossier markers, `repo:`, `revision:`, and
   `source-fingerprint:` tags per path. A dossier with only `repo:<path>` is indexed but
   stale — it never satisfies unchanged selection.
5. The selector checks current Git revisions cheaply first, then calls the canonical
   fingerprint helper only for candidates whose dossier revision matches HEAD and whose
   fingerprint is needed. Each subprocess is timeout-bounded; failures are reported in
   `blocked` output rather than hanging the run.
6. Select a batch of 10 deterministically: missing dossiers → stale revision →
   stale fingerprint → procedure gaps → lowest indexed quality. A procedure gap means
   fewer than **three** fresh, reusable procedures. When eval quality is unavailable,
   the stable quality proxy is dossier content length, fresh procedure count, and
   high-confidence record count, followed by repository path.
7. Skip unchanged repos (current revision **and** fingerprint, at least three useful
   procedures, and passing evals). The selector emits `next_batch`, `selection_counts`,
   `indexed_dossier_paths`, and any blocked paths as JSON.

Memory is the progress manifest; the helper lives in dotfiles, not inside repositories,
and no scan state files are created in repositories.

## Lane 2 — Protect active work

Inspect branch, porcelain, upstream, reflog before any pull.

- **Active (read-only):** dirty tree; not on `main`/`master`; reflog activity within
  48 hours.
- **Eligible pull:** clean tracked `main`/`master`, no reflog activity in 48h →
  `git pull --ff-only` only.
- Record bare repos, detached worktrees, missing upstreams, network failures; index
  from local content at `unknown` revision when needed.
- Never mutate repos during inventory, read, index, or eval. Only healing lane may
  change eligible repos via `/ship-it`.

## Lane 3 — Read current documentation

Parallel subagents receive disjoint repository paths. For each repo they run the
fingerprint helper, fully read every emitted path, and return evidence/extracts plus the
exact helper output to the parent. README, AGENTS/CLAUDE (for extraction only — do not
store verbatim), VISION, ROADMAP, ARCHITECTURE, TASKS, CONTRIBUTING, CHANGELOG, SECURITY,
and runbooks are included by the helper.

Subagents are read-only with respect to shared memory: they must not call
`memory_store`, `memory_update`, `memory_delete`, or `commit_session_legacy`. This keeps
supersession and the once-per-run session commit serialized in the parent.

Exclude `.git`, dependencies, generated files, caches, secrets, transcripts, logs.

Contradiction order: explicit supersedes/deprecation → most recently committed doc →
specific runbook over generic README.

## Lane 4 — Store source-backed memories

### Repository dossier

Marker line exactly: `Repository dossier: ~/apps/<relative-path>`

Include purpose, architecture/data flow, ownership, workflows, direction, gotchas,
contradictions, and all required metadata fields.

Tags: `repo-docs`, `repo:<relative-path>`, `revision:<short-sha>`,
`source-fingerprint:<prefix>`. Type: `reference`.

### Procedures

One memory per distinct configure/deploy/test/debug/migrate/onboard/release workflow:

- question-shaped title + ordered steps;
- prerequisites, failure modes, verification;
- all required metadata fields;
- tags: `repo-procedure`, `repo:<relative-path>`, `domain:<topic>`,
  `revision:<short-sha>`, `source-fingerprint:<prefix>`;
- type: `pattern`.

How-to questions: procedures outrank dossiers **after** freshness gate.

### Supersession and deletion

- The parent first lists active records using the exact tier tag (`repo-docs` or
  `repo-procedure`) plus exact `repo:<relative-path>` and `tag_match=all`. Current
  revision/fingerprint search is not an inventory of stale records.
- Prefer `memory_update` with the previous `content_hash` and `versioned: true`.
- Otherwise: write replacement, validate retrieval, dry-run delete **only** previous
  exact content hash.
- **Never delete by `repo-docs` alone.** Tag delete requires `repo-docs` **and**
  exact `repo:<relative-path>` with `tag_match=all`.
- No parallel deletion for overlapping repo tags.
- Backfill incrementally in 10-repo batches — no bulk rewrite of entire fleet.

## Lane 5 — Validate writes and grounded evals

Per repo in batch:

1. Freshness-passing hybrid search (`tag_match: all`) for a distinguishing architecture fact.
2. Freshness-passing procedure retrieval (`tag_match: all`) for a realistic how-to question.
3. Confirm no sibling-prefix or stale-revision duplicates in active set.
4. Run ≥3 memory-first questions (architecture, operations, troubleshooting) using
   the freshness gate — verify against live docs, not memory alone.
5. Score correctness, completeness, provenance, usefulness 1–5. Store source-backed
   corrections; rerun failures.

Report exact-mode/tag-only/**tag_match any or omitted** checks as **forbidden** (must not
appear in validation totals as passes).

## Lane 6 — Heal demonstrated drift (after validation)

Repairs only with current-source proof: contradictory/stale source-of-truth docs,
broken documented check, missing recovery for reproduced failure, or owned config
drift.

1. Re-check status, reflog, ownership, CODEOWNERS, VISION/ROADMAP, PRs. Active,
   detached, unknown-owned, vision-conflicting, or multi-CODEOWNERS-scope repos stay
   read-only.
2. Minimal patch + exact sources + reproducible before/after. At most one logical
   change per eligible repo. Never heal from quality scores alone.
3. Feature branch + `/ship-it` per `docs/ship-it-reference.md`.
4. Re-index merged revision; supersede dossier/procedures with new fingerprint;
   validate freshness retrieval; rerun exposing eval. Unmerged PR = actual revision,
   not healed.

## Lane 7 — Report and resume

Report all fields:

- filesystem repo count; active unique dossier count;
- selected, updated, unchanged, skipped-active, blocked paths;
- dossiers/procedures written or superseded (with revision + fingerprint);
- freshness-passing vs rejected-stale retrieval counts;
- eval scores and corrected gaps;
- repair candidates, shipped PRs, merged count, review/blocker URLs, post-merge re-index;
- next deterministic batch.

The parent calls `commit_session_legacy` exactly once after all subagents and validation
finish, with structured decisions and errors. Subagents are forbidden from calling it.

## Dead-end recovery

When freshness search returns zero candidates:

1. Do **not** fall back to exact mode, tag-only search, `tag_match: any`, omitted
   `tag_match`, or superseded memories.
2. Read current repo docs; answer from sources with citation.
3. Store dossier/procedure with new metadata; validate freshness retrieval.
4. Record episodic note only if useful for future batch selection — not as answer
   source.

## Cross-repo isolation

Tags and paths are exact. `repo:tooling/foo` must never satisfy `repo:tooling/foobar`.
Validation must include a sibling-prefix negative case per batch when applicable.

## Golden eval question schema

`commands/evals/learn-repos.golden.json` holds the initial 20-question generic set.
**Top-level defaults inherit to every question** — do not repeat them on each object.
`/learn-repos` populates `{git_revision}`, `{source_fingerprint_prefix}`, and resolved
freshness tags at runtime from indexed repos. Do not invent live hashes in fixtures.

### Inherited defaults (every question)

| Top-level key | Purpose |
| --- | --- |
| `required_runtime_fields` | Metadata every dossier/procedure must carry |
| `freshness_required_tags.templates` | Tag patterns filled with runtime repo path, revision, fingerprint |
| `authoritative_search` | Non-empty query, allowed modes, `include_superseded: false`, `tag_match: all` |
| `required_source_citation` | Answer must cite `source_paths` and `git_revision` |
| `forbidden_recall` | Exact mode, tag-only, any/omitted tag_match, superseded recall |

### Per-question fields only

Each entry in `questions[]` defines only: `id`, `category`, `repo_relative_path`,
`question`, and question-specific `pass_criteria`.

Example resolved at runtime (illustrative — placeholders filled by `/learn-repos`):

```json
{
  "id": "arch-01",
  "category": "architecture",
  "repo_relative_path": "tooling/example-service",
  "question": "How does the example service authenticate outbound API calls?",
  "pass_criteria": "Answer cites source_paths; freshness-passing hybrid search returns the indexed procedure or dossier",
  "_inherited": {
    "required_runtime_fields": ["writer", "written_at_utc", "source_paths", "git_revision", "confidence", "source_fingerprint"],
    "freshness_required_tags": [
      "repo:tooling/example-service",
      "revision:<short-sha-at-index-time>",
      "source-fingerprint:<16-hex>"
    ],
    "authoritative_search": {
      "query_requirement": "non-empty",
      "modes_allowed": ["semantic", "ranked", "hybrid"],
      "include_superseded": false,
      "tag_match": "all"
    },
    "required_source_citation": {
      "fields": ["source_paths", "git_revision"],
      "min_source_paths": 1
    }
  }
}
```

The `_inherited` block is documentation-only — it is **not** stored in the golden file;
agents merge top-level defaults with each question when running evals.

See `commands/evals/learn-repos.golden.json` for the canonical defaults and question list.
