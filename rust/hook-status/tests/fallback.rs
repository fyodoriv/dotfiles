use std::io::Write;
#[cfg(target_os = "macos")]
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Stdio};

#[test]
fn check_mode_returns_only_a_decision() {
    for (input, expected) in [
        (br#"{"tool_input":{"command":"git status"}}"#.as_slice(), 0),
        (br#"{"tool_input":{"command":"git status; echo x"}}"#.as_slice(), 1),
    ] {
        let mut child = Command::new(env!("CARGO_BIN_EXE_dotfiles-hook-status"))
            .arg("--check").stdin(Stdio::piped()).stdout(Stdio::piped())
            .stderr(Stdio::piped()).spawn().unwrap();
        child.stdin.take().unwrap().write_all(input).unwrap();
        let result = child.wait_with_output().unwrap();
        assert_eq!(result.status.code(), Some(expected));
        assert!(result.stdout.is_empty() && result.stderr.is_empty());
    }
}

#[cfg(target_os = "macos")]
#[test]
fn fallback_replaces_the_reader_and_preserves_input() {
    let directory = std::env::temp_dir().join(format!("hook-status-exec-{}", std::process::id()));
    std::fs::create_dir(&directory).unwrap();
    let guard = directory.join("guard.sh");
    std::fs::write(&guard, b"#!/bin/bash\n[ \"$DOTFILES_NATIVE_GUARD_BYPASS\" = 1 ] || exit 12\nprintf '%s' \"$$\" >&2\ncat\nexit 7\n").unwrap();
    std::fs::set_permissions(&guard, std::fs::Permissions::from_mode(0o700)).unwrap();
    let input = br#"{"tool_input":{"command":"git status; echo x"}}"#;
    let mut child = Command::new("/bin/bash")
        .args(["-c", "exec 3>&1; exec \"$1\" --exec \"$2\"", "_"])
        .arg(env!("CARGO_BIN_EXE_dotfiles-hook-status")).arg(&guard)
        .stdin(Stdio::piped()).stdout(Stdio::piped())
        .stderr(Stdio::piped()).spawn().unwrap();
    let pid = child.id().to_string();
    child.stdin.take().unwrap().write_all(input).unwrap();
    let result = child.wait_with_output().unwrap();
    assert_eq!(result.status.code(), Some(7));
    assert_eq!(result.stdout, [b"F".as_slice(), input].concat());
    assert_eq!(result.stderr, pid.as_bytes());
    std::fs::remove_file(guard).unwrap();
    std::fs::remove_dir(directory).unwrap();
}

#[cfg(target_os = "macos")]
#[test]
fn receiptless_execution_fails_closed() {
    let mut child = Command::new("/bin/bash")
        .args(["-c", "exec 3>&-; exec \"$1\" --exec /missing/guard", "_"])
        .arg(env!("CARGO_BIN_EXE_dotfiles-hook-status"))
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped())
        .spawn().unwrap();
    child.stdin.take().unwrap().write_all(br#"{"tool_input":{"command":"git status"}}"#).unwrap();
    let result = child.wait_with_output().unwrap();
    assert_eq!(result.status.code(), Some(2));
    assert!(result.stdout.is_empty());
}

#[cfg(target_os = "macos")]
#[test]
fn accepted_status_sends_allow_receipt() {
    let mut child = Command::new("/bin/bash")
        .args(["-c", "exec 3>&1; exec \"$1\" --exec /missing/guard", "_"])
        .arg(env!("CARGO_BIN_EXE_dotfiles-hook-status"))
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped())
        .spawn().unwrap();
    child.stdin.take().unwrap().write_all(br#"{"tool_input":{"command":"git status"}}"#).unwrap();
    let result = child.wait_with_output().unwrap();
    assert!(result.status.success());
    assert_eq!(result.stdout, b"A");
    assert!(result.stderr.is_empty());
}
