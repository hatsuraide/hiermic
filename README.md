# HierMic

Are you annoyed that WO Mic isn't working on linux at all??
Then HierMic *might* be a nice replacment for it.

Use your phone as a wireless microphone over WiFi. Audio is streamed to a Linux device and injected into PipeWire as a real virtual microphone source.

---

## Requirements

**Server (Linux PC):**
- PipeWire with PulseAudio compatibility layer running:
  ```bash
  systemctl --user status pipewire pipewire-pulse
  ```
- `pactl` in PATH (usually from `libpulse` / `pipewire-pulse` package)

**Mobile (iOS or Android):**
- iOS 14+ or Android 6+
- Same WiFi network as the server

---

## Server: quick start

### Option A: download the binary

Grab the latest `hiermic` from [Releases](https://github.com/hatsuraide/hiermic/releases) and run it:

```bash
chmod +x ./hiermic
./hiermic
```

### Option B: install as a systemd user service

```bash
./hiermic--install
```

This copies the binary to `~/.local/bin/hiermic`, writes a systemd user unit, and starts the service automatically. It will also auto-start on login.

```bash
# Check status
systemctl --user status hiermic

# View live logs
journalctl --user -u hiermic -f

# Uninstall
hiermic --uninstall
```

### Option C: build from source

```bash
git clone https://github.com/hatsuraide/hiermic
cd hiermic/server
dotnet run --project src/HierMic.Server
```

---

## Mobile app

### iOS (sideload)

Download the unsigned IPA `HierMic-unsigned.ipa` from [Releases](https://github.com/hatsuraide/hiermic/releases) and install it via [AltStore](https://altstore.io), [Sideloadly](https://sideloadly.io) or [LiveContainer](https://github.com/LiveContainer/LiveContainer).

### Build from source (iOS / Android)

```bash
cd mobile/hiermic_app
flutter pub get
flutter run          # Android / connected device
```

For iOS, use the [GitHub Actions workflow](.github/workflows/ios-build.yml) since it produces an unsigned IPA without needing a Mac or Apple Developer account.

---

## Usage

1. Start the server (or have it running via systemd)
2. Open the HierMic app on your phone
3. The server appears automatically via mDNS — tap it to connect, and it is added to your saved servers automatically
4. If auto-discovery doesn't work, tap `+` under **Saved servers** and add a name, IP and port
5. Connect to as many saved servers as you like
6. Tap the mic button to stream to *all* connected servers at once
7. Select **hiermic** as your microphone source in OBS, Discord, etc.

---

## Protocol

| Channel | Port | Format |
|---------|------|--------|
| Control | TCP 7878 | Newline-delimited JSON (`Hello` / `HelloAck` / `Start` / `Stop` / `Ping` / `Pong`) |
| Audio   | UDP 7879 | Binary: `seq[4] + ts[4] + channels[1] + sampleCount[2] + PCM16LE data` |
| Discovery | mDNS | Service type `_hiermic._tcp` |

Audio format: PCM 16-bit little-endian, 48 000 Hz, mono (~1.5 Mbps).

---

## Notes

- No jitter buffer, audio may stutter on congested WiFi
- PCM only, Opus codec is not implemented yet
- The IPA is unsigned, so you will need AltStore, SideStore or LiveContainer to use it on a non-jailbroken device.
- This project was unfortunately mostly vibecoded since I needed an easy and similar alternative to WO Mic

## Why this name?
You can read `WO Mic` as `Where Mic` in german. So I thought of naming it `hier mic` which means translated `here mic` :D
