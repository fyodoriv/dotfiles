#!/bin/bash
# Node pin drift check, shared by the agentbrew doctor module and
# bin/dotfiles-node-upgrade (which runs it after a Node switch).
#
# macOS keys the "node would like to accept incoming connections" prompt on
# the executable. exec() resolves symlinks, so a version-independent symlink
# cannot hide a version change. The achievable goal is one path at a time:
# every com.agentbrew.* plist and ~/.local/bin/node must name the Node that
# ~/.node-version selects, so each deliberate upgrade prompts once, not once
# per drifted consumer. Prints the drifted paths on failure.
_agentbrew_launchagent_node_pinned() {
  local version_file="$HOME/.node-version" ver expected plist first drift=0 target
  [ -f "$version_file" ] || return 0
  ver="$(sed 's/^v//' "$version_file" 2>/dev/null | head -n1)"
  [ -n "$ver" ] || return 0
  expected="$HOME/.local/share/fnm/node-versions/v${ver}/installation/bin/node"
  [ -x "$expected" ] || return 0
  for plist in "$HOME"/Library/LaunchAgents/com.agentbrew.*.plist; do
    [ -f "$plist" ] || continue
    first="$(awk '/<key>ProgramArguments<\/key>/{f=1} f&&/<string>/{gsub(/.*<string>|<\/string>.*/,""); print; exit}' "$plist")"
    case "$first" in
      */node-versions/*/bin/node)
        if [ "$first" != "$expected" ]; then
          echo "$plist runs $first (expected $expected)"
          drift=1
        fi
        ;;
    esac
  done
  if [ -L "$HOME/.local/bin/node" ]; then
    target="$(readlink "$HOME/.local/bin/node" 2>/dev/null || true)"
    if [ -n "$target" ] && [ "$target" != "$expected" ]; then
      echo "$HOME/.local/bin/node -> $target (expected $expected)"
      drift=1
    fi
  fi
  [ "$drift" -eq 0 ]
}
