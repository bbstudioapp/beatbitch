# Datenschutzerklärung — BeatBitch

_Zuletzt aktualisiert: 2026-05-08 · App-Version 0.1.0_

**Sprachen** : [English](PRIVACY.md) · [Français](PRIVACY.fr.md) · Deutsch

---

## In einem Satz

**BeatBitch ist 100 % offline. Keine Daten verlassen jemals dein Handy.**

## Details

- **Keine Telemetrie, kein Analytics, kein Crash-Reporter.** Kein Drittanbieter-Tracking-SDK.
- **Kein Konto, keine Kennung.** Die App fragt nicht nach E-Mail, Benutzername oder Telefonnummer.
- **Die `INTERNET`-Berechtigung wird nicht deklariert** im Android-Manifest. Das Betriebssystem verweigert daher jeden Netzwerkverbindungsversuch, auch einen hypothetischen.
- **`CAMERA`-Berechtigung**: optional, nur angefordert, wenn du den Schalter „Hold-Kameraprüfung" im SOUNDS-Bildschirm aktivierst. Der Videostream wird **lokal** von Google ML Kit (On-Device-Modell) verarbeitet, um die Gesichtsposition zu erkennen. Kein Bild, kein Landmark, keine Metadaten werden an einen Server übertragen. Der Stream wird niemals auf die Festplatte geschrieben.
- **Ausschließlich lokale Speicherung**: deine Einstellungen (Lautstärke, TTS-Stimme, Sprache, Kamerakalibrierung) und Spielstatistiken (Zähler, Badges, Level, Humiliation/Obedience-Anzeigen) werden via `SharedPreferences` in der App-Sandbox gespeichert.
- **`android:allowBackup="false"`** im Manifest: kein automatisches Backup in die Google-Cloud. Wenn du die App deinstallierst, sind deine Daten weg.
- **Nur lokales TTS**: die Stimme wird vom auf deinem Gerät installierten Android-Text-to-Speech-Engine synthetisiert. Keine Netzwerksynthese (die `-network`-Stimmen des Engines werden explizit herausgefiltert).
- **Audio**: die App spielt nur die Beeps und Samples, die in der APK gebündelt sind. Kein Streaming, keine Downloads.

## ML-Kit-Modell

Beim ersten Start lädt Google ML Kit möglicherweise automatisch sein Gesichtserkennungsmodell (~3 MB) **über Google Play Services** herunter, unabhängig von der App. Dieser Download wird von Android selbst erledigt, nicht von BeatBitch — die App macht weiterhin keine eigenen Netzwerkaufrufe. Das Modell bleibt dann lokal und funktioniert offline.

## Kontakt

Bug-Reports, Fragen, Klarstellungen: öffne ein Issue im Projekt-Repo. Keine Support-E-Mail für diese Alpha-Version.

## Änderungen

Diese Erklärung kann sich weiterentwickeln, wenn die App neue Funktionen bekommt. Jede Aktualisierung wird im Release-Changelog angekündigt und das Datum oben in dieser Datei aktualisiert.
