use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Stdio};

#[test]
fn ambiguous_input_reaches_the_guard_unchanged() {
    let directory = std::env::temp_dir().join(format!("hook-status-fixture-{}", std::process::id()));
    std::fs::create_dir(&directory).unwrap();
    let guard = directory.join("guard.sh");
    std::fs::write(&guard, b"#!/bin/bash\ncat\nexit 7\n").unwrap();
    std::fs::set_permissions(&guard, std::fs::Permissions::from_mode(0o700)).unwrap();
    let input = br#"{"tool_input":{"command":"git status; echo x"}}"#;
    let mut child = Command::new(env!("CARGO_BIN_EXE_dotfiles-hook-status"))
        .arg(&guard).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    let result = child.wait_with_output().unwrap();
    assert_eq!(result.status.code(), Some(7));
    assert_eq!(result.stdout, input);
    std::fs::remove_file(guard).unwrap();
    std::fs::remove_dir(directory).unwrap();
}

#[test]
fn literal_status_does_not_start_the_guard() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_dotfiles-hook-status"))
        .arg("/missing/fixture/guard.sh")
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped())
        .spawn().unwrap();
    child.stdin.take().unwrap().write_all(br#"{"tool_input":{"command":"git status"}}"#).unwrap();
    let result = child.wait_with_output().unwrap();
    assert!(result.status.success());
    assert!(result.stdout.is_empty() && result.stderr.is_empty());
}
