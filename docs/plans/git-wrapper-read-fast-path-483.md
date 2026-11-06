# Git wrapper: bounded read-only fast path

Issue #483 reports about 90 ms of wrapper overhead per Git invocation. The
suggested list includes fetch, which writes remote-tracking refs. This test
does not treat fetch, arbitrary options, aliases, or general Git commands as
read-only.

Goal: reduce overhead for two exact calls while retaining Git fallback and
push checks. Question: can version and repository-directory lookups each
reduce their median added wrapper time by at least 30%?

Measurement, from the repository root: `heavy-run hyperfine --warmup 2 --runs
10 --export-json /tmp/git-wrapper-483.json '/usr/bin/git --version'
'./bin/git --version' '/usr/bin/git rev-parse --git-dir' './bin/git rev-parse
--git-dir'`. For each call subtract the direct Git median from the wrapper
median before and after. Run `heavy-run bats tests/git-wrapper.bats
tests/public-push-allowlist.bats` for behavior.

Success requires at least 30% less added median time for both calls, correct
output and exit status, working fallback when system Git cannot run, and
unchanged push refusals. A negative or negligible baseline overhead, either
improvement below 30%, or a safety failure rejects this approach. This does
not claim a speedup for other calls or the reported application workload.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #483's measured wrapper overhead.
