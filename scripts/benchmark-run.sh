#!/bin/bash
# Competitive scorecard: dotfiles against other dotfile managers.
#
# Every tool deploys the same synthetic workload into fresh temporary HOME
# directories. The real HOME is never a deploy target. Pinned competitor
# builds are cached in BENCH_CACHE_DIR (default: ~/.cache/dotfiles-benchmark).
# A tool that cannot run is reported as blocked, with a reason. It never gets
# made-up numbers.
#
# Usage: scripts/benchmark-run.sh [--json] [--files N] [--reps N]
#
# Environment:
#   BENCH_FILES      files in the workload (default 120)
#   BENCH_REPS       timed runs per metric; the median is reported (default 3)
#   BENCH_CACHE_DIR  competitor cache directory
#   BENCH_NO_FETCH=1 do not download competitors; a missing one is blocked
#   BENCH_TOOLS      space-separated subset of tools to run (default: all)
#   BENCH_<TOOL>     override a tool binary (CHEZMOI, STOW, YADM, DOTBOT, NIX)
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"

FILES="${BENCH_FILES:-120}"
REPS="${BENCH_REPS:-3}"
CACHE_DIR="${BENCH_CACHE_DIR:-$HOME/.cache/dotfiles-benchmark}"
OUTPUT="table"
YADM_VERSION="3.3.0"
YADM_SHA256="948d36b491eecad5cfebf310aa14853ac9e28c92f1d7c4844c30f1d127d4296d"
DOTBOT_VERSION="1.21.0"
ALL_TOOLS="dotfiles chezmoi stow yadm dotbot home-manager"
TOOLS="${BENCH_TOOLS:-$ALL_TOOLS}"

while [ $# -gt 0 ]; do
  case "$1" in
    --json) OUTPUT="json"; shift ;;
    --files) FILES="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$FILES$REPS" in
  *[!0-9]*) echo "--files and --reps need positive integers" >&2; exit 2 ;;
esac
[ "$FILES" -gt 0 ] && [ "$REPS" -gt 0 ] || { echo "--files and --reps need positive integers" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bench.XXXXXX")"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# Commands a person types on a fresh Mac that already has Homebrew and git.
# Sources are listed in docs/competition/scorecard.md.
manual_steps() {
  case "$1" in
    dotfiles) echo 4 ;;      # brew install chezmoi; git clone; chezmoi init --apply; dotfiles doctor --fix
    chezmoi) echo 1 ;;       # sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <user>
    stow) echo 3 ;;          # brew install stow; git clone; stow <packages>
    yadm) echo 2 ;;          # brew install yadm; yadm clone <url>
    dotbot) echo 2 ;;        # git clone --recursive; ./install
    home-manager) echo 5 ;;  # nix installer; nix-channel --add; nix-channel --update; install; switch
  esac
}

deploy_mode() {
  case "$1" in
    dotfiles|chezmoi|yadm) echo copy ;;
    stow|dotbot) echo symlink ;;
    home-manager) echo symlink ;;
  esac
}

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'; }

median() { sort -n | awk '{ v[NR] = $1 } END { if (NR == 0) exit 1; print v[int((NR + 1) / 2)] }'; }

# Run a command with HOME and the XDG dirs inside the isolated home $1.
in_home() {
  local h="$1"; shift
  env HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share" \
    XDG_STATE_HOME="$h/.local/state" XDG_CACHE_HOME="$h/.cache" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "$@"
}

# ── Workload ─────────────────────────────────────────────────────────
# $FILES deterministic config files spread over 12 nested directories
# under ~/.bench. Relative paths are listed in $WORK/files.txt.
build_fixture() {
  local root="$WORK/fixture" i dir line
  mkdir -p "$root"
  : > "$WORK/files.txt"
  for i in $(seq 1 "$FILES"); do
    dir="d$((i % 12))/sub$((i % 3))"
    mkdir -p "$root/$dir"
    for line in $(seq 1 24); do
      printf 'key_%d_%d = value_%d_%d\n' "$i" "$line" "$i" "$line"
    done > "$root/$dir/f$i.conf"
    printf '.bench/%s/f%d.conf\n' "$dir" "$i" >> "$WORK/files.txt"
  done
}

new_home() { mktemp -d "$WORK/home.XXXXXX"; }

# Percent of workload files in home $1 that match the fixture byte for byte.
match_pct() {
  local h="$1" rel ok=0 total=0
  while IFS= read -r rel; do
    total=$((total + 1))
    if cmp -s "$h/$rel" "$WORK/fixture/${rel#.bench/}"; then ok=$((ok + 1)); fi
  done < "$WORK/files.txt"
  awk -v ok="$ok" -v total="$total" 'BEGIN { printf "%.1f\n", (total ? ok * 100 / total : 0) }'
}

# Replace one deployed file with a local edit (the drift event).
inject_drift() {
  local target
  target="$1/$(head -1 "$WORK/files.txt")"
  rm -f "$target"
  printf 'edited by hand\n' > "$target"
}

# ── Tool resolution ──────────────────────────────────────────────────
# Each resolver prints the binary path, or prints a reason and returns 1.
resolve_chezmoi() {
  local bin="${BENCH_CHEZMOI:-$(command -v chezmoi || true)}"
  [ -n "$bin" ] && [ -x "$bin" ] && { echo "$bin"; return 0; }
  echo "chezmoi is not installed"; return 1
}

resolve_stow() {
  local bin="${BENCH_STOW:-$(command -v stow || true)}"
  [ -n "$bin" ] && [ -x "$bin" ] && { echo "$bin"; return 0; }
  echo "GNU stow is not installed"; return 1
}

resolve_yadm() {
  local bin="${BENCH_YADM:-$CACHE_DIR/yadm-$YADM_VERSION}"
  if [ ! -x "$bin" ] && [ -z "${BENCH_YADM:-}" ] && [ "${BENCH_NO_FETCH:-0}" != 1 ]; then
    mkdir -p "$CACHE_DIR"
    if curl -fsSL -o "$bin.tmp" "https://raw.githubusercontent.com/yadm-dev/yadm/$YADM_VERSION/yadm" &&
       [ "$(shasum -a 256 "$bin.tmp" | cut -d' ' -f1)" = "$YADM_SHA256" ]; then
      chmod +x "$bin.tmp" && mv "$bin.tmp" "$bin"
    else
      rm -f "$bin.tmp"
    fi
  fi
  [ -x "$bin" ] && { echo "$bin"; return 0; }
  echo "yadm $YADM_VERSION is not cached and could not be fetched"; return 1
}

resolve_dotbot() {
  local venv="$CACHE_DIR/dotbot-$DOTBOT_VERSION"
  local bin="${BENCH_DOTBOT:-$venv/bin/dotbot}"
  if [ ! -x "$bin" ] && [ -z "${BENCH_DOTBOT:-}" ] && [ "${BENCH_NO_FETCH:-0}" != 1 ] && command -v uv >/dev/null 2>&1; then
    uv venv -q "$venv" >/dev/null 2>&1 &&
      uv pip install -q --python "$venv/bin/python" "dotbot==$DOTBOT_VERSION" >/dev/null 2>&1 || true
  fi
  [ -x "$bin" ] && { echo "$bin"; return 0; }
  echo "dotbot $DOTBOT_VERSION is not cached and could not be installed with uv"; return 1
}

resolve_home_manager() {
  local bin="${BENCH_NIX:-$(command -v nix || true)}"
  [ -n "$bin" ] && [ -x "$bin" ] && command -v home-manager >/dev/null 2>&1 && { echo "$bin"; return 0; }
  echo "nix and home-manager are not installed; installing nix needs admin rights and a system volume"; return 1
}

resolve_dotfiles() {
  resolve_chezmoi >/dev/null || { echo "dotfiles needs chezmoi, which is not installed"; return 1; }
  echo "$DOTFILES_DIR/bin/dotfiles"
}

# ── Per-tool source layout, apply, and drift check ───────────────────
# prepare_<tool> SRC builds the tool's source tree from the fixture.
# apply_<tool> SRC HOME deploys it. detect_<tool> SRC HOME prints "detected"
# when the tool reports the drift event, else "missed".

prepare_chezmoi() {
  mkdir -p "$1"
  cp -R "$WORK/fixture" "$1/dot_bench"
}
apply_chezmoi() { in_home "$2" "$BIN" apply --source "$1" --destination "$2" --no-tty >/dev/null; }
detect_chezmoi() {
  local out
  out="$(in_home "$2" "$BIN" status --source "$1" --destination "$2" 2>/dev/null || true)"
  [ -n "$out" ] && echo detected || echo missed
}

# dotfiles: its real `apply --no-fix` and `diff` code paths, run from a
# copy of bin/dotfiles whose repo root is the fixture source.
prepare_dotfiles() {
  mkdir -p "$1/bin" "$1/lib"
  cp "$DOTFILES_DIR/bin/dotfiles" "$1/bin/dotfiles"
  cp "$DOTFILES_DIR/lib/colors.sh" "$DOTFILES_DIR/lib/lock.sh" "$1/lib/"
  printf 'bin\nlib\n' > "$1/.chezmoiignore"
  cp -R "$WORK/fixture" "$1/dot_bench"
}
apply_dotfiles() {
  local cz; cz="$(dirname "$(resolve_chezmoi)")"
  in_home "$2" env PATH="$cz:$PATH" "$1/bin/dotfiles" apply --no-fix --no-tty >/dev/null
}
detect_dotfiles() {
  local out cz; cz="$(dirname "$(resolve_chezmoi)")"
  out="$(in_home "$2" env PATH="$cz:$PATH" "$1/bin/dotfiles" diff --no-pager 2>/dev/null || true)"
  [ -n "$out" ] && echo detected || echo missed
}

prepare_stow() {
  mkdir -p "$1/bench"
  cp -R "$WORK/fixture" "$1/bench/.bench"
}
apply_stow() { "$BIN" --no-folding --dir "$1" --target "$2" bench >/dev/null 2>&1; }
# stow has no status command. A dry run reports a conflict when a link
# was replaced by a regular file.
detect_stow() {
  if "$BIN" --no --no-folding --dir "$1" --target "$2" bench >/dev/null 2>&1; then echo missed; else echo detected; fi
}

prepare_yadm() {
  local wt="$1/worktree"
  mkdir -p "$wt"
  cp -R "$WORK/fixture" "$wt/.bench"
  # A private git identity and no hooks: the fixture repo is throwaway.
  local g=(git -c core.hooksPath=/dev/null -c user.name=bench -c user.email=bench@example.com)
  "${g[@]}" -C "$wt" init -q
  "${g[@]}" -C "$wt" add .bench
  "${g[@]}" -C "$wt" commit -qm "chore: benchmark fixture"
  "${g[@]}" clone -q --bare "$wt" "$1/remote.git"
}
apply_yadm() {
  if [ -d "$2/.local/share/yadm/repo.git" ]; then
    (cd "$2" && in_home "$2" "$BIN" checkout -- "$2/.bench" >/dev/null 2>&1)
  else
    (cd "$2" && in_home "$2" "$BIN" clone --no-bootstrap "$1/remote.git" >/dev/null 2>&1)
  fi
}
detect_yadm() {
  local out
  out="$(cd "$2" && in_home "$2" "$BIN" status --porcelain 2>/dev/null || true)"
  [ -n "$out" ] && echo detected || echo missed
}

prepare_dotbot() {
  local rel
  mkdir -p "$1"
  cp -R "$WORK/fixture" "$1/bench"
  {
    echo "- defaults:"
    echo "    link:"
    echo "      create: true"
    echo "- link:"
    while IFS= read -r rel; do
      printf '    ~/%s: bench/%s\n' "$rel" "${rel#.bench/}"
    done < "$WORK/files.txt"
  } > "$1/install.conf.yaml"
}
apply_dotbot() { in_home "$2" "$BIN" --quiet -d "$1" -c "$1/install.conf.yaml" >/dev/null 2>&1; }
# dotbot has no status command. A re-run refuses to replace a regular
# file and exits non-zero, which is the only drift signal it gives.
detect_dotbot() {
  if in_home "$2" "$BIN" --quiet -d "$1" -c "$1/install.conf.yaml" >/dev/null 2>&1; then echo missed; else echo detected; fi
}

drift_method() {
  case "$1" in
    dotfiles) echo "dotfiles diff (chezmoi diff)" ;;
    chezmoi) echo "chezmoi status" ;;
    yadm) echo "yadm status" ;;
    stow) echo "stow --no dry run (conflict)" ;;
    dotbot) echo "re-run install (refuses to overwrite)" ;;
  esac
}

# ── Measure one tool ─────────────────────────────────────────────────
blocked_row() {
  jq -n --arg tool "$1" --arg reason "$2" --argjson steps "$(manual_steps "$1")" --arg mode "$(deploy_mode "$1")" \
    '{tool: $tool, status: "blocked", reason: $reason, deploy_mode: $mode,
      metrics: {cold_apply_ms: null, noop_reapply_ms: null, drift_detect_ms: null,
                drift_detected: null, reproducibility_pct: null, manual_bootstrap_steps: $steps}}'
}

measure_tool() {
  local tool="$1" fn="${1//-/_}" src cold=() noop=() drift=() h h2 t0 t1 detected="" repro
  BIN="$("resolve_$fn")" || { blocked_row "$tool" "$BIN"; return 0; }
  src="$WORK/src-$fn"
  "prepare_$fn" "$src"
  for _ in $(seq 1 "$REPS"); do
    h="$(new_home)"
    t0="$(now_ms)"; "apply_$fn" "$src" "$h" || { blocked_row "$tool" "apply failed on the workload"; return 0; }; t1="$(now_ms)"
    cold+=("$((t1 - t0))")
    t0="$(now_ms)"; "apply_$fn" "$src" "$h" || { blocked_row "$tool" "re-apply failed on the workload"; return 0; }; t1="$(now_ms)"
    noop+=("$((t1 - t0))")
    inject_drift "$h"
    t0="$(now_ms)"; detected="$("detect_$fn" "$src" "$h")"; t1="$(now_ms)"
    drift+=("$((t1 - t0))")
  done
  # Reproducibility: two fresh homes, every file must match the fixture.
  h="$(new_home)"; h2="$(new_home)"
  "apply_$fn" "$src" "$h"; "apply_$fn" "$src" "$h2"
  repro="$(awk -v a="$(match_pct "$h")" -v b="$(match_pct "$h2")" 'BEGIN { print (a < b ? a : b) }')"
  jq -n --arg tool "$tool" --arg mode "$(deploy_mode "$tool")" --arg method "$(drift_method "$tool")" \
    --argjson cold "$(printf '%s\n' "${cold[@]}" | median)" \
    --argjson noop "$(printf '%s\n' "${noop[@]}" | median)" \
    --argjson drift "$(printf '%s\n' "${drift[@]}" | median)" \
    --argjson detected "$([ "$detected" = detected ] && echo true || echo false)" \
    --argjson repro "$repro" --argjson steps "$(manual_steps "$tool")" \
    '{tool: $tool, status: "ok", deploy_mode: $mode, drift_method: $method,
      metrics: {cold_apply_ms: $cold, noop_reapply_ms: $noop,
                drift_detect_ms: (if $detected then $drift else null end),
                drift_detected: $detected, reproducibility_pct: $repro,
                manual_bootstrap_steps: $steps}}'
}

# ── Main ─────────────────────────────────────────────────────────────
build_fixture
rows="$WORK/rows.jsonl"
: > "$rows"
for tool in $TOOLS; do
  case " $ALL_TOOLS " in *" $tool "*) ;; *) echo "unknown tool: $tool" >&2; exit 2 ;; esac
  measure_tool "$tool" >> "$rows"
done

# North star: on how many metrics dotfiles beats the best competitor that
# ran. Lower is better for times and steps; higher for reproducibility.
scorecard="$(jq -s \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg host "$(uname -s)-$(uname -m)" \
  --argjson files "$FILES" --argjson reps "$REPS" '
  def lower_better: ["cold_apply_ms", "noop_reapply_ms", "drift_detect_ms", "manual_bootstrap_steps"];
  (map(select(.tool == "dotfiles")) | first) as $d
  | map(select(.tool != "dotfiles")) as $c
  | ($c | map(select(.status == "ok"))) as $ran
  | {
      generatedAt: $generatedAt,
      host: $host,
      workload: {files: $files, reps: $reps, statistic: "median"},
      dotfiles: $d,
      competitors: $c,
      blocked: ([$d] + $c | map(select(. != null and .status == "blocked") | {tool, reason})),
      north_star: (
        if $d == null or $d.status != "ok" or ($ran | length) == 0 then null
        else
          [ ($d.metrics | keys[]) as $k
            | select($k != "drift_detected")
            | ($d.metrics[$k]) as $mine
            | ($ran | map(.metrics[$k]) | map(select(. != null))) as $theirs
            | select($mine != null and ($theirs | length) > 0)
            | (any(lower_better[]; . == $k)) as $low
            | (if $low then ($theirs | min) else ($theirs | max) end) as $best
            | {metric: $k, dotfiles: $mine, best_competitor: $best,
               beats: (if $low then $mine < $best else $mine > $best end)}
          ] as $cmp
          | {metrics_beaten: ($cmp | map(select(.beats)) | length),
             metrics_compared: ($cmp | length),
             detail: $cmp}
        end)
    }' "$rows")"

if [ "$OUTPUT" = json ]; then
  printf '%s\n' "$scorecard"
  exit 0
fi

printf '%s\n' "$scorecard" | jq -r '
  ["tool", "status", "cold_ms", "noop_ms", "drift_ms", "repro_%", "steps"],
  (([.dotfiles] + .competitors)[] | select(. != null)
    | [.tool, .status, (.metrics.cold_apply_ms // "-"), (.metrics.noop_reapply_ms // "-"),
       (.metrics.drift_detect_ms // "-"), (.metrics.reproducibility_pct // "-"),
       (.metrics.manual_bootstrap_steps // "-")])
  | @tsv' | column -t -s "$(printf '\t')"
printf '%s\n' "$scorecard" | jq -r '
  (.blocked[] | "blocked: \(.tool) — \(.reason)"),
  (if .north_star then "north star: dotfiles beats the best competitor on \(.north_star.metrics_beaten)/\(.north_star.metrics_compared) metrics" else "north star: not available" end)'
