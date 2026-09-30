#!/usr/bin/env bats
# Validate local markdown links in README.md and top-level docs.
# Covers two failure modes:
#   • broken file targets (e.g. `(missing.md)`)
#   • broken heading anchors  (e.g. `(README.md#renamed-section)`)
# External `https://` links and bare in-page `#frag` references that point
# at the file's own anchors are still considered out of scope here so the
# test stays free of the network and Markdown-renderer assumptions.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_link_check() {
  python3 - "$1" <<'PY'
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote
import re
import sys

root = Path(sys.argv[1]).resolve()
docs_dir = root / "docs"
md_files = sorted(set([root / "README.md", *docs_dir.glob("*.md")]))

LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#+)\s+(.+?)\s*$")
URL_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")

def slugify(text: str) -> str:
    """GitHub-flavored-Markdown slug: lowercase, strip non-word chars,
    collapse whitespace into hyphens. `&` and `?` drop out, hyphen
    sequences from punctuation runs are preserved (`Fork & customize`
    → `fork--customize`)."""
    s = text.lower()
    s = re.sub(r"[^\w\s-]", "", s, flags=re.UNICODE)
    s = re.sub(r"\s+", "-", s.strip())
    return s

def collect_slugs(path: Path) -> set[str]:
    """Walk headings, mirror GitHub's duplicate suffix policy
    (`heading`, `heading-1`, `heading-2`, …)."""
    seen = defaultdict(int)
    slugs: set[str] = set()
    in_fence = False
    for line in path.read_text().splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADING_RE.match(line)
        if not m:
            continue
        base = slugify(m.group(2))
        # GitHub assigns the bare slug to the first heading and `-N` to
        # subsequent collisions. Tracking with `seen[base]` plus a +1
        # offset matches that exactly.
        suffix = seen[base]
        slug = base if suffix == 0 else f"{base}-{suffix}"
        seen[base] += 1
        slugs.add(slug)
    return slugs

slugs_by_path = {p.resolve(): collect_slugs(p) for p in md_files}

def split_target(raw: str) -> tuple[str, str]:
    target = raw.strip()
    if target.startswith("<") and ">" in target:
        target = target[1:target.index(">")]
    else:
        target = target.split()[0]
    target = target.split("?", 1)[0]
    if "#" in target:
        path_part, fragment = target.split("#", 1)
    else:
        path_part, fragment = target, ""
    return unquote(path_part), unquote(fragment)

errors: list[str] = []
for md in md_files:
    in_fence = False
    for ln, line in enumerate(md.read_text().splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for match in LINK_RE.finditer(line):
            raw = match.group(1)
            if URL_SCHEME_RE.match(raw):
                continue
            path_part, fragment = split_target(raw)
            if not path_part and not fragment:
                continue

            if path_part:
                candidate = root / path_part.lstrip("/") if path_part.startswith("/") else md.parent / path_part
                if not candidate.exists():
                    errors.append(
                        f"{md.relative_to(root)}:{ln}: missing local link target: {path_part}"
                    )
                    continue
                tgt = candidate.resolve()
            else:
                # `(#frag)` resolves against the file the link lives in.
                tgt = md.resolve()

            if not fragment:
                continue
            if tgt not in slugs_by_path:
                # External markdown (e.g. ../README.md from a sibling repo)
                # is out of scope — we only own the docs in this tree.
                continue
            if fragment not in slugs_by_path[tgt]:
                errors.append(
                    f"{md.relative_to(root)}:{ln}: missing anchor #{fragment} in {tgt.relative_to(root)}"
                )

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY
}

@test "README and docs markdown local links resolve" {
  run run_link_check "$DOTFILES_DIR"
  [ "$status" -eq 0 ] || {
    echo "$output"
    return 1
  }
}

@test "anchor validator handles GitHub-style duplicate slugs" {
  # Two `## Setup` headings should produce slugs `setup` and `setup-1`.
  # Linking either with the matching slug must validate cleanly, while
  # a third `#setup-2` reference is correctly flagged as missing.
  cat > "$TEST_DIR/README.md" <<'MD'
# Title

[first](#setup)
[second](#setup-1)
[bogus third](#setup-2)

## Setup

content

## Setup

more content
MD
  mkdir -p "$TEST_DIR/docs"

  run run_link_check "$TEST_DIR"

  [ "$status" -ne 0 ]
  # `#setup` and `#setup-1` resolve, only `#setup-2` is reported.
  [[ "$output" == *"missing anchor #setup-2"* ]]
  [[ "$output" != *"missing anchor #setup\""* ]]
  [[ "$output" != *"missing anchor #setup-1"* ]]
}

@test "anchor validator flags missing heading fragments" {
  cat > "$TEST_DIR/README.md" <<'MD'
# Title

[broken](#missing-section)

## Real section
MD
  mkdir -p "$TEST_DIR/docs"

  run run_link_check "$TEST_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing anchor #missing-section"* ]]
  [[ "$output" == *"README.md:3"* ]]
}

@test "anchor validator flags missing anchors in linked files" {
  cat > "$TEST_DIR/README.md" <<'MD'
# Title

[broken](docs/guide.md#nope)
MD
  mkdir -p "$TEST_DIR/docs"
  cat > "$TEST_DIR/docs/guide.md" <<'MD'
# Guide

## Real
MD

  run run_link_check "$TEST_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing anchor #nope"* ]]
  [[ "$output" == *"docs/guide.md"* ]]
}

@test "anchor validator ignores external links and skips fenced code" {
  cat > "$TEST_DIR/README.md" <<'MD'
# Title

[external](https://example.com#irrelevant)
[mailto](mailto:nobody@example.org)

```
[in-fence](#also-irrelevant)
```

## Real
MD
  mkdir -p "$TEST_DIR/docs"

  run run_link_check "$TEST_DIR"
  [ "$status" -eq 0 ]
}
