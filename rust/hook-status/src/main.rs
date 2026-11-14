//! Read-only status shortcut. Other inputs are passed to the existing guard.
use std::io::{self, Read};

#[cfg(target_os = "macos")]
fn send_receipt(value: u8) -> io::Result<()> {
    // SAFETY: descriptor 3 is the caller's receipt pipe; value is valid for one byte.
    if unsafe { libc::write(3, (&value as *const u8).cast(), 1) } != 1 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: descriptor 3 belongs to this process and is no longer needed.
    if unsafe { libc::close(3) } != 0 { return Err(io::Error::last_os_error()); }
    Ok(())
}

#[cfg(target_os = "macos")]
fn private_input(input: &[u8]) -> io::Result<(std::fs::File, std::ffi::CString)> {
    use std::io::{Seek, SeekFrom, Write};
    use std::os::fd::FromRawFd;
    use std::os::unix::fs::MetadataExt;

    let mut template = b"/tmp/.dotfiles-hook-XXXXXX\0".to_vec();
    // SAFETY: template is writable, NUL-terminated, and ends with six Xs.
    let fd = unsafe { libc::mkstemp(template.as_mut_ptr().cast()) };
    if fd < 0 { return Err(io::Error::last_os_error()); }
    // SAFETY: mkstemp returned a new owned descriptor.
    let mut file = unsafe { std::fs::File::from_raw_fd(fd) };
    let name = std::ffi::CString::from_vec_with_nul(template).unwrap();
    // Unlink before writing; only this descriptor retains the input file.
    // SAFETY: name is the NUL-terminated path returned by mkstemp.
    if unsafe { libc::unlink(name.as_ptr()) } != 0 { return Err(io::Error::last_os_error()); }
    let metadata = file.metadata()?;
    // SAFETY: geteuid has no arguments or memory effects.
    if metadata.nlink() != 0 || metadata.mode() & 0o077 != 0 || metadata.uid() != unsafe { libc::geteuid() } {
        return Err(io::Error::new(io::ErrorKind::PermissionDenied, "private input check failed"));
    }
    // SAFETY: fd is owned and remains open; FD_CLOEXEC prevents descriptor leaks.
    if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } < 0 { return Err(io::Error::last_os_error()); }
    file.write_all(input)?;
    file.seek(SeekFrom::Start(0))?;
    Ok((file, name))
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
    #[cfg(not(target_os = "macos"))]
    if mode == "--exec" { return Err("unsupported platform"); }
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).map_err(|_| "input read failed")?;
    if literal_status(&input) {
        #[cfg(target_os = "macos")]
        if mode == "--exec" { send_receipt(b'A').map_err(|_| "receipt failed")?; }
        return Ok(0);
    }
    if mode == "--check" { return Ok(1); }
    #[cfg(target_os = "macos")]
    {
        use std::os::unix::process::CommandExt;
        use std::process::{Command, Stdio};
        let (file, _) = private_input(&input).map_err(|_| "fallback input failed")?;
        send_receipt(b'F').map_err(|_| "receipt failed")?;
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
    let exec_mode = std::env::args_os().nth(1).is_some_and(|mode| mode == "--exec");
    match run() {
        Ok(status) => std::process::exit(status),
        Err(_) if exec_mode => { eprintln!("BLOCKED: native guard could not complete safely."); std::process::exit(2); },
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
        // SAFETY: name remains a valid NUL-terminated path.
        assert_eq!(unsafe { libc::access(name.as_ptr(), libc::F_OK) }, -1);
        let mut content = Vec::new();
        file.read_to_end(&mut content).unwrap();
        assert_eq!(content, b"fixture input");
    }
}
