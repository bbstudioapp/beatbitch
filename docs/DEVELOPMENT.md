# Development setup

How to install the project, run it on every target platform, and where to edit if you want to tweak content without writing code.

**Languages**: English · [Français](DEVELOPMENT.fr.md) · [Deutsch](DEVELOPMENT.de.md)

---

## 1. Requirements

| Tool | Version | Notes |
|---|---|---|
| **Flutter SDK** | ≥ 3.19 (stable) | `flutter --version` must show at least 3.19. Newer = fine. |
| **Dart SDK** | bundled with Flutter | No need to install separately. |
| **Git** | any recent version | |
| **Android Studio** *(Android only)* | latest stable | Needed for the Android SDK, the emulator and `adb`. The Flutter IDE plugin is optional — you can develop in VS Code or any editor. |
| **Visual Studio 2022 Community** *(Windows desktop only)* | latest | **"Desktop development with C++"** workload required. Without it, `flutter build windows` fails at native compilation. |
| **Chrome** *(web only)* | any recent version | For `flutter run -d chrome` (dev mode). Web is **not** an official release target (see `docs/index.md`), but it stays usable for fast UI iteration. |

Quick check after install:

```bash
flutter doctor
```

Anything you intend to target must show ✅. The ❌ on platforms you don't target can be ignored.

---

## 2. Clone and resolve deps

```bash
git clone git@github.com:bbstudioapp/beatbitch.git
cd beatbitch/rhythm_coach
flutter pub get
flutter analyze   # should return "No issues found!"
flutter test      # ~80 unit tests
```

All Flutter code lives in **`rhythm_coach/`**. The repo root only holds public docs, the license, the CI/CD workflow and GitHub templates.

---

## 3. Run per platform

In every case, run from `rhythm_coach/`.

### 3.1 Android

```bash
flutter run                       # USB device or connected emulator
flutter build apk --release       # release APK (requires key.properties)
flutter build apk --debug         # debug APK, signed with the default Android key
```

`adb devices` to verify your phone is recognized. Enable **developer mode** + **USB debugging** on the phone. First launch: Android asks to authorize the computer (dialog on the phone).

> To build a signed release APK outside CI, you need an `android/key.properties` with your keystore. See `android/key.properties.example` for the format. CI uses a dedicated keystore stored as a GitHub secret (cf. `.github/RELEASE_SETUP.md`).

### 3.2 Windows desktop

```bash
flutter config --enable-windows-desktop   # once
flutter run -d windows                    # launches the app in debug
flutter build windows --release           # release build in build/windows/x64/runner/Release/
```

The final binary is `build/windows/x64/runner/Release/rhythm_coach.exe` + its Flutter DLLs and plugins. To distribute, **zip the whole Release folder** — that's what the `release-windows` CI job does (cf. `.github/workflows/release.yml`).

> ⚠ On Windows, several features are **disabled** by design: hold camera check, surprise notifications. Cf. `lib/services/platform_capabilities.dart`. TTS uses Microsoft Julie (SAPI) with rate 0.68 / pitch 1.22 forced for all coaches (Android voices `fr-fr-x-*-local` don't exist under SAPI).

### 3.3 Web (dev only — not a release target)

```bash
flutter config --enable-web         # once
flutter run -d chrome               # dev mode with hot-reload
flutter build web --release         # static build in build/web/
```

Web is for quick UI iteration without rebuilding Android. **It's not an official distribution target** — public NSFW hosting raises issues (GitHub Pages / Cloudflare Pages TOS, fragile adult gate in a browser, degraded experience without notifs / vibration / ML Kit camera).

> Several APIs aren't available on web. The code already uses `defaultTargetPlatform != TargetPlatform.android` guards for camera and surprise notifs — the app loads but those features are hidden.

### 3.4 Linux

```bash
flutter config --enable-linux-desktop
flutter run -d linux
flutter build linux --release
```

CI job `release-linux` packages it as a portable tar.gz (cf. `.github/workflows/release.yml`). Same capabilities disabled as on Windows (hold camera check + surprise notifs out of scope).

**TTS**: `flutter_tts` declares no Linux implementation → the service bypasses the plugin and picks at runtime between `piper` (neural TTS, natural voice) and `spd-say` (espeak-ng fallback). User-facing details + piper install: [LINUX_TTS.md](LINUX_TTS.md).

### 3.5 macOS (blocked)

Blocked by Apple Developer ID + notarization (~$99/year + Mac required). Not planned unless explicitly requested.

---

## 4. Customize content

**All editorial content is in `rhythm_coach/assets/`** as JSON / MP3 files. No code change needed to add a session, a phrase, a coach, a language.

### 4.1 Scenario sessions

Path: `assets/sessions/*.json` — preset Scenario-mode sessions (not the Career sessions, which are composed at runtime by `CareerSessionGenerator`).

| File | Description |
|---|---|
| `session_initiation.json` | 8 min, progressive tone. Soft demo. |
| `session_intense.json` | 10 min, intervals. |
| `session_advanced_demo.json` | Demo of advanced modes (24 steps). |
| `session_camera_test.json` | Camera-check tests (5 holds tip→full). |
| `session_initiation_en.json` | English variant (locale = `en`). |

**Schema**: a session is `{id, name, description, duration_seconds, mode, lang, steps[], …}`. Full details in `rhythm_coach/CLAUDE.md` section *Modèles de données* + `lib/models/session.dart`.

**Add a session**:
1. Create `assets/sessions/my_session.json` with the expected schema.
2. Add the path to `lib/services/session_loader.dart` → `_assetPaths` list.
3. No need to touch `pubspec.yaml` (the `assets/sessions/` folder is already declared).

### 4.2 Coaches

Path: `assets/career/coaches/`

| File | Description |
|---|---|
| `coach_<id>.json` | Coach metadata (locale-independent) — id, name, archetype, specialties, modeWeights, voicePreset, etc. |
| `coach_<id>_<lang>.json` | Coach TTS phrases for the locale (FR, EN…). Pool by mode/tier (soft/medium/hard/boost/finale) + intros + transitions + recovery. |

Each coach is > 100 lines + > 200 phrases per locale. AI contributors should refer to **[`docs/CONTENT_GUIDE.md`](CONTENT_GUIDE.md)** which describes the expected structure line by line.

**Add a coach**:
1. Create the `coach_<id>.json` (metadata).
2. Create at least one `coach_<id>_fr.json` (FR phrases).
3. The coach automatically appears in the Career selector as soon as the unlock conditions (`requirements`) are met.

### 4.3 Punishments, comments, ambiences

| File | Role |
|---|---|
| `assets/punishments.json` (+ `_en.json`) | Fail phrases + mini punishment sequences. |
| `assets/random_comments.json` (+ `_en.json`) | Random comments interleaved into sessions. Pacing (`min/max_interval_seconds`) editable. |
| `assets/ambience_packs.json` (+ `_en.json`) | Ambience packs (mapping `SessionMode → MP3`). Editorially curated. |
| `assets/nicknames.json` (+ `_en.json`) | Global nickname pool (user override possible from Profile). |

Direct editing — no code change required. The loaders pick up the new version on the next run.

### 4.4 Guidance beeps (audio)

Path: `assets/audio/*.mp3`

| File | Usage |
|---|---|
| `tip_beep.mp3`, `head_beep.mp3`, `mid_beep.mp3`, `throat_beep.mp3`, `full_beep.mp3` | Sample per position (5 levels from highest to lowest). |
| `hold_beep.mp3`, `breath_beep.mp3`, `biffle_beep.mp3` | Mode-specific samples. |
| `hand_down_beep.mp3`, `hand_up_beep.mp3` | Hand mode: down-stroke + up-stroke. |
| `freestyle_start.mp3`, `freestyle_end.mp3` | Start/end markers for freestyle mode. |
| `finale_chime.mp3` | Coach's orgasm sound at end of session. Per-category variants in `assets/audio/finale/` (empty for now, single fallback). |

**Replace a beep**: drop in a new MP3 with the **same filename**. No code change. For a new sample type, extend the constants in `lib/services/beep_engine.dart`.

**Regenerate placeholders**: `bash tools/generate_beeps.sh` (needs `ffmpeg`). Frequencies/durations are at the top of the script.

### 4.5 Backgrounds (GIF / images) and ambiences (MP3)

Path: `assets/backgrounds/` (gitignored) and `assets/audio/ambience/` (gitignored).

Heavy binaries are **not** in the public repo — they're fetched from Cloudflare R2 by CI at build time (cf. `.github/workflows/release.yml` step *Fetch external assets from R2*). Locally these folders are empty and the app degrades gracefully (animated placeholder for backgrounds, silence for ambience).

To work with the real ambiences locally: request R2 bucket access (via a private issue or directly to the author), or manually drop your own MP3s into `assets/audio/ambience/`.

### 4.6 Internationalization (UI)

The Flutter UI consumes `AppLocalizations.of(context).xxx` (generated from `lib/l10n/app_<lang>.arb`). To add a language, create a new ARB file + add the locale to `kSupportedLocales` (`lib/services/locale_service.dart`) + create the editorial counterparts per language (sections 4.1–4.4).

Complete procedure: *Internationalisation* section in `rhythm_coach/CLAUDE.md`.

---

## 5. Tests

```bash
cd rhythm_coach
flutter test                          # all tests
flutter test test/coach_service_test.dart   # a specific file
flutter test --plain-name "encore"    # filter by name
```

No UI / golden tests — only pure Dart unit tests on business logic (coach validation, nicknames, phrases, milestones, session generator).

A separate `ci.yml` workflow will run `analyze` + `test` on every PR towards develop/main as a *required check* in the next release.

---

## 6. Git workflow

See [`CONTRIBUTING.md`](../CONTRIBUTING.md) section *Code — Git workflow*.

In short:

- `feat/`, `fix/`, `chore/`, `docs/`, `ci/` branches → PR towards **`develop`**
- `release/x.y.z` version bumps → PR towards **`main`** (triggers the auto-release workflow, builds APK + Windows zip + GitHub Release)
- `main` and `develop` are protected (no direct push, linear history, mandatory PR with 0 approvals required)
- Auto back-merge `main → develop` after every release (workflow `back-merge.yml`)

---

## 7. Going further

- **[`rhythm_coach/CLAUDE.md`](../rhythm_coach/CLAUDE.md)** — full internal architecture (controllers, services, BeepEngine, ExcitationEngine, HumiliationEngine, ObedienceEngine, Career mode, milestones, badges, i18n). This is the reference doc for understanding how the app works.
- **[`docs/CONTENT_GUIDE.md`](CONTENT_GUIDE.md)** — guide to the JSON formats for contributors (human or AI) who want to add phrases / scenarios without coding.
- **[`docs/ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md)** — rules for GIF / MP3 contributions (mandatory license + source).
- **[`.github/RELEASE_SETUP.md`](../.github/RELEASE_SETUP.md)** — CI/CD secrets, Android keystore, R2.
