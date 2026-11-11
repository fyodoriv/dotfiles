# Record lockfile integrity investigation

On Nov 7, a read-only count of Agentbrew's `package-lock.json` found 79 of 907
non-root, non-link package entries without an `integrity` field. Some may be
optional or represented by another verified source; this count is not a
vulnerability finding and does not prove any installed package is unsafe.

Add a task to the Agentbrew task backend after the current gate finishes. It
must classify those entries by resolved source, optional/platform status and
whether npm verifies their bytes through another mechanism. Do not print
credentials or private registry details. Register a reproducible measurement
and safe lockfile-regeneration experiment before any lockfile change. Preserve
install behavior and require the normal dependency and full gates. The count
command inspected `packages` entries, excluded the root and entries marked
`link`, and counted absent `integrity` fields.

A later local classification found no `resolved` field on any of the 79.
Of these, 65 are marked development dependencies and three are optional;
these categories can overlap. This still does not prove a vulnerability.
