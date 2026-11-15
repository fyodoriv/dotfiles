//! Inspect a shell syntax tree produced by `shfmt`; never execute its source.
//! These findings are candidates. This module cannot establish full coverage.

use serde_json::Value;

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
    let base = name.rsplit('/').next().unwrap_or(name);
    if matches!(base, "eval" | "source" | "." | "env" | "command" | "sudo" | "xargs") {
        push(findings, FindingKind::Unresolved, statement, len, "indirect-command")?;
    }
    if let Some(language) = interpreter(name) {
        let mut found = false;
        for redirect in redirects {
            if let Some(body) = redirect.get("Hdoc").filter(|body| !body.is_null()) {
                push(findings, FindingKind::Embedded, body, len, language)?;
                found = true;
            }
        }
        for (index, word) in words.iter().enumerate().skip(1) {
            let Some(flag) = word.as_deref() else {
                push(findings, FindingKind::Unresolved, &args[index], len, "dynamic-interpreter-argument")?;
                continue;
            };
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
