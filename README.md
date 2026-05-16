# BeatBitch

![version](https://img.shields.io/badge/version-0.4.0-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Web-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)
![no tracking](https://img.shields.io/badge/no-tracking-success)
![license](https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-lightgrey)

> **Immersive rhythmic voice coach for Android, Windows, Linux, iOS (PWA) & web.** Drop your phone flat on its side, start the session, close your eyes. A voice guides you, beeps mark the rhythm — no screen-watching needed.

**Languages**: English · [Français](README.fr.md) · [Deutsch](README.de.md)

---

## In 30 seconds

- A **voice coach** speaking your language, locally — no network synthesis.
- **Guidance beeps** locked to a BPM to drive every move.
- 8 play modes, a Career mode that unlocks as you go, coaches with distinct personalities.
- **100% offline** on Android: `INTERNET` permission not declared, nothing leaves your phone.
- **No Play Store, no ads, no IAP.** Distribution is direct signed APK (Android), portable zip (desktop), installable web app (iOS / browser).

## 📥 Download

➡ **[Releases page](../../releases)** — signed APK + its SHA256.

> ⚠ Android 9 minimum. Tested on Android 13/14.

## 📲 Install on Android (side-load, step by step)

**Side-load** just means "install an app outside the Play Store". Android supports this natively — you just need to allow your browser or file manager to do it.

1. **On your phone**, open the [Releases page](../../releases) and download the latest `BeatBitch-X.Y.Z.apk`.
2. (*Optional but recommended*) Verify the SHA256 hash of the downloaded file matches the one published next to the APK. An app like **Hash Droid** on F-Droid does it in two taps.
3. Open the APK from your downloads.
4. Android will ask you to **allow this source**: tap "Settings", enable the permission for your browser (or file manager), come back and confirm.
5. Install runs. Once done, open BeatBitch.
6. **First launch**: 18+ confirmation (non-skippable), then 3 onboarding screens (phone placement, volume, voice test).

> 💡 You can disable "unknown sources" again after installing — Android won't reopen it unless you update the app.

## 🍎 Install on iPhone / iPad (PWA)

BeatBitch is **not** available on the App Store (Apple does not allow adult content). On iOS, we ship an **installable web version** (PWA). Once added to your home screen, it behaves like a real app: dedicated icon, full screen, no Safari bar, works offline after the first load.

1. On your iPhone / iPad (iOS 16.4+), open **Safari** (not Chrome / Firefox — Apple blocks PWA install from those).
2. Go to **[beatbitch.pages.dev](https://beatbitch.pages.dev)** and wait for the page to fully load (the whole app gets downloaded the first time).
3. Tap the **Share** button → **Add to Home Screen** → **Add**.
4. Launch BeatBitch from your home screen. First launch: 18+ adult gate, then 3-step onboarding.

> Detailed guide: **[docs/INSTALL-iOS.en.md](docs/INSTALL-iOS.en.md)**.
>
> ⚠ The web/iOS version uses **iOS native speech synthesis** (no Android voices). Hold camera check and surprise notifications are not available. First load needs an Internet connection; everything else runs offline from the home-screen icon.

## 🌐 Use in a desktop browser

Same URL as iOS — **[beatbitch.pages.dev](https://beatbitch.pages.dev)** works in any modern browser (Chrome, Edge, Firefox, Safari). Handy to try the app before installing the APK or desktop build. Voice quality depends on your OS speech engine.

## 🖥 Install on Windows desktop

Available since **v0.1.3**. Portable zip — no installer, no registry / system-folder writes.

1. From the [Releases page](../../releases), download `BeatBitch-X.Y.Z-windows-x64.zip` (and its `.sha256` if you want to verify integrity).
2. Unzip wherever you like: `C:\Users\you\Documents\BeatBitch\`, a USB stick, etc.
3. Run `rhythm_coach.exe`. Windows SmartScreen may warn (binary not signed by a recognized publisher) → click *More info* → *Run anyway*.
4. First launch: 18+ adult gate, then 3-step onboarding (identical to Android).

> ⚠ **Disabled on Windows**: hold camera check and surprise notifications aren't ported (the native plugins don't have Windows implementations). The coach voice uses **Microsoft Julie** (SAPI) instead of Android voices. Sessions, Career mode, coaches, badges, languages: all work identically to Android.

## 🐧 Install on Linux desktop

Available since **v0.3.0**. Portable `tar.gz` — no `.deb`/`.rpm` package, the app stays in its own folder and nothing is installed system-wide.

1. From the [Releases page](../../releases), download `BeatBitch-X.Y.Z-linux-x64.tar.gz` (and its `.sha256` if you want to verify integrity).
2. Verify the hash: `sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256`.
3. Unpack wherever you like: `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Launch the binary: `./BeatBitch-X.Y.Z-linux-x64/beat_bitch` (right-click → *Allow execution* in your file manager if needed).
5. First launch: 18+ adult gate, then 3-step onboarding (identical to Android).

> ⚠ **Disabled on Linux**: hold camera check and surprise notifications aren't ported. The coach voice uses the default **Speech Dispatcher** voice (typically `espeak-ng` on Ubuntu/Debian — install a French/English voice via your package manager if the default doesn't sound right). Sessions, Career mode, coaches, badges, languages: all work identically to Android.

## 🔄 Automatic updates (Obtainium)

The Android app stays **strictly offline** — it doesn't reach out for updates by itself. To get notified when a new version ships and install it in two taps, use **[Obtainium](https://github.com/ImranR98/Obtainium)**, an open-source Android store that watches GitHub Releases pages.

1. Install Obtainium (available on [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/) or as a direct APK from its repo).
2. In Obtainium: *Add App* → paste the URL `https://github.com/bbstudioapp/beatbitch`.
3. On every new release, Obtainium picks up the `BeatBitch-X.Y.Z.apk` and prompts you to update.

> No network traffic comes from BeatBitch itself — Obtainium queries GitHub on the user side, independently of the app. The 100% offline promise stays intact.

## 🔒 Is it safe?

- **APK signed** with the same key on every release — Android refuses to install a tampered APK (signature won't match).
- **Source code public** — you can read what runs (or have it read for you).
- **No network permission** (Android) — neither `INTERNET` nor `ACCESS_NETWORK_STATE`. The Android app *literally cannot* call out to a server.
- **`allowBackup="false"`** — no Google Backup upload.
- **Camera is opt-in** — the hold camera check is off by default and processing is 100% on-device (Google ML Kit local). No image leaves the phone.

Details in **[PRIVACY.md](docs/PRIVACY.md)** ([published version](https://bbstudioapp.github.io/beatbitch/PRIVACY)).

## 🎮 How to play

1. Drop your phone flat, on its side — no need to keep it in sight.
2. Pick a preset session or let Career mode generate one for you.
3. Follow the voice. Beeps mark the tempo (a low + a high alternating, or just one if you have to hold a position).
4. The **"I can't"** button is always available if you drop off. The coach takes over with a short punishment, then the session resumes where it makes sense.
5. At the end, the screen tells you what you unlocked (badges, career levels, milestones).

## 🐛 Found a bug, got an idea, want to contribute?

Issue templates available:
- 🐛 [Bug](.github/ISSUE_TEMPLATE/bug_report.md) · 💡 [Idea / feature](.github/ISSUE_TEMPLATE/feature_request.md) · ✍ [Coach lines / scenarios / translation](.github/ISSUE_TEMPLATE/content_contribution.md)

Everything is explained in **[CONTRIBUTING.md](CONTRIBUTING.md)**.

> **Editorial** contributions (coach lines, scenarios, nicknames, new languages) are the most valuable and **need no technical skill**. The Content template guides you to the right format.
>
> AI contributors (ChatGPT, Claude, etc.) should refer to **[docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md)** — a structured guide to the JSON formats the generator consumes.

## 🛠 Curious about the code?

The full Flutter project lives in **[`rhythm_coach/`](rhythm_coach/)**:
- **[Developer setup](docs/DEVELOPMENT.md)** — install Flutter, run per platform (Android, Windows, web Chrome), customize assets without coding
- **[Full dev README](rhythm_coach/README.md)** — detailed features, local build, tests
- **[Architecture](rhythm_coach/CLAUDE.md)** — session flow, excitation engine, Career mode, i18n
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — auto-release workflow

## 📝 License

Code and editorial content under **[PolyForm Noncommercial 1.0.0](LICENSE)**.

- ✅ Personal use, study, modification, fork, noncommercial redistribution.
- ❌ Sale, monetization, "Premium" fork on Telegram / Gumroad / alternative store.

Off-repo binary assets (background gifs and ambience mp3s) remain subject to their original sources' rights.
