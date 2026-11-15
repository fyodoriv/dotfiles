//! Inspect a shell syntax tree produced by `shfmt`; never execute its source.
//! These findings are candidates. This module cannot establish full coverage.

use serde_json::Value;
use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use crate::snapshot::Snapshot;

const MAX_SOURCE: usize = 1024 * 1024;
const MAX_AST: usize = 32 * 1024 * 1024;
const TOOL_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Eq, PartialEq)]
pub enum FindingKind { Embedded, GeneratedCandidate, Unresolved }

#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub kind: FindingKind,
    pub start: usize,
    pub end: usize,
    /// Fixed interpreter or finding category, never source text.
    pub category: &'static str,
}

#[derive(Debug, Eq, PartialEq)]
pub struct Report {
    pub findings: Vec<Finding>,
    /// Shell-only static analysis cannot prove complete source discovery.
    pub complete: bool,
}

fn span(node: &Value, source_len: usize) -> Result<(usize, usize), &'static str> {
    let offset = |key| node.get(key).and_then(|p| p.get("Offset")).and_then(Value::as_u64).and_then(|n| usize::try_from(n).ok());
    let start = offset("Pos").ok_or("missing source position")?;
    let end = offset("End").ok_or("missing source position")?;
    if start > end || end > source_len { return Err("invalid source position"); }
    Ok((start, end))
}

fn literal(word: &Value) -> Option<String> {
    fn part(node: &Value) -> Option<String> {
        match node.get("Type")?.as_str()? {
            "Lit" | "SglQuoted" => Some(node.get("Value")?.as_str()?.to_owned()),
            "DblQuoted" => node.get("Parts")?.as_array()?.iter().map(part).collect(),
            _ => None,
        }
    }
    word.get("Parts")?.as_array()?.iter().map(part).collect()
}

fn interpreter(name: &str) -> Option<&'static str> {
    let name = name.rsplit('/').next()?;
    if name == "python" || name == "python3" || name.strip_prefix("python3.").is_some_and(|v| !v.is_empty() && v.bytes().all(|b| b.is_ascii_digit())) { return Some("python"); }
    match name {
        "perl" => Some("perl"), "node" => Some("node"), "ruby" => Some("ruby"),
        "awk" => Some("awk"), "jq" => Some("jq"), "sed" => Some("sed"),
        "sh" | "bash" | "zsh" => Some("shell"), "osascript" => Some("osascript"),
        "swift" => Some("swift"), "lua" => Some("lua"), "php" => Some("php"),
        _ => None,
    }
}

fn push(findings: &mut Vec<Finding>, kind: FindingKind, node: &Value, len: usize, category: &'static str) -> Result<(), &'static str> {
    let (start, end) = span(node, len)?;
    findings.push(Finding { kind, start, end, category });
    Ok(())
}

fn inspect_statement(statement: &Value, len: usize, findings: &mut Vec<Finding>) -> Result<(), &'static str> {
    let Some(command) = statement.get("Cmd").filter(|c| c.get("Type").and_then(Value::as_str) == Some("CallExpr")) else { return Ok(()); };
    let args = command.get("Args").and_then(Value::as_array).ok_or("invalid call arguments")?;
    if args.is_empty() { return Ok(()); }
    let words: Vec<_> = args.iter().map(literal).collect();
    let redirects = statement.get("Redirs").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
    for redirect in redirects {
        if matches!(redirect.get("Op").and_then(Value::as_str), Some(">" | ">>" | ">|" | "&>" | "&>>")) {
            push(findings, FindingKind::GeneratedCandidate, redirect, len, "output-redirection")?;
        }
    }
    let Some(name) = words[0].as_deref() else {
        return push(findings, FindingKind::Unresolved, statement, len, "dynamic-command");
    };
    for (index, word) in words.iter().enumerate().skip(1) {
        if word.is_none() { push(findings, FindingKind::Unresolved, &args[index], len, "dynamic-argument")?; }
    }
    let base = name.rsplit('/').next().unwrap_or(name);
    if matches!(base, "eval" | "source" | "." | "env" | "command" | "sudo" | "xargs") {
        push(findings, FindingKind::Unresolved, statement, len, "indirect-command")?;
    }
    if let Some(language) = interpreter(name) {
        let mut found = false;
        for redirect in redirects {
            if let Some(body) = redirect.get("Hdoc").filter(|body| !body.is_null()) {
                push(findings, FindingKind::Embedded, body, len, language)?;
                if !body.get("Parts").and_then(Value::as_array).is_some_and(|parts| parts.iter().all(|part| part.get("Type").and_then(Value::as_str) == Some("Lit"))) {
                    push(findings, FindingKind::Unresolved, body, len, "dynamic-heredoc")?;
                }
                found = true;
            }
        }
        for (index, word) in words.iter().enumerate().skip(1) {
            let Some(flag) = word.as_deref() else { continue; };
            let inline = matches!(flag, "-c" | "-e") || (language == "perl" && flag.starts_with('-') && !flag.starts_with("--") && flag.contains('e'));
            if inline {
                if let Some(argument) = args.get(index + 1) {
                    let kind = if words[index + 1].is_some() { FindingKind::Embedded } else { FindingKind::Unresolved };
                    push(findings, kind, argument, len, language)?;
                    found = true;
                } else {
                    push(findings, FindingKind::Unresolved, statement, len, "missing-interpreter-body")?;
                }
            }
        }
        if !found { push(findings, FindingKind::Unresolved, statement, len, "interpreter-input")?; }
    } else if !matches!(base, "cat" | "/bin/cat") && redirects.iter().any(|r| r.get("Hdoc").is_some_and(|v| !v.is_null())) {
        push(findings, FindingKind::Unresolved, statement, len, "heredoc-consumer")?;
    }
    Ok(())
}

fn walk(node: &Value, len: usize, findings: &mut Vec<Finding>) -> Result<(), &'static str> {
    match node {
        Value::Object(object) => {
            if object.contains_key("Cmd") { inspect_statement(node, len, findings)?; }
            for value in object.values() { walk(value, len, findings)?; }
        }
        Value::Array(values) => for value in values { walk(value, len, findings)?; },
        _ => {}
    }
    Ok(())
}

/// Inspect a trusted shfmt JSON tree for a given source length.
/// The caller must bind the tree to the source and handle all unresolved cases.
pub fn inspect(source_len: usize, ast: &[u8]) -> Result<Report, &'static str> {
    let tree: Value = serde_json::from_slice(ast).map_err(|_| "invalid shell syntax tree")?;
    if tree.get("Type").and_then(Value::as_str) != Some("File") { return Err("invalid shell syntax root"); }
    span(&tree, source_len)?;
    let mut findings = Vec::new();
    walk(&tree, source_len, &mut findings)?;
    Ok(Report { findings, complete: false })
}

/// Run one trusted, owned child with bounded input, output, and elapsed time.
/// `shfmt` and Git are expected not to leave descendants holding their pipes.
fn run_tool(program: &Path, args: &[&str], input: Vec<u8>, limit: usize) -> Result<Vec<u8>, &'static str> {
    let mut child = Command::new(program).args(args)
        .env("GIT_NO_REPLACE_OBJECTS", "1").env("GIT_NO_LAZY_FETCH", "1")
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null())
        .spawn().map_err(|_| "cannot start discovery tool")?;
    let (Some(mut stdin), Some(stdout)) = (child.stdin.take(), child.stdout.take()) else {
        let _ = child.kill();
        let _ = child.wait();
        return Err("missing tool pipe");
    };
    let writer = thread::spawn(move || stdin.write_all(&input));
    let reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        stdout.take((limit + 1) as u64).read_to_end(&mut bytes).map(|_| bytes)
    });
    let deadline = Instant::now() + TOOL_TIMEOUT;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
            _ => { let _ = child.kill(); let _ = child.wait(); break None; }
        }
    };
    let wrote = writer.join().map_err(|_| "tool input failed")?;
    let output = reader.join().map_err(|_| "tool output failed")?.map_err(|_| "tool output failed")?;
    if status.is_none() { return Err("discovery tool timed out or failed"); }
    if !status.unwrap().success() || wrote.is_err() || output.len() > limit { return Err("discovery tool failed or exceeded output limit"); }
    Ok(output)
}

/// Inspect one regular file from a committed snapshot with an external trusted shfmt.
/// Parse failures, oversized source, and unsupported encodings are errors, not clearance.
pub fn scan_committed_shell(root: &Path, snapshot: &Snapshot, path: &str, shfmt: &Path) -> Result<Report, &'static str> {
    let mut matches = snapshot.paths.iter().filter(|entry| entry.path == path);
    let entry = matches.next().ok_or("source path not in snapshot")?;
    if matches.next().is_some() || !matches!(entry.mode.as_str(), "100644" | "100755") { return Err("source is not one regular tracked file"); }
    if !matches!(entry.object.len(), 40 | 64) || !entry.object.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) { return Err("invalid source identity"); }
    let root = root.canonicalize().map_err(|_| "invalid repository root")?;
    let tool = shfmt.canonicalize().map_err(|_| "shell parser unavailable")?;
    if tool.starts_with(&root) || tool.file_name().and_then(|name| name.to_str()) != Some("shfmt") || !tool.is_file() {
        return Err("external trusted shell parser required");
    }
    let root_text = root.to_str().ok_or("unsupported repository path")?;
    let git = Path::new("/usr/bin/git");
    let size = run_tool(git, &["-C", root_text, "cat-file", "-s", &entry.object], Vec::new(), 128)?;
    let size = std::str::from_utf8(&size).map_err(|_| "invalid source size")?.trim().parse::<usize>().map_err(|_| "invalid source size")?;
    if size > MAX_SOURCE { return Err("source exceeds discovery limit"); }
    let source = run_tool(git, &["-C", root_text, "cat-file", "blob", &entry.object], Vec::new(), MAX_SOURCE)?;
    if source.len() != size || std::str::from_utf8(&source).is_err() { return Err("invalid or unsupported source"); }
    let source_len = source.len();
    let ast = run_tool(&tool, &["-ln", "bash", "--to-json"], source, MAX_AST)?;
    inspect(source_len, &ast)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn detects_static_boundaries_and_keeps_dynamic_unresolved() {
        let word = |value: &str, start: usize, end: usize| json!({"Parts":[{"Type":"Lit","Value":value}],"Pos":{"Offset":start},"End":{"Offset":end}});
        let tree = json!({"Type":"File","Pos":{"Offset":0},"End":{"Offset":100},"Stmts":[
            {"Pos":{"Offset":0},"End":{"Offset":30},"Cmd":{"Type":"CallExpr","Args":[word("python3",0,7),word("-c",8,10),word("print(1)",11,19)]}},
            {"Pos":{"Offset":30},"End":{"Offset":60},"Cmd":{"Type":"CallExpr","Args":[word("cat",30,33)]},"Redirs":[{"Op":">","Pos":{"Offset":34},"End":{"Offset":40}}]},
            {"Pos":{"Offset":60},"End":{"Offset":90},"Cmd":{"Type":"CallExpr","Args":[{"Parts":[{"Type":"ParamExp"}],"Pos":{"Offset":60},"End":{"Offset":64}}]}}
        ]});
        let report = inspect(100, &serde_json::to_vec(&tree).unwrap()).unwrap();
        assert!(report.findings.iter().any(|f| f.kind == FindingKind::Embedded && f.category == "python"));
        assert!(report.findings.iter().any(|f| f.kind == FindingKind::GeneratedCandidate));
        assert!(report.findings.iter().any(|f| f.kind == FindingKind::Unresolved));
        assert!(!report.complete);
        assert!(inspect(3, &serde_json::to_vec(&tree).unwrap()).is_err());
        assert!(inspect(100, b"not-json").is_err());
    }
}
