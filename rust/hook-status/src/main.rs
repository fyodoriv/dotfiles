//! Read-only status shortcut. Other inputs are passed to the existing guard.
use std::io::{self, Read, Write};
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};

fn literal_status(input: &[u8]) -> bool {
    // Escaped keys and duplicate target keys always go to the original guard.
    if input.contains(&b'\\')
        || input.windows(12).filter(|w| *w == b"\"tool_input\"").count() != 1
        || input.windows(9).filter(|w| *w == b"\"command\"").count() != 1
    {
        return false;
    }
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(input) else { return false };
    let Some(command) = value.get("tool_input").and_then(|v| v.get("command")).and_then(|v| v.as_str()) else { return false };
    if !command.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b' ' | b'=' | b'-')) { return false; }
    let mut words = command.split_ascii_whitespace();
    if words.next() != Some("git") || words.next() != Some("status") { return false; }
    words.all(|word| matches!(word, "-s" | "-b" | "--short" | "--branch" | "--long" | "--porcelain" | "--porcelain=v1" | "--porcelain=v2"))
}

fn run() -> Result<i32, &'static str> {
    let mut args = std::env::args_os();
    let _ = args.next();
    let legacy = args.next().ok_or("missing guard path")?;
    if args.next().is_some() { return Err("unexpected argument"); }
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).map_err(|_| "input read failed")?;
    if literal_status(&input) { return Ok(0); }
    let mut child = Command::new("/bin/bash").arg(legacy)
        .stdin(Stdio::piped()).stdout(Stdio::inherit()).stderr(Stdio::inherit())
        .spawn().map_err(|_| "guard start failed")?;
    if let Some(mut stdin) = child.stdin.take() { let _ = stdin.write_all(&input); }
    let status = child.wait().map_err(|_| "guard wait failed")?;
    Ok(status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(1)))
}

fn main() {
    match run() {
        Ok(status) => std::process::exit(status),
        Err(message) => { eprintln!("hook-status: {message}"); std::process::exit(1); }
    }
}

#[cfg(test)]
mod tests {
    use super::literal_status;

    #[test]
    fn accepts_only_literal_status_and_known_flags() {
        assert!(literal_status(br#"{"tool_input":{"command":"git status --short"}}"#));
        assert!(literal_status(br#"{"tool_input":{"command":"git status"},"cwd":"/tmp"}"#));
        assert!(!literal_status(br#"{"tool_input":{"command":"git status; echo x"}}"#));
        assert!(!literal_status(br#"{"tool_input":{"command":"git status --unknown"}}"#));
    }

    #[test]
    fn rejects_ambiguous_or_malformed_json() {
        assert!(!literal_status(br#"{"tool_input":{"command":"git status","command":"other"}}"#));
        assert!(!literal_status(br#"{"tool_input":{"command":"git status"},"tool_input":{}}"#));
        assert!(!literal_status(br#"{"tool_input":{"comm\u0061nd":"git status"}}"#));
        assert!(!literal_status(br#"{"tool_input":{"command":"git status"}"#));
        assert!(!literal_status(b""));
    }

    #[test]
    fn shell_control_characters_never_take_the_shortcut() {
        for ch in [';', '&', '|', '$', '(', ')', '`', '\n', '\t', '>', '<', '*', '?', '/'] {
            let event = serde_json::json!({"tool_input": {"command": format!("git status{ch}")}});
            assert!(!literal_status(event.to_string().as_bytes()));
        }
    }
}
