"""Regenerate the Rust migration inventory ledgers from the committed tree.

Usage (from the repository root, after committing the source changes):
  python3 scripts/inventory-ledger.py --write   # rewrite both ledgers + embedded review
  python3 scripts/inventory-ledger.py --check   # exit 1 when a rewrite would change them

The ledgers pin Git blob ids, so any source edit makes them stale. This script
keeps every reviewed record's text and refreshes only its blob id. A path with
no record gets one from the ordered RULES table below; each executable rule
names a slice from "Recorded exceptions" in docs/plans/rust-migration.md.
Embedded programs come from the static shell scanner (migration-check
--scan-shell). Static scanning cannot prove complete discovery, so
`migration-check inventory --check` still fails closed after this runs.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER_DIR = ROOT / "rust/migration-inventory"
INVENTORY = "rust/migration-inventory/inventory.tsv"
OBSERVATIONS = "rust/migration-inventory/observations.tsv"
CHECKER = LEDGER_DIR / "target/release/migration-check"
EMBEDDED_REVIEW = "docs/plans/rust-embedded-discovery-review.json"
PINNED_REVIEWS = [
    "rust-shell-cold-boundary-review.json", "rust-shell-tooling-boundary-review.json",
    "rust-setup-service-boundary-review.json", "rust-plugin-workspace-boundary-review.json",
    "rust-safety-boundary-review.json",
]
REVIEWER = "rule-classification"
ANCHOR = "docs/plans/rust-source-classification.md"
GRANDFATHERED = ("checkup-read-consumer", "compiler-queue-observer", "connector-credentials", "queue-privacy-cutover")

# Reasons per state. Exception reasons name the slice row in rust-migration.md.
def exception(slice_name):
    return ("exception", f"Recorded {slice_name} exception in rust-migration.md.")

OUT_DATA = ("out-of-scope", "Declarative data, configuration or documentation; no executable body.")
OUT_SHELL = ("out-of-scope", "Interactive shell or editor configuration; shell must stay shell.")
OUT_LAUNCHD = ("out-of-scope", "Declarative launchd job template; its program has its own record.")

# Ordered (regex on path, caller, (state, reason)). First match wins.
# Only paths without an existing record use these rules.
EXECUTABLE_RULES = [
    (r"^tests/fixtures/(%s)/" % "|".join(GRANDFATHERED), "test tooling",
     ("grandfathered", "Fixture crate that shipped before gate G.")),
    (r"^(tests|scripts|\.github|docs)/", "test tooling", exception("test-build-tooling")),
    (r"^rust/app-priority/|^bin/app-priority$", "launchd job",
     ("ported", "Rust app-priority; ported 2026-11-15 (fixture ratio 0.267, live median 302 ms vs 920 ms).")),
    (r"^bin/app-priority-native$|^rust/\.cargo/", "launchd job",
     ("ported", "Build and launch wrapper for the ported Rust app-priority.")),
    (r"^rust/hook-status/|^bin/hook-status-native$|^agent-hooks/", "agent hook",
     exception("agent-hooks")),
    (r"^rust/migration-inventory/", "test tooling", exception("test-build-tooling")),
    (r"^git-hooks/", "git hook", exception("git-security-guards")),
    (r"^data/plugin-template/|^(bin/dotfiles-plugin|lib/plugin[^/]*)$", "plugin command", exception("plugin-trust")),
    (r"^\.chezmoiscripts/|(^|/)modify_|^macos[^/]*\.sh$|^snapshot\.sh$|^skills/update-tooling/", "chezmoi lifecycle",
     exception("apply-install")),
    (r"^modules/[^/]+/doctor\.sh$|^bin/dotfiles-doctor$", "doctor", exception("doctor-core and the doctor module groups")),
    (r"^modules/", "doctor", exception("doctor-core and the doctor module groups")),
    (r"^skills/tooling-checkup/", "agent skill", exception("metrics-checkup")),
    (r"^(bin|lib)/(heavy-run|cached-run|lock\.sh|bats-affected|check-all|run-with-timeout\.sh|launchctl-timeout\.sh)$",
     "cli", exception("shared-queue")),
    (r"^(bin|lib)/(agent-browser|chrome|chromework|headless-chrome|temp-browser|setup-chrome|agent-tab|"
     r"dotfiles-chrome|dotfiles-restore-focus|dotfiles-set-persistent-chrome|focus-steal|slack-draft|"
     r"quit-watcher|dotfiles-quit-relay)", "cli", exception("browser-native")),
    (r"^(bin|lib)/(local-ai|local-models|ollama|oc$|dotfiles-opencode|opencode|kimi-|mcp-memory|"
     r"dotfiles-memory|agentbrew-memory|dotfiles-mcp-launch)", "cli", exception("local-ai-runtime")),
    (r"^(bin|lib)/(dotfiles-metrics|dotfiles-stats|dotfiles-telemetry|stats\.sh|weekly-metrics|dotfiles-coverage|"
     r"coverage-|dotfiles-load-sampler|dotfiles-audit|morning|status$|dotfiles-profile)", "cli",
     exception("metrics-checkup")),
    (r"^(bin|lib)/(gh$|pr$|land$|hotfix$|gh-public-leak|leak-allow|dotfiles-leak|oss-readiness|private-ref-markers|"
     r"strip-agent-attribution|dotfiles-contribute)", "cli", exception("gh-public-write-safety")),
    (r"^(bin|lib)/(git$|git-safe|git-maintain|secret-scan|push-error-classify|gitconfig-user-migrate)", "cli",
     exception("git-security-guards")),
    (r"^(bin|lib)/(cascade-caffeinate|dotfiles-agent-keepawake|agent-keepawake|dotfiles-agent-wake-recover|"
     r"network-watchdog|dotfiles-pmset|dotfiles-launchd-maxfiles|dotfiles-reload-launchagents|"
     r"dotfiles-launchagent-drift|launchagent-|dotfiles-heal-stuck|heal-stuck|graceful-restart|"
     r"dotfiles-amphetamine|rancher-desktop|dotfiles-fix-launchagent|agent-scratch-prune|tooling-sync|"
     r"dotfiles-sync|dotfiles-updates-landed|updates-landed|self-reload|realtime-hold|timer$)", "launchd job",
     exception("services-power")),
    (r"^(bin|lib)/(dotfiles-python-tls-relax|python/)", "cli", exception("python-host-extension")),
    (r"^(bin|lib)/(dotfiles$|dotfiles-actions|dotfiles-config|dotfiles-start|dotfiles-validate|colors\.sh|"
     r"output\.sh|confirm\.sh|errors-log|dotfiles-source-dir|dotfiles-arch|cheat$|dotfiles-quickstart)", "cli",
     exception("cli-core")),
    (r"^(bin|lib)/(learn-repos|workspace-discovery|dotfiles-workspace|agent-worktrees)", "cli",
     exception("repository-discovery")),
    (r"^(bin|lib)/(dotfiles-|apply-|brew-|mac-baseline|node-pin|poetry-repair|xcode-license|login-apps|"
     r"blocked-software|jetbrains-install|setup-dock|agentfile-|claude-model|agentbrew|zshrc-appends|"
     r"glove80|spotlight-probe|zsh-completion|dotfiles-agent-)", "cli", exception("apply-install")),
    (r"^(bin|lib)/", "cli", exception("developer-utilities")),
    (r"^home/(sleep|wakeup)$", "sleepwatcher hook", exception("services-power")),
    (r"^home/git-editor$", "git editor", exception("developer-utilities")),
    (r"^(home|private_dot_|symlink_|dot_config|jetbrains|vscode)", "shell session", OUT_SHELL),
    (r"", "cli", exception("developer-utilities")),
]

CODE_SUFFIX = re.compile(r"\.(sh|bash|zsh|py|rb|swift|rs|mjs|cjs|js|pl|awk|jq|sh\.tmpl|bats|bash\.tmpl)$")
SHELL_CONFIG = re.compile(r"^(home/|symlink_dot_|private_dot_ssh|dot_gitconfig|dot_config/|jetbrains/|vscode/)")


def git(*args, binary=False):
    out = subprocess.run(["/usr/bin/git", "-C", str(ROOT), *args], check=True, capture_output=True).stdout
    return out if binary else out.decode()


def tree():
    paths = {}
    for row in git("ls-tree", "-r", "-z", "HEAD", binary=True).split(b"\0"):
        if not row:
            continue
        meta, path = row.split(b"\t", 1)
        mode, _kind, oid = meta.decode().split()
        path = path.decode()
        if path not in (INVENTORY, OBSERVATIONS):
            paths[path] = (mode, oid)
    return paths


def head_bytes(oid):
    return git("cat-file", "blob", oid, binary=True)[:256]


def is_executable(path, mode, oid):
    if mode == "100755" or CODE_SUFFIX.search(path):
        return True
    return mode == "100644" and head_bytes(oid).startswith(b"#!")


def classify(path, mode, oid):
    """Return (reviewer, anchor, owner, caller, state, reason) for an unrecorded path."""
    if mode == "120000":
        return REVIEWER, ANCHOR, "dotfiles", "declarative input", "out-of-scope", "Symbolic link; its target has its own record."
    if path.startswith("docs/") and path.endswith(".md") and mode == "100644" and not head_bytes(oid).startswith(b"#!"):
        return ("documentation-scope-review", "docs/plans/rust-document-ledger-prediction.md", "dotfiles",
                "documentation", "out-of-scope", "Regular non-shebang Markdown documentation.")
    if path.startswith("tests/") and path.endswith(".bats"):
        return (REVIEWER, ANCHOR, "dotfiles", "Bats test tooling", "exception",
                "Test tooling follows its component; embedded and generated programs remain unreviewed.")
    if path.startswith("launchagents/"):
        return (REVIEWER, ANCHOR, "dotfiles", "launchd job", *OUT_LAUNCHD)
    if SHELL_CONFIG.search(path) and mode != "100755" and not head_bytes(oid).startswith(b"#!"):
        return (REVIEWER, ANCHOR, "dotfiles", "shell session", *OUT_SHELL)
    if not is_executable(path, mode, oid):
        return (REVIEWER, ANCHOR, "dotfiles", "declarative input", *OUT_DATA)
    for pattern, caller, (state, reason) in EXECUTABLE_RULES:
        if re.search(pattern, path):
            return (REVIEWER, ANCHOR, "dotfiles", caller, state, reason)
    raise SystemExit(f"no rule for {path}")


def read_ledger(name):
    return [line.rstrip("\n").split("\t") for line in (ROOT / name).read_text().splitlines()
            if line and not line.startswith("#")]


def scan_embedded(paths, records):
    """Run the static scanner on shell sources; return embedded entries not pinned elsewhere."""
    shfmt = shutil.which("shfmt")
    if not shfmt or not CHECKER.exists():
        raise SystemExit("need shfmt and a release build of migration-check (heavy-run cargo build --locked --offline --release)")
    pinned = set()
    for name in PINNED_REVIEWS:
        for entry in json.loads((ROOT / "docs/plans" / name).read_text())["entries"]:
            pinned.add((entry["path"], entry["start"], entry["end"], entry["language"]))
    entries, unparsed, unresolved = [], 0, 0
    for path, (mode, oid) in sorted(paths.items()):
        if mode == "120000" or not is_executable(path, mode, oid) or not _shell(path, oid):
            continue
        run = subprocess.run([str(CHECKER), "inventory", "--scan-shell", path, "--shfmt", shfmt],
                             cwd=ROOT, capture_output=True, text=True)
        if run.returncode != 0:
            unparsed += 1
            continue
        for finding in json.loads(run.stdout)["findings"]:
            if finding["kind"] == "unresolved":
                unresolved += 1
            if finding["kind"] != "embedded":
                continue
            key = (path, finding["start"], finding["end"], finding["category"])
            if key in pinned:
                continue
            _r, _a, owner, caller, state, reason = records[path]
            entries.append({"path": path, "source_object": oid, "language": finding["category"],
                            "start": finding["start"], "end": finding["end"], "owner": owner,
                            "caller": caller, "state": state, "reason": reason})
    return entries, unparsed, unresolved


def _shell(path, oid):
    if re.search(r"\.(sh|bash|zsh|bats)(\.tmpl)?$", path):
        return True
    return re.match(rb"^#!\S*\b(ba|z)?sh\b", head_bytes(oid)) is not None


def build():
    paths = tree()
    old_reviews = {f[1]: f for f in read_ledger(OBSERVATIONS) if f[0] == "review"}
    old_files = {f[1]: f for f in read_ledger(INVENTORY) if f[0] == "file"}
    records = {}
    for path, (mode, oid) in paths.items():
        derived = None
        if path not in old_reviews or path not in old_files:
            derived = classify(path, mode, oid)
        reviewer, anchor = (old_reviews[path][3], old_reviews[path][4]) if path in old_reviews else derived[:2]
        owner, caller, state, reason = (old_files[path][4:8]) if path in old_files else derived[2:]
        records[path] = (reviewer, anchor, owner, caller, state, reason)

    entries, unparsed, unresolved = scan_embedded(paths, records)
    embedded = list(entries)
    for name in PINNED_REVIEWS:
        embedded += json.loads((ROOT / "docs/plans" / name).read_text())["entries"]

    review_lines = [f"review\t{p}\t{paths[p][1]}\t{r[0]}\t{r[1]}" for p, r in sorted(records.items())]
    obs_lines = sorted(f"observation\tembedded\t{e['path']}\tbytes:{e['start']}-{e['end']}:{e['language']}\t{e['source_object']}"
                       for e in embedded)
    file_lines = [f"file\t{p}\ttracked-file\t{paths[p][1]}\t{r[2]}\t{r[3]}\t{r[4]}\t{r[5]}" for p, r in sorted(records.items())]
    emb_lines = sorted(f"embedded\t{e['path']}\tbytes:{e['start']}-{e['end']}:{e['language']}\t{e['source_object']}\t"
                       f"{e['owner']}\t{e['caller']}\t{e['state']}\t{e['reason']}" for e in embedded)
    observations = "# Every tracked path reviewed; embedded discovery is static and incomplete.\n" + \
        "\n".join(review_lines + obs_lines) + "\n"
    inventory = "# Every tracked path classified; embedded entries cover static scanner findings only.\n" + \
        "\n".join(emb_lines + file_lines) + "\n"
    review = json.dumps({
        "scope": "Embedded programs the static shell scanner confirmed in tracked shell sources, outside the five "
                 "earlier boundary reviews. Not complete discovery: dynamic arguments and unparsed files stay unresolved.",
        "generator": "scripts/inventory-ledger.py",
        "unparsed_shell_files": unparsed,
        "unresolved_findings": unresolved,
        "entries": sorted(entries, key=lambda e: (e["path"], e["start"], e["end"])),
    }, indent=2) + "\n"
    states = {}
    for r in records.values():
        states[r[4]] = states.get(r[4], 0) + 1
    return {OBSERVATIONS: observations, INVENTORY: inventory, EMBEDDED_REVIEW: review}, states, len(embedded), unparsed, unresolved


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    files, states, embedded, unparsed, unresolved = build()
    stale = [name for name, text in files.items()
             if not (ROOT / name).exists() or (ROOT / name).read_text() != text]
    summary = (f"paths={sum(states.values())} states={json.dumps(states, sort_keys=True)} embedded={embedded} "
               f"unparsed_shell_files={unparsed} unresolved_findings={unresolved}")
    if args.write:
        for name in stale:
            (ROOT / name).write_text(files[name])
        print(f"inventory-ledger: wrote {len(stale)} file(s); {summary}")
        return 0
    if stale:
        print(f"inventory-ledger: stale: {', '.join(stale)}; run python3 scripts/inventory-ledger.py --write", file=sys.stderr)
        return 1
    print(f"inventory-ledger: current; {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
