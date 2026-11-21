use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::process::Command;

const ROUTES: &str = include_str!("../../../docs/plans/heavy-run-managed-routes.tsv");

#[derive(Debug, PartialEq, Eq)]
struct Route<'a> {
    scope: &'a str,
    mode: &'a str,
    blob: &'a str,
    path: &'a str,
}

#[derive(Debug, PartialEq, Eq)]
struct Inventory<'a> {
    revision: &'a str,
    routes: BTreeMap<&'a str, Route<'a>>,
}

fn object_id(value: &str) -> bool {
    value.len() == 40
        && value
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn tracked_path(path: &str) -> bool {
    path.bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || b"./_-".contains(&byte))
        && path.split('/').all(|part| !matches!(part, "" | "." | ".."))
}

fn parse_inventory(text: &str) -> Option<Inventory<'_>> {
    let mut rows = text.lines();
    let revision = rows.next()?.strip_prefix("revision\t")?;
    if !object_id(revision) {
        return None;
    }
    let mut routes = BTreeMap::new();
    let mut paths = BTreeSet::new();
    for row in rows {
        let [id, scope, mode, blob, path]: [&str; 5] =
            row.split('\t').collect::<Vec<_>>().try_into().ok()?;
        if id.is_empty()
            || !id
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
            || !matches!(
                scope,
                "source" | "managed" | "launchagent" | "direct" | "hosted" | "scratch"
            )
            || !matches!(mode, "100644" | "100755")
            || !object_id(blob)
            || !tracked_path(path)
            || !paths.insert(path)
            || routes
                .insert(
                    id,
                    Route {
                        scope,
                        mode,
                        blob,
                        path,
                    },
                )
                .is_some()
        {
            return None;
        }
    }
    (!routes.is_empty()).then_some(Inventory { revision, routes })
}

fn git(args: &[&str]) -> String {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("fixture under the tracked Dotfiles source");
    let output = Command::new("git")
        .arg("--no-replace-objects")
        .args(args)
        .current_dir(root)
        .output()
        .expect("read the reviewed Dotfiles tree");
    assert!(output.status.success(), "reviewed Git tree unavailable");
    String::from_utf8(output.stdout).expect("tracked source tree uses UTF-8")
}

#[test]
fn binds_all_reviewed_routes_to_the_frozen_tree() {
    let inventory = parse_inventory(ROUTES).expect("valid route inventory");
    let expected: BTreeMap<_, _> = inventory
        .routes
        .values()
        .map(|route| (route.path, (route.mode, route.blob)))
        .collect();
    assert_eq!(expected.len(), 63);
    let mut tree_args = vec!["ls-tree", "--full-tree", "-r", inventory.revision, "--"];
    tree_args.extend(expected.keys().copied());
    let tree = git(&tree_args);
    let actual: BTreeMap<_, _> = tree
        .lines()
        .map(|line| {
            let (identity, path) = line.split_once('\t').expect("tree path separator");
            let (mode, blob) = identity.split_once(" blob ").expect("tracked route blob");
            (path, (mode, blob))
        })
        .collect();
    assert_eq!(actual, expected);

    let expected_jobs: BTreeSet<_> = inventory
        .routes
        .values()
        .filter(|route| route.scope == "launchagent")
        .map(|route| route.path)
        .collect();
    let jobs = git(&[
        "grep",
        "-l",
        "-F",
        "template \"launchagent-path\"",
        inventory.revision,
        "--",
        "launchagents/*.tmpl",
    ]);
    let actual_jobs: BTreeSet<_> = jobs
        .lines()
        .map(|row| row.split_once(':').expect("Git revision prefix").1)
        .collect();
    assert_eq!(expected_jobs.len(), 27);
    assert_eq!(actual_jobs, expected_jobs);

    let gui = git(&[
        "grep",
        "-l",
        "-F",
        "launchctl setenv PATH",
        inventory.revision,
        "--",
        "launchagents/*.tmpl",
    ]);
    let gui_path = inventory.routes["gui-path-publisher"].path;
    assert_eq!(gui.trim(), format!("{}:{gui_path}", inventory.revision));

    for (id, path) in [
        ("controller", "bin/heavy-run"),
        ("terminal-path", "home/zshrc"),
        ("terminal-zshenv", "home/zshenv"),
        (
            "managed-bash-startup",
            "dot_config/dotfiles/bash-env.sh.tmpl",
        ),
        ("agent-hook-declarations", "Agentfile.yaml"),
        ("agent-session-path", "agent-hooks/session-endpoint-path.sh"),
        ("agent-pretool-path", "agent-hooks/prepend-endpoint-path.sh"),
        ("native-build", "lib/native-delivery.sh"),
        ("performance-budget", "config/perf-budget.tsv"),
    ] {
        assert_eq!(inventory.routes[id].path, path);
    }
}

#[test]
fn admits_only_exact_reviewed_source_evidence() {
    let expected = parse_inventory(ROUTES).expect("valid route inventory");
    let mut rows = ROUTES.lines();
    let revision = rows.next().expect("reviewed revision");
    let rows: Vec<_> = rows.collect();
    let matches = |observation: String| parse_inventory(&observation).as_ref() == Some(&expected);
    let render = |routes: &[&str]| format!("{revision}\n{}\n", routes.join("\n"));
    assert!(matches(render(&rows)));
    assert!(matches(render(
        &rows.iter().rev().copied().collect::<Vec<_>>()
    )));

    assert!(!matches(render(&rows[1..])), "missing route");
    let blob = expected
        .routes
        .values()
        .next()
        .expect("reviewed route")
        .blob;
    let changed = rows[0].replacen(blob, "0000000000000000000000000000000000000000", 1);
    assert_ne!(changed, rows[0], "fixture changes a reviewed blob");
    let mut observed = rows.clone();
    observed[0] = &changed;
    assert!(!matches(render(&observed)), "changed route");

    let extra = format!("extra-route\tdirect\t100644\t{blob}\tscripts/extra-route.sh");
    let mut observed = rows.clone();
    observed.push(&extra);
    assert!(!matches(render(&observed)), "extra route");
    *observed.last_mut().expect("extra row") = rows[0];
    assert!(!matches(render(&observed)), "duplicate route");
}
