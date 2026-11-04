use serde::Serialize;
use std::collections::BTreeMap;

// One machine credential operation owns these bytes; no diagnostic can format them.
struct Secret(Vec<u8>);

impl Secret {
    fn accept(bytes: Vec<u8>) -> Option<Self> {
        (!bytes.is_empty() && bytes.len() <= 4096 && bytes.iter().all(|b| (33..=126).contains(b)))
            .then_some(Self(bytes))
    }
}

// One invocation owns its supplied context. This module never reads the host env.
struct Context(BTreeMap<String, Vec<u8>>);

impl Context {
    fn callback_child(&self) -> Self {
        Self(
            self.0
                .iter()
                .filter(|(key, _)| !matches!(key.as_str(), "GH_TOKEN" | "GITHUB_TOKEN"))
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect(),
        )
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ReadKind {
    Value,
    Absent,
    Missing,
    Failed,
    Timeout,
    Unknown,
}

struct Read {
    kind: ReadKind,
    bytes: Vec<u8>,
    stderr: Vec<u8>,
}

impl Read {
    fn bounded(&self) -> bool {
        self.bytes.len() <= 8192 && self.stderr.len() <= 8192
    }
    fn keyring(self) -> Result<Secret, &'static str> {
        if !self.bounded() || self.kind != ReadKind::Value {
            return Err("keyring-unavailable");
        }
        Secret::accept(self.bytes).ok_or("invalid-keyring-token")
    }
    fn gui(self) -> Result<Option<Secret>, &'static str> {
        if !self.bounded() {
            return Err("gui-unavailable");
        }
        match self.kind {
            ReadKind::Absent => Ok(None),
            ReadKind::Value => Secret::accept(self.bytes)
                .map(Some)
                .ok_or("gui-unavailable"),
            _ => Err("gui-unavailable"),
        }
    }
}

trait KeyringPort {
    fn lookup(&mut self, child: &Context, args: &[&str]) -> Read;
}

trait GuiPort {
    fn read_github_token(&mut self) -> Read;
    fn set_github_token(&mut self, value: &Secret) -> bool;
    fn unset_github_token(&mut self) -> bool;
}

trait HeaderSink {
    fn accept(&mut self, value: &Secret);
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Selection {
    Unconfigured,
    Refresh,
    Remove,
    Unknown,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Consumer {
    ManagedKeyringGui,
    ExplicitEnvironment,
    Unknown,
}

enum Coverage {
    Unqualified,
    #[cfg(test)]
    FixtureQualified,
}

impl Coverage {
    fn qualified(&self) -> bool {
        match self {
            Self::Unqualified => false,
            #[cfg(test)]
            Self::FixtureQualified => true,
        }
    }
}

struct Policy {
    macos: bool,
    run: bool,
    selection: Selection,
    consumer: Consumer,
    fix: bool,
    coverage: Coverage,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Receipt {
    decision: &'static str,
    token_source: &'static str,
    keyring_reads: usize,
    gui_reads: usize,
    proposals: usize,
    writes: usize,
    rechecks: usize,
    fixed: bool,
    callback_fixture_matches: bool,
    both_vars_removed: bool,
    owner_context_retained: bool,
    unrelated_gh_token_preserved: bool,
    write_variable: Option<&'static str>,
    diagnostics: Vec<&'static str>,
}

fn missing() -> Receipt {
    Receipt {
        decision: "unavailable",
        token_source: "none",
        keyring_reads: 0,
        gui_reads: 0,
        proposals: 0,
        writes: 0,
        rechecks: 0,
        fixed: false,
        callback_fixture_matches: false,
        both_vars_removed: false,
        owner_context_retained: false,
        unrelated_gh_token_preserved: true,
        write_variable: None,
        diagnostics: vec!["missing-capability"],
    }
}

fn neutral() -> Receipt {
    let mut result = missing();
    result.decision = "skipped";
    result.diagnostics.clear();
    result
}

fn callback(
    context: &Context,
    keyring: &mut impl KeyringPort,
    sink: &mut impl HeaderSink,
) -> Receipt {
    let mut result = neutral();
    let child = context.callback_child();
    result.keyring_reads = 1;
    let read = keyring.lookup(&child, &["auth", "token", "-h", "github.com"]);
    match read.keyring() {
        Ok(secret) => {
            sink.accept(&secret);
            result.decision = "header-prepared";
            result.token_source = "keyring";
        }
        Err(code) => {
            result.decision = "unavailable";
            result.diagnostics.push(code);
        }
    }
    result
}

fn ordinary(context: &Context) -> Receipt {
    let mut result = neutral();
    result.decision = "unchanged";
    for (name, source) in [("GH_TOKEN", "gh-token"), ("GITHUB_TOKEN", "github-token")] {
        if context.0.get(name).is_some_and(|value| !value.is_empty()) {
            result.token_source = source;
            break;
        }
    }
    result
}

fn unknown(mut result: Receipt, code: &'static str) -> Receipt {
    result.decision = "unknown";
    result.diagnostics.push(code);
    result
}

fn doctor(
    policy: &Policy,
    context: &Context,
    keyring: &mut impl KeyringPort,
    gui: &mut impl GuiPort,
) -> Receipt {
    let mut result = neutral();
    if !policy.macos || !policy.run || policy.selection == Selection::Unconfigured {
        return result;
    }
    if policy.selection == Selection::Unknown {
        return unknown(result, "policy-unknown");
    }
    if policy.consumer == Consumer::ExplicitEnvironment {
        return result;
    }
    if policy.consumer == Consumer::Unknown {
        return unknown(result, "consumer-unknown");
    }
    let remove = policy.selection == Selection::Remove;
    if remove && !policy.coverage.qualified() {
        return unknown(result, "coverage-unqualified");
    }
    let desired = if remove {
        None
    } else {
        let child = context.callback_child();
        result.keyring_reads += 1;
        match keyring
            .lookup(&child, &["auth", "token", "-h", "github.com"])
            .keyring()
        {
            Ok(value) => Some(value),
            Err(code) => return unknown(result, code),
        }
    };
    result.gui_reads += 1;
    let current = match gui.read_github_token().gui() {
        Ok(value) => value,
        Err(code) => return unknown(result, code),
    };
    let matches = match (&desired, &current) {
        (None, None) => true,
        (Some(a), Some(b)) => a.0 == b.0,
        _ => false,
    };
    if matches {
        result.decision = "matching";
        return result;
    }
    result.decision = if current.is_none() { "absent" } else { "stale" };
    result.proposals = 1;
    if !policy.fix {
        result.diagnostics.push("repair-needed");
        return result;
    }
    result.writes = 1;
    result.write_variable = Some("GITHUB_TOKEN");
    let success = match &desired {
        Some(value) => gui.set_github_token(value),
        None => gui.unset_github_token(),
    };
    if !success {
        result.decision = "repair-failed";
        result.diagnostics.push("write-failed");
        return result;
    }
    result.rechecks = 1;
    let verified = match (desired, gui.read_github_token().gui()) {
        (None, Ok(None)) => true,
        (Some(a), Ok(Some(b))) => a.0 == b.0,
        _ => false,
    };
    if verified {
        result.decision = "fixed";
        result.fixed = true;
    } else {
        result.decision = "repair-unverified";
        result.diagnostics.push("postcheck-failed");
    }
    result
}

pub fn native_available() -> bool {
    false
}

pub fn native_callback_coverage() -> bool {
    false
}

#[cfg(test)]
pub struct Replay;

#[cfg(test)]
impl Replay {
    pub fn evaluate(input: &serde_json::Value) -> Receipt {
        fixtures::run(input)
    }
}

#[cfg(test)]
mod fixtures {
    use super::*;
    use serde_json::Value;

    fn bytes(value: &Value) -> Vec<u8> {
        value.as_str().unwrap_or("").as_bytes().to_vec()
    }
    fn read(value: &Value) -> Read {
        let kind = match value["status"].as_str() {
            Some("value") => ReadKind::Value,
            Some("absent") => ReadKind::Absent,
            Some("missing") => ReadKind::Missing,
            Some("failed") => ReadKind::Failed,
            Some("timeout") => ReadKind::Timeout,
            _ => ReadKind::Unknown,
        };
        Read {
            kind,
            bytes: bytes(&value["value"]),
            stderr: bytes(&value["stderr"]),
        }
    }

    struct FixtureKeyring {
        output: Option<Read>,
        observed: Option<Context>,
        args_correct: bool,
    }
    impl KeyringPort for FixtureKeyring {
        fn lookup(&mut self, child: &Context, args: &[&str]) -> Read {
            self.observed = Some(Context(child.0.clone()));
            self.args_correct = args == ["auth", "token", "-h", "github.com"];
            assert!(self.args_correct, "fixed keyring port argv");
            self.output.take().expect("fixture keyring read once")
        }
    }

    struct FixtureGui {
        reads: std::collections::VecDeque<Read>,
        write_ok: bool,
        write_attempts: usize,
        vars: BTreeMap<String, Vec<u8>>,
        expected_keyring: Vec<u8>,
    }
    impl GuiPort for FixtureGui {
        fn read_github_token(&mut self) -> Read {
            self.reads.pop_front().expect("sealed GUI read")
        }
        fn set_github_token(&mut self, value: &Secret) -> bool {
            self.write_attempts += 1;
            assert!(
                value.0 == self.expected_keyring,
                "GUI port received selected keyring value"
            );
            if self.write_ok {
                self.vars.insert("GITHUB_TOKEN".into(), value.0.clone());
            }
            self.write_ok
        }
        fn unset_github_token(&mut self) -> bool {
            self.write_attempts += 1;
            if self.write_ok {
                self.vars.remove("GITHUB_TOKEN");
            }
            self.write_ok
        }
    }

    struct FixtureSink {
        expected: Vec<u8>,
        matches: bool,
    }
    impl HeaderSink for FixtureSink {
        fn accept(&mut self, value: &Secret) {
            let mut synthetic = b"Bearer ".to_vec();
            synthetic.extend_from_slice(&value.0);
            self.matches = synthetic == self.expected;
        }
    }

    pub(super) fn run(input: &Value) -> Receipt {
        let context = Context(
            input["env"]
                .as_object()
                .expect("fixture env")
                .iter()
                .map(|(key, value)| (key.clone(), bytes(value)))
                .collect(),
        );
        let mut keyring = FixtureKeyring {
            output: Some(read(&input["keyring"])),
            observed: None,
            args_correct: false,
        };
        let mut gui = FixtureGui {
            reads: [read(&input["gui"]), read(&input["recheck"])].into(),
            write_ok: input["write_ok"].as_bool().unwrap_or(false),
            write_attempts: 0,
            vars: context.0.clone(),
            expected_keyring: bytes(&input["keyring"]["value"]),
        };
        let mut sink = FixtureSink {
            expected: bytes(&input["fixture_expected_header"]),
            matches: false,
        };
        let mut result = match input["operation"].as_str().expect("sealed operation") {
            "ordinary" => ordinary(&context),
            "callback" => callback(&context, &mut keyring, &mut sink),
            "doctor" => {
                let selection = match input["selection"].as_str() {
                    Some("unconfigured") => Selection::Unconfigured,
                    Some("refresh-managed-gui") => Selection::Refresh,
                    Some("remove-when-covered") => Selection::Remove,
                    _ => Selection::Unknown,
                };
                let consumer = match input["consumer"].as_str() {
                    Some("managed-keyring-gui") => Consumer::ManagedKeyringGui,
                    Some("explicit-environment") => Consumer::ExplicitEnvironment,
                    _ => Consumer::Unknown,
                };
                let coverage = if input["coverage"] == "fixture-qualified" {
                    Coverage::FixtureQualified
                } else {
                    Coverage::Unqualified
                };
                doctor(
                    &Policy {
                        macos: input["platform"] == "macos",
                        run: input["discovery"] == "run",
                        selection,
                        consumer,
                        fix: input["fix"].as_bool().unwrap(),
                        coverage,
                    },
                    &context,
                    &mut keyring,
                    &mut gui,
                )
            }
            _ => panic!("unregistered fixture operation"),
        };
        result.callback_fixture_matches = sink.matches;
        result.both_vars_removed = input["operation"] == "callback"
            && keyring.observed.as_ref().is_some_and(|child| {
                !child.0.contains_key("GH_TOKEN")
                    && !child.0.contains_key("GITHUB_TOKEN")
                    && keyring.args_correct
            });
        result.owner_context_retained = keyring.observed.as_ref().is_none_or(|child| {
            context
                .0
                .iter()
                .filter(|(name, _)| !matches!(name.as_str(), "GH_TOKEN" | "GITHUB_TOKEN"))
                .all(|(name, value)| child.0.get(name) == Some(value))
        });
        result.unrelated_gh_token_preserved = gui.vars.get("GH_TOKEN") == context.0.get("GH_TOKEN");
        assert_eq!(
            result.writes, gui.write_attempts,
            "actual fixture port writes"
        );
        result
    }
}
