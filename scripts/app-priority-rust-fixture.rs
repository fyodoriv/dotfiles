// Fixture-only Rust experiment. This program does not implement the live command.
// It refuses modified mock tools and invokes only the four fixed fixture scripts.
use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const PGREP: &str = "#!/bin/bash\ncase \"$*\" in\n  \"-l -x Slack|Google Chrome|Microsoft Outlook|ghostty|WebStorm|claude|codex|ollama|bats|shellcheck|parallel\")\n    printf \"101 claude\\\\n201 codex\\\\n301 Slack\\\\n401 bats\\\\n\" ;;\n  \"-l -f mlx_lm.server|node.*minsky|node_modules/vitest|node_modules/typescript/bin/tsc|bats-core|/biome \")\n    printf \"501 node minsky\\n601 node_modules/vitest\\n\" ;;\n  \"-x Slack\") printf \"301\\n\" ;;\n  \"-x claude\") printf \"101\\n\" ;;\n  \"-x codex\") printf \"201\\n\" ;;\n  \"-x bats\") printf \"401\\n\" ;;\n  \"-f node.*minsky\") printf \"501\\n\" ;;\n  \"-f node_modules/vitest\") printf \"601\\n\" ;;\n  *) exit 1 ;;\nesac\n";
const PS: &str = "#!/bin/bash\ncase \"$*\" in\n  \"-p 101 -o comm=\") printf \"/Applications/Terminal.app/Contents/MacOS/Terminal\\n\" ;;\n  \"-p 201 -o comm=\") printf \"/usr/bin/codex\\n\" ;;\n  \"-p 201 -o ppid=\") printf \"1\\n\" ;;\n  *) exit 1 ;;\nesac\n";
const TASKPOLICY: &str = "#!/bin/bash\nprintf 'taskpolicy %s\\n' \"$*\" >> \"$ACTION_LOG\"\n";
const RENICE: &str = "#!/bin/bash\nprintf 'renice %s\\n' \"$*\" >> \"$ACTION_LOG\"\n";

fn mock_dir() -> Result<PathBuf, &'static str> {
    if env::var("APP_PRIORITY_FIXTURE_ONLY").as_deref() != Ok("1") {
        return Err("fixture flag missing");
    }
    let log = PathBuf::from(env::var_os("ACTION_LOG").ok_or("missing action log")?);
    let root = log.parent().ok_or("invalid action log")?;
    let dir = root.join("mockbin");
    for (name, expected) in [("pgrep", PGREP), ("ps", PS), ("taskpolicy", TASKPOLICY), ("renice", RENICE)] {
        let path = dir.join(name);
        if !fs::symlink_metadata(&path).map_err(|_| "missing mock")?.file_type().is_file()
            || fs::read(&path).map_err(|_| "unreadable mock")? != expected.as_bytes() {
            return Err("modified mock");
        }
    }
    Ok(dir)
}

fn output(dir: &Path, name: &str, args: &[&str]) -> Result<String, &'static str> {
    let output = Command::new(dir.join(name)).args(args).stdin(Stdio::null())
        .stderr(Stdio::null()).output().map_err(|_| "mock failed")?;
    if !output.status.success() && output.status.code() != Some(1) { return Err("mock failed"); }
    String::from_utf8(output.stdout).map_err(|_| "invalid mock output")
}

fn rows(text: &str) -> Result<Vec<(String, String)>, &'static str> {
    let mut seen = HashSet::new();
    text.lines().map(|line| {
        let (pid, value) = line.split_once(' ').ok_or("invalid row")?;
        if pid.is_empty() || !pid.bytes().all(|b| b.is_ascii_digit()) || value.is_empty()
            || !seen.insert(pid.to_owned()) { return Err("invalid row"); }
        Ok((pid.to_owned(), value.to_owned()))
    }).collect()
}

fn action(dir: &Path, name: &str, args: &[&str]) -> Result<(), &'static str> {
    let status = Command::new(dir.join(name)).args(args).stdin(Stdio::null())
        .stdout(Stdio::null()).stderr(Stdio::null()).status().map_err(|_| "mock action failed")?;
    if status.success() { Ok(()) } else { Err("mock action failed") }
}

fn interactive(dir: &Path, pid: &str) -> Result<bool, &'static str> {
    let mut current = pid.to_owned();
    for _ in 0..16 {
        if current.parse::<u32>().map_err(|_| "invalid pid")? <= 1 { break; }
        let command = output(dir, "ps", &["-p", &current, "-o", "comm="])?;
        if ["WebStorm", "Ghostty", "Terminal", "iTerm", "WezTerm", "kitty", "Alacritty", "Warp", "Claude", "ChatGPT", "Codex"]
            .iter().any(|app| command.contains(&format!("/{app}.app/"))) { return Ok(true); }
        let parent = output(dir, "ps", &["-p", &current, "-o", "ppid="])?;
        let parent: String = parent.chars().filter(|c| !c.is_ascii_whitespace()).collect();
        if parent.is_empty() || !parent.bytes().all(|b| b.is_ascii_digit()) || parent == current { break; }
        current = parent;
    }
    Ok(false)
}

fn apply(dir: &Path, pid: &str, kind: &str) -> Result<(), &'static str> {
    match kind {
        "foreground" => action(dir, "taskpolicy", &["-B", "-t", "0", "-l", "0", "-p", pid]),
        "background" => { action(dir, "taskpolicy", &["-b", "-p", pid])?; action(dir, "renice", &["10", "-p", pid]) },
        "nice" => action(dir, "renice", &["10", "-p", pid]),
        "agent" => if interactive(dir, pid)? {
            action(dir, "taskpolicy", &["-B", "-t", "0", "-l", "0", "-p", pid])?;
            action(dir, "renice", &["0", "-p", pid])
        } else {
            action(dir, "taskpolicy", &["-b", "-p", pid])?;
            action(dir, "renice", &["10", "-p", pid])
        },
        _ => Err("invalid action"),
    }
}

fn run() -> Result<(), &'static str> {
    let dir = mock_dir()?;
    let config = PathBuf::from(env::var_os("XDG_CONFIG_HOME").ok_or("missing config")?)
        .join("dotfiles/priority-apps.txt");
    if config.is_file() {
        let input = fs::read_to_string(config).map_err(|_| "invalid custom config")?;
        for raw in input.split_inclusive('\n').filter(|line| line.ends_with('\n')) {
            let line = raw.trim_end_matches('\n').split('#').next().unwrap_or("").trim_matches(' ');
            if line.is_empty() { continue; }
            let option = if line.contains('*') || line.contains('.') { "-f" } else { "-x" };
            let found = output(&dir, "pgrep", &[option, line])?;
            for pid in found.lines().filter(|pid| !pid.is_empty()) {
                if !pid.bytes().all(|b| b.is_ascii_digit()) { return Err("invalid pid"); }
                apply(&dir, pid, "foreground")?;
            }
        }
        return Ok(());
    }
    let exact = rows(&output(&dir, "pgrep", &["-l", "-x", "Slack|Google Chrome|Microsoft Outlook|ghostty|WebStorm|claude|codex|ollama|bats|shellcheck|parallel"])?)?;
    let patterns = rows(&output(&dir, "pgrep", &["-l", "-f", "mlx_lm.server|node.*minsky|node_modules/vitest|node_modules/typescript/bin/tsc|bats-core|/biome "])?)?;
    for (name, kind) in [("Slack", "foreground"), ("Google Chrome", "foreground"), ("Microsoft Outlook", "foreground"), ("ghostty", "foreground"), ("WebStorm", "foreground"), ("claude", "agent"), ("codex", "agent"), ("ollama", "background")] {
        for (pid, value) in &exact { if value == name { apply(&dir, pid, kind)?; } }
    }
    for (pattern, kind) in [("mlx_lm.server", "background"), ("node.*minsky", "background")] {
        for (pid, value) in &patterns {
            let matches = if pattern == "node.*minsky" { value.find("node").is_some_and(|at| value[at + 4..].contains("minsky")) }
                else { value.as_bytes().windows(13).any(|w| &w[..6] == b"mlx_lm" && &w[7..] == b"server") };
            if matches { apply(&dir, pid, kind)?; }
        }
    }
    for name in ["bats", "shellcheck", "parallel"] {
        for (pid, value) in &exact { if value == name { apply(&dir, pid, "background")?; } }
    }
    for pattern in ["node_modules/vitest", "node_modules/typescript/bin/tsc", "bats-core", "/biome "] {
        for (pid, value) in &patterns { if value.contains(pattern) { apply(&dir, pid, "nice")?; } }
    }
    Ok(())
}

fn main() { if let Err(error) = run() { eprintln!("fixture refused: {error}"); std::process::exit(1); } }
