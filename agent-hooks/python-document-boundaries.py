"""Recognize one fixed shell shape; never execute the submitted source."""
import ast
import json
import re
import sys


def reject():
    raise ValueError("unsupported document command")


def literal(word, quoted=False):
    parts = word.get("Parts", [])
    if len(parts) != 1 or parts[0].get("Type") not in (("Lit", "SglQuoted") if quoted else ("Lit",)):
        reject()
    value = parts[0].get("Value")
    if not isinstance(value, str):
        reject()
    return value


def call(statement, redirections=False):
    if any(statement.get(key, False) for key in ("Background", "Coprocess", "Negated")):
        reject()
    cmd = statement.get("Cmd", {})
    if cmd.get("Type") != "CallExpr" or cmd.get("Assigns"):
        reject()
    redirects = statement.get("Redirs") or []
    if bool(redirects) != redirections:
        reject()
    return cmd.get("Args") or [], redirects


def pair(statement):
    if any(statement.get(key, False) for key in ("Background", "Coprocess", "Negated")) or statement.get("Redirs"):
        reject()
    cmd = statement.get("Cmd", {})
    if cmd.get("Type") != "BinaryCmd" or cmd.get("Op") != "&&":
        reject()
    return cmd["X"], cmd["Y"]


def main():
    tree = json.load(sys.stdin)
    if tree.get("Type") != "File" or len(tree.get("Stmts", [])) != 2:
        reject()
    first, writer = pair(tree["Stmts"][0])
    add, commit = pair(tree["Stmts"][1])
    words, _ = call(first)
    switch = [literal(word) for word in words]
    if len(switch) != 4 or switch[:3] != ["git", "switch", "-c"] or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_./-]*", switch[3]):
        reject()
    words, redirects = call(writer, True)
    if [literal(word) for word in words] != ["python3", "-"] or len(redirects) != 1:
        reject()
    redir = redirects[0]
    delimiter = redir.get("Word", {}).get("Parts", [])
    parts = (redir.get("Hdoc") or {}).get("Parts", [])
    if (redir.get("N") is not None or redir.get("Op") != "<<" or len(delimiter) != 1
            or delimiter[0].get("Type") != "SglQuoted" or len(parts) != 1
            or parts[0].get("Type") != "Lit"):
        reject()
    body = parts[0]["Value"]
    program = ast.parse(body)
    if len(program.body) != 2:
        reject()
    imported, statement = program.body
    if not (isinstance(imported, ast.ImportFrom) and imported.module == "pathlib" and imported.level == 0
            and len(imported.names) == 1 and imported.names[0].name == "Path" and imported.names[0].asname is None
            and isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Call)):
        reject()
    write = statement.value
    if not (isinstance(write.func, ast.Attribute) and write.func.attr == "write_text" and not write.keywords
            and len(write.args) == 1 and isinstance(write.args[0], ast.Constant) and isinstance(write.args[0].value, str)):
        reject()
    path = write.func.value
    if not (isinstance(path, ast.Call) and isinstance(path.func, ast.Name) and path.func.id == "Path"
            and not path.keywords and len(path.args) == 1 and isinstance(path.args[0], ast.Constant)
            and isinstance(path.args[0].value, str)):
        reject()
    destination = path.args[0].value
    if not re.fullmatch(r"docs/plans/[A-Za-z0-9_][A-Za-z0-9_.-]*\.md", destination):
        reject()
    words, _ = call(add)
    if [literal(word) for word in words] != ["git", "add", destination]:
        reject()
    words, _ = call(commit)
    if len(words) != 4 or [literal(word) for word in words[:3]] != ["git", "commit", "-m"]:
        reject()
    message = literal(words[3], True)
    # Retain the Python body and commit message in the same checks as before.
    print(json.dumps([" ".join(switch), "python3 -\n" + body,
                      "git add " + destination, "git commit -m '" + message + "'"]))


try:
    main()
except (ValueError, KeyError, TypeError, SyntaxError, RecursionError):
    sys.exit(1)
