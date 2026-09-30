#!/usr/bin/env python3
"""Tiny mock Ollama server for bats tests.

Speaks just enough of Ollama's HTTP surface to satisfy
`bin/local-ai-bench` and `lib/local-ai-agent.py`:

  - GET /v1/models      → OpenAI-style stub (bench's reachability probe).
  - POST /api/generate  → swallowed (bench's `--cold` keep_alive=0 ping).
  - POST /api/chat      → returns a scripted response from RESPONSES.

The mock takes a single positional arg — a port number — and optionally
reads its response script from a JSON file path passed as the second arg.
If no script is provided, a default "bash echo hello" tool call is
returned for every /api/chat hit (good enough for bench's four-row
table).

Usage:
  # In a bats test (default script — agent gets a bash tool call):
  python3 tests/fixtures/mock-ollama.py 18434 &
  MOCK_PID=$!
  sleep 0.2
  ... run agent against http://127.0.0.1:18434 ...
  command kill $MOCK_PID

  # Custom script (a list of /api/chat responses, played in order):
  cat > /tmp/script.json <<EOF
  [
    {"message": {"content": "", "tool_calls": [...]}, "eval_count": 5, "eval_duration": 1000000},
    {"message": {"content": "done", "tool_calls": []}, "eval_count": 5, "eval_duration": 1000000}
  ]
  EOF
  python3 tests/fixtures/mock-ollama.py 18434 /tmp/script.json &

The agent and bench both expect the response shape that real Ollama
emits. Concretely each /api/chat response must include:
  - message.content       (string)
  - message.tool_calls    (list — optional, omitted if no tool call)
  - eval_count            (int — output token count, for tok/s math)
  - eval_duration         (int, nanoseconds — for tok/s math)
  - prompt_eval_duration  (int, nanoseconds — for prompt-cache math)

The default-script response includes plausible non-zero values so the
bench's tok/s and prompt-cache columns aren't degenerate.
"""
import http.server
import json
import sys

PORT = int(sys.argv[1])
SCRIPT_PATH = sys.argv[2] if len(sys.argv) > 2 else None

if SCRIPT_PATH:
    with open(SCRIPT_PATH) as f:
        RESPONSES = json.load(f)
else:
    # Default: every /api/chat call returns a bash tool call. Enough
    # to let bench enumerate four rows and exit cleanly.
    RESPONSES = [
        {
            "message": {
                "content": "",
                "tool_calls": [{
                    "function": {
                        "name": "bash",
                        "arguments": {"command": "echo hello"},
                    },
                }],
            },
            "eval_count": 50,
            "eval_duration": 600_000_000,         # 600ms → ~83 tok/s
            "prompt_eval_duration": 40_000_000,   # 40ms (warm)
        },
    ]

COUNTER = [0]


class Handler(http.server.BaseHTTPRequestHandler):
    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/v1/models"):
            # Bench's reachability probe — return any non-empty list.
            self._json(200, {"object": "list", "data": [{"id": "mock"}]})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        _ = self.rfile.read(n)
        if self.path.startswith("/api/generate"):
            # Bench's cold-load unload ping. Always succeeds.
            self._json(200, {"done": True})
            return
        if self.path.startswith("/api/chat"):
            idx = min(COUNTER[0], len(RESPONSES) - 1)
            COUNTER[0] += 1
            self._json(200, RESPONSES[idx])
            return
        self._json(404, {"error": "not found"})

    def log_message(self, *args, **kwargs):  # silence stderr
        pass


if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
