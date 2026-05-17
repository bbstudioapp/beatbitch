# BeatBitch

![version](https://img.shields.io/badge/version-0.4.1-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)

> Immersiver rhythmischer Sprach-Coach. Das Handy liegt auf der Seite — du musst nicht auf den Bildschirm schauen. Alles wird durch Stimme und Guidance-Beeps gesteuert.

**Sprachen** : [English](README.md) · [Français](README.fr.md) · Deutsch

---

## Screenshots

> _Demnächst — die App ist in privater Alpha._

<p>
  <em>placeholder</em> · Startseite · Session · Sounds · Profil · Badges
</p>

## Funktionen

- **Weibliche TTS-Coach-Stimme**, fester Ton, ausschließlich lokal (keine Netzwerksynthese).
- **8 Spielmodi**: rhythm, lick, biffle, hold, breath, beg, freestyle, hand.
- **Karriere-Modus**: 20+ Level, 6 Spezialisierungszweige, Lern-Milestones, verkettete Encores, Quickie-Sessions, Fortschritts-Badges.
- **Freie Szenarien**: editierbare JSON-Sessions, erweiterbare Strafen und Zufallskommentare ohne Codeänderung.
- **Hold-Kameraprüfung** (experimentell, opt-in): On-Device-Erkennung via Google ML Kit — kein Bild verlässt jemals das Gerät.
- **Mehrsprachig**: Französisch, Englisch und Deutsch ausgeliefert; weitere Sprachen = einfaches Hinzufügen von Assets.
- **18+-Adult-Gate** nicht überspringbar beim ersten Start, 3-Schritt-Onboarding.

## 100 % offline · keine Telemetrie

Keine Daten verlassen dein Handy. Die `INTERNET`-Berechtigung wird nicht deklariert. ML Kit läuft lokal. Siehe [PRIVACY.md](PRIVACY.md).

## Installation (Android Side-Load)

Die App wird **nicht über den Play Store verteilt** — nur manuelle Installation.

1. Lade die APK von der Releases-Seite des Repos herunter.
2. Prüfe den neben der APK veröffentlichten SHA256:
   ```bash
   sha256sum BeatBitch-X.Y.Z.apk
   ```
3. Auf dem Handy: erlaube Installationen aus unbekannten Quellen für deinen Dateimanager / Browser.
4. Öffne die APK und bestätige die Installation.
5. Erster Start: 18+-Adult-Gate, dann 3-Schritt-Onboarding.

> ⚠ Android 9+ erforderlich. Getestet auf Android 13/14.

## Installation (Windows-Desktop)

Verfügbar ab v0.1.3 — portables Zip, kein Installer.

1. Lade `BeatBitch-X.Y.Z-windows-x64.zip` von der Releases-Seite herunter.
2. Prüfe den SHA256:
   ```powershell
   Get-FileHash BeatBitch-X.Y.Z-windows-x64.zip -Algorithm SHA256
   ```
3. Entpacke wohin du willst (`Documents\BeatBitch\`, USB-Stick, …).
4. Starte `rhythm_coach.exe`. Windows SmartScreen warnt eventuell (unsigniertes
   Binary) → klick auf *Weitere Informationen* → *Trotzdem ausführen*.
5. Erster Start: 18+-Adult-Gate, dann 3-Schritt-Onboarding.

> ⚠ Deaktiviert auf Windows: Hold-Kameraprüfung, Surprise-Benachrichtigungen.
> Die Coach-Stimme nutzt Microsoft Julie (SAPI). Alles andere — Sessions,
> Karriere-Modus, Coaches, Badges, i18n — funktioniert identisch zu Android.

## Installation (Linux-Desktop)

Verfügbar ab v0.3.0 — portables `tar.gz`, kein `.deb`/`.rpm`-Paket.

1. Lade `BeatBitch-X.Y.Z-linux-x64.tar.gz` von der Releases-Seite herunter.
2. Prüfe den SHA256:
   ```bash
   sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256
   ```
3. Entpacke wohin du willst: `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Starte das Binary: `./BeatBitch-X.Y.Z-linux-x64/beat_bitch`.
5. Erster Start: 18+-Adult-Gate, dann 3-Schritt-Onboarding.

> ⚠ Deaktiviert auf Linux: Hold-Kameraprüfung, Surprise-Benachrichtigungen.
> Die Coach-Stimme nutzt die Standardstimme des Speech Dispatcher
> (typischerweise `espeak-ng`). Alles andere — Sessions, Karriere-Modus,
> Coaches, Badges, i18n — funktioniert identisch zu Android.

## Automatische Updates (Obtainium)

Die App bleibt **strikt offline** — sie sucht nicht von selbst nach Updates. Um benachrichtigt zu werden, wenn eine neue Version erscheint, nutze **[Obtainium](https://github.com/ImranR98/Obtainium)**, einen Open-Source-Android-Store, der GitHub-Releases-Seiten beobachtet. *Add App* → fügst du `https://github.com/bbstudioapp/beatbitch` ein. BeatBitch selbst erzeugt keinen Netzwerktraffic — Obtainium fragt GitHub auf der Nutzerseite ab, unabhängig von der App.

## Lokaler Build (Entwickler)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # sollte "No issues found!" zurückgeben
flutter test
flutter run           # verbundenes Android-Gerät / `-d windows` / `-d chrome`
flutter build apk --release
flutter build windows --release
```

Der redaktionelle Inhalt liegt in `assets/` (JSON-Sessions, Strafen, Zufallskommentare, Ambiente-Packs, Karriere-Phrasenbank). Vollständige plattformspezifische Einrichtung + Anpassungspfade: **[`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.de.md)**.

> ⚠ **Externalisierte Binär-Assets**: die Ordner `assets/backgrounds/` (Hintergrund-GIFs/Bilder) und `assets/audio/ambience/` (Ambiente-MP3s) sind **gitignored** — ihre Dateien sind nicht im Repo versioniert und müssen vor `flutter build` aus einem externen Kanal (TBD) bezogen werden. Der Code verhält sich graceful, wenn diese Ordner leer sind: der Hintergrund fällt auf einen animierten Verlauf zurück, die Ambience auf Stille.

## Datenschutz

Siehe [PRIVACY.md](PRIVACY.md) — Kurzfassung: keine Erfassung, alles ist lokal, `allowBackup="false"`.

## Lizenz

Code und redaktionelle Inhalte (JSON-Sessions, Coach-Phrasen, Zufallskommentare, Spitznamen, Milestones usw.) veröffentlicht unter der **[PolyForm Noncommercial License 1.0.0](../LICENSE)**.

- ✅ **Studieren, forken, modifizieren, weitergeben** zu nicht-kommerziellen Zwecken.
- ✅ **Beiträge willkommen** — neue Coach-Phrasen, Sessions, Übersetzungen, Code-Fixes, Spezialisierungsideen usw. Öffne ein Issue oder einen PR.
- ❌ **Keine kommerzielle Nutzung, kein Verkauf, keine bezahlte Weitergabe** — kein „BeatBitch Premium"-Fork auf Telegram, Gumroad oder einem alternativen Store.

Off-Repo-Binär-Assets (`assets/backgrounds/*.gif`, `assets/audio/ambience/*.mp3`) unterliegen weiterhin den Rechten ihrer Originalquellen und sind nicht von dieser Lizenz abgedeckt.

## Bug-Reports

Öffne ein Issue im Repo. Bitte gib Gerätemodell, Android-Version und Schritte zur Reproduktion an.
