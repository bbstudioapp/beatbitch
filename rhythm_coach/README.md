# BeatBitch

![version](https://img.shields.io/badge/version-0.4.0-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)

> An immersive rhythmic voice coach. The phone lies on its side — no need to watch the screen. Everything is driven by voice and guidance beeps.

**Languages**: English · [Français](README.fr.md) · [Deutsch](README.de.md)

---

## Screenshots

> _Coming soon — the app is in private alpha._

<p>
  <em>placeholder</em> · home · session · sounds · profile · badges
</p>

## Features

- **Female TTS voice coach**, firm tone, local voice only (no network synthesis).
- **8 play modes**: rhythm, lick, biffle, hold, breath, beg, freestyle, hand.
- **Career mode**: 20+ levels, 6 specialization branches, learning milestones, chained encore, quickie sessions, progression badges.
- **Free scenarios**: editable JSON sessions, extensible punishments and random comments without touching code.
- **Hold camera check** (experimental, opt-in): on-device detection via Google ML Kit — no image ever leaves the device.
- **Multilingual**: French, English and German shipped; other locales = asset drop-in.
- **18+ adult gate** non-skippable on first launch, 3-step onboarding.

## 100% offline · no telemetry

No data leaves your phone. The `INTERNET` permission is not declared. ML Kit runs locally. See [PRIVACY.md](PRIVACY.md).

## Install (Android side-load)

The app is **not distributed on the Play Store** — manual install only.

1. Download the APK from the repo Releases page.
2. Verify the SHA256 published next to the APK:
   ```bash
   sha256sum BeatBitch-X.Y.Z.apk
   ```
3. On the phone: allow installs from unknown sources for your file manager / browser.
4. Open the APK and confirm the install.
5. First launch: 18+ adult gate, then 3-step onboarding.

> ⚠ Android 9+ required. Tested on Android 13/14.

## Install (Windows desktop)

Available since v0.1.3 — portable zip, no installer.

1. Download `BeatBitch-X.Y.Z-windows-x64.zip` from the Releases page.
2. Verify the SHA256:
   ```powershell
   Get-FileHash BeatBitch-X.Y.Z-windows-x64.zip -Algorithm SHA256
   ```
3. Unzip wherever you like (`Documents\BeatBitch\`, USB stick, …).
4. Launch `rhythm_coach.exe`. Windows SmartScreen may warn (unsigned binary) →
   click *More info* → *Run anyway*.
5. First launch: 18+ adult gate, then 3-step onboarding.

> ⚠ Disabled on Windows: hold camera check, surprise notifications. The
> coach voice uses Microsoft Julie (SAPI). Everything else — sessions,
> Career mode, coaches, badges, i18n — works identically to Android.

## Install (Linux desktop)

Available since v0.3.0 — portable `tar.gz`, no `.deb`/`.rpm` package.

1. Download `BeatBitch-X.Y.Z-linux-x64.tar.gz` from the Releases page.
2. Verify the SHA256:
   ```bash
   sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256
   ```
3. Unpack wherever you like: `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Launch the binary: `./BeatBitch-X.Y.Z-linux-x64/beat_bitch`.
5. First launch: 18+ adult gate, then 3-step onboarding.

> ⚠ Disabled on Linux: hold camera check, surprise notifications. The
> coach voice uses the default Speech Dispatcher voice (typically
> `espeak-ng`). Everything else — sessions, Career mode, coaches, badges,
> i18n — works identically to Android.

## Automatic updates (Obtainium)

The app stays **strictly offline** — it doesn't reach out for updates by itself. To get notified when a new version ships, use **[Obtainium](https://github.com/ImranR98/Obtainium)**, an open-source Android store that watches GitHub Releases pages. *Add App* → paste `https://github.com/bbstudioapp/beatbitch`. No network traffic comes from BeatBitch itself — Obtainium queries GitHub on the user side, independently of the app.

## Local build (developers)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # should return "No issues found!"
flutter test
flutter run           # connected Android device / `-d windows` / `-d chrome`
flutter build apk --release
flutter build windows --release
```

Editorial content lives in `assets/` (JSON sessions, punishments, random comments, ambience packs, career phrase bank). Full per-platform setup + customization paths: **[`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md)**.

> ⚠ **Externalized binary assets**: the `assets/backgrounds/` (background GIFs/images) and `assets/audio/ambience/` (ambience MP3s) folders are **gitignored** — their files are not versioned in the repo and must be fetched from an external channel (TBD) before `flutter build`. The code degrades gracefully when these folders are empty: the background falls back to an animated gradient, ambience to silence.

## Privacy

See [PRIVACY.md](PRIVACY.md) — short version: no collection, everything is local, `allowBackup="false"`.

## License

Code and editorial content (JSON sessions, coach phrases, random comments, nicknames, milestones, etc.) released under the **[PolyForm Noncommercial License 1.0.0](../LICENSE)**.

- ✅ **Study, fork, modify, redistribute** for noncommercial use.
- ✅ **Contributions welcome** — new coach phrases, sessions, translations, code fixes, specialization ideas, etc. Open an issue or a PR.
- ❌ **No commercial use, sale, or paid redistribution** — no "BeatBitch Premium" fork on Telegram, Gumroad, or any alternative store.

Off-repo binary assets (`assets/backgrounds/*.gif`, `assets/audio/ambience/*.mp3`) remain subject to their original sources' rights and are not covered by this license.

## Bug reports

Open an issue on the repo. Please include device model, Android version, and steps to reproduce.
