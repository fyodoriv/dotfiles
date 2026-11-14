#[cfg(all(target_os = "macos", not(feature = "fixture-actions")))]
mod macos {
    use std::ffi::c_int;
    use std::process::{Command, Stdio};

    const PRIO_PROCESS: c_int = 0;
    const PRIO_DARWIN_PROCESS: c_int = 4;
    const PRIO_DARWIN_BG: c_int = 0x1000;
    unsafe extern "C" {
        fn setpriority(which: c_int, who: u32, priority: c_int) -> c_int;
    }

    pub fn background(pid: u32, enabled: bool) {
        if pid > i32::MAX as u32 { return; }
        if !enabled {
            let _ = Command::new("taskpolicy").args(["-B", "-t", "0", "-l", "0", "-p", &pid.to_string()])
                .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status();
            return;
        }
        // SAFETY: scalar inputs; callers ignore errors just as the shell does.
        unsafe { setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG); }
    }

    pub fn nice(pid: u32, value: i32) {
        // SAFETY: scalar inputs; callers ignore errors just as the shell does.
        unsafe { setpriority(PRIO_PROCESS, pid, value); }
    }
}

#[cfg(all(target_os = "macos", not(feature = "fixture-actions")))]
pub use macos::{background, nice};

#[cfg(all(not(target_os = "macos"), not(feature = "fixture-actions")))]
pub fn background(_: u32, _: bool) {}
#[cfg(all(not(target_os = "macos"), not(feature = "fixture-actions")))]
pub fn nice(_: u32, _: i32) {}

#[cfg(feature = "fixture-actions")]
mod fixture {
    use std::io::Write;
    use std::process::{Command, Stdio};
    fn record(line: &str) {
        let path = std::env::var_os("ACTION_LOG").expect("fixture log required");
        let mut file = std::fs::OpenOptions::new().append(true).open(path)
            .expect("fixture log unavailable");
        writeln!(file, "{line}").expect("fixture log unavailable");
    }
    pub fn background(pid: u32, enabled: bool) {
        if enabled { record(&format!("taskpolicy -b -p {pid}")); }
        else {
            let _ = Command::new("taskpolicy").args(["-B", "-t", "0", "-l", "0", "-p", &pid.to_string()])
                .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status();
        }
    }
    pub fn nice(pid: u32, value: i32) { record(&format!("renice {value} -p {pid}")); }
}
#[cfg(feature = "fixture-actions")]
pub use fixture::{background, nice};
