# JetBrains core-profile fixture correction

The executable check in #481 exposed two older core-profile fixtures that
create empty app bundles while expecting installed-IDE checks. On the unchanged
default branch, both `symlink.editor.webstorm` and `symlink.editor.goland`
assertions fail because those fixtures have no executable.

Goal: retain the intended installed-IDE coverage with runnable synthetic
bundles. Predict two observed assertion failures fall to zero while the
uninstalled-IDE control stays passing. Measurement: `heavy-run bats
tests/doctor-core-profile.bats`. Success requires all three tests; any missing
IDE check or changed no-IDE result rejects the fixture correction. The test
does not claim a real IDE can run.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; the captured default-branch failures.
