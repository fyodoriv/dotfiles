#!/usr/bin/env bats
# Pin user-story docs against silent drift from the codebase.
#
# `docs/user-stories/*.md` are the public-facing entry points for new adopters.
# When the code grows a new module, ships a new `morning` step, or renames a
# command, the user stories silently fall out of sync with reality and undersell
# (or oversell) what the dotfiles actually do. These tests fail loudly in CI so
# the fix lands in the same commit as the behavior change.
#
# Closes harden-story-05-module-counts, harden-story-02-morning-step-count,
#        harden-story-01-prompt-count, harden-story-03-add-mode-claim,
#        harden-story-06-audit-report-output-format,
#        harden-story-01-launchagent-count,
#        harden-story-06-max-deletes-threshold,
#        harden-story-06-protected-dirs,
#        harden-story-02-launchagent-table,
#        harden-story-08-task-estimates,
#        harden-story-04-profile-controls,
#        harden-story-03-check-functions,
#        harden-story-05-sync-interval,
#        harden-story-07-new-project-templates,
#        harden-story-06-git-safe-examples,
#        harden-story-06-forbidden-files,
#        harden-story-03-apply-hint,
#        harden-story-02-disk-threshold,
#        harden-story-02-launchagent-timings,
#        harden-story-07-review-prompt,
#        harden-story-07-pr-draft,
#        harden-story-02-doctor-example-counts,
#        harden-story-07-other-helpers-section-name,
#        harden-story-05-manual-commands-pin,
#        harden-story-06-secret-scan-patterns.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
STORY_01="$REPO_ROOT/docs/user-stories/01-fully-configured-mac.md"
STORY_02="$REPO_ROOT/docs/user-stories/02-start-day-ready-to-code.md"
STORY_03="$REPO_ROOT/docs/user-stories/03-add-and-maintain-config.md"
STORY_04="$REPO_ROOT/docs/user-stories/04-switch-profiles-and-customize.md"
STORY_05="$REPO_ROOT/docs/user-stories/05-config-heals-itself.md"
STORY_06="$REPO_ROOT/docs/user-stories/06-stay-safe-from-damage.md"
STORY_07="$REPO_ROOT/docs/user-stories/07-git-workflow-helpers.md"
STORY_08="$REPO_ROOT/docs/user-stories/08-time-saved-by-automation.md"
MORNING="$REPO_ROOT/bin/morning"

@test "story 05 does not claim a module count" {
  # Module counts go stale; `ls modules` is the source of truth.
  if grep -nE '[0-9]+\+? modules' "$STORY_05"; then
    echo "story 05 claims a module count — describe the modules instead"
    return 1
  fi
}

@test "story 02 step count matches bin/morning numbered step comments" {
  # Authoritative step count: `# 1.`, `# 2.`, … comments at column 0 in bin/morning.
  local script_steps
  script_steps=$(grep -cE '^# [0-9]+\. ' "$MORNING" | tr -d ' ')
  [ "$script_steps" -gt 0 ] || { echo "no '# N.' step comments in $MORNING"; return 1; }

  # Story step count: numbered list items inside the "Runs these steps in sequence:"
  # block. We pick lines that match `^[0-9]+\. \*\*` to avoid counting unrelated
  # numerals elsewhere in the doc (e.g. "8:30 AM" in the LaunchAgent table).
  local doc_steps
  doc_steps=$(grep -cE '^[0-9]+\. \*\*' "$STORY_02" | tr -d ' ')
  [ "$script_steps" = "$doc_steps" ] || {
    echo "step-count drift: bin/morning has $script_steps numbered steps but $STORY_02 lists $doc_steps"
    echo "fix: update the numbered list in $STORY_02 to match bin/morning"
    return 1
  }
}

@test "story 02 LaunchAgent timings match plist StartInterval for periodic agents" {
  # Story 02's LaunchAgent table maps each plist to a frequency string.
  # For agents that fire on a fixed StartInterval (in seconds), the
  # 'Every Ns' / 'Every N min' phrasing must follow the plist value.
  # Drift: tweaking StartInterval (or rewording the doc) silently
  # misleads adopters about how often each agent runs.
  #
  # We pin the periodic agents (fixed-interval StartInterval) here.
  # CalendarInterval-driven agents ('Weekly', 'Daily', '8:30 AM') are
  # less precise and intentionally left to the existing 'every plist'
  # pin. The sync agent is pinned by 'story 05 sync-interval' above.

  declare -A periodic_agents=(
    [cursor-priority]="60"      # 60 seconds
    [network-resilience]="300"  # 5 minutes
    [chrome-profile]="3600"     # 1 hour — Work profile + ChromeWork default browser
  )

  local short expected_seconds plist actual_seconds
  for short in "${!periodic_agents[@]}"; do
    expected_seconds="${periodic_agents[$short]}"
    plist="$REPO_ROOT/launchagents/com.dotfiles.${short}.plist.tmpl"
    [ -f "$plist" ] || plist="$REPO_ROOT/launchagents/com.dotfiles.${short}.plist"
    [ -f "$plist" ] || {
      echo "missing plist for '$short' (expected $expected_seconds s)"
      return 1
    }

    # Extract <integer>N</integer> following StartInterval. Two forms
    # supported: a plain '<integer>N</integer>' line, or a chezmoi-
    # templated form '<integer>{{ if ... }}...{{ else }}N{{ end }}
    # </integer>' where the doc tracks the fallback. Stop at the next
    # <key> so a later <integer>...</integer> (e.g. ThrottleInterval)
    # can't be misread as the StartInterval value.
    actual_seconds=$(awk '
      /<key>StartInterval<\/key>/ { want = 1; next }
      want && /<key>/ { exit }
      want {
        if (match($0, /<integer>[0-9]+<\/integer>/)) {
          tok = substr($0, RSTART, RLENGTH); gsub(/<\/?integer>/, "", tok)
          print tok; exit
        }
        if (match($0, /\{\{[[:space:]]*else[[:space:]]*\}\}[[:space:]]*[0-9]+[[:space:]]*\{\{[[:space:]]*end/)) {
          tok = substr($0, RSTART, RLENGTH)
          sub(/^\{\{[[:space:]]*else[[:space:]]*\}\}[[:space:]]*/, "", tok)
          sub(/[[:space:]]*\{\{[[:space:]]*end.*$/, "", tok)
          print tok; exit
        }
      }
    ' "$plist")
    [ -n "$actual_seconds" ] || {
      echo "could not extract StartInterval from $plist"
      return 1
    }
    [ "$actual_seconds" = "$expected_seconds" ] || {
      echo "drift: $plist StartInterval=$actual_seconds but pin expects $expected_seconds — adjust the test or the plist"
      return 1
    }

    # Doc check: row for $short must mention the documented frequency.
    # 60s → 'Every 60s'; 300s → 'Every 5 min'; 3600s → 'every 1 hour'.
    local doc_pattern row
    case "$expected_seconds" in
      60) doc_pattern='Every 60s' ;;
      300) doc_pattern='Every 5 min' ;;
      3600) doc_pattern='every 1 hour' ;;
      *)
        echo "no doc_pattern wired for ${expected_seconds}s — extend the test"
        return 1
        ;;
    esac
    row=$(grep -E "^\| \`${short}\` \| .* \| .*${doc_pattern}.* \|$" "$STORY_02" || true)
    [ -n "$row" ] || {
      echo "story 02 row for '$short' must contain '$doc_pattern' (StartInterval=${expected_seconds}s)"
      echo "current row: $(grep -E "^\| \`${short}\` \|" "$STORY_02" || echo '<none>')"
      return 1
    }
  done
}

@test "story 02 disk-space threshold matches bin/morning free_gb check" {
  # Story 02 advertises 'warns if below 20GB free' for the disk-space
  # step. The authoritative number lives in bin/morning as
  # `[ "\$free_gb" -lt 20 ]`. Pin both sides so changing the threshold
  # without updating the doc fails CI.
  local code_threshold doc_threshold
  code_threshold=$(grep -oE '\[ "\$free_gb" -lt [0-9]+ \]' "$MORNING" | grep -oE '[0-9]+' | head -1)
  [ -n "$code_threshold" ] || {
    echo "could not extract '\$free_gb -lt N' threshold from $MORNING"
    return 1
  }

  doc_threshold=$(grep -oE 'below [0-9]+GB free' "$STORY_02" | grep -oE '[0-9]+' | head -1)
  [ -n "$doc_threshold" ] || {
    echo "story 02 must mention 'warns if below <N>GB free' in the disk-space step"
    return 1
  }

  [ "$code_threshold" = "$doc_threshold" ] || {
    echo "drift: bin/morning trips at <${code_threshold}GB but story 02 says 'below ${doc_threshold}GB free'"
    echo "fix: align $STORY_02 with $MORNING (or vice versa)"
    return 1
  }
}

@test "story 02 LaunchAgent table covers every plist in launchagents/" {
  # Story 02's "What Runs in the Background" table maps each LaunchAgent
  # short name to its description and frequency. Adding a new plist to
  # `launchagents/` without updating the table silently undersells the
  # install; removing one without updating the table leaves a stale row.
  # Pin both directions: every plist must have a matching row, and every
  # row must point at a real plist.
  local short plist retired
  # Retired templates stay in the repo but are never installed.
  retired=$(sed -n 's/^for retired_label in \(.*\); do$/ \1 /p' \
    "$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")
  [ -n "$retired" ] || { echo "could not read retired_label list from run_onchange_launchagents.sh.tmpl"; return 1; }
  for plist in "$REPO_ROOT"/launchagents/com.dotfiles.*.plist*; do
    [ -f "$plist" ] || continue
    short=$(basename "$plist" | sed -E 's/^com\.dotfiles\.//; s/\.plist(\.tmpl)?$//')
    case "$retired" in *" com.dotfiles.$short "*) continue ;; esac
    grep -qE "^\| \`${short}\` " "$STORY_02" || {
      echo "story 02 LaunchAgent table missing row for '$short'"
      echo "fix: add a '| \`${short}\` | <description> | <frequency> |' row to $STORY_02"
      return 1
    }
  done

  # Converse: every backticked label in the table must be a real plist.
  while IFS= read -r short; do
    [ -f "$REPO_ROOT/launchagents/com.dotfiles.${short}.plist" ] || \
    [ -f "$REPO_ROOT/launchagents/com.dotfiles.${short}.plist.tmpl" ] || {
      echo "story 02 LaunchAgent table references '$short' but no com.dotfiles.${short}.plist[.tmpl] exists"
      echo "fix: drop the row from $STORY_02 or add the plist back to launchagents/"
      return 1
    }
  done < <(awk '/^\| `[a-z0-9-]+` \| .* \| .* \|$/ { gsub(/^\| `|` .*$/, ""); print }' "$STORY_02")
}

@test "story 02 step labels stay in sync with bin/morning step comments" {
  # Pin one stable keyword per step so renaming a step in bin/morning forces a
  # matching rename in the doc. Keywords are case-sensitive and must appear on
  # the matching numbered line of $STORY_02.
  declare -a keywords=(
    "Pull"     # 1. Pull latest on all active repos
    "doctor"   # 2. Run doctor (report only)
    "notes"    # 3. Show today's notes if any
    "alendar"  # 4. Show calendar/meetings reminder (works for "Calendar" too)
    "Disk"     # 5. Disk space check
    "macOS"    # 6. Pending macOS / Xcode updates
    "CPU"      # 7. Show top CPU consumers
    "Time"     # 8. Time saved summary
  )

  local script_steps
  script_steps=$(grep -cE '^# [0-9]+\. ' "$MORNING" | tr -d ' ')
  [ "$script_steps" = "${#keywords[@]}" ] || {
    echo "test out of date: bin/morning has $script_steps steps but the keyword pin covers ${#keywords[@]}"
    echo "fix: update the keywords[] array in tests/user-stories.bats and the doc"
    return 1
  }

  local i kw line
  for i in "${!keywords[@]}"; do
    kw="${keywords[$i]}"
    # Match the doc's "N. **Label**" line (1-indexed step number).
    line=$(grep -E "^$((i + 1))\. \*\*" "$STORY_02" | head -1)
    [ -n "$line" ] || { echo "missing step $((i + 1)) entry in $STORY_02"; return 1; }
    case "$line" in
      *"$kw"*) ;;
      *)
        echo "step $((i + 1)) drifted: expected keyword '$kw' in '$line'"
        echo "fix: update $STORY_02 step $((i + 1)) or the keyword pin"
        return 1
        ;;
    esac
  done
}

@test "story 01 does not claim a precise prompt count" {
  # `chezmoi init` prompts for many more values than just two — see
  # `.chezmoi.yaml.tmpl`. Story 01 used to say "answer two prompts" and
  # "Prompts: profile and enterprise. That's it.", which is misleading.
  # The doc must not reintroduce a precise prompt count for any small
  # number, in either word ("two", "three", …) or numeric ("2", "3", …)
  # form. Bigger counts are unstable too — the README configuration
  # table is the authoritative list.
  local pattern='\b(two|three|four|five|six|seven|eight|nine|ten|2|3|4|5|6|7|8|9|10)\s+prompts?\b'
  if grep -iE "$pattern" "$STORY_01"; then
    echo "story 01 reintroduced a precise prompt count — link to the README configuration table instead"
    return 1
  fi
}

@test "story 01 references the README configuration table" {
  # The doc must point readers at the README configuration table for the
  # full prompt list and defaults. We accept any of the relative-link
  # variants that resolve from `docs/user-stories/01-fully-configured-mac.md`.
  grep -E '\[.+\]\(\.\./\.\./README\.md#configuration\)' "$STORY_01" >/dev/null || {
    echo "story 01 must link to ../../README.md#configuration"
    return 1
  }
}

@test "story 01 does not claim a precise LaunchAgent count" {
  # The LaunchAgent count varies by profile (core gates several plists) and
  # grows whenever a new agent ships. Story 01 used to read "9 LaunchAgents"
  # against an actual count of 15 in launchagents/, silently underselling
  # the install. The doc must use either "all LaunchAgents" or the "N+"
  # approximate form (e.g. "15+ LaunchAgents", matching story 02) so the
  # count stays correct without maintenance per the global counter
  # precision rule.
  #
  # The regex matches digits followed directly by whitespace and
  # "LaunchAgent(s)". The "15+ LaunchAgents" form passes because the digits
  # are followed by `+`, not whitespace.
  if grep -nE '\b[0-9]+ +LaunchAgents?\b' "$STORY_01"; then
    echo "story 01 reintroduced a precise N-LaunchAgent count"
    echo "fix: use 'all LaunchAgents' or '15+ LaunchAgents' (matches story 02)"
    return 1
  fi
}

@test "story 04 profile-controls list covers every profile-gated surface" {
  # Story 04's "Profile controls X things" section enumerates each
  # surface that varies by profile. The authoritative surfaces are the
  # files that branch on `{{ if eq .profile "full" }}` (or check the
  # PROFILE shell var in the launchagents lifecycle script). Drift
  # signal: a new lifecycle script adds profile gating but the doc
  # forgets to mention it (or the inverse: doc lists a surface that
  # doesn't actually gate).
  #
  # The test maps each known gating surface to a keyword that must
  # appear as a bold bullet (`- **<keyword>** —`) in story 04. Adding
  # a fifth gating surface in the future will fail this test until the
  # story 04 list (and the keyword pin below) catches up.
  declare -A surface_keyword=(
    ["$REPO_ROOT/.chezmoiignore"]="File deployment"
    ["$REPO_ROOT/.chezmoiscripts/run_onchange_brew.sh.tmpl"]="Homebrew packages"
    ["$REPO_ROOT/.chezmoiscripts/run_onchange_macos.sh.tmpl"]="macOS defaults"
    ["$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"]="LaunchAgents"
  )

  local file kw
  for file in "${!surface_keyword[@]}"; do
    [ -f "$file" ] || {
      echo "expected profile-gating surface missing: $file"
      return 1
    }
    # The file must actually reference .profile (templating) or PROFILE
    # (shell var in the launchagents script) — otherwise the keyword pin
    # is wrong and should be removed.
    grep -qE '\.profile|\$PROFILE|"\$PROFILE"' "$file" || {
      echo "$file no longer references .profile / \$PROFILE — drop the keyword pin from this test"
      return 1
    }

    kw="${surface_keyword[$file]}"
    grep -qE "^- \*\*${kw}\*\* — " "$STORY_04" || {
      echo "story 04 'Profile controls' list missing bullet for '$kw' (gates: $file)"
      echo "fix: add '- **${kw}** — <description>' to $STORY_04"
      return 1
    }
  done

  # Pin the headline count too — when the bullet list grows, the
  # introductory "Profile controls N things" line must follow.
  local listed_count headline_count
  listed_count=$(awk '
    /^Profile controls / { in_list = 1; count = 0; next }
    in_list && /^- \*\*/ { count++; next }
    in_list && /^$/ && count > 0 { print count; exit }
    in_list && /^[^-]/ && count > 0 { print count; exit }
  ' "$STORY_04")
  [ -n "$listed_count" ] || {
    echo "could not parse the 'Profile controls' bullet list in $STORY_04"
    return 1
  }

  declare -A num_word=(
    [1]="one" [2]="two" [3]="three" [4]="four" [5]="five"
    [6]="six" [7]="seven" [8]="eight" [9]="nine" [10]="ten"
  )
  local expected_word="${num_word[$listed_count]:-}"
  [ -n "$expected_word" ] || {
    echo "story 04 lists $listed_count surfaces but the test only knows words for 1..10"
    return 1
  }

  headline_count=$(grep -oE 'Profile controls [a-z]+ things?' "$STORY_04" | head -1 | awk '{print $3}')
  [ "$headline_count" = "$expected_word" ] || {
    echo "headline drift: story 04 says 'Profile controls $headline_count things' but the bullet list has $listed_count items ($expected_word)"
    echo "fix: align the 'Profile controls N things' line with the bullet list"
    return 1
  }
}

@test "story 03 does not claim 'Auto-detects mode' for dotfiles add" {
  # `bin/dotfiles-add` does not auto-detect symlink-vs-copy. Default is
  # symlink, `--copy` toggles to copy. The *module* is auto-detected from
  # the path. The misleading "Auto-detects mode" wording sat at the top
  # of story 03 and oversold the magic to new adopters.
  if grep -iE 'auto[- ]?detects? mode' "$STORY_03"; then
    echo "story 03 reintroduced the misleading 'auto-detects mode' phrase"
    echo "fix: dotfiles-add defaults to symlink mode and only switches to copy when --copy is passed"
    return 1
  fi
}

@test "story 03 'add'/'brew-add' description matches the print-hint behavior" {
  # bin/dotfiles-add and bin/dotfiles-brew-add do NOT auto-run apply;
  # they print 'Next: dotfiles apply' as a hint and let the user run
  # apply themselves. Story 03 used to claim 'and runs apply' in both
  # descriptions — misleading users into expecting automatic deploy.
  # Pin the doc to the actual hint behavior in both directions.
  for cmd in dotfiles-add dotfiles-brew-add; do
    grep -qE 'echo "Next: dotfiles apply"' "$REPO_ROOT/bin/$cmd" || {
      echo "bin/$cmd no longer prints 'Next: dotfiles apply' hint — adjust this pin if intentional"
      return 1
    }
  done

  # The doc must NOT claim 'runs apply' / 'and applies' for either
  # command. (We use a generous boundary to allow phrasings like
  # 'run that yourself to deploy'.)
  if grep -nE '(runs apply|and applies( automatically)?\b)' "$STORY_03"; then
    echo "story 03 reintroduced the misleading 'runs apply' / 'and applies' claim"
    echo "fix: bin/dotfiles-{add,brew-add} only PRINT 'Next: dotfiles apply' — they do not auto-run"
    return 1
  fi

  # The doc must mention the deferred-apply hint for both commands so
  # users know to run apply themselves.
  grep -qE 'Next: `?dotfiles apply' "$STORY_03" || {
    echo "story 03 must mention 'Next: dotfiles apply' as the post-add follow-up step"
    return 1
  }
}

@test "story 03 check-functions table matches dotfiles-doctor public API" {
  # Story 03's "Available check functions" table is the contract module
  # authors read when writing a new doctor. It must list every public
  # `check*` function defined in `bin/dotfiles-doctor`, and must not
  # claim functions that don't exist. Drift signal: a new check helper
  # ships (e.g. for a new check class) but the table forgets to mention
  # it, leaving module authors guessing.
  local doctor_bin="$REPO_ROOT/bin/dotfiles-doctor"
  local fn
  local public_fns=()

  # Extract every top-level `check*()` function definition.
  while IFS= read -r fn; do
    public_fns+=("$fn")
    grep -qE "^\| \`${fn}\` \| " "$STORY_03" || {
      echo "story 03 'Available check functions' table missing row for '$fn'"
      echo "fix: add '| \`${fn}\` | <description> |' to $STORY_03"
      return 1
    }
  done < <(grep -oE '^check[a-z_]*\(\)' "$doctor_bin" | sed 's/()$//')

  [ "${#public_fns[@]}" -gt 0 ] || {
    echo "extracted no check* functions from $doctor_bin — parser regression?"
    return 1
  }

  # Converse: every backticked check* row in the table must point at a
  # real function in dotfiles-doctor.
  local doc_fn
  while IFS= read -r doc_fn; do
    case " ${public_fns[*]} " in
      *" $doc_fn "*) ;;
      *)
        echo "story 03 lists '$doc_fn' but $doctor_bin defines no such function"
        echo "fix: drop the row from $STORY_03 or add the function to dotfiles-doctor"
        return 1
        ;;
    esac
  done < <(awk '/^\| `check[a-z_]*` \| / { gsub(/^\| `|` \|.*$/, ""); print }' "$STORY_03")
}

@test "story 03 explains module auto-detection and --copy as the mode toggle" {
  # Positive pin: the doc must (a) note that --copy switches to copy mode
  # and (b) keep the accurate "auto-detects the doctor module" claim, so
  # a future rewrite can't quietly drop both halves of the contract.
  grep -F -- '--copy' "$STORY_03" >/dev/null || {
    echo "story 03 must reference the --copy flag as the mode toggle"
    return 1
  }
  grep -iE 'auto[- ]?detects? the (doctor )?module' "$STORY_03" >/dev/null || {
    echo "story 03 must explain that the module is auto-detected from the path"
    return 1
  }
}

@test "user-story bash blocks reference only existing commands" {
  # Authoritative source of "what dotfiles ships": every fenced ```bash
  # block in docs/user-stories/*.md should run only commands that resolve
  # to a backing binary in bin/ (a `bin/<name>` file or a
  # `bin/dotfiles-<sub>` for the `dotfiles <sub>` form), or to an external
  # tool we explicitly know is not ours to ship (chezmoi, git, brew, …).
  #
  # This is the cheapest insurance against the drift class that produced
  # the harden-story-* tasks. Renaming `bin/morning` to `bin/morning2`
  # without updating the user-story would now fire this assertion, and
  # likewise for any `dotfiles <sub>` rename.

  # External tools we don't ship — these are upstream dependencies and
  # can't be expected to live in `bin/`.
  local ext_tools_csv=" chezmoi git brew ollama launchctl npm yarn pnpm node python3 docker make ssh ssh-keygen age sudo cat echo cd ls cp mv rm mkdir chmod chown sed awk grep find date open which type test bash sh zsh "

  local doc
  declare -A documented=()
  for doc in "$REPO_ROOT"/docs/user-stories/*.md; do
    [[ "$(basename "$doc")" == "README.md" ]] && continue
    local in_block=0
    local heredoc_term=""
    while IFS= read -r line; do
      case "$line" in
        '```bash'*) in_block=1; heredoc_term=""; continue ;;
        '```'*) in_block=0; heredoc_term=""; continue ;;
      esac
      [ "$in_block" -eq 1 ] || continue

      # Strip leading whitespace.
      local trimmed="${line#"${line%%[![:space:]]*}"}"

      # Inside a heredoc body — skip until the terminator on its own line.
      if [ -n "$heredoc_term" ]; then
        [ "$trimmed" = "$heredoc_term" ] && heredoc_term=""
        continue
      fi

      [ -z "$trimmed" ] && continue
      [[ "$trimmed" == \#* ]] && continue

      # Detect a heredoc opener (`<< WORD` or `<< 'WORD'`) on this line so the
      # body that follows is skipped.
      if [[ "$line" =~ \<\<-?[[:space:]]*\'?([A-Za-z_][A-Za-z0-9_]*)\'?[[:space:]]*$ ]]; then
        heredoc_term="${BASH_REMATCH[1]}"
      fi

      # First whitespace-separated token, with non-identifier suffix stripped
      # ("[user]" → ""; "dotfiles" → "dotfiles").
      local first="${trimmed%% *}"
      first="${first%%[!a-zA-Z0-9_-]*}"
      [ -n "$first" ] || continue

      if [ "$first" = "dotfiles" ]; then
        local rest="${trimmed#dotfiles}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        local sub="${rest%% *}"
        sub="${sub%%[!a-zA-Z0-9_-]*}"
        # Skip option-only invocations like `dotfiles --help`.
        [ -n "$sub" ] || continue
        [[ "$sub" == --* || "$sub" == -* ]] && continue
        documented["dotfiles $sub"]=1
      else
        # External tools are upstream dependencies — skip them.
        case "$ext_tools_csv" in *" $first "*) continue ;; esac
        documented["$first"]=1
      fi
    done < "$doc"
  done

  [ "${#documented[@]}" -gt 0 ] || { echo "no commands extracted from user-stories"; return 1; }

  # Each documented command must have a backing binary, and `--help` must
  # exit 0. For `dotfiles <sub>` we also require the wrapper bin/dotfiles
  # has a case branch for `<sub>` — and if the branch routes to
  # `bin/dotfiles-<sub>`, that file must exist.
  local key sub cmd wrapper="$REPO_ROOT/bin/dotfiles"
  local wrapper_src
  wrapper_src=$(<"$wrapper")
  for key in "${!documented[@]}"; do
    if [[ "$key" == "dotfiles "* ]]; then
      sub="${key#dotfiles }"
      cmd="dotfiles-$sub"

      # The wrapper must have a `case` branch for $sub. The branch is
      # either a passthrough (chezmoi/git) or routes to bin/$cmd.
      printf '%s\n' "$wrapper_src" | grep -qE "^[[:space:]]+${sub})\s*$" || {
        echo "user-stories document 'dotfiles $sub' but bin/dotfiles has no case branch for '$sub'"
        return 1
      }

      # If the branch execs bin/$cmd, that file must exist.
      if printf '%s\n' "$wrapper_src" | grep -qF "bin/$cmd" ; then
        [ -x "$REPO_ROOT/bin/$cmd" ] || {
          echo "user-stories document 'dotfiles $sub' and bin/dotfiles routes to bin/$cmd but bin/$cmd is missing"
          return 1
        }
        run "$REPO_ROOT/bin/$cmd" --help
        [ "$status" -eq 0 ] || {
          echo "$cmd --help exited $status (expected 0)"
          printf '%s\n' "$output"
          return 1
        }
      fi
    else
      [ -x "$REPO_ROOT/bin/$key" ] || {
        echo "user-stories document '$key' but bin/$key is missing"
        return 1
      }
      run "$REPO_ROOT/bin/$key" --help
      [ "$status" -eq 0 ] || {
        echo "$key --help exited $status (expected 0)"
        printf '%s\n' "$output"
        return 1
      }
    fi
  done
}

@test "story 06 does not call dotfiles audit --report 'machine-readable'" {
  # `bin/dotfiles-audit --report` produces a markdown bullet-list report,
  # not JSON/YAML/TSV. The user-story comment beside the command must
  # match the help text in `bin/dotfiles-audit:6` ("markdown report (for
  # sharing)"). Look for the misleading word near the audit command.
  if grep -nB1 -A2 'dotfiles audit' "$STORY_06" | grep -iE '\bmachine[- ]readable\b'; then
    echo "story 06 reintroduced 'machine-readable' near the dotfiles audit example"
    echo "fix: dotfiles-audit --report emits markdown bullets — say 'markdown report' instead"
    return 1
  fi
}

@test "dotfiles-audit --report output is markdown bullets (matches story 06)" {
  # Belt-and-braces: even if the user-story doc stays correct, this
  # asserts the actual binary still emits markdown bullets, so a
  # behavior change in dotfiles-audit forces the doc to follow.
  run "$REPO_ROOT/bin/dotfiles-audit" --report
  # `dotfiles-audit` exits non-zero when there are warn/fail findings;
  # both 0 and 1 are valid for a healthy report.
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || {
    echo "dotfiles-audit --report exited $status (expected 0 or 1)"
    printf '%s\n' "$output"
    return 1
  }
  # First non-empty line should start with `- ` (markdown bullet).
  local first
  first=$(printf '%s\n' "$output" | grep -m1 '^[^[:space:]]')
  case "$first" in
    "- "*) ;;
    *)
      echo "dotfiles-audit --report no longer starts with a markdown bullet"
      echo "first non-empty line: $first"
      echo "fix: keep the bullet-list format or update story 06 to match"
      return 1
      ;;
  esac
}

@test "story 06 deletion threshold matches MAX_DELETES in pre-commit" {
  # Story 06's "Excessive deletion guard" section quotes the threshold
  # at which the pre-commit hook blocks a commit ("If more than 50 files
  # are staged for deletion..."). The authoritative value lives in
  # `git-hooks/pre-commit` as `MAX_DELETES=<n>`; the doc must match.
  # Without this pin, bumping MAX_DELETES (or rewording the doc) silently
  # drifts the user-facing safety claim.
  local code_threshold doc_threshold
  code_threshold=$(grep -E '^MAX_DELETES=[0-9]+' "$REPO_ROOT/git-hooks/pre-commit" | grep -oE '[0-9]+' | head -1)
  [ -n "$code_threshold" ] || {
    echo "could not extract MAX_DELETES=<n> from git-hooks/pre-commit"
    return 1
  }

  doc_threshold=$(grep -oE 'more than [0-9]+ files? (are|is) staged for deletion' "$STORY_06" | grep -oE '[0-9]+' | head -1)
  [ -n "$doc_threshold" ] || {
    echo "story 06 must mention 'more than <n> files staged for deletion' in the deletion-guard section"
    return 1
  }

  [ "$code_threshold" = "$doc_threshold" ] || {
    echo "drift: pre-commit MAX_DELETES=$code_threshold but story 06 says 'more than $doc_threshold files'"
    echo "fix: align $STORY_06 with git-hooks/pre-commit (or vice versa)"
    return 1
  }
}

@test "story 06 protected directory list matches pre-commit PROTECTED_DIRS" {
  # Story 06 lists which directories the pre-commit hook protects from
  # accidental deletion (`bin/`, `tests/`, `lib/`, `modules/`, `skills/`).
  # The authoritative regex lives in `git-hooks/pre-commit` as
  # `PROTECTED_DIRS="^(...)"`. Drift in either direction (adding a new
  # dir to the regex without updating the doc, or vice versa) silently
  # breaks the user-facing safety contract.
  local regex code_dirs doc_dir
  regex=$(grep -E '^[[:space:]]*PROTECTED_DIRS=' "$REPO_ROOT/git-hooks/pre-commit" | head -1)
  [ -n "$regex" ] || {
    echo "could not find PROTECTED_DIRS=... in git-hooks/pre-commit"
    return 1
  }

  # Extract the directory list from the regex (e.g. "bin/|tests/|lib/").
  # The regex is wrapped in `^(...)` and quoted; pull out the inside.
  code_dirs=$(printf '%s\n' "$regex" | sed -n 's/.*"\^(\(.*\))".*/\1/p')
  [ -n "$code_dirs" ] || {
    echo "could not extract directory list from PROTECTED_DIRS regex: $regex"
    return 1
  }

  # Each `<dir>/` in the regex must appear as a backticked entry in the
  # protected-directory bullet list of story 06.
  local IFS='|'
  for doc_dir in $code_dirs; do
    grep -qE "^- \`${doc_dir}\` " "$STORY_06" || {
      echo "story 06 missing protected directory '$doc_dir' from the bullet list"
      echo "fix: add '- \`${doc_dir}\` — ...' to $STORY_06 or update PROTECTED_DIRS"
      return 1
    }
  done

  # And the converse: every backticked dir bullet under the protected-
  # dirs section must be in the regex.
  local doc_only
  while IFS= read -r doc_only; do
    case "|$code_dirs|" in
      *"|$doc_only|"*) ;;
      *)
        echo "story 06 lists '$doc_only' as protected but PROTECTED_DIRS regex does not include it"
        echo "fix: align $STORY_06 with git-hooks/pre-commit"
        return 1
        ;;
    esac
  done < <(grep -oE '^- `[a-z]+/`' "$STORY_06" | grep -oE '[a-z]+/')
}

@test "story 08 per-task estimate table matches lib/stats.sh _task_estimate" {
  # Story 08's "Per-Task Estimates" table must match the actual estimates
  # in `lib/stats.sh`'s `_task_estimate` case statement. Adding a new
  # tracked task to lib/stats.sh without updating story 08 silently
  # undersells the install; tweaking an estimate without updating the
  # doc gives users wrong expectations about time-saved tracking.
  #
  # Pin both directions:
  # 1. Every `<task>) echo <N> ;;` row in `_task_estimate` has a matching
  #    `| \`<task>\` | ... | <N>s ... |` row in story 08.
  # 2. Every `| \`<task>\` |` row in story 08 has a matching case branch.
  local stats_file="$REPO_ROOT/lib/stats.sh"
  local task estimate row code_tasks=()

  # Extract `<task>) echo <N> ;;` pairs from _task_estimate.
  while IFS=$'\t' read -r task estimate; do
    [ -n "$task" ] || continue
    code_tasks+=("$task")
    # The doc table is the public surface — it should mention this task.
    row=$(grep -E "^\| \`${task}\` \|" "$STORY_08" || true)
    [ -n "$row" ] || {
      echo "story 08 per-task estimate table missing row for '$task' (estimate ${estimate}s in lib/stats.sh)"
      echo "fix: add a '| \`${task}\` | <runs-via> | ${estimate}s / <unit> | <scaler> |' row to $STORY_08"
      return 1
    }
    # The third column ("Per-unit estimate") must start with the same
    # number of seconds as the code says. Format examples: "3s / cycle",
    # "0s (background)".
    local doc_estimate
    doc_estimate=$(printf '%s\n' "$row" | awk -F '\\|' '{print $4}' | grep -oE '[0-9]+s' | head -1 | tr -d 's')
    [ -n "$doc_estimate" ] || {
      echo "could not extract per-unit estimate from story 08 row for '$task': $row"
      return 1
    }
    [ "$doc_estimate" = "$estimate" ] || {
      echo "drift: lib/stats.sh sets $task=${estimate}s but story 08 says ${doc_estimate}s"
      echo "fix: align $STORY_08 with lib/stats.sh (or vice versa)"
      return 1
    }
  done < <(awk '
    /^_task_estimate\(\)/ { in_func = 1; next }
    in_func && /^\}/ { in_func = 0; next }
    in_func && /^[[:space:]]*[a-z][a-z0-9-]*\)[[:space:]]*echo [0-9]+/ {
      sub(/^[[:space:]]*/, "")
      task = $1; sub(/\).*/, "", task)
      estimate = $0; sub(/^.*echo /, "", estimate); sub(/[[:space:]]*;;.*$/, "", estimate)
      print task "\t" estimate
    }
  ' "$stats_file")

  [ "${#code_tasks[@]}" -gt 0 ] || {
    echo "extracted no tasks from $stats_file _task_estimate — parser regression?"
    return 1
  }

  # Converse: every backticked task in the table must be a real key in
  # _task_estimate, otherwise the doc claims tracking for a task that
  # doesn't exist in the catalog.
  local doc_task
  while IFS= read -r doc_task; do
    case " ${code_tasks[*]} " in
      *" $doc_task "*) ;;
      *)
        echo "story 08 lists '$doc_task' but lib/stats.sh _task_estimate has no case branch for it"
        echo "fix: drop the row from $STORY_08 or add a branch to _task_estimate"
        return 1
        ;;
    esac
  done < <(awk '/^\| `[a-z][a-z0-9-]*` \| / { gsub(/^\| `|` \|.*$/, ""); print }' "$STORY_08")
}

@test "story 06 forbidden file claims match pre-commit FORBIDDEN_PATTERNS" {
  # Story 06's secret-scanning bullet enumerates representative file
  # types the pre-commit hook blocks. The authoritative regex lives in
  # git-hooks/pre-commit as FORBIDDEN_PATTERNS. Drift signal: story 06
  # used to claim '.env' files cannot be committed when only
  # .env.local and .env.production are blocked, leading developers to
  # assume false safety on plain .env / .env.development files.
  #
  # Pin three categories:
  # 1. Story 06 must name at least one cert extension from the regex.
  # 2. Story 06 must name at least one SSH key pattern.
  # 3. Story 06 must name .env.local / .env.production specifically
  #    (not bare '.env').
  local hook="$REPO_ROOT/git-hooks/pre-commit"
  local pat
  pat=$(grep -E "^FORBIDDEN_PATTERNS=" "$hook" | head -1)
  [ -n "$pat" ] || { echo "could not find FORBIDDEN_PATTERNS in $hook"; return 1; }

  # Sanity-check that the regex still contains all three categories so
  # the test can't silently pass when the regex is gutted.
  printf '%s\n' "$pat" | grep -qE '\\\.pem' || {
    echo "$hook FORBIDDEN_PATTERNS no longer covers .pem — adjust this test if intentional"
    return 1
  }
  printf '%s\n' "$pat" | grep -qE 'id_rsa' || {
    echo "$hook FORBIDDEN_PATTERNS no longer covers id_rsa — adjust this test if intentional"
    return 1
  }
  printf '%s\n' "$pat" | grep -qE 'env\\\.local' || {
    echo "$hook FORBIDDEN_PATTERNS no longer covers .env.local — adjust this test if intentional"
    return 1
  }

  # Cert files: at least one of .pem / .key / .p12 / .pfx / .keystore / .jks
  grep -qE '`\.(pem|key|p12|pfx|keystore|jks)`' "$STORY_06" || {
    echo "story 06 must name at least one cert extension from FORBIDDEN_PATTERNS (\`.pem\`, \`.key\`, ...)"
    return 1
  }

  # SSH key file names
  grep -qE '`id_(rsa|ed25519|dsa)`' "$STORY_06" || {
    echo "story 06 must name at least one SSH key from FORBIDDEN_PATTERNS (\`id_rsa\`, \`id_ed25519\`, \`id_dsa\`)"
    return 1
  }

  # .env files: must use the *.local or *.production suffix specifically
  grep -qE '`\.env\.(local|production)`' "$STORY_06" || {
    echo "story 06 must name .env.local or .env.production specifically — bare '.env' is NOT blocked"
    return 1
  }
}

@test "story 06 git-safe examples match actual git-safe behavior" {
  # Story 06 advertises git-safe with example invocations annotated as
  # '# safe — passes through' or '# blocked — <reason>'. The historical
  # drift was advertising 'git-safe push -f' and 'git-safe reset HEAD'
  # as blocked when the script does NOT block either pattern (push has
  # no case branch; reset only blocks --hard). Pin every example by
  # actually running it in a multi-agent test repo and asserting the
  # exit code matches the comment.
  local git_safe="$REPO_ROOT/bin/git-safe"
  [ -x "$git_safe" ] || { echo "missing: $git_safe"; return 1; }

  # Set up a throwaway multi-agent repo (per git-safe.bats convention).
  local test_dir test_repo
  test_dir=$(mktemp -d)
  test_repo="$test_dir/repo"
  mkdir -p "$test_repo"
  git -C "$test_repo" init --quiet
  git -C "$test_repo" commit --no-verify --allow-empty -m "chore: init" --quiet
  mkdir -p "$test_repo/.orchestrator"  # multi-agent signal
  cd "$test_repo"

  cleanup_git_safe_repo() { rm -rf "$test_dir"; }

  # Extract every line from the git-safe bash block in story 06 of the
  # form: 'git-safe <args>  # safe|blocked — <reason>'.
  local count=0
  local in_block=0
  local line cmd_args expectation expected_status actual_status
  while IFS= read -r line; do
    case "$line" in
      '```bash'*) in_block=1; continue ;;
      '```'*) [ "$in_block" -eq 1 ] && in_block=0 ;;
    esac
    [ "$in_block" -eq 1 ] || continue

    # Match 'git-safe <args>    # <safe|blocked> — <reason>' (loose
    # whitespace and em-dash tolerated).
    [[ "$line" =~ ^git-safe[[:space:]]+(.+)[[:space:]]*#[[:space:]]*(safe|blocked)[[:space:]]*[—-] ]] || continue
    cmd_args="${BASH_REMATCH[1]}"
    expectation="${BASH_REMATCH[2]}"

    # Trim trailing whitespace from cmd_args (regex was greedy across
    # padding spaces).
    cmd_args="${cmd_args%"${cmd_args##*[![:space:]]}"}"

    case "$expectation" in
      safe) expected_status=0 ;;
      blocked) expected_status=1 ;;
    esac

    # Run via eval to expand the shlex-style arg list.
    set +e
    eval "\"$git_safe\" $cmd_args >/dev/null 2>&1"
    actual_status=$?
    set -e

    if [ "$actual_status" -ne "$expected_status" ]; then
      cleanup_git_safe_repo
      echo "story 06 example '$line' expected exit $expected_status (${expectation}) but git-safe exited $actual_status"
      echo "fix: align $STORY_06 with bin/git-safe (or vice versa)"
      return 1
    fi

    count=$((count + 1))
  done < "$STORY_06"

  cleanup_git_safe_repo

  [ "$count" -ge 2 ] || {
    echo "story 06 must include at least one 'safe' and one 'blocked' git-safe example (parsed $count)"
    return 1
  }
}

@test "story 07 pr description matches bin/pr's draft + browser-fallback behavior" {
  # Story 07 advertises 'pr' as the PR-creation helper. Its description
  # used to read 'opens the PR in your browser via gh' — but bin/pr
  # actually invokes 'gh pr create --draft' as the primary path, and
  # only falls back to 'gh pr view --web' when create fails (e.g. when
  # a PR for the branch already exists). Pin the doc to the actual
  # primary-create + fallback-open behavior.
  local pr="$REPO_ROOT/bin/pr"
  [ -x "$pr" ] || { echo "missing: $pr"; return 1; }

  # Sanity: bin/pr must still call 'gh pr create --draft' as the
  # primary action.
  grep -qE 'gh pr create .*--draft' "$pr" || {
    echo "bin/pr no longer runs 'gh pr create --draft' — adjust this pin if intentional"
    return 1
  }

  # Doc must call out 'draft PR' or '--draft' so adopters know the
  # primary action is creating a draft (not just opening browser).
  grep -qE '(draft PR|`--draft`|gh pr create.*--draft)' "$STORY_07" || {
    echo "story 07 must describe 'pr' as creating a draft PR (gh pr create --draft)"
    echo "fix: bin/pr's primary path is creating a draft, not opening the browser"
    return 1
  }
}

@test "story 07 review description matches bin/review interactive behavior" {
  # Story 07 advertises 'review <PR>' but its description used to claim
  # the script 'runs the test suite if a Makefile or package.json is
  # found' — implying automatic execution. bin/review actually prompts
  # 'Run tests? (y/n)' (and 'Open in browser? (y/n)') with a 30s
  # default-to-no timeout. Pin the doc to the actual interactive
  # behavior.
  local review="$REPO_ROOT/bin/review"
  [ -x "$review" ] || { echo "missing: $review"; return 1; }

  # Sanity: bin/review must still emit the interactive prompts.
  grep -qE 'Run tests\? \(y/n\)' "$review" || {
    echo "bin/review no longer prompts 'Run tests? (y/n)' — adjust this pin if intentional"
    return 1
  }
  grep -qE 'Open in browser\? \(y/n\)' "$review" || {
    echo "bin/review no longer prompts 'Open in browser? (y/n)' — adjust this pin if intentional"
    return 1
  }

  # Doc must mention the prompt-before-tests behavior, not claim
  # automatic test runs.
  grep -qE '(prompt|prompts) (to run|before running) (the )?test' "$STORY_07" || {
    echo "story 07 must describe 'review' as prompting before running tests"
    echo "fix: bin/review asks 'Run tests? (y/n)' — describe it as 'prompts to run tests'"
    return 1
  }

  # Negative pin: must not reintroduce the false 'runs the test suite'
  # auto-execution claim.
  if grep -nE 'runs the test suite' "$STORY_07"; then
    echo "story 07 reintroduced the misleading 'runs the test suite' auto-execution claim"
    return 1
  fi
}

@test "story 07 new-project signature and templates match bin/new-project" {
  # Story 07's 'Other Git Helpers' table advertises `new-project`. The
  # script requires TWO positional args (template + name) and supports
  # exactly four templates (react, node, lib, python). Story 07 used to
  # claim a single-arg signature ('new-project <name>'), and falsely
  # claimed the script creates a README. Pin the signature and template
  # list to the source of truth: bin/new-project.
  local new_project="$REPO_ROOT/bin/new-project"
  [ -f "$new_project" ] || { echo "missing: $new_project"; return 1; }

  # The doc must call out the two-arg signature explicitly.
  grep -qE '`new-project <template> <name>`' "$STORY_07" || {
    echo "story 07 must use the two-arg signature 'new-project <template> <name>'"
    echo "fix: bin/new-project requires both <template> and <name> positional args"
    return 1
  }

  # The doc must NOT reintroduce the false single-arg signature (which
  # was the original drift) or the README claim (the script creates
  # .gitignore but no README).
  if grep -E '`new-project <name>`' "$STORY_07" >/dev/null; then
    echo "story 07 reintroduced the wrong single-arg signature 'new-project <name>'"
    return 1
  fi
  if grep -nE 'new-project.*README' "$STORY_07" >/dev/null; then
    echo "story 07 claims new-project creates a README — bin/new-project does not"
    return 1
  fi

  # Templates: every `<name>)` case branch in the template-dispatch
  # case statement must appear backticked in story 07's row, and every
  # backticked template in the row must be a real branch.
  local code_templates=()
  while IFS= read -r tmpl; do
    code_templates+=("$tmpl")
  done < <(awk '
    /case "\$template" in/ { in_case = 1; next }
    in_case && /^[[:space:]]*esac/ { exit }
    in_case && /^[[:space:]]+[a-z]+\)/ {
      sub(/^[[:space:]]+/, "")
      sub(/\).*/, "")
      if ($0 != "*") print
    }
  ' "$new_project")

  [ "${#code_templates[@]}" -gt 0 ] || {
    echo "extracted no templates from $new_project — parser regression?"
    return 1
  }

  local tmpl
  for tmpl in "${code_templates[@]}"; do
    grep -qE "\`new-project <template> <name>\`.*\`${tmpl}\`" "$STORY_07" || {
      echo "story 07 new-project row missing template '$tmpl' (defined in $new_project)"
      echo "fix: list every template (\`react\`, \`node\`, \`lib\`, \`python\`, ...) in the row"
      return 1
    }
  done

  # Converse: every backticked single-word `<name>` token after the
  # 'templates:' label in story 07 must be a real template.
  local doc_templates_line
  doc_templates_line=$(grep -oE 'templates: `[a-z]+`(, `[a-z]+`)*' "$STORY_07" | head -1)
  [ -n "$doc_templates_line" ] || {
    echo "story 07 must spell out 'templates: \`<name>\`, ...' in the new-project row"
    return 1
  }

  while IFS= read -r doc_tmpl; do
    case " ${code_templates[*]} " in
      *" $doc_tmpl "*) ;;
      *)
        echo "story 07 lists template '$doc_tmpl' but $new_project has no '$doc_tmpl)' case branch"
        return 1
        ;;
    esac
  done < <(printf '%s\n' "$doc_templates_line" | grep -oE '`[a-z]+`' | tr -d '`')
}

@test "story 05 sync-interval claim matches dotfiles-sync plist StartInterval" {
  # Story 05 advertises 'Auto-sync (every 30 minutes)' and 'every 30 min'
  # in story 02's LaunchAgent table. Both numbers come from the
  # StartInterval (in seconds) of launchagents/com.dotfiles.dotfiles-sync
  # .plist.tmpl. Pin the doc to the plist so changing StartInterval
  # without updating the doc fails CI.
  local plist="$REPO_ROOT/launchagents/com.dotfiles.dotfiles-sync.plist.tmpl"
  [ -f "$plist" ] || {
    echo "missing: $plist"
    return 1
  }

  # Extract <integer>N</integer> for the StartInterval key. Plist is
  # XML; awk to find the integer line that follows the StartInterval
  # key line.
  local start_interval expected_minutes
  start_interval=$(awk '
    /<key>StartInterval<\/key>/ { want = 1; next }
    want && /<integer>[0-9]+<\/integer>/ {
      sub(/^[[:space:]]*<integer>/, "")
      sub(/<\/integer>.*$/, "")
      print
      exit
    }
  ' "$plist")
  [ -n "$start_interval" ] || {
    echo "could not extract <integer> following StartInterval in $plist"
    return 1
  }

  expected_minutes=$((start_interval / 60))
  [ "$expected_minutes" -gt 0 ] || {
    echo "$plist StartInterval=$start_interval seconds — expected a multiple of 60"
    return 1
  }

  # Story 05's heading: '### 1. Auto-sync (every 30 minutes)'
  grep -qE "Auto-sync \\(every ${expected_minutes} minutes?\\)" "$STORY_05" || {
    local current
    current=$(grep -oE 'Auto-sync \(every [0-9]+ minutes?\)' "$STORY_05" | head -1)
    echo "drift: $plist StartInterval=${start_interval}s (${expected_minutes} minutes) but story 05 reads '$current'"
    echo "fix: align $STORY_05 with the plist (or vice versa)"
    return 1
  }
}

@test "story 05 severity table covers every module with the right severity" {
  # `bin/dotfiles-doctor` reads `modules/<name>/severity`; modules
  # without a severity file default to "cosmetic". Each module must appear
  # in exactly one row of story 05's severity table that matches its
  # actual severity, and the four rows together must cover every module.
  local mod sev row line
  declare -A row_for_severity=()
  # Pull the four severity rows from the table. Format:
  #   | <emoji> Critical | mod1, mod2 | ... |
  # We only care about (a) the severity name and (b) the comma-separated
  # module list in column 2.
  while IFS= read -r line; do
    case "$line" in
      *"| 🚨 Critical |"*)    row_for_severity[critical]="$line"   ;;
      *"| ⚙️ Important |"*)   row_for_severity[important]="$line"  ;;
      *"| ⚡ Performance |"*) row_for_severity[performance]="$line" ;;
      *"| 💅 Cosmetic |"*)    row_for_severity[cosmetic]="$line"   ;;
    esac
  done < "$STORY_05"

  for sev in critical important performance cosmetic; do
    [ -n "${row_for_severity[$sev]:-}" ] || {
      echo "story 05 severity table is missing the '$sev' row"
      return 1
    }
  done

  for d in "$REPO_ROOT"/modules/*/; do
    mod=$(basename "$d")
    if [ -f "$d/severity" ]; then
      sev=$(tr -d '[:space:]' < "$d/severity")
    else
      sev="cosmetic"
    fi
    row="${row_for_severity[$sev]:-}"
    [ -n "$row" ] || {
      echo "module $mod has unknown severity '$sev' (no matching row)"
      return 1
    }
    case "$row" in
      *" $mod,"*|*" $mod "*|*", $mod"*)
        # match: ", mod" (middle/end) or " mod, " (start) or " mod " (single)
        ;;
      *)
        echo "story 05 severity table is missing module '$mod' in '$sev' row"
        echo "row: $row"
        return 1
        ;;
    esac
  done
}

@test "story 07 'Other Helpers' section does not claim non-git tools are git helpers" {
  # new-project, note, and timer are not git helpers — the heading must
  # not include 'Git' before 'Helpers'.
  if grep -qE '^## Other Git Helpers' "$STORY_07"; then
    echo "story 07 still uses 'Other Git Helpers' — rename to 'Other Helpers'"
    return 1
  fi
  grep -qE '^## Other Helpers' "$STORY_07" || {
    echo "story 07 is missing the '## Other Helpers' section heading"
    return 1
  }
}

@test "story 05 manual commands - dotfiles doctor --list exits 0 with check IDs" {
  run "$REPO_ROOT/bin/dotfiles" doctor --list
  [ "$status" -eq 0 ]
  # Output must contain at least one check ID in the 'module.check' format.
  [[ "$output" =~ [a-z][a-z_-]*\.[a-z][a-z_-]* ]] || {
    echo "dotfiles doctor --list did not emit any check IDs (expected 'module.name' format)"
    return 1
  }
}

@test "story 05 manual commands - dotfiles-doctor help covers --fix --skip --list" {
  run "$REPO_ROOT/bin/dotfiles-doctor" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--fix"* ]]   || { echo "dotfiles-doctor --help is missing '--fix'";  return 1; }
  [[ "$output" == *"--skip"* ]]  || { echo "dotfiles-doctor --help is missing '--skip'"; return 1; }
  [[ "$output" == *"--list"* ]]  || { echo "dotfiles-doctor --help is missing '--list'"; return 1; }
}

@test "story 05 manual commands - diff and update are top-level subcommands" {
  run "$REPO_ROOT/bin/dotfiles" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff"* ]]   || { echo "dotfiles --help is missing 'diff' subcommand";   return 1; }
  [[ "$output" == *"update"* ]] || { echo "dotfiles --help is missing 'update' subcommand"; return 1; }
}

@test "story 06 secret-scan patterns list matches lib/secret-scan.sh" {
  local secret_scan="$REPO_ROOT/lib/secret-scan.sh"
  [ -f "$secret_scan" ] || { echo "missing: $secret_scan"; return 1; }

  # Extract pattern names from the alternation in DOTFILES_SECRET_PATTERNS.
  local patterns
  patterns=$(grep 'DOTFILES_SECRET_PATTERNS=' "$secret_scan" \
    | grep -oE '\([A-Z_|]+\)' | tr -d '()' | tr '|' '\n')
  [ -n "$patterns" ] || {
    echo "could not extract pattern names from $secret_scan"
    return 1
  }

  local pattern
  while IFS= read -r pattern; do
    grep -qF "$pattern" "$STORY_06" || {
      echo "story 06 is missing secret pattern '$pattern' from lib/secret-scan.sh"
      echo "fix: add '\`$pattern\`' to the 'Scans for' bullet in $STORY_06"
      return 1
    }
  done <<< "$patterns"
}
