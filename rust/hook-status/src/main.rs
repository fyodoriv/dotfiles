//! Read-only status shortcut. Other inputs are passed to the existing guard.
use std::io::{self, Read};

#[cfg(target_os = "macos")]
fn private_input(input: &[u8]) -> io::Result<(std::fs::File, std::ffi::CString)> {
    use std::io::{Seek, SeekFrom, Write};
    use std::os::fd::FromRawFd;

    for _ in 0..8 {
        let mut random = [0u8; 12];
        // SAFETY: random points to a writable buffer of the requested size.
        unsafe { libc::arc4random_buf(random.as_mut_ptr().cast(), random.len()) };
        let suffix: String = random.iter().map(|byte| format!("{byte:02x}")).collect();
        let name = std::ffi::CString::new(format!("/dfh-{suffix}")).unwrap();
        // SAFETY: name is NUL-terminated and the mode is supplied for O_CREAT.
        let fd = unsafe { libc::shm_open(name.as_ptr(), libc::O_CREAT | libc::O_EXCL | libc::O_RDWR, 0o600) };
        if fd < 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::AlreadyExists { continue; }
            return Err(error);
        }
        // SAFETY: shm_open returned a new owned descriptor.
        let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
        // Unlink before writing: only this descriptor retains the input object.
        // SAFETY: name remains a valid NUL-terminated shared-memory name.
        if unsafe { libc::shm_unlink(name.as_ptr()) } != 0 { return Err(io::Error::last_os_error()); }
        file.write_all(input)?;
        file.seek(SeekFrom::Start(0))?;
        return Ok((file, name));
    }
    Err(io::Error::new(io::ErrorKind::AlreadyExists, "shared-memory name collision"))
}

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
    let mode = args.next().ok_or("missing check mode")?;
    let guard = args.next();
    if args.next().is_some() { return Err("unexpected argument"); }
    if mode != "--check" && mode != "--exec" { return Err("unknown mode"); }
    if (mode == "--check") != guard.is_none() { return Err("invalid arguments"); }
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).map_err(|_| "input read failed")?;
    if literal_status(&input) { return Ok(0); }
    if mode == "--check" { return Ok(1); }
    #[cfg(target_os = "macos")]
    {
        use std::os::unix::process::CommandExt;
        use std::process::{Command, Stdio};
        let (file, _) = private_input(&input).map_err(|_| "fallback input failed")?;
        let error = Command::new("/bin/bash").arg(guard.unwrap())
            .env("DOTFILES_NATIVE_GUARD_BYPASS", "1")
            .stdin(Stdio::from(file)).exec();
        let _ = error;
        Err("fallback start failed")
    }
    #[cfg(not(target_os = "macos"))]
    { Err("unsupported platform") }
}

fn main() {
    match run() {
        Ok(status) => std::process::exit(status),
        Err(_) => std::process::exit(1),
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

    #[cfg(target_os = "macos")]
    #[test]
    fn fallback_input_is_unlinked_before_use() {
        use std::io::Read;
        let (mut file, name) = super::private_input(b"fixture input").unwrap();
        // SAFETY: name is NUL-terminated and O_RDONLY needs no mode argument.
        let fd = unsafe { libc::shm_open(name.as_ptr(), libc::O_RDONLY) };
        assert_eq!(fd, -1);
        let mut content = Vec::new();
        file.read_to_end(&mut content).unwrap();
        assert_eq!(content, b"fixture input");
    }
}
