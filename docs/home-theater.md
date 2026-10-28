# Home theater: 4K movies from the Mac on a Samsung TV

Turn it on with `dotfiles config set home_theater true`, then `dotfiles apply`. That installs
Plex Media Server, VLC and `duti`. `dotfiles doctor --module home-theater` checks the rest.
Add `dotfiles config set samsung_tv_host <tv-ip>` to check the TV's network too.

## Pick the player

| Where you watch | Use | Why |
|---|---|---|
| On the TV | **Plex** (server on the Mac, Plex app on the TV) | plays the file as-is in 4K HDR; no cable |
| On the Mac | **VLC** for `.mkv`, `.avi`, `.webm` | plays every codec; the doctor makes it the default |
| On the TV, Mac screen | HDMI cable (or an HDMI 2.1 switch) | AirPlay compresses and drops Atmos |

## What the doctor fixes or flags

See [module-reference.md](module-reference.md#home-theater--full-only-opt-in) for each check.
In short: both apps installed, Plex answering, VLC opens `.mkv`, the Mac never sleeps on its
power adapter (`sudo pmset -c sleep 0`), and the TV uses Ethernet.

## One-time settings that a script cannot set

**Plex server** (browser at `http://127.0.0.1:32400/web`):
1. Add a **Movies** library that points at your movie folder.
2. Settings > General: turn on **Start Plex Media Server at login**.
3. Remote Access can stay off for home use.

**Plex app on the TV** (Settings):
1. **Home streaming quality: Original** (direct play, no transcode).
2. **Audio passthrough: Dolby Digital Plus** (Atmos inside DD+ reaches the soundbar).

**Samsung TV** (Settings > Sound > Expert Settings):
1. **Sound Output**: the soundbar on **HDMI eARC**.
2. **HDMI eARC Mode: Auto**.
3. **Digital Output Audio Format: Pass-Through**.

**Samsung soundbar** (SmartThings app): turn on **SpaceFit Sound**, then set Channel Level
(centre +1, surround +2, woofer -1 in a small room).

## Limits

- Samsung TV apps cannot pass Dolby TrueHD or DTS; Plex converts those tracks. Pick a DD+
  track, or play the file from the Mac over HDMI.
- YouTube has no Dolby Atmos. Test Atmos with Netflix, Disney+ or Apple TV+.
- Samsung TVs play Dolby Vision files as HDR10.
