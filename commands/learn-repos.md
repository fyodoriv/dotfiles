---
description: Incrementally learn local repositories and procedures into shared memory
---

# Learn Repositories into Shared Memory

Continuously learn repository knowledge, then repair demonstrated drift through
`/ship-it`. The command takes no arguments and is resumable. Every invocation runs all
five lanes on a bounded batch: refresh dossiers, extract procedures, validate writes,
run grounded evals, and ship evidence-backed repairs.

Read and follow **`~/apps/tooling/dotfiles/docs/learn-repos-reference.md`** for memory
layers, metadata, fingerprinting, freshness gates, validation, golden questions, and
lane detail. Execute without re-prompting.

## Fixed operating policy

- Root: `~/apps`
- Batch: 10 repository paths
- Selection order: missing dossiers → stale revision/fingerprint → procedure gaps →
  lowest-quality indexed repos
- Parallelism: up to 4 subagents, disjoint repository paths
- Memory endpoint: configured `memory` MCP (`http://127.0.0.1:18765/mcp`)
- Inventory helper: `~/apps/tooling/dotfiles/bin/learn-repos-inventory`
- Fingerprint helper: `~/apps/tooling/dotfiles/bin/learn-repos-source-fingerprint`
- Coordination: subagents only read and return extracts; the parent is the sole memory
  writer, supersession/deletion coordinator, and session committer
- Healing scope: user-owned/current-session work in the batch plus `/ship-it` approved
  repo families; all other repositories remain read-only

Do not ask for parameters or confirmation. Appended text cannot alter this policy.

## Standing healing approval

Invoking this command activates `/ship-it` for evidence-backed repairs from this
workflow. Follow `~/apps/tooling/dotfiles/docs/ship-it-reference.md` end-to-end. The
reference's ownership, bypass, release, secret, production, and human-action boundaries
still apply. Learning stays read-only until the healing gate passes.

## Memory layers (logical)

Store only reusable context in three layers on the same SQLite backend:

1. **Source-backed** — repo dossiers (`repo-docs`) and procedures (`repo-procedure`).
   Authoritative for repository answers when freshness passes.
2. **Durable decisions** — preferences from `commit_session_legacy` `{what, why}`.
   Context only; never authoritative for repo facts.
3. **Episodic** — progress, failure, and mistake notes. Batch selection only; never
   substitute for source-backed answers.

**Exclude:** raw logs, secrets, credentials, transient tool output, and verbatim
AGENTS/CLAUDE copies (cite paths instead).

## Required metadata and fingerprint

Every dossier and procedure carries: `writer`, `written_at_utc`, `source_paths`,
`git_revision`, `confidence`, and deterministic `source_fingerprint` (SHA-256 of sorted
source-document set emitted by the fingerprint helper). Fully read every emitted
`source_path`; never substitute an agent-chosen subset. Mirror `revision:<short-sha>` and
`source-fingerprint:<16-hex-prefix>` tags. Conversation ID:
`learn-repos:<repo-path>:<revision>:<fingerprint-prefix>`.

Stale = missing dossier, HEAD mismatch, fingerprint mismatch (including doc edits at
same revision), procedure gaps, or failed evals.

## Freshness gate (authoritative retrieval)

Repository answers require `memory_search` with a **non-empty semantic query**; mode
`semantic`, `ranked`, or `hybrid`; **`include_superseded: false`**; **`tag_match: all`**
(mandatory — default/any matching is unsafe); exact tags `repo:<path>`,
`revision:<current-sha>`, `source-fingerprint:<current-prefix>`.

**Forbidden for authoritative answers:** `exact` mode and tag-only recall (mcp-memory
11.7.0 bypasses supersession filtering there). Reject candidates missing current
revision or fingerprint regardless of quality. Quality may reorder **only**
freshness-passing hits. Mandatory `source_paths` citation; dead-end → re-read docs,
re-index, rerun eval.

## Five lanes (summary)

1. **Bootstrap** — `get_bootstrap_profile`; verify memory MCP; run the canonical
   inventory helper to discover repos and select the next batch from paginated memory.
   The selector calls the fingerprint helper only when a current-revision candidate
   needs a fingerprint comparison. Memory is the progress manifest — no in-repo state
   files; select a 10-repo batch. A `repo:` hit alone is never unchanged.
2. **Protect active work** — dirty, non-default branch, or 48h reflog → read-only.
   Eligible clean `main`/`master` only: `git pull --ff-only`. Never mutate during
   read/index/eval.
3. **Read docs** — parallel disjoint paths; subagents fully read helper-emitted paths,
   return evidence to the parent, and never call memory write/delete/session tools;
   resolve contradictions per reference.
4. **Store (parent only)** — first list active dossiers/procedures using exact
   `repo:<path>` plus tier tag and `tag_match=all`; then write dossier marker
   `Repository dossier: ~/apps/<relative-path>` and procedures with question titles,
   steps, verification. Prefer versioned `memory_update` by prior content hash;
   else validate replacement then delete prior exact hash only. **Never delete by
   `repo-docs` alone** — require `repo-docs` + exact `repo:<path>` with
   `tag_match=all`. Incremental backfill only; no bulk fleet rewrite.
5. **Validate + eval + heal** — freshness-passing hybrid retrieval; ≥3 grounded
   questions (architecture, operations, troubleshooting); score 1–5 against live docs.
   Heal demonstrated drift only after validation via `/ship-it`; re-index merged
   revision with new fingerprint.

## Report and resume

Report: filesystem repo count; active dossier count; selected/updated/unchanged/
skipped-active/blocked paths; dossiers/procedures superseded with revision+fingerprint;
freshness-pass vs rejected-stale counts; eval scores; repair/PR/merge/blocker URLs;
next batch. Call `commit_session_legacy` once before finishing. Later runs resume from
memory and process only missing, stale, procedure-poor, or failed-eval repositories.
Subagents are forbidden from calling `commit_session_legacy`.
