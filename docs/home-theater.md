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

## Why this module stays here (decision 2026-10-28)

Rule 0 check: no maintained tool replaces these checks, and the module is not private.
- Plex and VLC installs: the Homebrew casks (`plex-media-server`, `vlc`) already install them; the doctor only confirms the app is there. No Plex CLI is needed for a `/identity` probe.
- TV wired check: the SmartThings CLI ([SmartThingsCommunity/smartthings-cli](https://github.com/SmartThingsCommunity/smartthings-cli)) talks to the cloud REST API with a login or token, and its docs show no network-type command. The local Tizen API call is simpler and needs no account.
- `duti` and `pmset` have no wrapper to adopt.
- Relocate: the module is opt-in (`home_theater` is off by default), holds no private data (the TV address is a setting), and any Mac can use it. It stays in the public base repo.

## One-time settings that a script cannot set

**Plex server** (browser at `http://127.0.0.1:32400/web`):
1. Add a **Movies** library that points at your movie folder.
2. Settings > General: turn on **Start Plex Media Server at login**.
3. Remote Access can stay off for home use.

**Plex app on the TV** (Settings):
1. **Home streaming quality: Original**, with **Automatically adjust quality** off.
2. **Direct Play: off, Direct Stream: on.** The Samsung player fails at once with
   "unexpected playback error" on some 4K MKVs that it should play. Direct Stream repackages
   the file on the Mac and copies the picture and sound as they are, so quality stays the same.
3. **Audio passthrough: Dolby Digital Plus** (Atmos inside DD+ reaches the soundbar).

**Language** (Plex account, Settings > Languages): set the audio and subtitle language, and
turn on **Automatically select audio and subtitle tracks**. Files you already have keep their
old track choice: pick the tracks once per file in the player, or with
`PUT /library/parts/<id>?audioStreamID=<a>&subtitleStreamID=<s>&allParts=1`.

**Samsung TV** (Settings > Sound > Expert Settings):
1. **Sound Output**: the soundbar on **HDMI eARC**.
2. **HDMI eARC Mode: Auto**.
3. **Digital Output Audio Format: Pass-Through**.

**Samsung soundbar** (SmartThings app): turn on **SpaceFit Sound**, then set Channel Level
(centre +1, surround +2, woofer -1 in a small room).

## Limits

- Samsung TVs cannot play DTS or Dolby TrueHD. Pick a DD+ track, or add one once and
  keep the video as it is:
  `ffmpeg -i in.mkv -map 0:v:0 -map 0:a:<n> -map 0:a:<n> -map 0:s? -c copy -c:a:0 eac3 -b:a:0 768k out.mkv`.
- The TV cannot show ASS or PGS subtitles, so Plex burns them into the 4K picture and playback
  stalls. Pick an SRT track.
- VLC can hang on 4K HDR at about 50 Mbit/s. Set Settings > Input / Codecs > Hardware Decoding
  to Automatic.
- YouTube has no Dolby Atmos. Test Atmos with Netflix, Disney+ or Apple TV+.
- Samsung TVs play Dolby Vision files as HDR10.
