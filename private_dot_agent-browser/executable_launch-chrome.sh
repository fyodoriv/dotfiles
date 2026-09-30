#!/bin/bash
set -euo pipefail

"$HOME/.agent-browser/ensure-chrome.sh" >/dev/null
echo "agent-browser Chrome is launchd-managed; attach with: agent-browser --cdp 9223"
