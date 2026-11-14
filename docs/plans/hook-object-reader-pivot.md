# Hook timing object-reader pivot

Registered before the in-process reader experiment, 2026-11-12.

The proposed Git subprocess reader has no proven bounded cleanup when an owned
child or descendant hangs. Do not use it for a qualified timing run. The
installed libgit2 library is a possible in-process alternative; its use is
not yet qualified.

Hypothesis: a pinned, offline libgit2 adapter can read the selected old and
candidate Git objects from the intended local repository without starting a
child process, following alternate object stores, or accepting changed object
identities. It can enforce explicit object-size limits before decoding.

Measurement: independently review the installed library, version, ABI,
dependency closure, repository-open and object-database settings. In scratch
repositories, compare the selected commit, tree, mode and blob identities
with Git-created fixtures. Test packed and loose objects, missing objects,
wrong type or path, altered content, size limits, alternate stores, symlinks,
replacement configuration and hostile environment settings. Verify all native
objects are freed and errors do not expose paths or source contents. Run no
source programs or timing workloads during this experiment.

Success: zero child processes or network access; every supported fixture
matches its independently created expected identity; every planted malformed,
oversized, alternate-store or wrong-repository case is refused; zero leaked
native handles in the reviewed lifecycle. Pin and check the actual library and
relevant repository inputs before and after any later observation.

Pivot: if object-store isolation, bounded reads, native lifecycle or source
identity cannot be established, leave the reader and timing result
inconclusive. Do not introduce a hand-written partial Git object parser or
signal a process without proven ownership and cleanup.

Anchors: [libgit2 repository open flags](https://libgit2.org/docs/reference/main/repository/git_repository_open_flag_t.html),
[object database API](https://libgit2.org/docs/reference/main/odb/index.html),
and [candidate observation prediction](hook-candidate-observation-prediction.md).

## Candidate snapshot alternative

Registered before building the snapshot adapter, 2026-11-12. A read-only
inspection found checked-out copies whose hook bytes match the previously
observed old blob. That observation is not a timing result.

Hypothesis: an independently reviewed, private source snapshot can bind the
old and candidate paths to their pinned commits before admission. The timing
worker can then verify bounded regular-file reads against that snapshot without
running Git or decoding packed objects during measurement.

Measurement: independently verify commit, path, mode and Git blob identity
for every old and candidate input. Record the mapping in a private audit bound
to a fresh run ID and both revisions. Copy only bounded regular files into an
owner-only snapshot; reject links, mismatched hashes, changed source, missing
files and altered audit records. Recheck snapshot identities before and after
capture. Test the exact adapter and its launcher in isolated fixtures, then
have an independent reviewer audit the actual source, tool and startup inputs.

Success: every required input has one verified revision/path/mode/blob mapping;
zero live Git, library object reads or source changes during measurement;
every planted missing, linked, oversized, altered or mismatched input is
refused. Preserve all timing, memory, output, admission and postflight gates.

Pivot: if the commit-to-blob mapping, snapshot source, ownership or retained
binding cannot be established, do not time and mark the result inconclusive.
This is trusted local correlation, not protection from same-user tampering or
transient swaps. An audit command that hangs does not authorize a measurement;
never send a signal without independently proven ownership and cleanup.
