use std::io::Write;
use std::process::{Command, Stdio};

use dotfiles_migration_inventory::{shell_discovery::{inspect, scan_committed_shell, FindingKind}, snapshot::committed_tree};

#[test]
fn shfmt_tree_reports_bodies_outputs_and_dynamic_calls_without_running_source() {
    let Some(shfmt) = std::env::var_os("INVENTORY_SHFMT") else { return; };
    let marker = std::env::temp_dir().join(format!("inventory-source-not-run-{}", std::process::id()));
    assert!(!marker.exists());
    let source = format!("python3 -c \"open('{}','w').write('executed')\"\npython3 - <<'PY'\nprint(1)\nPY\ncat > generated <<'END'\n#!/bin/sh\nEND\npython3 - <<PY\n$SOURCE\nPY\n$PROGRAM -c example\n", marker.display());
    let mut child = Command::new(shfmt).args(["-ln", "bash", "--to-json"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
    child.stdin.take().unwrap().write_all(source.as_bytes()).unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let report = inspect(source.len(), &output.stdout).unwrap();
    assert!(report.findings.iter().filter(|f| f.kind == FindingKind::Embedded && f.category == "python").count() >= 2);
    assert!(report.findings.iter().any(|f| f.kind == FindingKind::GeneratedCandidate));
    assert!(report.findings.iter().any(|f| f.kind == FindingKind::Unresolved));
    assert!(report.findings.iter().any(|f| f.category == "dynamic-heredoc"));
    assert!(!report.complete);
    assert!(!marker.exists());
}

#[test]
fn interpreter_flags_do_not_replace_the_inline_program() {
    let Some(shfmt) = std::env::var_os("INVENTORY_SHFMT") else { return; };
    let source = concat!(
        "jq -e --argjson want \"$VALUE\" '.env' input\n",
        "jq -ce --arg name value '.name' input\n",
        "jq -e --slurpfile config input.json '.config' input\n",
        "jq -e --arg name value '.one' input\n",
        "jq -e --argjson n 1 '.two' input\n",
        "jq -e --arg n 1 '.three' input\n",
        "jq -e --arg n 1 '.four' input\n",
        "perl -MTime::HiRes=clock_gettime -e 'print 1'\n",
        "perl -MTime::HiRes=time -e 'print 2'\n",
        "perl -pe 's/a/b/'\n",
        "perl -eprint\\ 3\n",
        "jq --unknown value '.unknown' input\n",
    );
    let mut child = Command::new(shfmt).args(["-ln", "bash", "--to-json"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
    child.stdin.take().unwrap().write_all(source.as_bytes()).unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let report = inspect(source.len(), &output.stdout).unwrap();
    let bodies: Vec<_> = report.findings.iter().filter(|f| f.kind == FindingKind::Embedded)
        .map(|f| &source[f.start..f.end]).collect();
    for expected in ["'.env'", "'.name'", "'.config'", "'.one'", "'.two'", "'.three'", "'.four'", "'print 1'", "'print 2'", "'s/a/b/'"] {
        assert!(bodies.contains(&expected), "missing {expected}: {bodies:?}");
    }
    for flag in ["--arg", "--argjson", "--slurpfile", "-e"] {
        assert!(!bodies.contains(&flag), "option was reported as code: {flag}");
    }
    assert!(report.findings.iter().any(|f| f.category == "unsupported-jq-option"));
    assert!(report.findings.iter().any(|f| f.category == "interpreter-input"));
    assert!(!report.complete);
}

#[test]
fn scans_a_committed_shell_blob_with_a_trusted_parser() {
    let Some(shfmt) = std::env::var_os("INVENTORY_SHFMT") else { return; };
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let snapshot = committed_tree(&root).unwrap();
    let report = scan_committed_shell(&root, &snapshot, "agent-hooks/require-heavy-run.sh", std::path::Path::new(&shfmt)).unwrap();
    assert!(report.findings.iter().any(|f| f.kind == FindingKind::Embedded && f.category == "perl"));
    assert!(!report.complete);
    let in_repo_tool = root.join("rust/migration-inventory/tests/fixtures/shfmt");
    assert!(scan_committed_shell(&root, &snapshot, "agent-hooks/require-heavy-run.sh", &in_repo_tool).is_err());
    assert!(scan_committed_shell(&root.join("agent-hooks"), &snapshot, "agent-hooks/require-heavy-run.sh", std::path::Path::new(&shfmt)).is_err());
}

#[test]
fn command_reports_committed_findings_without_source_text() {
    let Some(shfmt) = std::env::var_os("INVENTORY_SHFMT") else { return; };
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let output = Command::new(env!("CARGO_BIN_EXE_migration-check"))
        .current_dir(root).args(["inventory", "--scan-shell", "agent-hooks/require-heavy-run.sh", "--shfmt"])
        .arg(shfmt).output().unwrap();
    assert!(output.status.success());
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["complete"], false);
    assert!(value["findings"].as_array().unwrap().iter().any(|f| f["kind"] == "embedded" && f["category"] == "perl"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("sub strip"));
}
