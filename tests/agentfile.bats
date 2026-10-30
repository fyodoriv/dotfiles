#!/usr/bin/env bats

agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"

# The 2026-10-13 usage audit removed context7, tasks-mcp, github, figma,
# chrome-devtools, and shadcn-mcp (0 calls in 180 days). playwright stays.
@test "Agentfile includes MCP servers expected in fresh agent sessions" {
  for server in playwright; do
    run awk -v server="$server" '
      /^mcp:/ { in_mcp = 1; next }
      /^[^[:space:]][^:]*:/ { in_mcp = 0 }
      in_mcp && $0 ~ "^[[:space:]]+- " server "$" { found = 1 }
      in_mcp && $0 ~ "^[[:space:]]+- name: " server "$" { found = 1 }
      END { exit found ? 0 : 1 }
    ' "$agentfile"
    [ "$status" -eq 0 ]
  done
}

# Parse a YAML file the way a broken Agentfile would fail agentbrew: yq when
# it is on PATH (the Brewfile installs it), else the macOS system Ruby.
parse_yaml() {
  if command -v yq >/dev/null 2>&1; then
    yq e '.' "$1" >/dev/null
  elif [ -x /usr/bin/ruby ]; then
    /usr/bin/ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$1"
  else
    echo "no YAML parser (install yq)" >&2
    return 2
  fi
}

@test "Agentfile.yaml parses as YAML" {
  run parse_yaml "$agentfile"
  [ "$status" -ne 2 ] || skip "needs yq or ruby"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the Agentfile YAML check fails on a broken file" {
  printf 'skills:\n  - a\n bad: [\n' > "$BATS_TEST_TMPDIR/broken.yaml"
  run parse_yaml "$BATS_TEST_TMPDIR/broken.yaml"
  [ "$status" -ne 2 ] || skip "needs yq or ruby"
  [ "$status" -ne 0 ]
}


@test "Agentfile hook targets keep legacy handlers out of native Codex sync" {
  local checkout node_bin scratch
  checkout="$(bash -c 'source "$1/lib/agentbrew-locate.sh"; agentbrew_locate' _ "$BATS_TEST_DIRNAME/.." 2>/dev/null || true)"
  [ -n "$checkout" ] && [ -x "$checkout/node_modules/.bin/tsx" ] || skip "needs agentbrew source checkout with dependencies"
  node_bin="$(command -v node)"
  [ -n "$node_bin" ] || skip "needs Node"
  scratch="$BATS_TEST_TMPDIR/hook-targets"
  mkdir -p "$scratch/home"
  run env -u BASH_ENV -u ENV HOME="$scratch/home" \
    XDG_CONFIG_HOME="$scratch/home/.config" XDG_DATA_HOME="$scratch/home/.local/share" \
    XDG_STATE_HOME="$scratch/home/.local/state" AGENTBREW_NO_AUTO_SYNC=1 \
    "$node_bin" "$checkout/node_modules/tsx/dist/cli.mjs" --input-type=module - "$agentfile" "$checkout" "$scratch" <<'NODE'
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const [agentfile, checkout, scratch] = process.argv.slice(2);
const moduleAt = relative => import(pathToFileURL(join(checkout, relative)).href);
const yaml = createRequire(join(checkout, 'package.json'))('js-yaml');
const { parseAgentfile } = await moduleAt('src/agentfile.ts');
const { filterHooksForTarget, syncHooks } = await moduleAt('src/sync/hooks-sync.ts');
const { defaultState, saveState } = await moduleAt('src/state.ts');
const { AGENT_DEFINITIONS } = await moduleAt('src/types.ts');
const hooks = parseAgentfile(readFileSync(agentfile, 'utf8')).hooks.map(hook => ({
  ...hook, type: hook.type ?? 'command', source: 'agentfile',
}));
const identity = hook => `${hook.event}:${hook.matcher ?? '*'} ${hook.command}`;
const legacy = [
  'PreToolUse:Shell ~/.config/dotfiles/hooks/prepend-endpoint-path.sh',
  'PreToolUse:Task ~/.config/dotfiles/hooks/prepend-endpoint-path.sh',
  'SessionStart:* ~/.config/dotfiles/hooks/session-endpoint-path.sh',
];
const claude = filterHooksForTarget(hooks, 'claude-code');
assert.equal(claude.length, 6, 'Claude keeps all six dotfiles handlers');
assert.deepEqual(claude.map(identity), hooks.map(identity));
const native = filterHooksForTarget(hooks, 'codex');
assert.deepEqual(native.filter(hook => legacy.includes(identity(hook))).map(identity), [], 'no legacy native handlers');
assert.equal(native.length, 3, 'all three supported dotfiles Bash handlers remain');
assert.ok(native.every(hook => hook.event === 'PreToolUse' && hook.matcher === 'Bash'));
// The sync fixture uses the real manifest policy with isolated module-run state.
const fixtureRepo = join(scratch, 'agentbrew-fixture');
mkdirSync(join(fixtureRepo, 'hooks'), { recursive: true });
const manifest = yaml.load(readFileSync(join(checkout, 'hooks/manifest.yaml'), 'utf8'));
const docsPolicy = manifest.hooks.find(hook => hook.id === 'gh-pr-body-requires-docs');
assert.ok(docsPolicy?.agents.includes('codex'), 'manifest policy supports native Codex');
writeFileSync(join(fixtureRepo, 'hooks/manifest.yaml'), yaml.dump({ version: 1, hooks: [{ ...docsPolicy, defaultEnabled: true }] }));
for (const dir of ['checks', 'lib']) symlinkSync(join(checkout, 'hooks', dir), join(fixtureRepo, 'hooks', dir));
process.env.AGENTBREW_REPO_ROOT = fixtureRepo;
saveState({ ...defaultState(), hooks, agents: AGENT_DEFINITIONS.filter(agent => ['claude-code', 'codex'].includes(agent.name)).map(agent => ({ ...agent, detected: true })) });
await syncHooks({ quiet: true, prune: false });
const flatten = config => Object.entries(config).flatMap(([event, groups]) => groups.flatMap(group => group.hooks.map(hook => ({ event, matcher: group.matcher, command: hook.command }))));
const nativeSynced = flatten(JSON.parse(readFileSync(join(process.env.HOME, '.codex/hooks.json'), 'utf8')).hooks);
assert.equal(nativeSynced.length, 4, 'native sync keeps exactly four supported policies');
assert.ok(nativeSynced.every(hook => hook.event === 'PreToolUse' && hook.matcher === 'Bash'));
const claudeSynced = flatten(JSON.parse(readFileSync(join(process.env.HOME, '.claude/settings.json'), 'utf8')).hooks);
assert.deepEqual(claudeSynced.filter(hook => hooks.some(source => identity(source) === identity(hook))).map(identity).sort(), hooks.map(identity).sort(), 'Claude sync keeps every original source hook');
assert.equal(claudeSynced.length, 7, 'Claude sync also retains the manifest policy');
console.log('legacy Codex 0; native policies 4; Claude source handlers 6; real sync passed');
NODE
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
