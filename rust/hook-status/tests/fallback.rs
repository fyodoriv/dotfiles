use std::io::Write;
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
