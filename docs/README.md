# Documentation map

This page lists every dotfiles doc and the question it answers. Start with the
first doc in your group. Agents start with [`AGENTS.md`](../AGENTS.md) and open
only the doc its routing table names.

Groups follow [Diátaxis](https://diataxis.fr/): tutorials teach, how-to guides
solve one task, reference lists facts, explanation gives the reasons.

## Tutorials — learn by doing

| Doc | What it answers | Audience |
|---|---|---|
| [onboarding.md](onboarding.md) | How do I set up a new Mac from zero? | human |
| [verify-setup.md](verify-setup.md) | How do I check that the setup worked? | human |
| [migration.md](migration.md) | How do I move from my old dotfiles? | human |

## How-to guides — solve one task

| Doc | What it answers | Audience |
|---|---|---|
| [troubleshooting.md](troubleshooting.md) | Something broke. What is the fix? | both |
| [forking-guide.md](forking-guide.md) | How do I fork and adapt this repo for my team? | human |
| [adoption-checklist.md](adoption-checklist.md) | What must a team lead do before a rollout? | human |
| [team-onboarding.md](team-onboarding.md) | How do I roll this out to a team? | human |
| [ci-setup.md](ci-setup.md) | How do I run the checks in CI for a team fork? | human |
| [multi-machine.md](multi-machine.md) | How do I keep several Macs in sync? | human |
| [key-rotation.md](key-rotation.md) | How do I rotate SSH and API keys? | human |
| [agentbrew-setup.md](agentbrew-setup.md) | How do I set up or repair agentbrew on this Mac? | both |
| [local-llm.md](local-llm.md) | How do I run the local-LLM stack? | both |
| [obsidian.md](obsidian.md) | How do I use Obsidian with Claude Code? | human |
| [workspace.md](workspace.md) | How do I see work across several workspaces? | both |
| [ship-it-reference.md](ship-it-reference.md) | How does an agent verify, commit, open a PR, and merge? | agent |
| [learn-repos-reference.md](learn-repos-reference.md) | How does the learn-repos workflow run? | agent |
| [research-url-reference.md](research-url-reference.md) | How does the research-url workflow run? | agent |

## Reference — look up facts

| Doc | What it answers | Audience |
|---|---|---|
| [changelog-archive.md](changelog-archive.md) | What changed before CHANGELOG.md became generated (2026-10-16)? | human |
| [learnings.md](learnings.md) | What did we predict for each change, and what happened? | both |
| [metrics.md](metrics.md) | Is dotfiles working? Each metric with its goal, pivot, and command | both |
| [observability.md](observability.md) | What did dotfiles do, what failed, and how healthy is this Mac? Logs, the errors log, and the doctor | both |
| [repo-map.md](repo-map.md) | Where does each file live, and which repo owns which path? | both |
| [module-reference.md](module-reference.md) | What does each doctor check do? | both |
| [what-gets-changed.md](what-gets-changed.md) | What does `dotfiles apply` change on my Mac? | human |
| [constitution.md](constitution.md) | What is the full text of each editing rule? | agent |
| [model-configuration.md](model-configuration.md) | Which model does each agent use, and where is it set? | both |
| [agent-browser-policy.md](agent-browser-policy.md) | How must agents use the shared browsers? | agent |
| [agent-hooks.md](agent-hooks.md) | Which hooks and wrappers enforce agent rules? | agent |
| [privacy-gates.md](privacy-gates.md) | Which gates stop private data from reaching GitHub? | both |
| [plugin-system.md](plugin-system.md) | How do tooling-app plugins work? | both |
| [faq.md](faq.md) | Short answers to common questions. | human |

## Explanation — understand why

| Doc | What it answers | Audience |
|---|---|---|
| [architecture.md](architecture.md) | How do the parts fit together, and why? | both |
| [security-model.md](security-model.md) | What does the security design protect against? | both |
| [local-ai-roadmap.md](local-ai-roadmap.md) | Which upstream work does the local-AI stack wait for? | both |

## Folders

| Folder | What it holds | Audience |
|---|---|---|
| [user-stories/](user-stories/) | What success looks like for each user goal | both |
| [competition/](competition/) | The competitive scorecard and how it is measured | both |
| [decisions/](decisions/) | Why the hard-to-reverse choices were made (ADRs) | both |
| [plans/](plans/) | Plans for non-trivial tasks (one per task ID) | agent |
| [templates/](templates/) | Templates, such as the plan template | agent |
| [audits/](audits/) | Past audits and run logs | both |
| [human-blocked-actions/](human-blocked-actions/) | Steps that need a human, with the exact command | both |
| [archive/](archive/) | Old RFCs, kept for history | human |

## Keep this map current

A new top-level `docs/*.md` file needs a row here in the same PR.
`tests/docs-contract.bats` fails when a doc is missing from this map or a link here
does not resolve.
