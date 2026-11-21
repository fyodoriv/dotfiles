# Recognize inert text in one direct invocation.
# This filter consumes shfmt's typed tree, not shell source text.
def quoted_delimiter:
  (.Parts | length) == 1 and
  (.Parts[0] | .Type == "SglQuoted" or
    (.Type == "DblQuoted" and all(.Parts[]; .Type == "Lit")));
def output_path:
  (.Parts | length) == 1 and .Parts[0].Type == "Lit" and
  (.Parts[0].Value | test("^[A-Za-z0-9_./-]+\\.(md|txt|json)$"));

def standalone_call:
  select(.Type == "File" and (.Stmts | length) == 1)
  | select(.Stmts[0] | .Background != true and .Coprocess != true and .Negated != true)
  | select(.Stmts[0].Cmd | .Type == "CallExpr" and ((.Assigns // []) | length) == 0);

def plain_word:
  if (.Parts | length) == 1 and .Parts[0].Type == "Lit" then .Parts[0].Value else null end;

def quoted_issue_word:
  quoted_delimiter and .Parts[0].Dollar != true;

def issue_options:
  if length == 0 then []
  elif (.[0] | plain_word | IN("--body", "-b")) and (.[1] | quoted_issue_word) then
    [.[1].Parts[0]] + (.[2:] | issue_options)
  elif (.[0].Parts | length) == 2 and .[0].Parts[0].Type == "Lit" and
       .[0].Parts[0].Value == "--body=" and ({Parts: [.[0].Parts[1]]} | quoted_issue_word) then
    [.[0].Parts[1]] + (.[1:] | issue_options)
  elif (.[0] | plain_word | IN("--title", "-t", "--repo", "-R")) and
       (.[1] | (plain_word != null or quoted_issue_word)) then
    .[2:] | issue_options
  else empty
  end;

def issue_body_span:
  standalone_call
  | select(((.Stmts[0].Redirs // []) | length) == 0)
  | .Stmts[0].Cmd.Args
  | select(([.[0:3][] | plain_word]) == ["gh", "issue", "create"])
  | .[3:] | issue_options
  | select(length == 1)
  | [.[0].Pos.Offset, .[0].End.Offset] | @tsv;

def plain_document:
standalone_call
| .Stmts[0] as $statement
| select(($statement.Cmd.Args | length) == 1)
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
  };

if $ARGS.named.mode == "issue-body" then issue_body_span else plain_document end
