#!/usr/bin/env bats
# dotfiles-doctor runs each fix in a new process (`bash -c "$cmd"`), so a fix
# that calls a function defined in its module, or in a lib/ file the module
# sources, must `export -f` it. The jetbrains plugin fix and the workflow
# duplicate-agent fix missed this and failed on every Mac.

load test_helper

_missing_fix_exports() {
  python3 - "$1" <<'PYTHON'
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])

def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)

def literal_prefix(word):
    result = ""
    for part in word.get("Parts", []):
        kind = part.get("Type")
        if kind in ("Lit", "SglQuoted"):
            result += part.get("Value", "")
        elif kind == "DblQuoted":
            prefix, complete = literal_prefix(part)
            result += prefix
            if not complete:
                return result, False
        else:
            return result, False
    return result, True

for module in sorted(root.glob("modules/*/doctor.sh")):
    source = module.read_text()
    definitions = source
    for lib in re.findall(r'source "\$DOTFILES_DIR/(lib/[A-Za-z0-9_.-]+\.sh)"', source):
        definitions += "\n" + (root / lib).read_text()
    functions = set(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\(\)", definitions, re.M))
    tree = json.loads(subprocess.run(
        ["shfmt", "--to-json"], input=source, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout)
    for call in nodes(tree):
        args = call.get("Args", [])
        # Args includes the command name. Only check's fourth argument is a repair.
        if call.get("Type") != "CallExpr" or len(args) < 5 or literal_prefix(args[0]) != ("check", True):
            continue
        prefix, complete = literal_prefix(args[4])
        match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(?:\s|$)", prefix)
        if not match or (not complete and len(prefix) == len(match[1])) or match[1] not in functions:
            continue
        function = match[1]
        export = r"^\s*export -f\b[^\n]*\b" + re.escape(function) + r"\b"
        if not re.search(export, source.replace("\\\n", ""), re.M):
            print(f"{module.relative_to(root)}:{function}")
PYTHON
}

@test "every fix that calls a module or lib function exports that function" {
  run _missing_fix_exports "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ] || { echo "not exported: $output"; false; }
}

@test "the export guard distinguishes predicates from missing and exported repairs" {
  local root="$BATS_TEST_TMPDIR/guard" source expected
  mkdir -p "$root/modules/control"
  for source in predicate missing exported advisory dynamic-name dynamic-argument; do
    printf 'helper() { :; }\n' > "$root/modules/control/doctor.sh"
    expected=""
    case "$source" in
      predicate) printf 'check "id" "description" "helper"\n' ;;
      missing) expected="modules/control/doctor.sh:helper"; printf 'check "id" "description" "true" "helper"\n' ;;
      exported) printf 'export -f helper\ncheck "id" "description" "true" "helper"\n' ;;
      advisory) printf 'check_advisory "id" "description" "helper"\n' ;;
      dynamic-name) printf 'check "id" "description" "true" "helper$(printf suffix)"\n' ;;
      dynamic-argument) expected="modules/control/doctor.sh:helper"; printf 'check "id" "description" "true" "helper $arg"\n' ;;
    esac >> "$root/modules/control/doctor.sh"
    run _missing_fix_exports "$root"
    [ "$status" -eq 0 ] || { echo "$source: $output"; false; }
    [ "$output" = "$expected" ] || { echo "$source expected '$expected', got '$output'"; false; }
  done
}

@test "dotfiles-doctor still runs fixes in a new bash process" {
  grep -q 'bash -c "$cmd"' "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  # Lib functions that fixes call read DOTFILES_DIR at run time.
  grep -q "^export DOTFILES_DIR$" "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
}

@test "workflow duplicate-agent fix runs in a new bash process" {
  local tmp; tmp="$(mktemp -d)"
  ( source "$BATS_TEST_DIRNAME/../lib/launchagent-duplicates.sh"
    export -f launchagent_argv launchagent_duplicates launchagent_remove_duplicates
    bash -c "launchagent_remove_duplicates '$tmp' '$tmp'" )
  rm -rf "$tmp"
}
