#![cfg(target_os = "macos")]

use std::io::Write;
use std::process::{Command, Output, Stdio};

fn invoke(native: bool, fail_perl: bool, receipt: &std::path::Path) -> Output {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let guard = root.join("agent-hooks/require-heavy-run.sh");
    let mut command = if native {
        let mut command = Command::new("/bin/bash");
        command.args(["-c", "exec \"$1\" --exec \"$2\" 3>\"$3\"", "_"])
            .arg(env!("CARGO_BIN_EXE_dotfiles-hook-heavy")).arg(&guard).arg(receipt);
        command
    } else {
        let mut command = Command::new("/bin/bash");
        command.arg(&guard).env("DOTFILES_NATIVE_HEAVY_BYPASS", "1");
        command
    };
    command.env_remove("HEAVY_RUN_HOOK").env_remove("PERL5OPT");
    if fail_perl { command.env("PERL5OPT", "-MDotfilesMissingPerlFixture"); }
    let mut child = command.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
    child.stdin.take().unwrap().write_all(br#"{"tool_input":{"command":"git status"},"cwd":"/tmp"}"#).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn native_status_keeps_perl_success_and_failure_results() {
    let receipt = std::env::temp_dir().join(format!("dotfiles-heavy-receipt-{}", std::process::id()));
    for fail in [false, true] {
        let baseline = invoke(false, fail, &receipt);
        let native = invoke(true, fail, &receipt);
        assert_eq!(native.status.code(), baseline.status.code());
        assert_eq!(native.stdout, baseline.stdout);
        assert_eq!(native.stderr, baseline.stderr);
        assert_eq!(std::fs::read(&receipt).unwrap(), if fail { b"F" } else { b"A" });
    }
    std::fs::remove_file(receipt).unwrap();
}
