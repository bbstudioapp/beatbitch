# Privacy Policy — BeatBitch

_Last updated: 2026-05-08 · App version 0.1.0_

**Languages**: English · [Français](PRIVACY.fr.md) · [Deutsch](PRIVACY.de.md)

---

## In one sentence

**BeatBitch is 100% offline. No data ever leaves your phone.**

## Details

- **No telemetry, no analytics, no crash reporter.** No third-party tracking SDK.
- **No account, no identifier.** The app doesn't ask for email, username, or phone number.
- **`INTERNET` permission is not declared** in the Android manifest. The OS therefore refuses any network connection attempt, even hypothetical.
- **`CAMERA` permission**: optional, requested only if you enable the "Hold camera check" toggle in the SOUNDS screen. The video stream is processed **locally** by Google ML Kit (on-device model) to detect face position. No image, landmark, or metadata is transmitted to any server. The stream is never written to disk.
- **Local storage only**: your preferences (volume, TTS voice, language, camera calibration) and gameplay stats (counters, badges, level, humiliation/obedience meters) are persisted via `SharedPreferences` inside the app sandbox.
- **`android:allowBackup="false"`** in the manifest: no automatic backup to Google cloud. If you uninstall the app, your data is gone with it.
- **Local TTS only**: voice is synthesized by the Android Text-to-Speech engine installed on your device. No network synthesis (the engine's `-network` voices are explicitly filtered out).
- **Audio**: the app only plays the beeps and samples bundled inside the APK. No streaming, no downloads.

## ML Kit model

On first launch, Google ML Kit may automatically download its face detection model (~3 MB) **via Google Play Services**, independently of the app. This download is handled by Android itself, not by BeatBitch — the app still makes no network calls of its own. The model then stays local and works offline.

## Contact

Bug reports, questions, clarifications: open an issue on the project repo. No support email for this alpha version.

## Changes

This policy may evolve as the app gains features. Any update will be announced in the release changelog and the date at the top of this file will be updated.
