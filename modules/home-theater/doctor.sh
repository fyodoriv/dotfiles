#!/bin/bash
# Doctor checks for the home-theater module: Mac as a 4K movie server (Plex),
# VLC for local files, and a Samsung TV on a wired network. Guide:
# docs/home-theater.md.

if [ "${DOTFILES_PROFILE:-full}" != "full" ]; then
  return 0 2>/dev/null || exit 0
fi

# Opt-in: set `home_theater: true` in ~/.config/chezmoi/chezmoi.yaml.
if [ "${HOME_THEATER_ENABLED:-false}" != "true" ]; then
  return 0 2>/dev/null || exit 0
fi

PLEX_URL="${PLEX_URL:-http://127.0.0.1:32400}"
APPS_DIR="${HOME_THEATER_APPS_DIR:-/Applications}"

check "tool.plex-media-server" \
  "Plex Media Server installed (fix: brew install --cask plex-media-server)" \
  "[ -d '$APPS_DIR/Plex Media Server.app' ] || [ -d '$HOME/Applications/Plex Media Server.app' ]" \
  ""

check "home_theater.plex_running" \
  "Plex Media Server answers on $PLEX_URL (fix: open -a 'Plex Media Server')" \
  "curl -fsS -m 3 '$PLEX_URL/identity' | grep -q 'machineIdentifier'" \
  "open -a 'Plex Media Server'"

check "tool.vlc" \
  "VLC installed (fix: brew install --cask vlc)" \
  "[ -d '$APPS_DIR/VLC.app' ] || [ -d '$HOME/Applications/VLC.app' ]" \
  ""

# MKV, AVI and WebM open in VLC; MP4 and MOV stay with QuickTime, which
# plays HDR with less power on Apple Silicon.
check "home_theater.vlc_default_mkv" \
  "VLC opens .mkv files (fix: duti -s org.videolan.vlc .mkv all)" \
  "duti -x mkv 2>/dev/null | grep -q 'VLC'" \
  "duti -s org.videolan.vlc .mkv all && duti -s org.videolan.vlc .avi all && duti -s org.videolan.vlc .webm all"

# A sleeping Mac stops Plex mid-movie. Display sleep is fine; system sleep on
# power adapter is not. Needs sudo, so no auto-fix.
check "home_theater.no_sleep_on_ac" \
  "Mac does not sleep on power adapter (fix: sudo pmset -c sleep 0)" \
  "[ \"\$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f && \$1==\"sleep\"{print \$2; exit}')\" = 0 ]" \
  ""

# Samsung Tizen TVs answer GET :8001/api/v2/ on the LAN with device info.
# 4K remuxes need a steady 80+ Mbit/s; Wi-Fi drops frames, Ethernet does not.
if [ -n "${SAMSUNG_TV_HOST:-}" ]; then
  check "home_theater.tv_wired" \
    "Samsung TV at $SAMSUNG_TV_HOST is on wired Ethernet (fix: plug in a cable; TV Settings > Connection > Network)" \
    "curl -fsS -m 3 'http://$SAMSUNG_TV_HOST:8001/api/v2/' | jq -e '.device.networkType == \"wired\"'" \
    ""
fi
