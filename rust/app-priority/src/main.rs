//! Candidate command; the installed shell remains active until qualification.
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

mod platform;
#[cfg(target_os = "macos")]
mod selector;

trait Backend {
    fn find(&mut self, query: &OsStr, full: bool) -> Vec<u32>;
    fn info(&mut self, pid: u32, field: &str) -> Vec<u8>;
    fn background(&mut self, pid: u32, enabled: bool);
    fn nice(&mut self, pid: u32, value: i32);
}

#[derive(Default)]
struct System {
    #[cfg(target_os = "macos")]
    identities: Option<(std::collections::BTreeMap<u32, selector::Identity>, std::ffi::OsString, bool)>,
}
impl Backend for System {
    fn find(&mut self, query: &OsStr, full: bool) -> Vec<u32> {
        #[cfg(target_os = "macos")]
        {
            if let Ok(found) = selector::find(query, full) {
                let pids = found.keys().copied().collect();
                self.identities = Some((found, query.to_owned(), full));
                return pids;
            }
            self.identities = None;
        }
        Command::new("pgrep").arg(if full { "-f" } else { "-x" }).arg(query)
            .stdin(Stdio::null()).stderr(Stdio::null()).output().ok()
            .map(|out| out.stdout.split(|b| *b == b'\n')
                .filter_map(|line| std::str::from_utf8(line).ok()?.parse::<u32>().ok())
                .filter(|pid| *pid > 0).collect()).unwrap_or_default()
    }
    fn info(&mut self, pid: u32, field: &str) -> Vec<u8> {
        Command::new("ps").args(["-p", &pid.to_string(), "-o", field])
            .stdin(Stdio::null()).stderr(Stdio::null()).output()
            .map(|out| out.stdout).unwrap_or_default()
    }
    fn background(&mut self, pid: u32, enabled: bool) {
        if self.current(pid) { platform::background(pid, enabled); }
    }
    fn nice(&mut self, pid: u32, value: i32) {
        if self.current(pid) { platform::nice(pid, value); }
    }
}
impl System {
    fn current(&self, pid: u32) -> bool {
        #[cfg(target_os = "macos")]
        if let Some((identities, query, full)) = &self.identities {
            return identities.get(&pid).is_some_and(|identity| selector::same(pid, *identity, query, *full));
        }
        let _ = pid;
        true
    }
}

#[derive(Clone, Copy)]
enum Action { Foreground, Background, Nice, Agent }

fn interactive<B: Backend>(backend: &mut B, pid: u32) -> bool {
    let mut current = pid;
    for _ in 0..16 {
        if current <= 1 { break; }
        let command = backend.info(current, "comm=");
        if ["WebStorm", "Ghostty", "Terminal", "iTerm", "WezTerm", "kitty", "Alacritty", "Warp", "Claude", "ChatGPT", "Codex"]
            .iter().any(|name| command.windows(name.len() + 6).any(|part| {
                part.starts_with(b"/") && &part[1..1 + name.len()] == name.as_bytes()
                    && &part[1 + name.len()..] == b".app/"
            })) { return true; }
        let parent = backend.info(current, "ppid=");
        let digits: Vec<u8> = parent.into_iter().filter(|b| !b.is_ascii_whitespace()).collect();
        let Some(next) = std::str::from_utf8(&digits).ok().and_then(|v| v.parse::<u32>().ok()) else { break };
        if next == current { break; }
        current = next;
    }
    false
}

fn apply<B: Backend>(backend: &mut B, name: &OsStr, full: bool, action: Action) {
    for pid in backend.find(name, full) {
        match action {
            Action::Foreground => backend.background(pid, false),
            Action::Background => { backend.background(pid, true); backend.nice(pid, 10); }
            Action::Nice => backend.nice(pid, 10),
            Action::Agent => {
                let fg = interactive(backend, pid);
                backend.background(pid, !fg);
                backend.nice(pid, if fg { 0 } else { 10 });
            }
        }
    }
}

fn custom<B: Backend>(backend: &mut B, bytes: &[u8]) {
    for raw in bytes.split_inclusive(|b| *b == b'\n').filter(|line| line.ends_with(b"\n")) {
        let line = raw.split(|b| *b == b'#').next().unwrap_or_default();
        let line = line.strip_suffix(b"\n").unwrap_or(line);
        let start = line.iter().position(|b| *b != b' ').unwrap_or(line.len());
        let end = line.iter().rposition(|b| *b != b' ').map_or(start, |p| p + 1);
        let line = &line[start..end];
        if !line.is_empty() {
            apply(backend, OsStr::from_bytes(line), line.contains(&b'*') || line.contains(&b'.'), Action::Foreground);
        }
    }
}

fn defaults<B: Backend>(backend: &mut B) {
    for name in ["Slack", "Google Chrome", "Microsoft Outlook", "ghostty", "WebStorm"] {
        apply(backend, OsStr::new(name), false, Action::Foreground);
    }
    for name in ["claude", "codex"] { apply(backend, OsStr::new(name), false, Action::Agent); }
    apply(backend, OsStr::new("ollama"), false, Action::Background);
    for name in ["mlx_lm.server", "node.*minsky"] { apply(backend, OsStr::new(name), true, Action::Background); }
    for name in ["bats", "shellcheck", "parallel"] { apply(backend, OsStr::new(name), false, Action::Background); }
    for name in ["node_modules/vitest", "node_modules/typescript/bin/tsc", "bats-core", "/biome "] {
        apply(backend, OsStr::new(name), true, Action::Nice);
    }
}

fn run() -> std::io::Result<()> {
    let home = std::env::var_os("HOME").unwrap_or_default();
    let config = std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty())
        .map(PathBuf::from).unwrap_or_else(|| PathBuf::from(home).join(".config"))
        .join("dotfiles/priority-apps.txt");
    let mut backend = System::default();
    if config.is_file() { custom(&mut backend, &std::fs::read(config)?); }
    else { defaults(&mut backend); }
    Ok(())
}

fn main() {
    if !cfg!(target_os = "macos") || std::env::args_os().nth(1).as_deref() != Some(OsStr::new("--apply")) {
        std::process::exit(2);
    }
    #[cfg(target_os = "macos")]
    // SAFETY: set the process locale before the single-threaded command starts.
    unsafe { libc::setlocale(libc::LC_ALL, b"\0".as_ptr().cast()); }
    if run().is_err() { std::process::exit(1); }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[derive(Default)]
    struct Fake {
        ids: HashMap<Vec<u8>, Vec<u32>>,
        info: HashMap<(u32, String), Vec<u8>>,
        actions: Vec<(u32, String)>,
    }
    impl Backend for Fake {
        fn find(&mut self, query: &OsStr, full: bool) -> Vec<u32> {
            let mut key = vec![u8::from(full)];
            key.extend_from_slice(query.as_bytes());
            self.ids.get(&key).cloned().unwrap_or_default()
        }
        fn info(&mut self, pid: u32, field: &str) -> Vec<u8> {
            self.info.get(&(pid, field.into())).cloned().unwrap_or_default()
        }
        fn background(&mut self, pid: u32, enabled: bool) {
            self.actions.push((pid, if enabled { "background" } else { "foreground" }.into()));
        }
        fn nice(&mut self, pid: u32, value: i32) {
            self.actions.push((pid, format!("nice:{value}")));
        }
    }
    fn key(full: bool, name: &str) -> Vec<u8> {
        let mut result = vec![u8::from(full)];
        result.extend_from_slice(name.as_bytes());
        result
    }
    #[test]
    fn default_rules_preserve_order_and_ancestry() {
        let mut b = Fake::default();
        for (name, pid) in [("Slack", 301), ("claude", 101), ("codex", 201), ("bats", 401)] {
            b.ids.insert(key(false, name), vec![pid]);
        }
        b.ids.insert(key(true, "node.*minsky"), vec![501]);
        b.ids.insert(key(true, "node_modules/vitest"), vec![601]);
        b.info.insert((101, "comm=".into()), b"/Applications/Terminal.app/Contents/MacOS/Terminal\n".to_vec());
        b.info.insert((201, "ppid=".into()), b"1\n".to_vec());
        defaults(&mut b);
        let expected = [(301,"foreground"),(101,"foreground"),(101,"nice:0"),
            (201,"background"),(201,"nice:10"),(501,"background"),(501,"nice:10"),
            (401,"background"),(401,"nice:10"),(601,"nice:10")];
        assert_eq!(b.actions, expected.into_iter().map(|(pid, action)| (pid, action.to_owned())).collect::<Vec<_>>());
    }
    #[test]
    fn custom_list_keeps_comments_patterns_and_incomplete_line() {
        let mut b = Fake::default();
        b.ids.insert(key(false, "Slack"), vec![1]);
        b.ids.insert(key(true, "node.*minsky"), vec![2]);
        custom(&mut b, b" Slack # comment\nnode.*minsky\n# skip\nSlack");
        assert_eq!(b.actions, vec![(1,"foreground".into()), (2,"foreground".into())]);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn native_background_changes_only_owned_child() {
        const CHILD: &str = "DOTFILES_PRIORITY_OWNED_CHILD";
        if std::env::var_os(CHILD).is_some() {
            unsafe extern "C" { fn getpriority(which: i32, who: u32) -> i32; }
            let pid = std::process::id();
            platform::background(pid, true);
            // SAFETY: who=0 queries this child, not another process.
            assert!(unsafe { getpriority(4, 0) } > 0);
            return;
        }
        let status = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "tests::native_background_changes_only_owned_child"])
            .env(CHILD, "1").stdin(Stdio::null()).status().unwrap();
        assert!(status.success());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn priority_action_child() {
        use std::io::{BufRead, Write};
        if std::env::var_os("DOTFILES_ACTION_CHILD").is_none() { return; }
        unsafe extern "C" {
            static mach_task_self_: u32;
            fn getpriority(which: i32, who: u32) -> i32;
            fn task_policy_get(task: u32, flavor: i32, policy: *mut i32,
                count: *mut u32, get_default: *mut i32) -> i32;
        }
        println!("POLICY_READY");
        std::io::stdout().flush().unwrap();
        for line in std::io::stdin().lock().lines() {
            assert_eq!(line.unwrap(), "state");
            let mut qos = [0; 2];
            let mut count = 2;
            let mut default = 0;
            // SAFETY: the output pointers are valid and both queries target this child.
            let status = unsafe { task_policy_get(mach_task_self_, 9, qos.as_mut_ptr(), &mut count, &mut default) };
            let background = unsafe { getpriority(4, 0) };
            assert!(status == 0 && count == 2 && background >= 0);
            println!("POLICY_STATE {background},{},{},{default}", qos[0], qos[1]);
            std::io::stdout().flush().unwrap();
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn cross_process_policy_matches_on_owned_children() {
        use std::io::{BufRead, BufReader, Write};
        use std::process::{Child, ChildStdout};
        unsafe extern "C" { fn getpriority(which: i32, who: u32) -> i32; }
        struct ChildOwner { child: Child, output: BufReader<ChildStdout> }
        impl ChildOwner {
            fn spawn() -> Self {
                let mut child = Command::new(std::env::current_exe().unwrap())
                    .args(["--exact", "tests::priority_action_child", "--nocapture"])
                    .env("DOTFILES_ACTION_CHILD", "1").stdin(Stdio::piped())
                    .stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
                let mut output = BufReader::new(child.stdout.take().unwrap());
                let mut line = String::new();
                loop {
                    line.clear();
                    assert!(output.read_line(&mut line).unwrap() > 0, "owned child did not start");
                    if line.contains("POLICY_READY") { break; }
                }
                Self { child, output }
            }
            fn state(&mut self) -> String {
                let input = self.child.stdin.as_mut().unwrap();
                input.write_all(b"state\n").unwrap();
                input.flush().unwrap();
                let mut line = String::new();
                loop {
                    line.clear();
                    assert!(self.output.read_line(&mut line).unwrap() > 0, "owned child state unavailable");
                    if let Some((_, state)) = line.split_once("POLICY_STATE ") { return state.trim().to_owned(); }
                }
            }
            fn finish(mut self) -> bool {
                self.child.stdin.take();
                self.child.wait().is_ok_and(|status| status.success())
            }
        }
        impl Drop for ChildOwner {
            fn drop(&mut self) { self.child.stdin.take(); let _ = self.child.wait(); }
        }
        let mut reference = ChildOwner::spawn();
        let mut native = ChildOwner::spawn();
        let reference_pid = reference.child.id();
        let native_pid = native.child.id();
        for (args, enabled) in [(vec!["-b"], true), (vec!["-B", "-t", "0", "-l", "0"], false)] {
            let status = Command::new("/usr/sbin/taskpolicy").args(args).args(["-p", &reference_pid.to_string()])
                .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().unwrap();
            assert!(status.success(), "reference action failed");
            platform::background(native_pid, enabled);
            let expected = reference.state();
            let actual = native.state();
            assert_eq!(expected, actual, "owned child policy differs");
        }
        for value in [19, 10] {
            let _ = Command::new("/usr/bin/renice").args([&value.to_string(), "-p", &reference_pid.to_string()])
                .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().unwrap();
            platform::nice(native_pid, value);
            // SAFETY: both PIDs are owned children retained without reaping.
            let expected = unsafe { getpriority(0, reference_pid) };
            let actual = unsafe { getpriority(0, native_pid) };
            assert!(expected >= 0 && actual >= 0, "nice state unavailable");
            assert_eq!(expected, actual, "owned child nice value differs");
        }
        assert!(reference.finish());
        assert!(native.finish());
    }
}
