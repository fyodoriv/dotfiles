# Windsurf configuration (managed by dotfiles)

This directory is the source of truth for the operator's [Windsurf](https://windsurf.com/)
user-level config: editor settings, keybindings, and the recommended extension
bundle. `modules/windsurf/doctor.sh` symlinks these files into
`~/Library/Application Support/Windsurf/User/` on every `dotfiles-doctor --fix`
invocation, and installs any missing extensions from `extensions.txt`.

The design goal: **get as close to the operator's WebStorm muscle memory and
typography as Windsurf will allow, with aggressive performance defaults for
large TypeScript monorepos.**

## Ownership boundary

| Target | Owner | Notes |
|--------|-------|-------|
| `~/Library/Application Support/Windsurf/User/settings.json` | **dotfiles** | This dir → symlinked |
| `~/Library/Application Support/Windsurf/User/keybindings.json` | **dotfiles** | This dir → symlinked |
| Installed extensions | **dotfiles** | `extensions.txt` → `windsurf --install-extension` |
| `~/.codeium/windsurf/` (Cascade, MCP, skills, rules, memories) | **agentbrew** | See `Agentfile.yaml` |
| `~/.codeium/windsurf/global_workflows/` | **agentbrew** | Same |

Never edit `~/.codeium/windsurf/*` to make a dotfiles change — that's agentbrew's
territory. Never edit `~/Library/Application Support/Windsurf/User/*` directly to
make a permanent change — modify this dir, run `dotfiles-doctor --fix`, commit.

## Round-trip: UI changes persist into git

`settings.json` and `keybindings.json` are symlinked, not copied. When Windsurf
writes the file (via the UI, settings sync, or extension), the change lands in
this directory directly. Run `dotfiles-sync` (or wait for the hourly
launchagent) and the change commits to git.

This is the same round-trip property the `jetbrains/` module gives the
operator's WebStorm config: edit the setting in the IDE, the dotfiles repo picks
it up. No copy-paste, no two-source-of-truth drift.

Trade-off: JSON comments survive Windsurf's rewrite cycle (unlike JetBrains XML
where they don't), so rationale lives inline. Keep the comment headers
when restructuring — they're the operator-facing docs.

## WebStorm → Windsurf mapping

The table below traces every WebStorm setting from `jetbrains/` that has a
Windsurf equivalent. **Anything not in this table is a Windsurf-only setting
chosen for performance or ergonomics — see comments inline in `settings.json`.**

### Typography (from `jetbrains/editor-font.xml` + `terminal-font.xml`)

| WebStorm                       | Windsurf                                    |
|--------------------------------|---------------------------------------------|
| FONT_FAMILY = JetBrainsMono NF | `editor.fontFamily`                         |
| FONT_SIZE = 15                 | `editor.fontSize: 15`                       |
| LINE_SPACING = 1.5 (editor)    | `editor.lineHeight: 1.5`                    |
| LINE_SPACING = 1.4 (terminal)  | `terminal.integrated.lineHeight: 1.4`       |
| USE_LIGATURES = true           | `editor.fontLigatures: true`                |

The font itself lives in `~/Library/Fonts/JetBrainsMonoNerdFont*.ttf` (installed
by the `nerd-fonts/font-jetbrains-mono-nerd-font` Homebrew cask from the
operator's Brewfile). The `windsurf` doctor module verifies the font is
discoverable via `fc-list` and warns if not — same check the `jetbrains` module
does.

### Editor behavior (from `jetbrains/editor.xml`)

| WebStorm                                  | Windsurf                          |
|-------------------------------------------|-----------------------------------|
| STRIP_TRAILING_SPACES = "Whole"           | `files.trimTrailingWhitespace: true` |
| SOFT_WRAP_FILE_MASKS = "*.md; *.txt; …"   | `[markdown]/[plaintext]/...: editor.wordWrap: "on"` |
| AUTO_POPUP_JAVADOC_INFO = true            | `editor.parameterHints.enabled: true` |
| AUTO_POPUP_COMPLETION_LOOKUP = false      | `editor.suggest.preview: true` (close equivalent) |
| All chain/type inlay hints OFF            | Per-lang `inlayHints.*.enabled: false` |

### UI density (from `jetbrains/ui.xml`)

| WebStorm                                  | Windsurf                          |
|-------------------------------------------|-----------------------------------|
| UI_DENSITY = COMPACT                      | `workbench.tree.indent: 12` + `workbench.layoutControl.enabled: false` |
| OPEN_IN_PREVIEW_TAB_IF_POSSIBLE = true    | `workbench.editor.enablePreview: true` |
| ProjectViewFileNesting rules              | `explorer.fileNesting.patterns: {…}` |

### Code style (from `jetbrains/codestyle.xml`)

| WebStorm                                  | Windsurf                          |
|-------------------------------------------|-----------------------------------|
| INDENT_SIZE = 2 (default)                 | `editor.tabSize: 2`               |
| INDENT_SIZE = 4 (Java/Kotlin/Py/Rust)     | Per-lang `editor.tabSize: 4`      |
| USE_DOUBLE_QUOTES = false (JS/TS)         | `typescript/javascript.preferences.quoteStyle: "single"` + Prettier `singleQuote: true` |
| ENFORCE_TRAILING_COMMA = "WhenMultiline"  | Prettier `trailingComma: "all"`   |
| FORCE_SEMICOLON_STYLE = true              | Prettier `semi: true`             |
| MarkdownNavigatorCodeStyleSettings RIGHT_MARGIN = 72 | Not enforced — use `.editorconfig` per-repo if needed |

### Performance tuning (from `jetbrains/idea.properties` + `webstorm.vmoptions`)

| WebStorm                                          | Windsurf                          |
|---------------------------------------------------|-----------------------------------|
| typescript.service.memoryLimit = 4096             | `typescript.tsserver.maxTsServerMemory: 8192` |
| idea.max.intellisense.filesize = 5000             | `editor.maxTokenizationLineLength: 20000` |
| idea.max.highlight.filesize = 2000                | `editor.largeFileOptimizations: true` (auto) |
| editor.zero.latency.typing = true                 | `editor.experimental.asyncTokenization: true` |
| -Xmx8192m                                         | (Electron-driven; not user-configurable) |
| -XX:+UseZGC (low-pause GC)                        | (N/A for Electron) |
| git.wait.for.changed.files.indexing = false       | `git.autorefresh: true` + `git.autofetch: false` |

### Keymap (from `jetbrains/keymap.xml`)

The IntelliJ Keybindings extension covers ~90% of the shortcuts. The custom
WebStorm bindings from `keymap.xml` that need explicit override live in
`keybindings.json` with one comment header per binding linking back to the
WebStorm action ID:

| WebStorm action                       | Bind                       | Windsurf cmd                          |
|---------------------------------------|----------------------------|---------------------------------------|
| `RecentFiles`                         | `cmd+e`                    | `workbench.action.openRecent`         |
| `FindUsages`                          | `alt+f7` + `shift+cmd+l`   | `editor.action.goToReferences`        |
| `GotoTypeDeclaration`                 | `shift+cmd+b` + `shift+ctrl+b` | `editor.action.goToTypeDefinition`|
| `QuickTypeDefinition`                 | `shift+ctrl+alt+q`         | `editor.action.peekTypeDefinition`    |
| `EditorCloneCaretAbove`/`Below`       | `shift+cmd+alt+up/down`    | `editor.action.insertCursor[Above/Below]` |
| `GotoTest`                            | `shift+ctrl+t`             | `testing.runCurrentFile`              |
| `RunClass`                            | `shift+ctrl+r`             | `workbench.action.tasks.runTask`      |
| `SplitHorizontally/Vertically/Unsplit`| `shift+ctrl+cmd+{h/s/u}`   | `workbench.action.split*`             |
| `MoveTabDown/Right`                   | `shift+ctrl+alt+{j/l}`     | `workbench.action.moveEditorTo*Group` |
| `HideAllWindows`                      | `shift+cmd+f12`            | `workbench.action.maximizeEditor`     |
| `ActivateTerminalToolWindow`          | `alt+f12`+`ctrl+cmd+4`     | `workbench.action.terminal.toggleTerminal` |
| `Javascript.Linters.EsLint.Fix`       | `alt+s`                    | `eslint.executeAutofix`               |
| `Vcs.Push.Force`                      | `shift+ctrl+cmd+k`         | `git.pushForce`                       |
| `Annotate`                            | `ctrl+alt+a`               | `gitlens.toggleFileBlame`             |

### Vim layering

The IntelliJ extension and `vscodevim` cooperate via the `vim.handleKeys` map
in `settings.json`. Keys that should reach IntelliJ (e.g. `<C-w>` for window
nav, `<C-/>` for comment line) are set to `false` so vim doesn't intercept
them. Motion keys (`<C-d>`, `<C-u>`, `<C-f>`, `<C-b>`) stay vim-owned.

If the operator wants more vim ergonomics later (e.g. `relativenumber`,
`scrolloff`, `<leader>` mappings for fuzzy file open), add them under
`vim.normalModeKeyBindingsNonRecursive` / `vim.visualMode…` in
`settings.json`. The leader is set to `<space>` to match common neovim
configs.

## Extensions

`extensions.txt` is the source of truth. Each block of extensions replaces a
specific WebStorm built-in — see comments in the file. Doctor module reads it,
diffs against `windsurf --list-extensions`, and installs missing ones on
`--fix`.

**Adding an extension:** append to `extensions.txt`, run `dotfiles-doctor --fix`.

**Removing an extension:** delete from `extensions.txt` AND run `windsurf
--uninstall-extension <id>` manually (the doctor never uninstalls — it only adds
and verifies, so an operator can install local-only extensions through the UI
without dotfiles fighting back).

**Per-machine extensions** (e.g. work-only or one-off): install via the
Windsurf UI. They land in `~/.codeium/windsurf/extensions/` and are NOT
managed by dotfiles. Use `extensions.txt` only for cross-machine essentials.

### Corporate TLS-inspection workaround

Windsurf's CLI uses Electron's bundled Node, which does **not** honour the
macOS keychain. On networks that do TLS inspection (a corporate
CA), `windsurf --install-extension <id>` fails with `self signed
certificate in certificate chain`.

The doctor module handles this automatically: it exports a Node-compatible
PEM bundle from `/Library/Keychains/System.keychain` and
`/System/Library/Keychains/SystemRootCertificates.keychain` to
`$WINDSURF_LOCAL_DIR/ca-bundle.pem` (default
`~/.local/share/dotfiles-windsurf/ca-bundle.pem`) and passes it via
`NODE_EXTRA_CA_CERTS` for every install. The bundle refreshes if older than
30 days, so newly-trusted corporate roots get picked up within a month
without manual intervention.

**Force refresh:** delete the cached PEM and rerun the doctor.

```bash
rm -f ~/.local/share/dotfiles-windsurf/ca-bundle.pem
dotfiles-doctor --fix --module windsurf
```

**Off a corp network:** the doctor still creates the bundle, but the install
proceeds against public CAs without needing it. No harm done.

## Performance choices worth flagging

The settings below intentionally diverge from Windsurf's defaults to win speed
on large TypeScript / multi-package monorepos. Each is reversible by
removing the key from `settings.json`.

- **`editor.minimap.enabled: false`** — JetBrains has no minimap by default;
  rendering it eats GPU on large files. Off matches WebStorm and saves ~5–10%
  CPU on big files.
- **`extensions.autoUpdate: false` + `update.mode: "manual"`** — Windsurf's
  background update checks slow cold-start by 1–2s; manual mode means a stable
  IDE between explicit upgrades.
- **`telemetry.telemetryLevel: "off"`** — Cuts network chatter at startup and
  during use. The same setting in WebStorm's `disabled_plugins.txt` disables
  `com.intellij.filePrediction` for the same reason.
- **`files.watcherExclude`** — Excludes `node_modules`, `dist`, `.next`,
  `.turbo`, `.yarn/cache`, `.worktrees`, `.minsky/`, and other generated dirs
  from the file watcher. Without this, opening a yarn-workspace monorepo can
  burn 1+ CPU continuously on `chokidar` watching ~50k files. With this, the
  watcher tracks only source files.
- **`search.exclude`** — Same paths excluded from search, plus lock files and
  minified bundles. Speeds full-text search by 10–100× on large repos.
- **`typescript.tsserver.maxTsServerMemory: 8192`** — JetBrains' default
  tsserver heap is 512MB and chokes on monorepos with 30+ workspaces;
  WebStorm bumps to 4GB. Windsurf inherits VS Code's default of 3GB; we go
  to 8GB to match the operator's WebStorm tuning.
- **`typescript.tsserver.experimental.enableProjectDiagnostics: false`** —
  Full-project type errors on every keystroke is too aggressive for a large
  TS monorepo; per-file is fine and avoids 1–2s pauses on save.
- **`workbench.editor.limit.value: 20`** — Cap open editor tabs per group.
  Hundreds of open tabs makes the tab strip render the entire row on every
  switch; capping at 20 (with LRU eviction) keeps switches instant.

## Per-machine overrides

Same convention as `jetbrains/`: drop an `override.json5` file at
`$WINDSURF_LOCAL_DIR/settings.override.json5` (default
`~/.local/share/dotfiles-windsurf/`) and the doctor module will merge it on
top of the base `settings.json` before symlinking. Useful when:

- A 4K monitor needs a different font size (`editor.fontSize: 17`).
- A specific machine has different memory pressure (`tsserver.maxTsServerMemory: 4096`).
- The operator wants to experiment with a setting before committing it to all
  machines.

`override.json5` is machine-local, never committed. The merge is shallow + deep
for object values (e.g. `files.watcherExclude` keys merge), so the override file
can be small.

## Verification

Run `dotfiles-doctor windsurf` to verify symlinks + extensions, or `dotfiles-doctor
--fix windsurf` to repair. The module is self-discovered via
`modules/windsurf/doctor.sh`.

The full audit list:

- `symlink.settings` — `windsurf/settings.json` → `User/settings.json`
- `symlink.keybindings` — `windsurf/keybindings.json` → `User/keybindings.json`
- `font.jetbrains_mono_nerd` — `fc-list` reports the font (shared with `jetbrains/`)
- `windsurf.installed` — Windsurf.app exists in `/Applications/`
- `extensions.installed.*` — every entry in `extensions.txt` is reported by
  `windsurf --list-extensions`

`make check` from the dotfiles root runs shellcheck on `doctor.sh` (alongside
all other module scripts) and runs the full bats suite, so any regression in
the doctor helpers is caught before commit.
