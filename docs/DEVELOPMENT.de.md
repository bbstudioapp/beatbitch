# Entwickler-Setup

Wie du das Projekt installierst, es auf jeder Zielplattform startest und wo du etwas anpasst, um den Inhalt ohne Codeänderung zu personalisieren.

**Sprachen** : [English](DEVELOPMENT.md) · [Français](DEVELOPMENT.fr.md) · Deutsch

---

## 1. Voraussetzungen

| Werkzeug | Version | Hinweise |
|---|---|---|
| **Flutter SDK** | ≥ 3.19 (stable) | `flutter --version` muss mindestens 3.19 anzeigen. Neuer = okay. |
| **Dart SDK** | mit Flutter gebündelt | Muss nicht separat installiert werden. |
| **Git** | beliebige aktuelle Version | |
| **Android Studio** *(nur Android)* | aktuellstes stable | Erforderlich für das Android-SDK, den Emulator und `adb`. Das Flutter-IDE-Plugin ist optional — du kannst in VS Code oder einem Editor deiner Wahl entwickeln. |
| **Visual Studio 2022 Community** *(nur Windows-Desktop)* | aktuellste | **„Desktop development with C++"**-Workload erforderlich. Ohne das schlägt `flutter build windows` bei der nativen Kompilierung fehl. |
| **Chrome** *(nur Web)* | beliebige aktuelle Version | Für `flutter run -d chrome` (Dev-Modus). Web ist **kein** offizielles Release-Ziel (siehe `docs/index.md`), bleibt aber nutzbar für schnelle UI-Iteration. |

Schnelle Überprüfung nach der Installation:

```bash
flutter doctor
```

Alles, was du anvisieren willst, muss ✅ anzeigen. Die ❌ auf Plattformen, die du nicht anvisierst, können ignoriert werden.

---

## 2. Klonen und Abhängigkeiten auflösen

```bash
git clone git@github.com:bbstudioapp/beatbitch.git
cd beatbitch/rhythm_coach
flutter pub get
flutter analyze   # sollte "No issues found!" zurückgeben
flutter test      # ~80 Unit-Tests
```

Der gesamte Flutter-Code liegt in **`rhythm_coach/`**. Das Repo-Root enthält nur die öffentlichen Docs, die Lizenz, den CI/CD-Workflow und die GitHub-Templates.

---

## 3. Ausführen pro Plattform

In jedem Fall ausgehend von `rhythm_coach/`.

### 3.1 Android

```bash
flutter run                       # USB-Gerät oder verbundener Emulator
flutter build apk --release       # Release-APK (erfordert key.properties)
flutter build apk --debug         # Debug-APK, mit dem standardmäßigen Android-Key signiert
```

`adb devices`, um zu sehen, ob dein Telefon korrekt erkannt wird. Aktiviere den **Entwicklermodus** + **USB-Debugging** auf dem Telefon. Beim ersten Start: Android bittet dich, den PC zu autorisieren (Dialogfeld auf dem Telefon).

> Um eine signierte Release-APK außerhalb der CI zu bauen, brauchst du eine `android/key.properties` mit deinem Keystore. Siehe `android/key.properties.example` für das Format. Die CI nutzt einen dedizierten Keystore, der als GitHub-Secret hinterlegt ist (vgl. `.github/RELEASE_SETUP.md`).

### 3.2 Windows-Desktop

```bash
flutter config --enable-windows-desktop   # einmalig
flutter run -d windows                    # startet die App im Debug-Modus
flutter build windows --release           # Release-Build in build/windows/x64/runner/Release/
```

Das finale Binary ist `build/windows/x64/runner/Release/rhythm_coach.exe` + seine Flutter-DLLs und Plugins. Zur Verteilung **zippe den gesamten Release-Ordner** — genau das macht der `release-windows`-CI-Job (vgl. `.github/workflows/release.yml`).

> ⚠ Unter Windows sind mehrere Funktionen by-design **deaktiviert**: Hold-Kameraprüfung, Surprise-Benachrichtigungen. Vgl. `lib/services/platform_capabilities.dart`. TTS nutzt Microsoft Julie (SAPI) mit erzwungenem Rate 0.68 / Pitch 1.22 für alle Coaches (die Android-Stimmen `fr-fr-x-*-local` existieren nicht unter SAPI).

### 3.3 Web (nur Dev — kein Release-Ziel)

```bash
flutter config --enable-web         # einmalig
flutter run -d chrome               # Dev-Modus mit Hot-Reload
flutter build web --release         # statischer Build in build/web/
```

Web dient der schnellen UI-Iteration ohne Android-Rebuild. **Es ist kein offizielles Distributionsziel** — öffentliches NSFW-Hosting wirft Probleme auf (GitHub-Pages-/Cloudflare-Pages-TOS, fragile Adult-Gate im Browser, eingeschränkte Erfahrung ohne Notifs / Vibration / ML-Kit-Kamera).

> Mehrere APIs sind im Web nicht verfügbar. Der Code nutzt bereits `defaultTargetPlatform != TargetPlatform.android`-Guards für Kamera und Surprise-Notifs — die App lädt, aber diese Funktionen sind ausgeblendet.

### 3.4 Linux

```bash
flutter config --enable-linux-desktop
flutter run -d linux
flutter build linux --release
```

Der CI-Job `release-linux` packt das Ganze als portables tar.gz (vgl. `.github/workflows/release.yml`). Dieselben Capabilities sind deaktiviert wie unter Windows (Hold-Kameraprüfung + Surprise-Notifs außerhalb des Geltungsbereichs).

**TTS**: `flutter_tts` deklariert keine Linux-Implementierung → der Service umgeht das Plugin und wählt zur Laufzeit zwischen `piper` (neuronales TTS, natürliche Stimme) und `spd-say` (espeak-ng-Fallback). Benutzerorientierte Details + piper-Installation: [LINUX_TTS.md](LINUX_TTS.md).

### 3.5 macOS (blockiert)

Blockiert durch Apple Developer ID + Notarization (~99 $/Jahr + Mac erforderlich). Nicht geplant, außer auf ausdrückliche Anfrage.

---

## 4. Inhalt personalisieren

**Der gesamte redaktionelle Inhalt liegt in `rhythm_coach/assets/`** als JSON-/MP3-Dateien. Keine Codeänderung erforderlich, um eine Session, eine Phrase, einen Coach oder eine Sprache hinzuzufügen.

### 4.1 Szenario-Sessions

Pfad: `assets/sessions/*.json` — voreingestellte Sessions des Szenario-Modus (nicht die Karriere-Sessions, die zur Laufzeit von `CareerSessionGenerator` zusammengestellt werden).

| Datei | Beschreibung |
|---|---|
| `session_initiation.json` | 8 min, progressiver Ton. Sanfte Demo. |
| `session_intense.json` | 10 min, Intervalle. |
| `session_advanced_demo.json` | Demo der fortgeschrittenen Modi (24 Steps). |
| `session_camera_test.json` | Tests der Kameraprüfung (5 Holds tip→full). |
| `session_initiation_en.json` | Englische Variante (Locale = `en`). |

**Schema**: eine Session ist `{id, name, description, duration_seconds, mode, lang, steps[], …}`. Vollständige Details in `rhythm_coach/CLAUDE.md` Abschnitt *Modèles de données* + `lib/models/session.dart`.

**Eine Session hinzufügen**:
1. Erstelle `assets/sessions/meine_session.json` mit dem erwarteten Schema.
2. Füge den Pfad zur Liste `_assetPaths` in `lib/services/session_loader.dart` hinzu.
3. Keine Änderung an `pubspec.yaml` nötig (der Ordner `assets/sessions/` ist bereits deklariert).

### 4.2 Coaches

Pfad: `assets/career/coaches/`

| Datei | Beschreibung |
|---|---|
| `coach_<id>.json` | Coach-Metadaten (sprachunabhängig) — id, name, archetype, specialties, modeWeights, voicePreset usw. |
| `coach_<id>_<lang>.json` | TTS-Phrasen des Coaches für die Locale (FR, EN…). Pool nach Mode/Tier (soft/medium/hard/boost/finale) + intros + transitions + recovery. |

Jeder Coach umfasst > 100 Zeilen + > 200 Phrasen pro Locale. KI-Beitragende können sich auf **[`docs/CONTENT_GUIDE.md`](CONTENT_GUIDE.md)** beziehen, das die erwartete Struktur Zeile für Zeile beschreibt.

**Einen Coach hinzufügen**:
1. Erstelle die `coach_<id>.json` (Metadaten).
2. Erstelle mindestens eine `coach_<id>_fr.json` (FR-Phrasen).
3. Der Coach erscheint automatisch im Karriere-Selektor, sobald die Freischalt-Bedingungen (`requirements`) erfüllt sind.

### 4.3 Strafen, Kommentare, Ambiente

| Datei | Rolle |
|---|---|
| `assets/punishments.json` (+ `_en.json`) | Fail-Phrasen + Mini-Strafsequenzen. |
| `assets/random_comments.json` (+ `_en.json`) | Zufallskommentare, die in Sessions eingefügt werden. Taktung (`min/max_interval_seconds`) anpassbar. |
| `assets/ambience_packs.json` (+ `_en.json`) | Ambiente-Packs (Mapping `SessionMode → MP3`). Redaktionell kuratiert. |
| `assets/nicknames.json` (+ `_en.json`) | Globaler Spitznamen-Pool (User-Override möglich im Profil). |

Direkte Bearbeitung — keine Codeänderung erforderlich. Beim nächsten Run konsumieren die Loader die neue Version.

### 4.4 Guidance-Beeps (Audio)

Pfad: `assets/audio/*.mp3`

| Datei | Nutzung |
|---|---|
| `tip_beep.mp3`, `head_beep.mp3`, `mid_beep.mp3`, `throat_beep.mp3`, `full_beep.mp3` | Sample pro Position (5 Ebenen vom höchsten zum tiefsten). |
| `hold_beep.mp3`, `breath_beep.mp3`, `biffle_beep.mp3` | Modus-spezifische Samples. |
| `hand_down_beep.mp3`, `hand_up_beep.mp3` | Hand-Modus: abwärts-Stroke + aufwärts-Stroke. |
| `freestyle_start.mp3`, `freestyle_end.mp3` | Start-/End-Marker für den Freestyle-Modus. |
| `finale_chime.mp3` | Orgasmus-Sound des Coaches am Sessionende. Kategorie-Varianten in `assets/audio/finale/` (derzeit leer, einzelner Fallback). |

**Einen Beep ersetzen**: lege eine neue MP3 mit dem **gleichen Dateinamen** ab. Keine Codeänderung. Für einen neuen Sample-Typ erweitere die Konstanten in `lib/services/beep_engine.dart`.

**Platzhalter neu generieren**: `bash tools/generate_beeps.sh` (benötigt `ffmpeg`). Frequenzen/Längen sind oben im Skript.

### 4.5 Hintergründe (GIF / Bilder) und Ambiente (MP3)

Pfad: `assets/backgrounds/` (gitignored) und `assets/audio/ambience/` (gitignored).

Schwere Binärdateien sind **nicht** im öffentlichen Repo — sie werden zum Build-Zeitpunkt von der CI aus Cloudflare R2 geholt (vgl. `.github/workflows/release.yml` Step *Fetch external assets from R2*). Lokal sind diese Ordner leer und die App verhält sich graceful (animierter Platzhalter für Hintergründe, Stille für Ambiente).

Um lokal mit den echten Ambienten zu arbeiten: R2-Bucket-Zugang anfragen (über ein privates Issue oder direkt beim Autor) oder eigene MP3s manuell in `assets/audio/ambience/` ablegen.

### 4.6 Internationalisierung (UI)

Die Flutter-UI konsumiert `AppLocalizations.of(context).xxx` (generiert aus `lib/l10n/app_<lang>.arb`). Um eine Sprache hinzuzufügen, eine neue ARB-Datei erstellen + die Locale zu `kSupportedLocales` (`lib/services/locale_service.dart`) hinzufügen + die redaktionellen Pendants pro Sprache erstellen (Abschnitte 4.1–4.4).

Vollständiges Verfahren: Abschnitt *Internationalisation* in `rhythm_coach/CLAUDE.md`.

---

## 5. Tests

```bash
cd rhythm_coach
flutter test                          # alle Tests
flutter test test/coach_service_test.dart   # eine bestimmte Datei
flutter test --plain-name "encore"    # nach Namen filtern
```

Keine UI-/Golden-Tests — nur reine Dart-Unit-Tests auf der Geschäftslogik (Coach-Validierung, Spitznamen, Phrasen, Milestones, Session-Generator).

Im nächsten Release wird ein separater `ci.yml`-Workflow `analyze` + `test` bei jedem PR Richtung develop/main als *required check* laufen.

---

## 6. Git-Workflow

Siehe [`CONTRIBUTING.md`](../CONTRIBUTING.de.md) Abschnitt *Code — Git-Workflow*.

Kurz:

- `feat/`-, `fix/`-, `chore/`-, `docs/`-, `ci/`-Branches → PR Richtung **`develop`**
- `release/x.y.z`-Versionsbumps → PR Richtung **`main`** (triggert den Auto-Release-Workflow, baut APK + Windows-Zip + GitHub-Release)
- `main` und `develop` sind geschützt (kein Direktpush, linear history, obligatorischer PR mit 0 Approvals required)
- Auto-Back-Merge `main → develop` nach jedem Release (Workflow `back-merge.yml`)

---

## 7. Weiterführend

- **[`rhythm_coach/CLAUDE.md`](../rhythm_coach/CLAUDE.md)** — komplette interne Architektur (Controller, Services, BeepEngine, ExcitationEngine, HumiliationEngine, ObedienceEngine, Karriere-Modus, Milestones, Badges, i18n). Das ist die Referenz-Doku, um zu verstehen, wie die App funktioniert.
- **[`docs/CONTENT_GUIDE.md`](CONTENT_GUIDE.md)** — Leitfaden zu den JSON-Formaten für Beitragende (Mensch oder KI), die Phrasen / Szenarien ohne Coden hinzufügen wollen.
- **[`docs/ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.de.md)** — Regeln für GIF-/MP3-Beiträge (verpflichtende Lizenz + Quelle).
- **[`.github/RELEASE_SETUP.md`](../.github/RELEASE_SETUP.md)** — CI/CD-Secrets, Android-Keystore, R2.
