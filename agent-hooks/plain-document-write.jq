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

def simple_call:
  select(.Background != true and .Coprocess != true and .Negated != true and
    ((.Redirs // []) | length) == 0 and
    .Cmd.Type == "CallExpr" and ((.Cmd.Assigns // []) | length) == 0);

def literal_argument_spans:
  standalone_call | .Stmts[0] | simple_call | .Cmd.Args
  | if (.[0] | plain_word) == "echo" then
      .[1:][] | select(quoted_issue_word)
    elif length == 6 and ([.[0:3][] | plain_word] == ["jq", "-n", "--arg"]) and
         (.[3] | plain_word | strings | test("^[A-Za-z_][A-Za-z0-9_]*$")) and
         (.[4] | quoted_issue_word) and
         (.[5].Parts | length == 1 and .[0].Type == "SglQuoted" and .[0].Dollar != true) and
         (.[5].Parts[0].Value == ("$" + (.[3] | plain_word))) then
      .[4]
    else empty
    end
  | [.Pos.Offset, .End.Offset, "argument"];

def static_repo_operand:
  ((plain_word // "") | test("^[A-Za-z0-9_./-]+$")) or
  ((.Parts | length) == 1 and .Parts[0].Type == "DblQuoted" and .Parts[0].Dollar != true and
    (.Parts[0].Parts | length == 1 and
      (.[0] | .Type == "ParamExp" and .Short == true and
        (.Param.Value | test("^[A-Za-z_][A-Za-z0-9_]*$")))));

def repo_branch_query:
  select((.Parts | length) == 1 and .Parts[0].Type == "DblQuoted" and .Parts[0].Dollar != true)
  | .Parts[0].Parts
  | select(length == 1 and .[0].Type == "CmdSubst" and .[0].Backquotes != true)
  | .[0].Stmts
  | select(length == 1)
  | .[0] | simple_call | .Cmd.Args
  | select(length == 5 and
      (.[0] | plain_word) == "git" and (.[1] | plain_word) == "-C" and
      (.[2] | static_repo_operand) and
      (.[3] | plain_word) == "branch" and (.[4] | plain_word) == "--show-current");

def repo_branch_comparison_spans:
  select(.Type == "File")
  | select(all(.. | objects | select(.Type == "FuncDecl"); false))
  | select(all(.. | objects | select(.Type == "CallExpr" and ((.Args // []) | length) > 0);
      (.Args[0] | plain_word) as $name | $name != null and
      ($name | IN("alias", "unalias", "eval", "source", ".", "builtin", "enable", "hash") | not)))
  | .Stmts[] | simple_call
  | select(.Cmd.Args | length == 5 and
      (.[0] | plain_word) == "[" and (.[2] | plain_word) == "=" and
      (.[3] | plain_word | strings | test("^[A-Za-z0-9][A-Za-z0-9._/-]*$")) and
      (.[4] | plain_word) == "]" and
      ((.[1] | repo_branch_query) != null))
  | [.Pos.Offset, .Cmd.Args[-1].End.Offset, "comparison"];

def inert_branch_spans:
  [literal_argument_spans, repo_branch_comparison_spans]
  | sort_by(.[0]) | reverse | .[] | @tsv;

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

if $ARGS.named.mode == "issue-body" then issue_body_span
elif $ARGS.named.mode == "branch-inert" then inert_branch_spans
else plain_document end
