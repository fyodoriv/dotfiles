"""Lint agent skills and instruction files against Anthropic's published rules.

It checks what a script can check without judgment:
  skills  (every SKILL.md): frontmatter name and description rules, body size,
          broken relative links, reference depth, long references without a
          table of contents, Windows-style paths
  rules   (CLAUDE.md, AGENTS.md, shared rules): size, broken @imports,
          lines repeated inside one always-loaded file

The rule list and its sources are in reference/config-audit.md.

Usage:
  python3 audit_agent_config.py                      # default scope (see below)
  python3 audit_agent_config.py --skills DIR --rules FILE ...
  python3 audit_agent_config.py --cache               # replay when no input changed

Default scope: skill sources and instruction files under $TOOLING_ROOT
(default ~/apps/tooling), ~/.config/agentbrew, and ~/.claude/CLAUDE.md.
Add --include-installed to also lint third-party skills in
~/.config/agentbrew/installed-skills (report only; fix those upstream).

Output: one line per finding, `LEVEL CODE path[:line]: message`, then a
summary line. Exit status 1 when there is at least one ERROR.
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
from collections import Counter

HOME = pathlib.Path.home()
NAME_RE = re.compile(r"^[a-z0-9-]+$")
XML_RE = re.compile(r"<[A-Za-z/][^>]*>")
PERSON_RE = re.compile(
    r"\b(I can|I will|I'll|I'm|I help|you can use|you'll|we can|we will)\b"
    r"|(^|[.!?]\s+)(I|We|You)\s+(can|will|help|should|am|are)\b",
    re.IGNORECASE,
)
WHEN_RE = re.compile(r"\b(use (it |this |this skill )?(when|for|to|if|after|before)|when\b|trigger|invoke|run (it )?(when|after|before))", re.IGNORECASE)
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
BACKSLASH_PATH_RE = re.compile(r"\b[\w.-]+\\[\w.-]+\.(md|py|sh|js|ts|json|ya?ml)\b")
IMPORT_RE = re.compile(r"(?<![\w`])@((?:~|\.{1,2})?/?[\w.~/-]+)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
CODE_SPAN_RE = re.compile(r"`[^`]*`")
FOLDED = {">", ">-", ">+", "|", "|-", "|+"}

# Each skill rule against the Agent Skills spec (https://agentskills.io/specification,
# #315): the spec section it enforces, or None when it is ours only (Anthropic
# best practices, Claude Code, or this audit). --spec-coverage prints the map.
RULE_SPEC = {
    "S001": "SKILL.md format", "S002": "name", "S003": "name", "S004": None,
    "S005": "name", "S006": "description", "S007": "description", "S008": None,
    "S009": None, "S010": None, "S011": "description", "S012": "progressive disclosure",
    "S013": None, "S014": "file references", "S015": None, "S016": None,
    "S017": "name", "S018": "name", "S019": "compatibility", "S020": "metadata",
    "S021": "allowed-tools", "S022": "progressive disclosure",
}
# Every requirement the spec states for a skill, and the rule that checks it.
SPEC_REQUIREMENTS = {
    "YAML frontmatter, then Markdown": "S001",
    "name: required": "S002",
    "name: 1-64 lowercase letters, digits, hyphens": "S003",
    "name: no leading or trailing hyphen": "S017",
    "name: no consecutive hyphens": "S018",
    "name: matches the parent directory": "S005",
    "description: required, non-empty": "S006",
    "description: at most 1024 characters": "S007",
    "description: says what it does and when to use it": "S011",
    "compatibility: 1-500 characters": "S019",
    "metadata: a map from string keys to string values": "S020",
    "allowed-tools: a space-separated string": "S021",
    "SKILL.md under 500 lines": "S012",
    "instructions under 5000 tokens": "S022",
    "file references one level deep": "S014",
}


def spec_tag(code):
    section = RULE_SPEC.get(code)
    return f" [spec: {section}]" if section else ""


def spec_coverage():
    print("Skill rules and the Agent Skills spec (https://agentskills.io/specification):")
    for code, section in RULE_SPEC.items():
        print(f"  {code}  {'spec: ' + section if section else 'ours (not in the spec)'}")
    # A requirement is covered when its rule exists and cites the same spec field.
    missing = [req for req, code in SPEC_REQUIREMENTS.items()
               if code not in RULE_SPEC or (":" in req and RULE_SPEC[code] != req.split(":", 1)[0])]
    cited = sum(1 for section in RULE_SPEC.values() if section)
    print(f"skill rules citing a spec section: {cited} of {len(RULE_SPEC)}")
    print(f"spec requirements: {len(SPEC_REQUIREMENTS)}; spec requirements without a check: {len(missing)}")
    for req in missing:
        print(f"  missing: {req}")
    return 1 if missing else 0


def frontmatter_blocks(text: str):
    """Return {key: (inline value, [indented lines])} for top-level keys."""
    lines = text.split("\n")
    out, key = {}, None
    if not lines or lines[0].strip() != "---":
        return out
    for raw in lines[1:]:
        if raw.strip() == "---":
            break
        top = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", raw)
        if top and not raw.startswith((" ", "\t")):
            key = top.group(1)
            out[key] = (top.group(2).strip(), [])
        elif key is not None and raw.strip() and not raw.strip().startswith("#"):
            out[key][1].append(raw)
    return out


class Report:
    def __init__(self):
        self.lines = []
        self.counts = Counter()

    def add(self, level, code, path, message, line=None):
        where = f"{path}:{line}" if line else str(path)
        self.lines.append(f"{level} {code} {where}: {message}{spec_tag(code)}")
        self.counts[level] += 1


def tag(path: pathlib.Path) -> str:
    """Name the place to fix a generated file."""
    text = str(path)
    if text.startswith(str(HOME / ".claude")) or text.startswith(str(HOME / ".cursor")):
        return " (generated by agentbrew: fix the source, then sync)"
    return ""


def parse_frontmatter(text: str):
    """Return (fields, body, body_start_line) or (None, text, 1).

    A small YAML subset: top-level `key: value`, quoted scalars, and block
    scalars (`>`, `|`). Enough for skill frontmatter without a YAML library.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text, 1
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return None, text, 1
    fields = {}
    key = None
    block = []
    style = None
    for raw in lines[1:end]:
        top = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", raw)
        if top and not raw.startswith((" ", "\t")):
            if key is not None and style is not None:
                fields[key] = join_block(block, style)
            key, value = top.group(1), top.group(2).strip()
            block, style = [], None
            if value in FOLDED or value == "":
                style = value or ">"
            else:
                fields[key] = unquote(value)
        elif key is not None and style is not None:
            block.append(raw.strip())
    if key is not None and style is not None:
        fields[key] = join_block(block, style)
    return fields, "\n".join(lines[end + 1:]), end + 2


def join_block(block, style):
    block = [line for line in block]
    if style.startswith("|"):
        return "\n".join(block).strip()
    return " ".join(line for line in block if line).strip()


def unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def outside_code(lines):
    """Yield (line_number, text) for lines outside fenced code, code spans removed."""
    fenced = False
    for number, line in enumerate(lines, 1):
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if not fenced:
            yield number, CODE_SPAN_RE.sub("", line)


def local_links(text: str):
    for number, line in outside_code(text.split("\n")):
        for match in LINK_RE.finditer(line):
            target = match.group(1)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE) or target.startswith("#"):
                continue
            yield number, target.split("#", 1)[0]


def check_skill(skill_md: pathlib.Path, report: Report):
    text = skill_md.read_text(errors="replace")
    where = skill_md
    fields, body, body_start = parse_frontmatter(text)
    if fields is None:
        report.add("ERROR", "S001", where, "no YAML frontmatter (needs name and description)" + tag(where))
        return
    name = fields.get("name", "")
    description = fields.get("description", "")
    if not name:
        report.add("ERROR", "S002", where, "frontmatter has no name")
    else:
        if len(name) > 64 or not NAME_RE.match(name):
            report.add("ERROR", "S003", where, f"name '{name}' must be 1-64 lowercase letters, digits, or hyphens")
        if "anthropic" in name or "claude" in name:
            report.add("ERROR", "S004", where, f"name '{name}' contains a reserved word (anthropic, claude)")
        if name.startswith("-") or name.endswith("-"):
            report.add("ERROR", "S017", where, f"name '{name}' must not start or end with a hyphen")
        if "--" in name:
            report.add("ERROR", "S018", where, f"name '{name}' must not contain consecutive hyphens")
        if name != skill_md.resolve().parent.name:
            report.add("ERROR", "S005", where, f"name '{name}' differs from its directory '{skill_md.resolve().parent.name}'")
    if not description:
        report.add("ERROR", "S006", where, "frontmatter has no description")
    else:
        if len(description) > 1024:
            report.add("ERROR", "S007", where, f"description has {len(description)} characters (limit 1024)")
        listing = len(description) + len(fields.get("when_to_use", ""))
        if listing > 1536:
            report.add("WARN", "S008", where, f"description + when_to_use has {listing} characters; Claude Code truncates the listing at 1536")
        if PERSON_RE.search(description):
            report.add("WARN", "S010", where, "description is not in the third person (avoid 'I can', 'you can use')")
        if not WHEN_RE.search(description) and not fields.get("when_to_use"):
            report.add("WARN", "S011", where, "description says what the skill does but not when to use it")
    for value, field in ((name, "name"), (description, "description")):
        tag_match = XML_RE.search(CODE_SPAN_RE.sub("", value))
        if tag_match:
            report.add("WARN", "S009", where, f"{field} contains an angle-bracket tag {tag_match.group(0)}; Claude Code escapes it, the Skills API rejects it")

    blocks = frontmatter_blocks(text)
    if "compatibility" in fields:
        compat = fields.get("compatibility", "")
        if not 1 <= len(compat) <= 500:
            report.add("ERROR", "S019", where, f"compatibility has {len(compat)} characters (must be 1-500)")
    if "metadata" in blocks:
        inline, nested = blocks["metadata"]
        indents = {len(line) - len(line.lstrip()) for line in nested}
        # Each value is a scalar: not a list, map, or nothing.
        flat = all(re.match(r"^\s+[^\s:#][^:]*:\s*[^\s\[{]", line) for line in nested)
        flow_ok = inline == "" or re.match(r"^\{[^\[\]{}]*\}$", inline)
        if not flow_ok or not flat or len(indents) > 1:
            report.add("ERROR", "S020", where, "metadata must be a map from string keys to string values (no lists or nested maps)")
    if "allowed-tools" in blocks:
        inline, nested = blocks["allowed-tools"]
        if nested or inline.startswith("["):
            report.add("WARN", "S021", where, "allowed-tools must be one space-separated string, not a list")

    body_lines = body.split("\n")
    # The spec recommends under 5000 tokens of instructions; ~4 characters a token.
    if len(body) // 4 > 5000:
        report.add("WARN", "S022", where, f"body is about {len(body) // 4} tokens (keep under 5000; move detail to reference files)")
    if len(body_lines) > 500:
        report.add("WARN", "S012", where, f"body has {len(body_lines)} lines (keep under 500; move detail to reference files)")

    skill_dir = skill_md.parent
    for number, target in local_links(body):
        if not target:
            continue
        resolved = (skill_dir / target).resolve()
        if not resolved.exists():
            report.add("ERROR", "S013", where, f"broken link: {target}", body_start + number - 1)
            continue
        if resolved.suffix == ".md" and skill_dir.resolve() in resolved.parents:
            check_reference(resolved, skill_dir.resolve(), report)
    for number, line in outside_code(body_lines):
        if BACKSLASH_PATH_RE.search(line):
            report.add("WARN", "S016", where, "Windows-style path; use forward slashes", body_start + number - 1)


def check_reference(reference: pathlib.Path, skill_dir: pathlib.Path, report: Report):
    text = reference.read_text(errors="replace")
    lines = text.split("\n")
    for _number, target in local_links(text):
        if not target:
            continue
        nested = (reference.parent / target).resolve()
        if nested.suffix == ".md" and skill_dir in nested.parents and nested.exists():
            report.add("WARN", "S014", reference, f"links to {target}; keep references one level deep from SKILL.md")
            break
    if len(lines) > 100:
        head = "\n".join(lines[:40]).lower()
        if "contents" not in head:
            report.add("INFO", "S015", reference, f"{len(lines)} lines and no table of contents near the top")


def normalize(line: str) -> str:
    line = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", line)
    return re.sub(r"\s+", " ", line).strip().lower()


def check_rules(path: pathlib.Path, report: Report):
    text = path.read_text(errors="replace")
    lines = text.split("\n")
    where = path
    if len(lines) > 200:
        report.add("WARN", "R001", where, f"{len(lines)} lines (target under 200; move detail to skills or path-scoped rules){tag(path)}")
    for number, line in outside_code(lines):
        for match in IMPORT_RE.finditer(line):
            target = match.group(1).rstrip(".,:;)")
            looks_like_path = target.startswith(("~/", "./", "../", "/")) or re.search(r"\.[A-Za-z0-9]{1,5}$", target)
            if not looks_like_path:
                continue
            resolved = pathlib.Path(os.path.expanduser(target))
            if not resolved.is_absolute():
                resolved = path.parent / resolved
            if not resolved.exists():
                report.add("WARN", "R002", where, f"@{target} does not resolve to a file", number)
    seen = Counter()
    first = {}
    for number, line in outside_code(lines):
        key = normalize(line)
        if len(key) < 40 or key.startswith(("|", "#")):
            continue
        seen[key] += 1
        first.setdefault(key, number)
    repeats = [(first[key], count, key) for key, count in seen.items() if count > 1]
    for number, count, key in sorted(repeats)[:5]:
        report.add("WARN", "R003", where, f"line repeated {count} times in one always-loaded file: '{key[:70]}'{tag(path)}", number)
    if len(repeats) > 5:
        report.add("WARN", "R003", where, f"{len(repeats) - 5} more repeated line(s)")


def default_scope(include_installed: bool):
    root = pathlib.Path(os.environ.get("TOOLING_ROOT") or HOME / "apps" / "tooling")
    skill_roots, rule_files = [], []
    if root.is_dir():
        for repo in sorted(root.iterdir()):
            if not (repo / ".git").is_dir():
                continue
            for sub in ("skills", "skill-plugins", ".claude/skills", "commands"):
                if (repo / sub).is_dir():
                    skill_roots.append(repo / sub)
            for name in ("CLAUDE.md", "AGENTS.md"):
                if (repo / name).is_file():
                    rule_files.append(repo / name)
            rules_dir = repo / ".claude" / "rules"
            if rules_dir.is_dir():
                rule_files.extend(sorted(rules_dir.glob("*.md")))
    agentbrew_config = HOME / ".config" / "agentbrew"
    if (agentbrew_config / "shared-rules.md").is_file():
        rule_files.append(agentbrew_config / "shared-rules.md")
    for generated in (HOME / ".claude" / "CLAUDE.md",):
        if generated.is_file():
            rule_files.append(generated)
    if include_installed and (agentbrew_config / "installed-skills").is_dir():
        skill_roots.append(agentbrew_config / "installed-skills")
    return skill_roots, rule_files


def find_skills(roots):
    found = []
    for root in roots:
        for skill_md in sorted(pathlib.Path(root).rglob("SKILL.md")):
            parts = set(skill_md.parts)
            if parts & {"node_modules", ".git", "evals", "fixtures", "test", "tests"}:
                continue
            found.append(skill_md)
    return found


def dedupe(paths):
    seen, unique = set(), []
    for path in paths:
        real = os.path.realpath(path)
        if real not in seen:
            seen.add(real)
            unique.append(pathlib.Path(path))
    return unique


def fingerprint(paths) -> str:
    digest = hashlib.sha256(pathlib.Path(__file__).read_bytes())
    for path in sorted(str(p) for p in paths):
        try:
            stat = os.stat(path)
        except OSError:
            continue
        digest.update(f"{path}\0{stat.st_size}\0{stat.st_mtime_ns}\n".encode())
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--skills", action="append", default=[], help="directory to search for SKILL.md files")
    parser.add_argument("--rules", action="append", default=[], help="CLAUDE.md, AGENTS.md, or rules file")
    parser.add_argument("--include-installed", action="store_true")
    parser.add_argument("--cache", action="store_true", help="replay the last result when no input changed")
    parser.add_argument("--spec-coverage", action="store_true",
                        help="print each skill rule's Agent Skills spec section, and any spec requirement without a check")
    args = parser.parse_args()

    if args.spec_coverage:
        return spec_coverage()
    if args.skills or args.rules:
        skill_roots, rule_files = args.skills, args.rules
    else:
        skill_roots, rule_files = default_scope(args.include_installed)
    skills = dedupe(find_skills(skill_roots))
    rules = dedupe(pathlib.Path(p) for p in rule_files)
    inputs = list(skills) + list(rules)
    for skill in skills:
        inputs.extend(p for p in skill.parent.rglob("*.md") if p != skill)

    cache_file = pathlib.Path(os.environ.get("TOOLING_CHECKUP_STATE_DIR") or HOME / ".local/state/tooling-checkup") / "audit-cache.json"
    key = fingerprint(inputs)
    if args.cache and cache_file.exists():
        try:
            cached = json.loads(cache_file.read_text())
        except (OSError, json.JSONDecodeError):
            cached = {}
        if cached.get("fingerprint") == key:
            print(f"audit: replayed from cache; no input changed since {cached.get('time', '?')}")
            print(cached.get("output", ""))
            return cached.get("status", 0)

    report = Report()
    for skill in skills:
        check_skill(skill, report)
    for rule in rules:
        if rule.is_file():
            check_rules(rule, report)
        else:
            report.add("ERROR", "R000", rule, "file does not exist")
    summary = (
        f"audit: {len(skills)} skill(s), {len(rules)} instruction file(s): "
        f"{report.counts['ERROR']} error(s), {report.counts['WARN']} warning(s), {report.counts['INFO']} info"
    )
    output = "\n".join(report.lines + [summary])
    print(output)
    status = 1 if report.counts["ERROR"] else 0

    if args.cache:
        import datetime as dt

        cache_file.parent.mkdir(parents=True, exist_ok=True)
        cache_file.write_text(json.dumps({
            "fingerprint": key,
            "time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "output": output,
            "status": status,
        }) + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
