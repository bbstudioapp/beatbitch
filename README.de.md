# BeatBitch

![version](https://img.shields.io/badge/version-0.4.0-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Web-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)
![no tracking](https://img.shields.io/badge/no-tracking-success)
![license](https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-lightgrey)

> **Immersiver rhythmischer Sprach-Coach für Android, Windows, Linux, iOS (PWA) & Web.** Leg dein Handy flach auf die Seite, starte die Session, schließ die Augen. Eine Stimme führt dich, Beeps geben den Rhythmus vor — du musst nicht mehr auf den Bildschirm schauen.

**Sprachen**: [English](README.md) · [Français](README.fr.md) · Deutsch

---

## In 30 Sekunden

- Eine **Coach-Stimme**, die deine Sprache spricht, lokal — keine Netzwerksynthese.
- **Guidance-Beeps**, fest an ein BPM gebunden, takten jede Bewegung.
- 8 Spielmodi, ein Karriere-Modus, der sich nach und nach freischaltet, Coaches mit unterschiedlichen Persönlichkeiten.
- **100 % offline** auf Android: die `INTERNET`-Berechtigung wird nicht deklariert, nichts verlässt dein Handy.
- **Kein Play Store, keine Werbung, keine In-App-Käufe.** Direktvertrieb als signierte APK (Android), portables Zip (Desktop), installierbare Web-App (iOS / Browser).

## 📥 Herunterladen

➡ **[Releases-Seite](../../releases)** — signierte APK + zugehöriger SHA256.

> ⚠ Android 9 Minimum. Getestet auf Android 13/14.

## 📲 Auf Android installieren (Side-Load, Schritt für Schritt)

**Side-Load** heißt einfach „eine App außerhalb des Play Store installieren". Android unterstützt das nativ — du musst nur deinem Browser oder Dateimanager die Erlaubnis dafür geben.

1. **Auf deinem Handy** öffne die [Releases-Seite](../../releases) und lade die aktuelle `BeatBitch-X.Y.Z.apk` herunter.
2. (*Optional aber empfohlen*) Prüfe, ob der SHA256-Hash der heruntergeladenen Datei mit dem neben der APK veröffentlichten übereinstimmt. Eine App wie **Hash Droid** auf F-Droid macht das mit zwei Taps.
3. Öffne die APK aus deinen Downloads.
4. Android fragt dich, ob du **diese Quelle zulassen** willst: tippe auf „Einstellungen", aktiviere die Berechtigung für deinen Browser (oder Dateimanager), geh zurück und bestätige.
5. Die Installation läuft. Wenn sie fertig ist, öffne BeatBitch.
6. **Erster Start**: 18+-Bestätigung (nicht überspringbar), dann 3 Onboarding-Screens (Handy-Position, Lautstärke, Stimmprobe).

> 💡 Du kannst „Unbekannte Quellen" nach der Installation wieder deaktivieren — Android öffnet sie erst wieder, wenn du die App aktualisierst.

## 🍎 Auf iPhone / iPad installieren (PWA)

BeatBitch ist **nicht** im App Store verfügbar (Apple erlaubt keine Erwachseneninhalte). Auf iOS liefern wir eine **installierbare Web-Version** (PWA). Einmal auf den Home-Bildschirm gelegt, verhält sie sich wie eine echte App: eigenes Icon, Vollbild, keine Safari-Leiste, läuft nach dem ersten Laden offline.

1. Auf deinem iPhone / iPad (iOS 16.4+) öffne **Safari** (nicht Chrome / Firefox — Apple blockiert die PWA-Installation aus diesen Browsern).
2. Geh auf **[beatbitch.pages.dev](https://beatbitch.pages.dev)** und warte, bis die Seite vollständig geladen ist (die gesamte App wird beim ersten Mal heruntergeladen).
3. Tippe auf den **Teilen**-Button → **Zum Home-Bildschirm** → **Hinzufügen**.
4. Starte BeatBitch vom Home-Bildschirm. Erster Start: 18+-Adult-Gate, dann 3-Schritt-Onboarding.

> Detaillierte Anleitung: **[docs/INSTALL-iOS.de.md](docs/INSTALL-iOS.de.md)**.
>
> ⚠ Die Web/iOS-Version nutzt die **native iOS-Sprachsynthese** (keine Android-Stimmen). Die Kameraprüfung bei Holds und die Surprise-Benachrichtigungen sind nicht verfügbar. Der erste Ladevorgang braucht eine Internetverbindung; alles Weitere läuft offline vom Home-Icon aus.

## 🌐 Im Desktop-Browser nutzen

Selbe URL wie auf iOS — **[beatbitch.pages.dev](https://beatbitch.pages.dev)** funktioniert in jedem aktuellen Browser (Chrome, Edge, Firefox, Safari). Praktisch, um die App auszuprobieren, bevor du die APK oder den Desktop-Build installierst. Die Stimmqualität hängt vom TTS-Engine deines OS ab.

## 🖥 Auf Windows-Desktop installieren

Verfügbar ab **v0.1.3**. Portables Zip — kein Installer, keine Registry- oder Systemordner-Schreibvorgänge.

1. Auf der [Releases-Seite](../../releases) lade `BeatBitch-X.Y.Z-windows-x64.zip` herunter (und die zugehörige `.sha256`, wenn du die Integrität prüfen willst).
2. Entpacke, wohin du willst: `C:\Users\du\Documents\BeatBitch\`, USB-Stick, egal.
3. Starte `rhythm_coach.exe`. Windows SmartScreen kann eine Warnung anzeigen (Binärdatei nicht von einem bekannten Herausgeber signiert) → klick auf *Weitere Informationen* → *Trotzdem ausführen*.
4. Erster Start: 18+-Adult-Gate, dann 3-Schritt-Onboarding (identisch zu Android).

> ⚠ **Deaktiviert auf Windows**: Kameraprüfung bei Holds und Surprise-Benachrichtigungen sind nicht portiert (die nativen Plugins haben keine Windows-Implementierung). Die Coach-Stimme nutzt **Microsoft Julie** (SAPI) statt der Android-Stimmen. Sessions, Karriere-Modus, Coaches, Badges, Sprachen: alles funktioniert identisch zu Android.

## 🐧 Auf Linux-Desktop installieren

Verfügbar ab **v0.3.0**. Portables `tar.gz` — kein `.deb`/`.rpm`-Paket, die App bleibt in ihrem Ordner und nichts wird systemweit installiert.

1. Auf der [Releases-Seite](../../releases) lade `BeatBitch-X.Y.Z-linux-x64.tar.gz` herunter (und die zugehörige `.sha256`, um die Integrität zu prüfen).
2. Prüfe den Hash: `sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256`.
3. Entpacke, wohin du willst: `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Starte das Binary: `./BeatBitch-X.Y.Z-linux-x64/beat_bitch` (Rechtsklick → *Ausführen erlauben* im Dateimanager, falls nötig).
5. Erster Start: 18+-Adult-Gate, dann 3-Schritt-Onboarding (identisch zu Android).

> ⚠ **Deaktiviert auf Linux**: Kameraprüfung bei Holds und Surprise-Benachrichtigungen sind nicht portiert. Die Coach-Stimme nutzt die Standardstimme des **Speech Dispatcher** (typischerweise `espeak-ng` auf Ubuntu/Debian — installier eine deutsche/englische Stimme über deinen Paketmanager, wenn die Standardstimme nicht gut klingt). Sessions, Karriere-Modus, Coaches, Badges, Sprachen: alles funktioniert identisch zu Android.

## 🔄 Automatische Updates (Obtainium)

Die Android-App bleibt **strikt offline** — sie holt sich keine Updates von selbst. Um benachrichtigt zu werden, wenn eine neue Version erscheint, und sie mit zwei Taps zu installieren, nutze **[Obtainium](https://github.com/ImranR98/Obtainium)**, einen Open-Source-Android-Store, der GitHub-Releases-Seiten beobachtet.

1. Installiere Obtainium (verfügbar auf [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/) oder als direkte APK aus dem zugehörigen Repo).
2. In Obtainium: *Add App* → fügst du die URL `https://github.com/bbstudioapp/beatbitch` ein.
3. Bei jedem neuen Release erkennt Obtainium die `BeatBitch-X.Y.Z.apk` und schlägt dir das Update vor.

> BeatBitch selbst erzeugt keinen Netzwerktraffic — Obtainium fragt GitHub auf der Nutzerseite ab, unabhängig von der App. Das 100-%-Offline-Versprechen bleibt intakt.

## 🔒 Ist das sicher?

- **APK signiert** mit demselben Schlüssel bei jedem Release — Android verweigert die Installation einer manipulierten APK (die Signatur stimmt dann nicht).
- **Quellcode öffentlich** — du kannst nachlesen, was läuft (oder es nachlesen lassen).
- **Keine Netzwerkberechtigung** (Android) — weder `INTERNET` noch `ACCESS_NETWORK_STATE`. Die Android-App *kann* buchstäblich keinen Server aufrufen.
- **`allowBackup="false"`** — keine Übertragung an Google Backup.
- **Kamera ist opt-in** — die Kameraprüfung bei Holds ist standardmäßig aus, und die Verarbeitung läuft zu 100 % on-device (Google ML Kit lokal). Kein Bild verlässt das Handy.

Details in **[PRIVACY.md](docs/PRIVACY.md)** ([veröffentlichte Version](https://bbstudioapp.github.io/beatbitch/PRIVACY)).

## 🎮 Wie wird gespielt

1. Leg dein Handy flach auf die Seite — du musst es nicht im Blick haben.
2. Wähl eine voreingestellte Session oder lass den Karriere-Modus eine für dich generieren.
3. Folge der Stimme. Beeps geben den Takt (ein tiefer + ein hoher abwechselnd, oder nur einer, wenn du eine Position halten sollst).
4. Der **„Ich kann nicht"**-Button ist immer verfügbar, falls du aussteigst. Die Coach übernimmt mit einer kurzen Strafe, dann setzt die Session dort fort, wo es Sinn ergibt.
5. Am Ende zeigt der Bildschirm, was du freigeschaltet hast (Badges, Karriere-Level, Milestones).

## 🐛 Einen Bug gefunden, eine Idee, mitmachen?

Issue-Templates verfügbar:
- 🐛 [Bug](.github/ISSUE_TEMPLATE/bug_report.md) · 💡 [Idee / Feature](.github/ISSUE_TEMPLATE/feature_request.md) · ✍ [Coach-Phrasen / Szenarien / Übersetzung](.github/ISSUE_TEMPLATE/content_contribution.md)

Alles ist in **[CONTRIBUTING.md](CONTRIBUTING.md)** erklärt.

> **Redaktionelle** Beiträge (Coach-Phrasen, Szenarien, Spitznamen, neue Sprachen) sind die wertvollsten und brauchen **keinerlei technische Kenntnisse**. Das Content-Template führt dich zum richtigen Format.
>
> KI-Beitragende (ChatGPT, Claude usw.) können sich auf **[docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md)** beziehen — strukturierter Leitfaden zu den vom Generator akzeptierten JSON-Formaten.

## 🛠 Neugierig auf den Code?

Das gesamte Flutter-Projekt liegt in **[`rhythm_coach/`](rhythm_coach/)**:
- **[Entwickler-Setup](docs/DEVELOPMENT.md)** — Flutter installieren, plattformspezifisch starten (Android, Windows, Web Chrome), Assets ohne Coden anpassen
- **[Voller Dev-README](rhythm_coach/README.md)** — detaillierte Features, lokaler Build, Tests
- **[Architektur](rhythm_coach/CLAUDE.md)** — Session-Flow, Erregungs-Engine, Karriere-Modus, i18n
- **[CI/CD-Setup](.github/RELEASE_SETUP.md)** — Auto-Release-Workflow

## 📝 Lizenz

Code und redaktionelle Inhalte unter **[PolyForm Noncommercial 1.0.0](LICENSE)**.

- ✅ Private Nutzung, Studium, Modifikation, Fork, nicht-kommerzielle Weitergabe.
- ❌ Verkauf, Monetarisierung, „Premium"-Fork auf Telegram / Gumroad / alternativem Store.

Off-Repo-Binärdateien (Hintergrund-GIFs und Ambiente-MP3s) unterliegen weiterhin den Rechten ihrer Originalquellen.
