# Power-settings watcher tool check

The watcher records process details when macOS power settings change.
Its log can lose those details when a utility is missing from the job's
PATH. Use the existing LaunchAgent check to find the problem before repair.

- **Hypothesis**: Checking the rendered job PATH detects each missing bare
  utility without running the watcher or those utilities.
- **Measurement**: Run hosted `bats tests/dotfiles-launchagent-drift.bats`.
  Remove each declared utility from an otherwise complete scratch PATH
  in turn. Use a separate missing-`ps` repair case and a complete
  healthy job. Check the real job with `dotfiles-launchagent-drift`
  in read-only mode after merge.
- **Success**: All 10 missing tools produce one useful name each.
  Missing `ps` permits zero repair calls. One complete job reports
  healthy. Zero fixtures run the job or its tools.
- **Pivot**: Reject after 1 false finding, 1 missing utility reported
  healthy or 1 repair or script execution in a failing fixture.
- **Anchor**: The watcher in `bin/dotfiles-pmset-drift-watch` and
  Basili, Caldiera and Rombach (1994), Goal Question Metric.

The watcher chooses its power-setting reader by an absolute path.
The PATH check covers its ten bare utilities and uses the existing
behavior for an unsupported job form. The four-week live result stays
part of the broader LaunchAgent task.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44861475146/job/136715625345)
failed both missing-tool checks at the expected exit-status assertion.
The complete scratch job passed.
