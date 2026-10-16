#!/usr/bin/env bats
# Tests for the `allow-scripts=` line that modify_private_dot_npmrc renders
# from data/npm-global-allow-scripts.json. npm 11+ blocks install scripts of
# global CLIs unless allowed, so topgrade's `npm update -g` left them broken.

load test_helper

MODIFY="$BATS_TEST_DIRNAME/../modify_private_dot_npmrc"
SHIPPED_LIST="$BATS_TEST_DIRNAME/../data/npm-global-allow-scripts.json"
REGISTRY_PY="$BATS_TEST_DIRNAME/fixtures/mock-npm-registry.py"

setup() {
  FIXTURE="$(mktemp -d)"
  unset DOTFILES_NPM_ALLOW_SCRIPTS_DATA CHEZMOI_SOURCE_DIR
}

teardown() {
  [ -n "${REGISTRY_PID:-}" ] && kill "$REGISTRY_PID" 2>/dev/null
  rm -rf "$FIXTURE"
}

@test "renders one allow-scripts line with every package in the list" {
  cat > "$FIXTURE/list.json" <<'EOF'
[
  { "package": "@railway/cli", "bin": "railway" },
  { "package": "script-cli", "bin": "script-cli" }
]
EOF
  run env DOTFILES_NPM_ALLOW_SCRIPTS_DATA="$FIXTURE/list.json" sh "$MODIFY" </dev/null

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^allow-scripts=')" -eq 1 ]
  printf '%s\n' "$output" | grep -qx 'allow-scripts=@railway/cli,script-cli'
}

@test "reads the list from CHEZMOI_SOURCE_DIR during chezmoi apply" {
  run env CHEZMOI_SOURCE_DIR="$BATS_TEST_DIRNAME/.." sh "$MODIFY" </dev/null

  [ "$status" -eq 0 ]
  expected="allow-scripts=$(jq -r '[.[].package] | join(",")' "$SHIPPED_LIST")"
  printf '%s\n' "$output" | grep -qx -- "$expected"
}

@test "omits the line when the list is missing and keeps credentials" {
  run env DOTFILES_NPM_ALLOW_SCRIPTS_DATA="$FIXTURE/missing.json" sh "$MODIFY" \
    <<<$'allow-scripts=stale\n//registry.npmjs.org/:_authToken=placeholder'

  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q '^allow-scripts='
  printf '%s\n' "$output" | grep -qx '//registry.npmjs.org/:_authToken=placeholder'
}

# Build version $1 of a CLI whose bin only works after its postinstall ran.
_pack_script_cli() {
  local src="$FIXTURE/src"
  mkdir -p "$src"
  cat > "$src/package.json" <<EOF
{"name":"script-cli","version":"$1","bin":{"script-cli":"cli.js"},
 "scripts":{"postinstall":"node -e \"require('fs').writeFileSync('built.txt','ok')\""}}
EOF
  cat > "$src/cli.js" <<'EOF'
#!/usr/bin/env node
const fs = require("fs");
if (!fs.existsSync(require("path").join(__dirname, "built.txt"))) {
  console.error("could not find the CLI binary");
  process.exit(1);
}
console.log(require("./package.json").version);
EOF
  chmod +x "$src/cli.js"
  (cd "$src" && npm pack -q --cache "$FIXTURE/cache" --pack-destination "$FIXTURE/reg" >/dev/null 2>&1)
  node -e 'const p=require(process.argv[1]);delete p.name;delete p.version;console.log(JSON.stringify(p))' \
    "$src/package.json" > "$FIXTURE/reg/script-cli-$1.tgz.json"
}

@test "npm update -g with the rendered npmrc keeps a script CLI working" {
  command -v npm >/dev/null || skip "npm not installed"
  command -v python3 >/dev/null || skip "python3 not installed"
  [ "$(npm --version 2>/dev/null | cut -d. -f1)" -ge 11 ] 2>/dev/null || skip "npm 11+ needed for allow-scripts"

  mkdir -p "$FIXTURE/reg"
  _pack_script_cli 1.0.0
  python3 -I "$REGISTRY_PY" "$FIXTURE/reg" > "$FIXTURE/port" 2>/dev/null &
  REGISTRY_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$FIXTURE/port" ] && break; sleep 0.5; done
  port="$(cat "$FIXTURE/port")"
  [ -n "$port" ]

  echo '[{"package":"script-cli","bin":"script-cli"}]' > "$FIXTURE/list.json"
  DOTFILES_NPM_ALLOW_SCRIPTS_DATA="$FIXTURE/list.json" sh "$MODIFY" </dev/null > "$FIXTURE/npmrc"
  # Keep the fixture away from the real registry and the user's cache.
  printf 'registry=http://127.0.0.1:%s/\nprefer-offline=false\n' "$port" >> "$FIXTURE/npmrc"
  npm_fixture=(--cache "$FIXTURE/cache" --userconfig "$FIXTURE/npmrc" --prefix "$FIXTURE/prefix")

  npm install -g "${npm_fixture[@]}" script-cli >/dev/null 2>&1
  run "$FIXTURE/prefix/bin/script-cli"
  [ "$output" = "1.0.0" ]

  _pack_script_cli 1.0.1
  npm update -g "${npm_fixture[@]}" >/dev/null 2>&1
  run "$FIXTURE/prefix/bin/script-cli"
  [ "$status" -eq 0 ]
  [ "$output" = "1.0.1" ]
}
