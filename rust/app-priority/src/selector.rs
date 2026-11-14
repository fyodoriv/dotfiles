//! Per-rule macOS process lookup. Failure falls back to the existing pgrep path.
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{CString, OsStr};
use std::os::unix::ffi::OsStrExt;
use sysinfo::{Pid, Process, ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};

#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Identity { seconds: u64, micros: u64 }

struct Expression(libc::regex_t);
impl Expression {
    fn compile(pattern: &OsStr) -> Result<Self, ()> {
        let pattern = CString::new(pattern.as_bytes()).map_err(|_| ())?;
        let mut value = std::mem::MaybeUninit::<libc::regex_t>::uninit();
        // SAFETY: the output pointer is valid and the pattern is NUL terminated.
        if unsafe { libc::regcomp(value.as_mut_ptr(), pattern.as_ptr(), libc::REG_EXTENDED) } != 0 { return Err(()); }
        // SAFETY: regcomp initialized the regex on success.
        Ok(Self(unsafe { value.assume_init() }))
    }
    fn matches(&self, value: &[u8], exact: bool) -> bool {
        let Ok(value) = CString::new(value) else { return false };
        let mut matched = libc::regmatch_t { rm_so: 0, rm_eo: 0 };
        // SAFETY: the regex and string are valid and one result is allocated.
        let status = unsafe { libc::regexec(&self.0, value.as_ptr(), 1, &mut matched, 0) };
        status == 0 && (!exact || (matched.rm_so == 0 && matched.rm_eo as usize == value.as_bytes().len()))
    }
}
impl Drop for Expression {
    fn drop(&mut self) {
        // SAFETY: this regex was initialized by a successful regcomp.
        unsafe { libc::regfree(&mut self.0) }
    }
}

fn matches(process: &Process, expression: &Expression, full: bool) -> bool {
    let args = process.cmd();
    let value = if !full {
        let first = args.first().map(OsStr::new).unwrap_or_else(|| process.name());
        first.as_bytes().rsplit(|b| *b == b'/').next().unwrap_or_default().to_vec()
    } else if args.is_empty() {
        process.name().as_bytes().to_vec()
    } else {
        let mut value = Vec::new();
        for (index, arg) in args.iter().enumerate() {
            if index != 0 { value.push(b' '); }
            value.extend_from_slice(arg.as_bytes());
        }
        value
    };
    expression.matches(&value, !full)
}

fn details(pid: u32) -> Result<(Identity, bool), ()> {
    let mut info = std::mem::MaybeUninit::<libc::proc_bsdinfo>::uninit();
    let size = std::mem::size_of::<libc::proc_bsdinfo>();
    // SAFETY: info has space for the requested structure; the PID is bounded below.
    if pid > i32::MAX as u32 || unsafe {
        libc::proc_pidinfo(pid as i32, libc::PROC_PIDTBSDINFO, 0, info.as_mut_ptr().cast(), size as i32)
    } != size as i32 { return Err(()); }
    // SAFETY: proc_pidinfo returned the complete structure.
    let info = unsafe { info.assume_init() };
    Ok((Identity { seconds: info.pbi_start_tvsec, micros: info.pbi_start_tvusec }, info.pbi_flags & 1 != 0))
}

fn refresh(system: &mut System, scope: ProcessesToUpdate<'_>) -> bool {
    system.refresh_processes_specifics(scope, true,
        ProcessRefreshKind::nothing().with_cmd(UpdateKind::Always)) > 0
}

pub fn find(query: &OsStr, full: bool) -> Result<BTreeMap<u32, Identity>, ()> {
    let expression = Expression::compile(query)?;
    let mut system = System::new().map_err(|_| ())?;
    if !refresh(&mut system, ProcessesToUpdate::All) { return Err(()); }
    let mut ancestors = BTreeSet::new();
    let mut current = Some(Pid::from_u32(std::process::id()));
    while let Some(pid) = current {
        if !ancestors.insert(pid.as_u32()) { return Err(()); }
        current = system.process(pid).and_then(Process::parent);
    }
    let candidates: Vec<Pid> = system.processes().iter()
        .filter(|(pid, process)| !ancestors.contains(&pid.as_u32()) && matches(process, &expression, full))
        .map(|(pid, _)| *pid).collect();
    let mut result = BTreeMap::new();
    for pid in candidates {
        let (before, is_system) = details(pid.as_u32())?;
        if is_system { continue; }
        if !refresh(&mut system, ProcessesToUpdate::Some(&[pid])) { return Err(()); }
        let process = system.process(pid).ok_or(())?;
        if !matches(process, &expression, full) { continue; }
        let (after, is_system) = details(pid.as_u32())?;
        if before == after && !is_system { result.insert(pid.as_u32(), after); }
    }
    Ok(result)
}

pub fn same(pid: u32, expected: Identity, query: &OsStr, full: bool) -> bool {
    let Ok(expression) = Expression::compile(query) else { return false };
    if !details(pid).is_ok_and(|(current, is_system)| current == expected && !is_system) { return false; }
    let Ok(mut system) = System::new() else { return false };
    let pid_value = Pid::from_u32(pid);
    if !refresh(&mut system, ProcessesToUpdate::Some(&[pid_value])) { return false; }
    if !system.process(pid_value).is_some_and(|process| matches(process, &expression, full)) { return false; }
    details(pid).is_ok_and(|(current, is_system)| current == expected && !is_system)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Read, Write};
    use std::os::unix::process::CommandExt;
    use std::process::{Child, Command, Stdio};

    struct Fixture { child: Child, _stdout: BufReader<std::process::ChildStdout> }
    impl Drop for Fixture {
        fn drop(&mut self) {
            self.child.stdin.take();
            let _ = self.child.wait();
        }
    }
    fn spawn(name: &str) -> Fixture {
        let child = Command::new(std::env::current_exe().unwrap()).arg0(name)
            .args(["--exact", "selector::tests::controlled_child", "--nocapture"])
            .env("DOTFILES_SELECTOR_CHILD", "1").stdin(Stdio::piped())
            .stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
        let mut child = child;
        let mut stdout = BufReader::new(child.stdout.take().unwrap());
        let mut line = String::new();
        loop {
            line.clear();
            assert!(stdout.read_line(&mut line).unwrap() > 0, "child did not start");
            if line.contains("SELECTOR_READY") { break; }
        }
        Fixture { child, _stdout: stdout }
    }
    #[test]
    fn controlled_child() {
        if std::env::var_os("DOTFILES_SELECTOR_CHILD").is_none() { return; }
        println!("SELECTOR_READY");
        std::io::stdout().flush().unwrap();
        std::io::stdin().read_to_end(&mut Vec::new()).unwrap();
    }
    #[test]
    fn lookup_matches_pgrep_order_and_rechecks_identity() {
        let name = format!("rp{}test", std::process::id());
        let first = spawn(&name);
        let second = spawn(&name);
        for (pattern, full) in [(format!("^{name}$"), false), (format!("{name}.*controlled_child"), true)] {
            let output = Command::new("/usr/bin/pgrep").arg(if full { "-f" } else { "-x" })
                .arg(&pattern).stderr(Stdio::null()).output().unwrap();
            assert!(output.status.success(), "reference lookup failed");
            let reference: Vec<u32> = std::str::from_utf8(&output.stdout).unwrap().lines()
                .map(|line| line.parse().unwrap()).collect();
            let candidate = find(OsStr::new(&pattern), full).unwrap();
            assert!(reference == candidate.keys().copied().collect::<Vec<_>>(), "controlled selection order differs");
            assert!(candidate.contains_key(&first.child.id()) && candidate.contains_key(&second.child.id()));
            assert!(same(first.child.id(), candidate[&first.child.id()], OsStr::new(&pattern), full));
        }
    }
}
