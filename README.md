# AutoBiss E2

AutoBiss E2 is an Enigma2 plugin for **Dreambox / Gemini (DreamOS)**, **OpenATV**,
**OpenPLi** and other Enigma2 images. It detects BISS-encrypted channels, finds
the control word, writes it to the softcam and keeps a live list of satellite
feeds with one-click **Search** and **Zap**.

![version](https://img.shields.io/badge/version-3.7.5-blue)
![python](https://img.shields.io/badge/python-2.7%20%7C%203.x-green)

## Features

- Full-screen 1920x1080 interface (Control Center, Channel Info, Live Feeds, Settings).
- BISS key detection with CW cache and automatic softcam injection.
- Keys are written with an identifier proven by OSCam for the same service:
  universal/namespace hash or a verified `Key found` transaction — no SID+PMT guessing.
- Softcam reload is verified against the emulator entitlements before reporting success.
- Live Feeds: imported automatically, colour status lamp (BISS / 4:2:2 / FTA),
  **Search** (native service scan on the tuner that receives the feed) and **Zap** buttons.
- Works on Python 2.7 (DreamOS, OpenPLi 7) and Python 3 (OpenATV 7+).
- Signed, verified updates (HMAC-SHA256 manifest).

## What's new in 3.7.5

- **DreamOS service detection fixed**: the service reference, TSID, ONID and
  PMT PID are read from the real reference/OSCam log instead of the bogus
  DreamOS `sTSID`/`sONID`/`sPMTPID` values.
- The VPS reuses a key already found by another image for the same
  SID + PMT + video/audio PID fingerprint, so a DreamOS box can open a channel
  whose key was discovered on OpenATV without recording anything.
- Emulator refresh works with `oscam_2 -b` (no `--config-dir`) and falls back
  from localhost to the receiver's LAN IP when the WebIF rejects loopback.

## What's new in 3.7.4

- **DreamOS / Gemini freeze fixed**: the plugin no longer starts a `RecordTimer`
  capture on those images (the recording indicator could freeze Enigma2).
  It asks the VPS for the SID/cached key directly instead.
- Active emulator detection works with `oscam -b` (no `--config-dir`): the key
  file is taken from the running reader's `device` path (e.g.
  `/etc/tuxbox/config/SoftCam.Key`).
- Reliable recording on other images: the file is created inside the movie
  folder even when DreamOS concatenates the directory without a slash.

## Installation (one command)

```sh
wget -O - https://raw.githubusercontent.com/prof-abdo/autobiss-e2/main/install.sh | sh
```

or:

```sh
curl -sSL https://raw.githubusercontent.com/prof-abdo/autobiss-e2/main/install.sh | sh
```

The installer **detects the receiver and the image first**, then installs the
right package:

| Detection | Action |
|---|---|
| DreamOS / Gemini, OpenATV 8+, OpenPLi 8+ (apt/dpkg) | installs the `.deb` |
| OpenATV 6/7, OpenPLi 7, OpenViX (opkg) | installs the `.ipk` |
| Receiver model | `dreambox-two`, VU+, Zgemma, ... (from `/etc/opkg/platform`, device-tree, hostname) |
| Architecture | aarch64 / arm / mips / mipsel |
| Python | 2.7 or 3.x, verified with `py_compile` after install |

Useful options:

```sh
sh install.sh --check          # only detect receiver/image, install nothing
sh install.sh --uninstall      # remove the plugin
sh install.sh --local file.deb # install a package already on the receiver
```

The installer verifies the SHA-256 of the package, removes stale `.pyo/.pyc`
bytecode, restarts Enigma2 and **rolls back automatically** if the GUI does not
come back.

## Manual installation

- Debian/apt based images: `dpkg -i enigma2-plugin-extensions-autobiss_3.7.5_all.deb`
- opkg based images: `opkg install enigma2-plugin-extensions-autobiss_3.7.5_all.ipk`

Then restart Enigma2 and open **Extensions → AutoBiss E2**.

## Requirements

- Enigma2 receiver with network access.
- An active softcam (OSCam / Ncam / ...) for descrambling.
- The AutoBiss VPS service for key lookup (configured in Settings).

## Notes

- The Live Feeds source is intentionally not displayed in the UI.
- 4:2:2 feeds are marked yellow; they may not play on all receivers.
- The plugin never writes outside its own folder except the softcam key file.

## License

MIT — see [LICENSE](LICENSE).
