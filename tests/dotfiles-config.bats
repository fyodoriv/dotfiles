#!/usr/bin/env bats
# `dotfiles config` shows and changes settings against one table,
# config/settings.yaml. Values live under `data:` in
# ~/.config/chezmoi/chezmoi.yaml. `config set` validates, never applies.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
TABLE="$REPO_ROOT/config/settings.yaml"
# The real chezmoi, found before setup puts a logging fake first on PATH.
REAL_CHEZMOI="$(command -v chezmoi || true)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  unset XDG_CONFIG_HOME
  export DOTFILES_LOCK="$TEST_DIR/dotfiles.lock"
  CFG="$HOME/.config/chezmoi/chezmoi.yaml"
  mkdir -p "$HOME/.config/chezmoi" "$TEST_DIR/bin"
  cat > "$CFG" <<'EOF'
sourceDir: "/tmp/dotfiles-source"
data:
  profile: "core"
  is_enterprise: false
  brew_skip:
    []
  owner_machine: false
  morning_hour: 8
  git_work_name: "Alex Example"
  git_work_email: "alex@example.com"
EOF
  chmod 600 "$CFG"
  # Any chezmoi or sudo call is logged: config must call neither.
  for tool in chezmoi sudo; do
    printf '#!/bin/bash\necho "%s $*" >> "%s/calls.log"\n' "$tool" "$TEST_DIR" > "$TEST_DIR/bin/$tool"
    chmod +x "$TEST_DIR/bin/$tool"
  done
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

cfg() { run bash "$REPO_ROOT/bin/dotfiles" config "$@"; }
table_keys() { yq -r '.settings | keys | .[]' "$TABLE"; }
cfg_hash() { shasum -a 256 "$CFG" | awk '{ print $1 }'; }

@test "config lists every setting in the table with its value, source, and allowed values" {
  cfg
  [ "$status" -eq 0 ]
  local key
  while IFS= read -r key; do
    printf '%s\n' "$output" | grep -qE "^$key +" || { echo "missing row: $key"; return 1; }
  done < <(table_keys)
  printf '%s\n' "$output" | grep -qE '^profile +core +default +core\|full$'
  printf '%s\n' "$output" | grep -qE '^git_work_name +Alex Example +chezmoi\.yaml '
  # A key that is not in the file shows its default.
  printf '%s\n' "$output" | grep -qE '^weekly_metrics +false +default +true\|false$'
  [[ "$output" == *"dotfiles config set <key> <value>"* ]]
}

@test "config get prints only the value; a @key default follows the other setting" {
  cfg get morning_hour
  [ "$status" -eq 0 ] && [ "$output" = "8" ]
  cfg get weekly_metrics
  [ "$output" = "false" ]
  cfg get auto_sync
  [ "$output" = "false" ]
  sed -i.bak 's/^  owner_machine: false$/  owner_machine: true/' "$CFG" && rm -f "$CFG.bak"
  cfg get auto_sync
  [ "$output" = "true" ]
  cfg
  printf '%s\n' "$output" | grep -qE '^auto_sync +true +default '
}

@test "config <key> explains one setting" {
  cfg weekly_metrics
  [ "$status" -eq 0 ]
  [[ "$output" == *"Value:     false"* ]]
  [[ "$output" == *"Source:    default"* ]]
  [[ "$output" == *"Default:   false"* ]]
  [[ "$output" == *"Allowed:   true|false"* ]]
  [[ "$output" == *"What:      "*"metrics"* ]]
}

@test "config set saves a bool that config get reads back, and keeps the file private" {
  cfg set weekly_metrics true
  [ "$status" -eq 0 ]
  [[ "$output" == *"weekly_metrics: false → true"* ]]
  [[ "$output" == *"Next: dotfiles apply"* ]]
  [ "$(yq '.data.weekly_metrics | tag' "$CFG")" = '!!bool' ]
  cfg get weekly_metrics
  [ "$output" = "true" ]
  [ "$(stat -f %Lp "$CFG")" = "600" ]
  # Other values and the rest of the file are kept.
  [ "$(yq '.data.git_work_name' "$CFG")" = "Alex Example" ]
  [ "$(yq '.sourceDir' "$CFG")" = "/tmp/dotfiles-source" ]
}

@test "config set normalizes yes and writes whole numbers as numbers" {
  cfg set obsidian yes
  [ "$status" -eq 0 ]
  [ "$(yq '.data.obsidian' "$CFG")" = "true" ]
  cfg set morning_hour 07
  [ "$status" -eq 0 ]
  [ "$(yq '.data.morning_hour' "$CFG")" = "7" ]
  [ "$(yq '.data.morning_hour | tag' "$CFG")" = '!!int' ]
  cfg set profile full
  [ "$(yq '.data.profile' "$CFG")" = "full" ]
  cfg set profile full
  [[ "$output" == *"already full. Nothing changed."* ]]
}

@test "config set refuses a bad value with the reason and leaves the file unchanged" {
  local before key value
  before="$(cfg_hash)"
  while IFS='|' read -r key value; do
    cfg set "$key" "$value"
    [ "$status" -eq 2 ] || { echo "$key=$value: status $status: $output"; return 1; }
    [[ "$output" == *"is not allowed"* ]] || { echo "$key=$value: $output"; return 1; }
  done <<'EOF'
weekly_metrics|maybe
profile|medium
morning_hour|24
morning_minute|-1
dotfiles_dir|/etc
dotfiles_dir|apps/../..
git_work_email|not-an-email
github_enterprise_host|bad host
claude_effort|max
brew_skip|bad name
EOF
  [ "$(cfg_hash)" = "$before" ]
}

@test "config set refuses an unknown key and a missing value" {
  cfg set no_such_setting 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown setting: no_such_setting"* ]]
  cfg set profile
  [ "$status" -eq 2 ]
  [[ "$output" == *"core|full"* ]]
}

@test "config set stores text literally: no shell or YAML injection" {
  local value='A "q"; $(touch '"$TEST_DIR"'/pwned) `id` #x'
  cfg set git_work_name "$value"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/pwned" ]
  cfg get git_work_name
  [ "$output" = "$value" ]
  [ "$(yq '.data.git_work_name' "$CFG")" = "$value" ]
}

@test "config set writes a list and clears it" {
  cfg set brew_skip ' watchman, rancher '
  [ "$status" -eq 0 ]
  [ "$(yq '.data.brew_skip | length' "$CFG")" = "2" ]
  [ "$(yq '.data.brew_skip[1]' "$CFG")" = "rancher" ]
  cfg get brew_skip
  [ "$output" = "watchman,rancher" ]
  cfg set brew_skip ''
  [ "$status" -eq 0 ]
  [ "$(yq '.data.brew_skip | length' "$CFG")" = "0" ]
}

@test "an optional setting set to empty is removed, so the built-in default applies" {
  cfg set claude_effort high
  [ "$(yq '.data.claude_effort' "$CFG")" = "high" ]
  cfg set claude_effort ''
  [ "$status" -eq 0 ]
  [ "$(yq '.data | has("claude_effort")' "$CFG")" = "false" ]
}

@test "config set never applies and never uses sudo" {
  cfg set weekly_metrics true
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_DIR/calls.log" ]
  # No sudo or apply command in the code (comments may name them).
  ! grep -v '^[[:space:]]*#' "$REPO_ROOT/bin/dotfiles-config" | grep -qwE 'sudo|chezmoi apply'

}

@test "config set without a chezmoi config names the install step" {
  rm -f "$CFG"
  cfg set profile full
  [ "$status" -eq 1 ]
  [[ "$output" == *"dotfiles install plan"* ]]
  cfg
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not exist yet"* ]]
}

@test "settings table defaults match a new-user render of .chezmoi.yaml.tmpl" {
  [ -n "$REAL_CHEZMOI" ] || skip "chezmoi not installed"
  local render="$TEST_DIR/render.yaml" key type def opt got want ref refs
  # A home with no chezmoi config yet, as on a new Mac.
  mkdir -p "$TEST_DIR/new-home"
  HOME="$TEST_DIR/new-home" "$REAL_CHEZMOI" init --source "$REPO_ROOT" --config-path "$render" --promptDefaults >/dev/null 2>&1
  [ -s "$render" ]
  rendered() {
    yq -r ".data | has(\"$1\")" "$render" | grep -qx true || return 1
    yq -r ".data[\"$1\"] as \$v | (if (\$v | tag) == \"!!seq\" then (\$v | join(\",\")) else (\$v | tostring) end)" "$render"
  }
  # Every rendered key is in the table.
  while IFS= read -r key; do
    yq -e ".settings | has(\"$key\")" "$TABLE" >/dev/null || { echo "template key not in the table: $key"; return 1; }
  done < <(yq -r '.data | keys | .[]' "$render")
  # Every table key has the template's default (or is optional and omitted).
  while IFS=$'\t' read -r key opt def; do
    [ "$def" = "null" ] && def=""
    if ! got="$(rendered "$key")"; then
      [ "$opt" = "true" ] || { echo "not rendered and not optional: $key"; return 1; }
      continue
    fi
    case "$def" in
      derived) continue ;;
      @*)
        want=false
        IFS='|' read -r -a refs <<< "${def#@}"
        for ref in "${refs[@]}"; do
          yq -e ".settings | has(\"$ref\")" "$TABLE" >/dev/null || { echo "$key refers to unknown $ref"; return 1; }
          [ "$(rendered "$ref")" = "true" ] && want=true
        done
        ;;
      *) want="$def" ;;
    esac
    [ "$got" = "$want" ] || { echo "$key: table default '$want', template renders '$got'"; return 1; }
  done < <(yq -r '.settings | to_entries | .[] | .key + "\t" + ((.value.optional // false) | tostring) + "\t" + (.value.default | tostring)' "$TABLE")
}

@test "every table key is in the template's data block and in the README Configuration table" {
  local key section
  section="$(awk '/^### Configuration/ { on = 1; next } on && /^### / { exit } on' "$REPO_ROOT/README.md")"
  while IFS= read -r key; do
    grep -qE "^  $key:( |\$)" "$REPO_ROOT/.chezmoi.yaml.tmpl" || { echo "not in the template data: $key"; return 1; }
    [[ "$section" == *"\`$key\`"* ]] || { echo "not in README Configuration: $key"; return 1; }
  done < <(table_keys)
}
