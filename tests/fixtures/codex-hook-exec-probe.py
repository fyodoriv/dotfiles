import http.server
import json
import pathlib
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import threading

from pathlib import Path

old = "printf '%s\\n' codex-fixture-original"
new = "printf '%s\\n' codex-fixture-rewritten"
codex = str(Path(sys.argv[1]).absolute())
if sys.platform != "linux":
    raise RuntimeError("This focused host proof requires Linux.")
ip = shutil.which("ip")
assert ip is not None
links = json.loads(subprocess.check_output([ip,"-j","link","show"],text=True))
assert [row["ifname"] for row in links] == ["lo"], "unexpected network interface"
assert "UP" in links[0]["flags"], "local fixture interface is not up"
node_dir = str(Path(sys.argv[2]).parent)
assert subprocess.check_output([codex,"--version"],text=True).strip() == "codex-cli 0.167.0"

HOOK = r'''
import json, sys
from pathlib import Path
phase, mode, root, original, update = sys.argv[1:]
data = json.load(sys.stdin)
tool_input = data.get("tool_input", {})
actual = tool_input.get("command")
known = "original" if actual == original else "rewritten" if actual == update else "unknown"
with (Path(root)/"hook-events").open("a") as out:
    out.write(json.dumps({"phase":phase,"input":known})+"\n")
if phase == "post":
    raise SystemExit
reply = {"hookEventName":"PreToolUse","permissionDecision":"allow" if known != "unknown" else "deny"}
if phase == "update" and mode == "rewrite" and known == "original":
    reply["updatedInput"] = {**tool_input, "command":update}
print(json.dumps({"hookSpecificOutput":reply}))
'''

def native_list(cwd, env):
    p = subprocess.Popen([codex,"app-server","--listen","stdio://"],
                         cwd=cwd,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE,text=True)
    def send(data):
        p.stdin.write(json.dumps(data)+"\n")
        p.stdin.flush()
    def get(target):
        for line in p.stdout:
            row=json.loads(line)
            if row.get("id")==target:
                return row["result"]
        raise RuntimeError("discovery ended before response")
    try:
        send({"id":1,"method":"initialize","params":{
            "clientInfo":{"name":"benign-hook-fixture","version":"1"},"capabilities":None,
        }})
        get(1)
        send({"method":"initialized"})
        send({"id":2,"method":"hooks/list","params":{"cwds":[str(cwd)]}})
        return get(2)["data"][0]
    finally:
        p.stdin.close()
        try:
            p.wait(timeout=4)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait(timeout=4)


def sse(kind, **data):
    return f"event: {kind}\ndata: ".encode()+json.dumps({"type":kind,**data}).encode()+b"\n\n"


def stream(tool, workspace):
    message = {
        "id":"resp_fixture_tool" if tool else "resp_fixture_end",
        "object":"response","created_at":1,"model":"fixture-model","status":"in_progress",
        "output":[],"error":None,
    }
    data = sse("response.created", response=message)
    if tool:
        name="exec_command"
        finished={"type":"function_call","id":"fc_fixture","call_id":"call_fixture",
                  "name":name,"arguments":json.dumps({"cmd":old,"workdir":str(workspace),"yield_time_ms":1000,
                                                     "max_output_tokens":1000}),"status":"completed"}
        data += sse("response.output_item.added", output_index=0, item={**finished,"arguments":"","status":"in_progress"})
        data += sse("response.function_call_arguments.delta", output_index=0,item_id="fc_fixture",
                    delta=finished["arguments"])
        data += sse("response.function_call_arguments.done", output_index=0,item_id="fc_fixture",
                    arguments=finished["arguments"], name=name)
    else:
        part={"type":"output_text","text":"Fixture complete.","annotations":[]}
        finished={"type":"message","id":"msg_fixture","role":"assistant","status":"completed","content":[part]}
        data += sse("response.output_item.added", output_index=0,item={**finished,"status":"in_progress","content":[]})
        data += sse("response.content_part.added", output_index=0,content_index=0,item_id="msg_fixture",
                    part={**part,"text":""})
        data += sse("response.output_text.delta", output_index=0,content_index=0,item_id="msg_fixture",
                    delta=part["text"])
        data += sse("response.output_text.done", output_index=0,content_index=0,item_id="msg_fixture",
                    text=part["text"])
    data += sse("response.output_item.done", output_index=0,item=finished)
    data += sse("response.completed", response={**message,"status":"completed","output":[finished],
        "usage":{"input_tokens":1,"input_tokens_details":{"cached_tokens":0},"output_tokens":1,
                 "output_tokens_details":{"reasoning_tokens":0},"total_tokens":2}})
    return data


def run(root, mode):
    home=root/"home"
    config=home/".codex"
    work=root/"work"
    temp=root/"tmp"
    for folder in (config,work,temp):
        folder.mkdir(parents=True)
    hook=root/"hook.py"
    hook.write_text(HOOK)
    def command(phase):
        return shlex.join([sys.executable,str(hook),phase,mode,str(root),old,new])
    commands={phase:command(phase) for phase in ("observe","update","post")}
    def recipe(phase):
        return {"type":"command","timeout":5,"command":commands[phase]}
    (config/"hooks.json").write_text(json.dumps({"hooks":{
        "PreToolUse":[{"matcher":"Bash","hooks":[recipe("observe"),recipe("update")]}],
        "PostToolUse":[{"matcher":"Bash","hooks":[recipe("post")]}],
    }}))
    env={"HOME":str(home),"CODEX_HOME":str(config),"TMPDIR":str(temp),
         "XDG_CONFIG_HOME":str(home/".config"),"XDG_STATE_HOME":str(home/".state"),
         "PATH":node_dir+":"+str(Path(codex).parent)+":/usr/bin:/bin:/usr/sbin:/sbin","LANG":"en_US.UTF-8"}
    metadata=native_list(work,env)
    assert not metadata["errors"] and len(metadata["hooks"])==3
    assert {x.get("command") for x in metadata["hooks"]}==set(commands.values())
    assert all(x["enabled"] and x["trustStatus"]=="untrusted" and not x["isManaged"] for x in metadata["hooks"])
    requests=[]
    paths=[]
    outputs=[]
    output_diagnostics=[]
    class Server(http.server.BaseHTTPRequestHandler):
        def log_message(self,*args):
            return
        def do_POST(self):
            route=self.path.split("?")[0]
            paths.append("responses" if route.endswith("/responses") else "other")
            if not route.endswith("/responses") or len(requests)>=2:
                self.send_error(400)
                return
            size=int(self.headers.get("Content-Length","0"))
            if not 0<size<=1_048_576:
                self.send_error(413)
                return
            body=json.loads(self.rfile.read(size))
            calls=[item for item in body.get("input",[]) if isinstance(item,dict)
                   and item.get("type")=="function_call_output" and item.get("call_id")=="call_fixture"]
            tool=not requests
            if tool and not any(
                x.get("name")=="exec_command" or x.get("function",{}).get("name")=="exec_command"
                for x in body.get("tools",[]) if isinstance(x,dict)
            ):
                self.send_error(422)
                return
            if not tool:
                for x in calls:
                    value=json.dumps(x.get("output"))
                    output_diagnostics.append({
                        "sandbox": "sandbox" in value.lower(),
                        "permission": "permission" in value.lower() or "not permitted" in value.lower(),
                        "exit_reported": "exit" in value.lower(),
                        "output_type": type(x.get("output")).__name__,
                    })
                    if "codex-fixture-" not in value:
                        output_diagnostics[-1]["message_kind"] = (
                            "sandbox_apply" if "sandbox_apply" in value else
                            "SandboxDenied" if "SandboxDenied" in value else
                            "launch_failure" if "launch" in value.lower() else "other"
                        )
                    outputs.append("original" if "codex-fixture-original" in value else
                                   "rewritten" if "codex-fixture-rewritten" in value else "unobserved")
            requests.append("proposal" if tool else "result")
            data=stream(tool,work)
            self.send_response(200)
            self.send_header("Content-Type","text/event-stream")
            self.send_header("Content-Length",str(len(data)))
            self.end_headers()
            self.wfile.write(data)
    with http.server.ThreadingHTTPServer(("127.0.0.1",0),Server) as server:
        port=server.server_address[1]
        (config/"config.toml").write_text(
            'model="fixture-model"\nmodel_provider="fixture"\ncheck_for_update_on_startup=false\n'
            '[model_providers.fixture]\nname="Fixture"\nwire_api="responses"\n'
            f'base_url="http://127.0.0.1:{port}/v1"\nrequires_openai_auth=false\n'
        )
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            result=subprocess.run([codex,
                                   "--ask-for-approval","never","exec","--sandbox","read-only",
                                   "--skip-git-repo-check","--json","--dangerously-bypass-hook-trust",
                                   "Run only the harmless fixture command, then finish."],
                                  cwd=work,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=45)
        finally:
            server.shutdown()
            thread.join(timeout=3)
    logfile=root/"hook-events"
    events=[json.loads(line) for line in logfile.read_text().splitlines()] if logfile.exists() else []
    events_from_cli=[json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    command_receipts=[row["item"] for row in events_from_cli
                      if row.get("type")=="item.completed" and
                      row.get("item",{}).get("type")=="command_execution"]
    def marker(output):
        if isinstance(output,str):
            value=output.strip()
            for name in ("original","rewritten"):
                if value==f"codex-fixture-{name}":
                    return name
        return "unobserved"
    receipts=[{"exit":item.get("exit_code"),"marker":marker(item.get("aggregated_output"))}
              for item in command_receipts]
    response={"case":mode,"status":result.returncode,"requests":requests,
              "routes":paths,"events":events,"execution":outputs,"command_receipts":receipts,
              "diagnostics":output_diagnostics}
    if result.returncode:
        response["error_labels"]=[row[:230] for row in result.stderr.splitlines()
                                  if row.startswith(("Error:","sandbox-exec:"))][:4]
        response["event_types"]=[json.loads(row).get("type") for row in result.stdout.splitlines()
                                  if row.startswith("{")][:12]
    print(json.dumps(response),flush=True)
    expected="rewritten" if mode=="rewrite" else "original"
    return (result.returncode==0 and requests==["proposal","result"] and outputs==[expected]
            and receipts==[{"exit":0,"marker":expected}]
            and sorted(x["phase"] for x in events)==["observe","post","update"])


with tempfile.TemporaryDirectory(prefix="benign-codex-hook-",dir="/tmp") as folder:
    root=pathlib.Path(folder).resolve()
    outcomes=[run(root/mode,mode) for mode in ("observe","rewrite")]
sys.exit(0 if all(outcomes) else 1)
