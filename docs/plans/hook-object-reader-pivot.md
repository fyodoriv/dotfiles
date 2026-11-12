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
