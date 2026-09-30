# JetBrains font configuration (managed by dotfiles)

This file documents the font defaults dotfiles enforces across all detected JetBrains IDEs (WebStorm, IntelliJ IDEA, GoLand, etc.). The actual XML files are siblings: `editor-font.xml` and `terminal-font.xml`. They get symlinked into each IDE's `~/Library/Application Support/JetBrains/<IDE>/options/` by `modules/jetbrains/doctor.sh` on every `dotfiles-doctor --fix` invocation.

## Current defaults

| Surface  | Size | Family                    | Line spacing | Ligatures |
|----------|-----:|---------------------------|-------------:|-----------|
| Editor   |   15 | JetBrainsMono Nerd Font   |          1.5 | on        |
| Terminal |   15 | JetBrainsMono Nerd Font   |          1.4 | on        |

Picked 2026-05-12. "A bit bigger" than the JetBrains defaults (13 editor / 14 terminal), matching the editor-font setting that existed before the 2025.3 → 2026.1 migration silently reset the file.

## Per-machine override

Some operators run two machines (e.g. M-series laptop + 4K external monitor) where the same font size doesn't translate. To override either file without touching the dotfiles repo:

```bash
# Default location, configurable via $JETBRAINS_LOCAL_DIR
mkdir -p ~/.local/share/dotfiles-jetbrains
cp ~/apps/tooling/dotfiles/jetbrains/editor-font.xml \
   ~/.local/share/dotfiles-jetbrains/editor-font.override.xml
# Edit the FONT_SIZE / LINE_SPACING in the override; rerun:
dotfiles-doctor --fix
```

When `editor-font.override.xml` (or `terminal-font.override.xml`) exists at `$JETBRAINS_LOCAL_DIR/`, the doctor symlinks the override instead of the dotfiles base. The override file is machine-local, never committed.

## Why these values

- **FONT_FAMILY = JetBrainsMono Nerd Font** — the Nerd Font variant carries powerline glyphs (`` `` ``, `` `` ``, etc.) that `~/.zshrc.ai-tools'` starship prompt uses. Both editor and terminal share the family so a screenshot of an IDE pane reads the same as a terminal screenshot.
- **Editor LINE_SPACING = 1.5** — JetBrains' recommended range is 1.2–1.6; 1.5 is comfortable for long sessions on a 16" MBP. Lower (1.0–1.2) feels cramped at 15pt.
- **Terminal LINE_SPACING = 1.4** — slightly tighter than editor so the embedded terminal can show one extra line of agent output without scrolling. Still in the comfort range.
- **USE_LIGATURES = true** — JetBrainsMono is designed for ligatures (`==`, `!=`, `=>`, `->`, etc.). Off makes the family look like generic monospace; the operator picked JetBrainsMono specifically for the ligature set.

## Changing the size for ALL machines

Edit `editor-font.xml` and/or `terminal-font.xml` directly, commit, push. Other machines pick up the change on the next `dotfiles-sync` run. Update the table above when changing the defaults so the rationale stays in sync.

If you want to "experiment" with a different size on one machine before committing to all, use the per-machine override above and commit only once you're happy with the value.

## Why XML, not a generator

JetBrains writes through these symlinks when the operator changes a setting in the IDE UI (Settings > Editor > Font, etc.) — the file on disk is the source of truth, both for dotfiles and for the IDE. A generator (e.g. `sed`-substituted template) would lose the "operator can change a setting in the IDE and it persists into dotfiles" property. Symlink + plain XML preserves that round-trip.

Trade-off: XML comments don't survive JetBrains' rewrite cycle, so rationale lives in this `FONTS.md` instead of inline in the XML.
