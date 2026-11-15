# Git guard: literal Python document boundary

Registered before implementation on 2026-11-15. The full safe fixture fails in
[PR 691](https://github.com/fyodoriv/dotfiles/pull/691). Its quoted Python
heredoc writes a literal document; prose backticks are mistaken for shell
syntax and a later flag is counted against it.

**Hypothesis:** A bounded syntax proof can recognize that literal writer and
leave surrounding shell commands visible to the existing guard. The planted
safe command changes from blocked to allowed, with no new destructive allow.

**Measurement:** Hosted CI runs the original reproduction, existing guard
suite, and adversarial controls for executable Python, shell substitutions,
unsafe destinations, pipelines, and destructive Git before and after the writer.

**Success:** The planted safe case is allowed; every destructive control stays
blocked; parser or checker failures keep the original guard. **Pivot:** Any
new unsafe allow or unsupported syntax ambiguity rejects the change.

**Boundary:** Parse shell with the existing shfmt tool and Python with the
standard-library AST parser. Never execute the input. Accept only a literal
`pathlib.Path(...).write_text(...)` document writer in the proven command
shape; unknown statements, expressions, arguments and redirections fall back.
Do not suppress surrounding shell code or a Python program that can invoke it.

**Anchor:** `dangerous-git-safe-document-false-block` in TASKS.md; Basili,
Caldiera and Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).
