//! Per-rule macOS process lookup. Failure falls back to the existing pgrep path.
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{CString, OsStr};
use std::os::unix::ffi::OsStrExt;

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

struct Details { identity: Identity, parent: u32, system: bool, name: Vec<u8> }

fn details(pid: u32) -> Result<Details, ()> {
    let mut info = std::mem::MaybeUninit::<libc::proc_bsdinfo>::uninit();
    let size = std::mem::size_of::<libc::proc_bsdinfo>();
    // SAFETY: info has space for the requested structure and the PID is bounded.
    if pid > i32::MAX as u32 || unsafe {
        libc::proc_pidinfo(pid as i32, libc::PROC_PIDTBSDINFO, 0, info.as_mut_ptr().cast(), size as i32)
    } != size as i32 { return Err(()); }
    // SAFETY: proc_pidinfo returned the complete structure.
    let info = unsafe { info.assume_init() };
    let name = info.pbi_comm.iter().take_while(|c| **c != 0).map(|c| *c as u8).collect();
    Ok(Details { identity: Identity { seconds: info.pbi_start_tvsec, micros: info.pbi_start_tvusec },
        parent: info.pbi_ppid, system: info.pbi_flags & 1 != 0, name })
}

fn arguments(pid: u32) -> Option<Vec<Vec<u8>>> {
    let mut mib = [libc::CTL_KERN, libc::KERN_PROCARGS2, pid as i32];
    let mut size = 0usize;
    // SAFETY: the MIB and output length are valid; no output buffer is provided.
    if unsafe { libc::sysctl(mib.as_mut_ptr(), 3, std::ptr::null_mut(), &mut size,
        std::ptr::null_mut(), 0) } != 0 || size > 8 * 1024 * 1024 || size < 4 { return None; }
    let mut data = vec![0u8; size];
    // SAFETY: data has size bytes and the MIB and length pointers remain valid.
    if unsafe { libc::sysctl(mib.as_mut_ptr(), 3, data.as_mut_ptr().cast(), &mut size,
        std::ptr::null_mut(), 0) } != 0 || size > data.len() { return None; }
    data.truncate(size);
    let argc = i32::from_ne_bytes(data.get(..4)?.try_into().ok()?);
    if !(0..=65536).contains(&argc) { return None; }
    let mut pos = 4 + data.get(4..)?.iter().position(|b| *b == 0)?;
    while data.get(pos) == Some(&0) { pos += 1; }
    let mut args = Vec::new();
    for _ in 0..argc {
        let rest = data.get(pos..)?;
        let end = rest.iter().position(|b| *b == 0)?;
        args.push(rest[..end].to_vec());
        pos += end + 1;
    }
    Some(args)
}

fn matches(pid: u32, info: &Details, expression: &Expression, full: bool) -> bool {
    let args = arguments(pid).unwrap_or_default();
    let value = if !full {
        let first = args.first().filter(|a| !a.is_empty()).unwrap_or(&info.name);
        first.rsplit(|b| *b == b'/').next().unwrap_or_default().to_vec()
    } else if args.is_empty() {
        info.name.clone()
    } else {
        args.join(&b' ')
    };
    expression.matches(&value, !full)
}

pub fn find(query: &OsStr, full: bool) -> Result<BTreeMap<u32, Identity>, ()> {
    let expression = Expression::compile(query)?;
    // SAFETY: querying the count uses no output buffer.
    let count = unsafe { libc::proc_listallpids(std::ptr::null_mut(), 0) };
    if count <= 0 { #[cfg(test)] eprintln!("process list count failed"); return Err(()); }
    let mut pids = vec![0i32; count as usize + 128];
    let bytes = pids.len().checked_mul(std::mem::size_of::<i32>()).ok_or(())?;
    if bytes > i32::MAX as usize { return Err(()); }
    // SAFETY: pids contains bytes writable bytes for the returned PID list.
    let count = unsafe { libc::proc_listallpids(pids.as_mut_ptr().cast(), bytes as i32) };
    if count <= 0 || count as usize >= pids.len() { #[cfg(test)] eprintln!("process list read failed"); return Err(()); }
    pids.truncate(count as usize);
    let mut ancestors = BTreeSet::new();
    let mut current = std::process::id();
    while current != 0 {
        if !ancestors.insert(current) { #[cfg(test)] eprintln!("ancestor cycle"); return Err(()); }
        current = details(current).map_err(|_| { #[cfg(test)] eprintln!("ancestor details failed"); })?.parent;
    }
    let mut result = BTreeMap::new();
    for pid in pids.into_iter().filter(|pid| *pid > 0).map(|pid| pid as u32) {
        if ancestors.contains(&pid) { continue; }
        let Ok(before) = details(pid) else { continue };
        if before.system || !matches(pid, &before, &expression, full) { continue; }
        let after = details(pid).map_err(|_| { #[cfg(test)] eprintln!("candidate details failed"); })?;
        if before.identity == after.identity && !after.system && matches(pid, &after, &expression, full) {
            result.insert(pid, after.identity);
        }
    }
    Ok(result)
}

pub fn same(pid: u32, expected: Identity, query: &OsStr, full: bool) -> bool {
    let Ok(expression) = Expression::compile(query) else { return false };
    let Ok(before) = details(pid) else { return false };
    if before.identity != expected || before.system || !matches(pid, &before, &expression, full) { return false; }
    details(pid).is_ok_and(|after| after.identity == expected && !after.system)
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
        let pattern = format!("^{name}$");
        let selected = find(OsStr::new(&pattern), false).unwrap();
        let pid = first.child.id();
        let identity = selected[&pid];
        let altered = Identity { seconds: identity.seconds, micros: identity.micros ^ 1 };
        assert!(!same(pid, altered, OsStr::new(&pattern), false));
        drop(first);
        assert!(!same(pid, identity, OsStr::new(&pattern), false));
    }
}
