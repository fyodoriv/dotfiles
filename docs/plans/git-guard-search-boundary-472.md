# Quoted search: shell execution boundary

Issue #472 asks for a narrow, proven literal-search exception. The guard sees
command text before the execution shell interprets it. Its current matching
normalizes quoted words, so literal search data can be mistaken for a Git
operation. No change to that conservative matching is made here.

On 2026-11-06, isolated zsh probes showed that a shell alias or function can
replace an absolute command name. In the commands below the replacement only
prints a synthetic marker; no file or remote is changed:

```sh
zsh -c 'alias /usr/bin/env="printf unsafe"; eval "/usr/bin/env printf safe"'
zsh -c 'function /usr/bin/env { printf unsafe; }; eval "\\/usr/bin/env printf safe"'
```

Both printed `unsafe`. This establishes only the shown zsh cases. It does not
establish the state of any user's shell or the behavior of every shell. An
absolute path in parsed text alone is therefore not enough to prove which
executable that shell will invoke.

Before qualifying an exception, establish a trusted execution boundary that
accounts for the actual shell's aliases, functions, configuration and binary
identity. Then register the issue's exact four safe and eight unsafe inputs
before running that matrix. Unsupported or unproven cases must keep the
existing conservative refusal. No four-by-eight result or safe exception is
claimed here; #472 remains open.
