//! Candidate command; the installed shell remains active until qualification.
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

mod platform;

trait Backend {
    fn find(&mut self, query: &OsStr, full: bool) -> Vec<u32>;
    fn info(&mut self, pid: u32, field: &str) -> Vec<u8>;
    fn background(&mut self, pid: u32, enabled: bool);
    fn nice(&mut self, pid: u32, value: i32);
}

struct System;
impl Backend for System {
    fn find(&mut self, query: &OsStr, full: bool) -> Vec<u32> {
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
    fn background(&mut self, pid: u32, enabled: bool) { platform::background(pid, enabled); }
    fn nice(&mut self, pid: u32, value: i32) { platform::nice(pid, value); }
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
    let mut backend = System;
    if config.is_file() { custom(&mut backend, &std::fs::read(config)?); }
    else { defaults(&mut backend); }
    Ok(())
}

fn main() {
    if !cfg!(target_os = "macos") || run().is_err() { std::process::exit(1); }
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
            platform::background(pid, false);
            // SAFETY: who=0 queries this child, not another process.
            assert_eq!(unsafe { getpriority(4, 0) }, 0);
            return;
        }
        let status = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "tests::native_background_changes_only_owned_child"])
            .env(CHILD, "1").stdin(Stdio::null()).status().unwrap();
        assert!(status.success());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn native_policy_matches_taskpolicy_on_owned_children() {
        const CHILD: &str = "DOTFILES_PRIORITY_PARITY_CHILD";
        if let Ok(mode) = std::env::var(CHILD) {
            unsafe extern "C" {
                static mach_task_self_: u32;
                fn getpriority(which: i32, who: u32) -> i32;
                fn task_policy_get(task: u32, flavor: i32, policy: *mut i32,
                    count: *mut u32, get_default: *mut i32) -> i32;
            }
            if mode == "native-background" { platform::background(std::process::id(), true); }
            if mode == "native-foreground" { platform::background(std::process::id(), false); }
            let mut qos = [0i32; 2];
            let mut count = 2u32;
            let mut get_default = 0i32;
            // SAFETY: all output pointers refer to valid local storage for this child.
            let result = unsafe { task_policy_get(mach_task_self_, 9, qos.as_mut_ptr(), &mut count, &mut get_default) };
            // SAFETY: who=0 queries only this child.
            let background = unsafe { getpriority(4, 0) };
            println!("OBS {result},{count},{background}");
            assert_eq!(result, 0);
            assert_eq!(count, 2);
            println!("STATE {background},{},{},{get_default}", qos[0], qos[1]);
            return;
        }
        let exe = std::env::current_exe().unwrap();
        for (mode, args) in [("background", vec!["-b"]), ("foreground", vec!["-t", "0", "-l", "0"])] {
            let test_args = ["--exact", "tests::native_policy_matches_taskpolicy_on_owned_children", "--nocapture"];
            let reference = Command::new("/usr/sbin/taskpolicy").args(args).arg(&exe).args(test_args)
                .env(CHILD, "reference").stdin(Stdio::null()).output().unwrap();
            let native = Command::new(&exe).args(test_args).env(CHILD, format!("native-{mode}"))
                .stdin(Stdio::null()).output().unwrap();
            let extract = |out: &[u8]| -> String {
                let text = String::from_utf8(out.to_vec()).unwrap();
                text.lines().find_map(|line| line.split_once("STATE ").map(|(_, s)| s.to_owned())).unwrap()
            };
            let observation = |out: &[u8]| -> String {
                let text = String::from_utf8_lossy(out);
                text.lines().find_map(|line| line.split_once("OBS ").map(|(_, s)| s.to_owned()))
                    .unwrap_or_else(|| "missing".into())
            };
            assert!(reference.status.success(), "reference {mode} failed: exit={:?} observation={}",
                reference.status.code(), observation(&reference.stdout));
            assert!(native.status.success(), "native {mode} failed: exit={:?} observation={}",
                native.status.code(), observation(&native.stdout));
            assert_eq!(extract(&reference.stdout), extract(&native.stdout), "{mode} policy differs");
        }
    }
}
