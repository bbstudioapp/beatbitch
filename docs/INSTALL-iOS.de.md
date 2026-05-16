# BeatBitch auf iPhone / iPad installieren

> BeatBitch ist **nicht** im App Store verfügbar (der App Store erlaubt keine
> Inhalte für Erwachsene). Für iOS verwenden wir eine **installierbare
> Web-Version** (PWA). Einmal zum Home-Bildschirm hinzugefügt, verhält sie
> sich wie eine echte App: eigenes Symbol, Vollbild, keine Safari-Leiste,
> funktioniert offline nach dem ersten Laden.

**Sprachen**: [Français](INSTALL-iOS.fr.md) · [English](INSTALL-iOS.en.md) · Deutsch

---

## Bevor du beginnst

- Du brauchst ein **iPhone** oder **iPad** mit **iOS 16.4 oder neuer**.
- Du musst **Safari** verwenden (nicht Chrome oder Firefox unter iOS — Apple
  erlaubt die PWA-Installation nicht aus anderen Browsern).
- Das erste Laden erfordert eine **Internetverbindung**. Danach funktioniert
  alles offline.

---

## Installation — Schritt für Schritt

### 1. Öffne Safari und gehe zu

```
https://beatbitch.pages.dev
```

Warte, bis die Seite vollständig geladen ist (ein paar Sekunden: die gesamte
App wird heruntergeladen, inklusive Audio, damit sie danach offline
funktioniert).

### 2. Tippe auf das **Teilen**-Symbol

Es ist das Symbol unten am Bildschirm (Mitte auf iPhone, oben auf iPad), das
wie ein Quadrat mit einem Pfeil nach oben aussieht:

```
   ┌──┐
   │↑ │
   └──┘
```

### 3. Scrolle durch das Teilen-Menü

In der Liste der Aktionen suche **„Zum Home-Bildschirm"** (Symbol **+** auf
einem Quadrat). Tippe diese Option an.

> Wenn du sie nicht siehst, scrolle nach unten — je nach iOS-Version kann sie
> weiter unten in der Liste stehen.

### 4. Bestätige den Namen und tippe auf **Hinzufügen**

iOS schlägt den Namen „BeatBitch" vor. Behalte ihn so (oder ändere ihn, wenn
du Diskretion auf deinem Home-Bildschirm möchtest — zum Beispiel „Coach").

Tippe oben rechts auf **Hinzufügen**.

### 5. Starte BeatBitch über das Symbol

Verlasse Safari. Du findest das **BeatBitch**-Symbol auf deinem
Home-Bildschirm, wie jede andere App. Tippe darauf: Die App startet im
Vollbild, ohne die Safari-Leiste, genau wie eine native App.

---

## Was du wissen musst

### Offline

Nach dem ersten Start funktioniert BeatBitch **ohne Netzwerk**. Du kannst dein
iPhone in den Flugmodus versetzen: Alles funktioniert.

### Updates

Wenn BB Studio eine neue Version veröffentlicht, lädt dein iPhone sie
automatisch beim nächsten App-Start **mit Verbindung** herunter. Keine
sichtbare Update-Benachrichtigung — es geschieht im Hintergrund.

### Speicherung: Vorsicht vor der 7-Wochen-Grenze

iOS löscht den Cache einer PWA automatisch, wenn du die App **etwa 7 Wochen
lang nicht öffnest**. Wenn das passiert:

- Die App benötigt eine Internetverbindung, um neu zu laden.
- **Dein Karrierefortschritt geht verloren** (Level, Abzeichen, Milestones,
  Spitznamen, Einstellungen).

> 💡 Öffne BeatBitch mindestens einmal pro Monat, um diesen Reset zu vermeiden.

### Unterschiede zur Android-Version

Einige Funktionen sind auf iOS PWA **nicht verfügbar**:

- **Kamera-Hold-Prüfung** — verwendet die Kamera nicht.
- **Überraschungsbenachrichtigungen** — iOS erlaubt geplante Benachrichtigungen
  für PWAs nicht so frei wie Android.
- **TTS-Stimme** — du bekommst nur die auf deinem iPhone installierten
  Apple-Stimmen (nicht die Google-Stimmen von Android). Die Qualität ist
  ordentlich, aber der Ton kann weniger „streng" wirken als erwartet.
- **Hintergrund-Audio** — Safari iOS kann das Audio abschneiden, wenn du den
  Bildschirm sperrst. Halte den Bildschirm während deiner Sitzung an.

---

## Häufige Probleme

### „Die Option ‚Zum Home-Bildschirm' erscheint nicht"

Du bist wahrscheinlich nicht in Safari. Überprüfe: Wenn du Chrome oder Firefox
auf dem iPhone verwendest, funktioniert es nicht. Öffne die URL **in Safari**.

### „Die App startet offline nicht"

Das erste Laden hat die gesamte App nicht zwischengespeichert. Verbinde dein
iPhone wieder mit dem Internet, öffne BeatBitch, warte, bis sie vollständig
geladen ist, und versuche es dann erneut im Flugmodus.

### „Der Ton knistert / fällt aus"

Safari iOS hat Beschränkungen für Hintergrund-Audio. Stelle sicher, dass:

- Der Bildschirm an bleibt (**Einstellungen → Anzeige & Helligkeit →
  Automatische Sperre → Nie** während der Sitzung).
- Die Medienlautstärke (nicht der Klingelton) hochgedreht ist.
- Keine andere Audio-App läuft (Musik, Podcast).

### „Überhaupt kein Ton"

iOS blockiert manchmal die automatische Audiowiedergabe. Tippe einmal eine
beliebige Taste in der App (zum Beispiel Sitzung starten/stoppen), um das
Audio freizugeben.

---

## Deinstallieren

Tippe und halte das **BeatBitch**-Symbol auf dem Home-Bildschirm → **App
entfernen** → **Löschen**. Alle lokalen Daten werden gelöscht.

---

## Support

GitHub-Repo: [github.com/bbstudioapp/beatbitch](https://github.com/bbstudioapp/beatbitch)
Issues: Eröffne ein Issue auf Deutsch, Französisch oder Englisch.
