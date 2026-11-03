# Recognize one plain cat invocation, never a shell input or pipeline.
# This filter consumes shfmt's typed tree, not shell source text.
def quoted_delimiter:
  (.Parts | length) == 1 and
  (.Parts[0] | .Type == "SglQuoted" or
    (.Type == "DblQuoted" and all(.Parts[]; .Type == "Lit")));
def output_path:
  (.Parts | length) == 1 and .Parts[0].Type == "Lit" and
  (.Parts[0].Value | test("^[A-Za-z0-9_./-]+\\.(md|txt|json)$"));

select(.Type == "File" and (.Stmts | length) == 1)
| .Stmts[0] as $statement
| select(($statement.Background // false) == false and
         ($statement.Coprocess // false) == false and
         ($statement.Negated // false) == false)
| select($statement.Cmd.Type == "CallExpr" and
         (($statement.Cmd.Assigns // []) | length) == 0 and
         ($statement.Cmd.Args | length) == 1)
| select(($statement.Cmd.Args[0].Parts | length) == 1 and
         $statement.Cmd.Args[0].Parts[0].Type == "Lit" and
         ($statement.Cmd.Args[0].Parts[0].Value | IN("cat", "/bin/cat", "/usr/bin/cat")))
| ($statement.Redirs // []) as $redirects
| [$redirects[] | select(.Hdoc != null)] as $heredocs
| [$redirects[] | select(.Op == ">" or .Op == ">>")] as $outputs
| select(($heredocs | length) >= 1 and ($outputs | length) <= 1 and
         ($redirects | length) == (($heredocs | length) + ($outputs | length)))
| select(all($redirects[]; .N == null))
| select(all($heredocs[];
    (.Op == "<<" or .Op == "<<-") and
    (.Word | quoted_delimiter) and all(.Hdoc.Parts[]; .Type == "Lit")))
| select(all($outputs[]; .Word | output_path))
| {
    destination: ($outputs[0].Word.Parts[0].Value // ""),
    tree: ((.Stmts[0].Redirs[] | select(.Hdoc) | .Hdoc.Parts[].Value) = "")
  }
