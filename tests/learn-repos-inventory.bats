#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/learn-repos-inventory"

setup() {
  TEST_DIR="$(mktemp -d)"
  ROOT="$TEST_DIR/apps"
  mkdir -p "$ROOT"
}

teardown() {
  rm -rf "$TEST_DIR"
}

make_repo() {
  local path="$1"
  mkdir -p "$ROOT/$path"
  git -C "$ROOT/$path" init -q
  printf '# %s\n' "$path" > "$ROOT/$path/README.md"
  git -C "$ROOT/$path" add README.md
  git -C "$ROOT/$path" -c user.name=Test -c user.email=test@example.com \
    commit -qm 'chore: initialize fixture'
}

write_fingerprint_helper() {
  FINGERPRINT_LOG="$TEST_DIR/fingerprints.log"
  HELPER="$TEST_DIR/fingerprint-helper"
  cat > "$HELPER" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >> "$FINGERPRINT_LOG"
case "${1##*/}" in
  c-stale-fingerprint) prefix=cccccccccccccccc ;;
  d-procedure-gap) prefix=dddddddddddddddd ;;
  e-quality-short) prefix=eeeeeeeeeeeeeeee ;;
  f-quality-long) prefix=ffffffffffffffff ;;
  integer-content-length) prefix=1111111111111111 ;;
  marker-only) prefix=2222222222222222 ;;
  *) prefix=0000000000000000 ;;
esac
printf 'source_fingerprint\t%s0000000000000000\n' "$prefix"
printf 'source_fingerprint_prefix\t%s\n' "$prefix"
STUB
  chmod +x "$HELPER"
  export FINGERPRINT_LOG HELPER
}

@test "discover detects nested repositories and prunes dependencies" {
  make_repo "project"
  make_repo "project/nested"
  make_repo "project/node_modules/dependency"
  mkdir -p "$ROOT/worktree"
  printf 'gitdir: ../project/.git\n' > "$ROOT/worktree/.git"

  run "$SCRIPT" discover --root "$ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = $'project\nproject/nested\nworktree' ]
}

@test "select-batch enforces tier order and avoids needless fingerprints" {
  make_repo "a-missing"
  make_repo "b-stale-revision"
  make_repo "c-stale-fingerprint"
  make_repo "d-procedure-gap"
  make_repo "e-quality-short"
  make_repo "f-quality-long"
  write_fingerprint_helper

  c_revision="$(git -C "$ROOT/c-stale-fingerprint" rev-parse --short=12 HEAD)"
  d_revision="$(git -C "$ROOT/d-procedure-gap" rev-parse --short=12 HEAD)"
  e_revision="$(git -C "$ROOT/e-quality-short" rev-parse --short=12 HEAD)"
  f_revision="$(git -C "$ROOT/f-quality-long" rev-parse --short=12 HEAD)"
  cat > "$TEST_DIR/index.json" <<EOF
{
  "dossiers": [
    {"content": "Repository dossier: ~/apps/b-stale-revision", "tags": ["repo-docs", "repo:b-stale-revision", "revision:000000000000", "source-fingerprint:bbbbbbbbbbbbbbbb"]},
    {"content": "Repository dossier: ~/apps/c-stale-fingerprint", "tags": ["repo-docs", "repo:c-stale-fingerprint", "revision:$c_revision", "source-fingerprint:0000000000000000"]},
    {"content": "Repository dossier: ~/apps/d-procedure-gap", "tags": ["repo-docs", "repo:d-procedure-gap", "revision:$d_revision", "source-fingerprint:dddddddddddddddd"]},
    {"content": "Repository dossier: ~/apps/e-quality-short", "content_len": 10, "tags": ["repo-docs", "repo:e-quality-short", "revision:$e_revision", "source-fingerprint:eeeeeeeeeeeeeeee"]},
    {"content": "Repository dossier: ~/apps/f-quality-long", "content_len": 100, "tags": ["repo-docs", "repo:f-quality-long", "revision:$f_revision", "source-fingerprint:ffffffffffffffff"]}
  ],
  "procedures": [
    {"content": "d-1", "tags": ["repo-procedure", "repo:d-procedure-gap", "revision:$d_revision", "source-fingerprint:dddddddddddddddd"]},
    {"content": "d-2", "tags": ["repo-procedure", "repo:d-procedure-gap", "revision:$d_revision", "source-fingerprint:dddddddddddddddd"]},
    {"content": "e-1", "tags": ["repo-procedure", "repo:e-quality-short", "revision:$e_revision", "source-fingerprint:eeeeeeeeeeeeeeee"]},
    {"content": "e-2", "tags": ["repo-procedure", "repo:e-quality-short", "revision:$e_revision", "source-fingerprint:eeeeeeeeeeeeeeee"]},
    {"content": "e-3", "tags": ["repo-procedure", "repo:e-quality-short", "revision:$e_revision", "source-fingerprint:eeeeeeeeeeeeeeee"]},
    {"content": "f-1", "tags": ["repo-procedure", "repo:f-quality-long", "revision:$f_revision", "source-fingerprint:ffffffffffffffff"]},
    {"content": "f-2", "tags": ["repo-procedure", "repo:f-quality-long", "revision:$f_revision", "source-fingerprint:ffffffffffffffff"]},
    {"content": "f-3", "tags": ["repo-procedure", "repo:f-quality-long", "revision:$f_revision", "source-fingerprint:ffffffffffffffff"]}
  ]
}
EOF

  run "$SCRIPT" select-batch \
    --root "$ROOT" \
    --memory-index "$TEST_DIR/index.json" \
    --batch-size 6 \
    --fingerprint-helper "$HELPER" \
    --max-workers 1

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.next_batch[].path' | paste -sd, -)" = \
    "a-missing,b-stale-revision,c-stale-fingerprint,d-procedure-gap,e-quality-short,f-quality-long" ]
  [ "$(printf '%s\n' "$output" | jq -r '.selection_counts.missing_dossier')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.selection_counts.stale_revision')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.selection_counts.stale_fingerprint')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.selection_counts.procedure_gap')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | jq -r '.selection_counts.lowest_quality')" -eq 2 ]
  ! grep -q 'a-missing' "$FINGERPRINT_LOG"
  ! grep -q 'b-stale-revision' "$FINGERPRINT_LOG"
  [ "$(wc -l < "$FINGERPRINT_LOG" | tr -d ' ')" -eq 4 ]
}

@test "select-batch accepts integer content_len in quality ranking" {
  make_repo "integer-content-length"
  write_fingerprint_helper
  revision="$(git -C "$ROOT/integer-content-length" rev-parse --short=12 HEAD)"
  cat > "$TEST_DIR/index.json" <<EOF
{
  "dossiers": [
    {"content": "Repository dossier: ~/apps/integer-content-length", "content_len": 42, "tags": ["repo-docs", "repo:integer-content-length", "revision:$revision", "source-fingerprint:1111111111111111"]}
  ],
  "procedures": [
    {"content": "one", "tags": ["repo-procedure", "repo:integer-content-length", "revision:$revision", "source-fingerprint:1111111111111111"]},
    {"content": "two", "tags": ["repo-procedure", "repo:integer-content-length", "revision:$revision", "source-fingerprint:1111111111111111"]},
    {"content": "three", "tags": ["repo-procedure", "repo:integer-content-length", "revision:$revision", "source-fingerprint:1111111111111111"]}
  ]
}
EOF

  run "$SCRIPT" select-batch \
    --root "$ROOT" \
    --memory-index "$TEST_DIR/index.json" \
    --batch-size 1 \
    --fingerprint-helper "$HELPER" \
    --max-workers 1

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.next_batch[0].reason')" = "lowest_quality" ]
  [ "$(printf '%s\n' "$output" | jq -r '.next_batch[0].fresh_procedure_count')" -eq 3 ]
}

@test "select-batch indexes a dossier marker without a repo tag" {
  make_repo "marker-only"
  write_fingerprint_helper
  revision="$(git -C "$ROOT/marker-only" rev-parse --short=12 HEAD)"
  cat > "$TEST_DIR/index.json" <<EOF
{
  "dossiers": [
    {"content": "Repository dossier: ~/apps/marker-only\ngit_revision: $revision\nsource_fingerprint: 2222222222222222", "tags": ["repo-docs", "revision:$revision", "source-fingerprint:2222222222222222"]}
  ]
}
EOF

  run "$SCRIPT" select-batch \
    --root "$ROOT" \
    --memory-index "$TEST_DIR/index.json" \
    --batch-size 1 \
    --fingerprint-helper "$HELPER" \
    --max-workers 1

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.indexed_dossier_paths[0]')" = "marker-only" ]
  [ "$(printf '%s\n' "$output" | jq -r '.next_batch[0].reason')" = "procedure_gap" ]
}

@test "select-batch reports a fingerprint timeout instead of hanging" {
  make_repo "slow-fingerprint"
  revision="$(git -C "$ROOT/slow-fingerprint" rev-parse --short=12 HEAD)"
  HELPER="$TEST_DIR/slow-fingerprint-helper"
  cat > "$HELPER" <<'STUB'
#!/bin/bash
sleep 2
STUB
  chmod +x "$HELPER"
  cat > "$TEST_DIR/index.json" <<EOF
{
  "dossiers": [
    {"content": "Repository dossier: ~/apps/slow-fingerprint", "tags": ["repo-docs", "repo:slow-fingerprint", "revision:$revision", "source-fingerprint:3333333333333333"]}
  ]
}
EOF

  run "$SCRIPT" select-batch \
    --root "$ROOT" \
    --memory-index "$TEST_DIR/index.json" \
    --batch-size 1 \
    --fingerprint-helper "$HELPER" \
    --fingerprint-timeout 0.05 \
    --max-workers 1

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.next_batch | length')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | jq -r '.blocked[0].reason')" = "fingerprint_unavailable" ]
}
