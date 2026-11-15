use std::io::Write;
use std::process::{Command, Stdio};

use dotfiles_migration_inventory::shell_discovery::{inspect, FindingKind};

#[test]
fn shfmt_tree_reports_bodies_outputs_and_dynamic_calls_without_running_source() {
    let Some(shfmt) = std::env::var_os("INVENTORY_SHFMT") else { return; };
    let marker = std::env::temp_dir().join(format!("inventory-source-not-run-{}", std::process::id()));
    assert!(!marker.exists());
    let source = format!("python3 -c \"open('{}','w').write('executed')\"\npython3 - <<'PY'\nprint(1)\nPY\ncat > generated <<'END'\n#!/bin/sh\nEND\n$PROGRAM -c example\n", marker.display());
    let mut child = Command::new(shfmt).args(["-ln", "bash", "--to-json"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
    child.stdin.take().unwrap().write_all(source.as_bytes()).unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let report = inspect(source.len(), &output.stdout).unwrap();
    assert!(report.findings.iter().filter(|f| f.kind == FindingKind::Embedded && f.category == "python").count() >= 2);
    assert!(report.findings.iter().any(|f| f.kind == FindingKind::GeneratedCandidate));
    assert!(report.findings.iter().any(|f| f.kind == FindingKind::Unresolved));
    assert!(!report.complete);
    assert!(!marker.exists());
}
