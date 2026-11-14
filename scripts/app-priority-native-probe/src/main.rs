//! Hosted-only comparison. It reads a process table and changes no priority.
#![cfg(target_os = "macos")]

use std::collections::BTreeSet;
use std::ffi::{CString, OsStr};
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::Instant;
use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};

struct Fixture(Child);
impl Fixture {
    fn finish(mut self) -> Result<(), &'static str> {
        self.0.stdin.take();
        if self.0.wait().map_err(|_| "child cleanup failed")?.success() {
            Ok(())
        } else {
            Err("child cleanup failed")
        }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.0.stdin.take();
        let _ = self.0.wait();
    }
}

struct Expression(libc::regex_t);
impl Expression {
    fn compile(pattern: &str) -> Result<Self, &'static str> {
        let pattern = CString::new(pattern).map_err(|_| "invalid pattern")?;
        let mut value = std::mem::MaybeUninit::<libc::regex_t>::uninit();
        // SAFETY: regcomp initializes value on success; pattern is NUL terminated.
        if unsafe { libc::regcomp(value.as_mut_ptr(), pattern.as_ptr(), libc::REG_EXTENDED) } != 0 {
            return Err("invalid pattern");
        }
        // SAFETY: regcomp returned success.
        Ok(Self(unsafe { value.assume_init() }))
    }
    fn matches(&self, value: &[u8], exact: bool) -> bool {
        let Ok(value) = CString::new(value) else { return false };
        let mut m = libc::regmatch_t { rm_so: 0, rm_eo: 0 };
        // SAFETY: all pointers are valid for this call and one match is allocated.
        let status = unsafe { libc::regexec(&self.0, value.as_ptr(), 1, &mut m, 0) };
        status == 0 && (!exact || (m.rm_so == 0 && m.rm_eo as usize == value.as_bytes().len()))
    }
}
impl Drop for Expression {
    fn drop(&mut self) {
        // SAFETY: each Expression contains one successfully compiled regex.
        unsafe { libc::regfree(&mut self.0) };
    }
}

fn spawn_child(name: &str, marker: &str) -> Result<Fixture, &'static str> {
    let exe = std::env::current_exe().map_err(|_| "child setup failed")?;
    let child = Command::new(exe).arg0(name).arg("--child").arg(marker)
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null())
        .spawn().map_err(|_| "child setup failed")?;
    let mut fixture = Fixture(child);
    let mut ready = [0u8; 1];
    let result = fixture.0.stdout.take().ok_or("child setup failed")?
        .read_exact(&mut ready);
    if result.is_err() || ready != [b'R'] { return Err("child setup failed"); }
    Ok(fixture)
}

fn native(pattern: &str, exact: bool) -> Result<BTreeSet<u32>, &'static str> {
    let expression = Expression::compile(pattern)?;
    let mut system = System::new().map_err(|_| "process scan failed")?;
    let n = system.refresh_processes_specifics(ProcessesToUpdate::All, true,
        ProcessRefreshKind::nothing().with_cmd(UpdateKind::Always));
    if n == 0 { return Err("process scan failed"); }
    let mut excluded = BTreeSet::new();
    let mut current = Some(Pid::from_u32(std::process::id()));
    while let Some(pid) = current {
        if !excluded.insert(pid.as_u32()) { return Err("ancestor cycle"); }
        current = system.process(pid).and_then(|p| p.parent());
    }
    let mut selected = BTreeSet::new();
    for (pid, process) in system.processes() {
        if excluded.contains(&pid.as_u32()) { continue; }
        let args = process.cmd();
        let value = if exact {
            let first = args.first().map(OsStr::new).unwrap_or_else(|| process.name());
            first.as_bytes().rsplit(|b| *b == b'/').next().unwrap_or_default().to_vec()
        } else if args.is_empty() {
            process.name().as_bytes().to_vec()
        } else {
            let mut result = Vec::new();
            for (index, arg) in args.iter().enumerate() {
                if index != 0 { result.push(b' '); }
                result.extend_from_slice(arg.as_bytes());
            }
            result
        };
        if expression.matches(&value, exact) { selected.insert(pid.as_u32()); }
    }
    Ok(selected)
}

fn pgrep(pattern: &str, exact: bool) -> Result<BTreeSet<u32>, &'static str> {
    let option = if exact { "-x" } else { "-f" };
    let result = Command::new("/usr/bin/pgrep").args([option, pattern])
        .stdin(Stdio::null()).stderr(Stdio::null()).output().map_err(|_| "reference failed")?;
    if !result.status.success() && result.status.code() != Some(1) { return Err("reference failed"); }
    let output = std::str::from_utf8(&result.stdout).map_err(|_| "reference output invalid")?;
    output.lines().map(|line| line.parse().map_err(|_| "reference output invalid")).collect()
}

fn compare(patterns: &[(&str, bool)]) -> Result<(), &'static str> {
    for (pattern, exact) in patterns {
        if pgrep(pattern, *exact)? != native(pattern, *exact)? { return Err("selection mismatch"); }
    }
    Ok(())
}

fn require_child(label: &'static str, pattern: &str, exact: bool, pid: u32) -> Result<(), &'static str> {
    let reference = pgrep(pattern, exact)?;
    let candidate = native(pattern, exact)?;
    if reference != candidate || !reference.contains(&pid) {
        eprintln!("case {label}: reference_child={} native_child={} equal={}",
            reference.contains(&pid), candidate.contains(&pid), reference == candidate);
        return Err("controlled selection mismatch");
    }
    Ok(())
}

fn run(measure: bool) -> Result<(), &'static str> {
    if std::env::var("GITHUB_ACTIONS").as_deref() != Ok("true")
        || std::env::var("RUNNER_ENVIRONMENT").as_deref() != Ok("github-hosted")
        || std::env::var("RUNNER_OS").as_deref() != Ok("macOS") {
        return Err("hosted macOS required");
    }
    let seed = std::process::id();
    let first = format!("rp{seed}a");
    let second = format!("rp{seed}b");
    let marker = format!("priorityprobe{seed}marker");
    let child_a = spawn_child(&first, "controlled-a")?;
    let child_b = spawn_child(&second, &marker)?;
    let exact_pattern = format!("^{first}$");
    let absent_pattern = format!("^rp{seed}never$");
    let patterns = [(exact_pattern.as_str(), true), (marker.as_str(), false), (absent_pattern.as_str(), true)];
    compare(&patterns)?;
    // SAFETY: getppid has no arguments and does not mutate process state.
    let parent = unsafe { libc::getppid() } as u32;
    let reference_all = pgrep(".*", false)?;
    let native_all = native(".*", false)?;
    for pid in [std::process::id(), parent] {
        if reference_all.contains(&pid) || native_all.contains(&pid) {
            return Err("ancestor exclusion mismatch");
        }
    }
    let long_name = format!("priorityselection{seed}long");
    let spaced_marker = format!("priorityprobe{seed} node minsky");
    let long_child = spawn_child(&long_name, &spaced_marker)?;
    let long_pattern = format!("^{long_name}$");
    let spaced_pattern = format!("priorityprobe{seed} node.*minsky");
    require_child("long-name", &long_pattern, true, long_child.0.id())?;
    require_child("spaced-arguments", &spaced_pattern, false, long_child.0.id())?;
    let finished_pid = long_child.0.id();
    long_child.finish()?;
    if pgrep(&long_pattern, true)?.contains(&finished_pid)
        || native(&long_pattern, true)?.contains(&finished_pid) {
        return Err("exited child remained selected");
    }
    let empty_child = spawn_child("", "empty-argument-zero")?;
    require_child("empty-argument-zero", "^app-priority.*$", true, empty_child.0.id())?;
    empty_child.finish()?;
    if !measure {
        child_a.finish()?;
        child_b.finish()?;
        println!("controlled selection parity passed");
        return Ok(());
    }
    let mut base = Vec::new();
    let mut candidate = Vec::new();
    for pair in 0..30 {
        for selector in if pair % 2 == 0 { [0, 1] } else { [1, 0] } {
            let now = Instant::now();
            for (pattern, exact) in &patterns {
                let result = if selector == 0 { pgrep(pattern, *exact)? } else { native(pattern, *exact)? };
                let expected = if *pattern == exact_pattern { Some(child_a.0.id()) }
                    else if *pattern == marker { Some(child_b.0.id()) } else { None };
                if result != expected.into_iter().collect() { return Err("selection mismatch"); }
            }
            let elapsed = now.elapsed().as_secs_f64() * 1000.0;
            if selector == 0 { base.push(elapsed); } else { candidate.push(elapsed); }
        }
    }
    base.sort_by(f64::total_cmp);
    candidate.sort_by(f64::total_cmp);
    let base = (base[14] + base[15]) / 2.0;
    let candidate = (candidate[14] + candidate[15]) / 2.0;
    let ratio = candidate / base;
    child_a.finish()?;
    child_b.finish()?;
    println!("{{\"pairs\":30,\"base_median_ms\":{base:.3},\"candidate_median_ms\":{candidate:.3},\"ratio\":{ratio:.6}}}");
    if ratio > 0.40 || candidate > 400.0 { return Err("timing threshold missed"); }
    Ok(())
}

fn main() {
    if std::env::args_os().nth(1).as_deref() == Some(OsStr::new("--child")) {
        let _ = std::io::stdout().write_all(b"R");
        let _ = std::io::stdout().flush();
        let _ = std::io::stdin().read_to_end(&mut Vec::new());
        return;
    }
    let measure = std::env::args_os().nth(1).as_deref() == Some(OsStr::new("--measure"));
    if let Err(message) = run(measure) { eprintln!("probe: {message}"); std::process::exit(1); }
}
