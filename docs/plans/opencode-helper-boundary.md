# OpenCode helper boundary

Register this review before the detailed source trace. An exploratory search
found the version helper in the LaunchAgent template, a CLI wrapper, a doctor
module and tests. A name search does not establish complete caller coverage.

- **Hypothesis:** A pinned source review can bind the helper and four observed
  caller categories to their declared resolution and invocation boundaries,
  while leaving dynamic selection and unknown callers unresolved.
- **Measurement:** Inspect source at commit
  `d6e4e4acc9e9e0ca2658b2875100316780c4b95b` with `git show` and a bounded
  tracked-source search. Record each source blob, exact line range, declared
  action and conditions. Verify identities and anchors against that commit.
- **Success:** Four of four observed caller categories and the helper have
  pinned source evidence or an explicit unresolved status; zero runtime
  execution, installed-binary identity or complete caller coverage claims.
- **Pivot:** A missing, ambiguous or changed source anchor remains unresolved.
  Do not infer that the selected executable is the installed binary or that a
  source-declared branch ran.
- **Anchor:** [lifecycle reconciliation](current-lifecycle-reconciliation.md),
  Basili, Caldiera and Rombach (1994), Goal Question Metric.

The review does not execute the helper, agent or tests. It does not qualify
the shared validator, generated output, or the migration audit.

## Pinned source review

These source declarations are bound to the registered commit. They do not
show that a branch ran, identify the selected executable, or establish all
dynamic callers. The bounded name search found the paths below; it cannot
exclude generated, aliased, or dynamically constructed references.

| Source | Blob | Declared boundary |
| --- | --- | --- |
| `lib/opencode-version.sh` | `5e6987aa133e73427fc6a620d04e6df95d25c9c1` | Lines 3–8 select the managed path if executable, otherwise use `command -v`; lines 12–21 execute the supplied path with `--version` and parse its major version. Lines 25–28 accept only major 1 for the legacy service. Lines 31–34 execute the supplied path with `service status` and check the returned prefix. |
| `.chezmoiscripts/run_onchange_launchagents.sh.tmpl` | `be36ad00231fe1fd95f6d2036831d12235486716` | Line 161 sources the helper. Lines 115–118 use the legacy predicate only after the setting and managed executable checks; lines 193–201 use the major-version helper on a separate skip path. The template also has a distinct render-time version command at line 5. |
| `bin/dotfiles-opencode` | `49ae52ffacba1a736af15327bcd96c561726b24b` | Lines 4–10 source the helper, resolve the executable, inspect its version and exec the version-1 attach route. Lines 11–45 handle version 2 arguments and exec the selected executable, or reject unsupported versions. |
| `modules/local-ai/doctor.sh` | `c565c5549fc38ee96ef51682c5668285e21d4312` | Lines 44–52 conditionally source the helper and choose a binary before requesting its version. Lines 64–74 and 90–100 declare distinct checks for major versions 1 and 2. The check framework's later invocation and its selected binary remain separate boundaries. |
| `tests/opencode-service.bats` | `88c75b6e0293748c83186da62a28ebb6f1e289a4` | Lines 3–29 create a scratch executable and isolate HOME and PATH. Lines 131–140 invoke the legacy predicate with that fixture; lines 155–165 extract and invoke a selector from the template. These test declarations are not evidence that tests ran during this review. |

All five identities and selected anchors were checked against the pinned Git
tree. The helper and four observed caller categories are now source-bound for
this review. Complete callers, generated code, runtime selection, ownership
and validator coverage remain unresolved. No reviewed source was executed.
