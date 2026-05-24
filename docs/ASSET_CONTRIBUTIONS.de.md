# BeatBitch — Binär-Asset-Beiträge

> Diese Seite erklärt, wie du ein Paket aus **Hintergrund-GIFs** oder
> **Ambiente-Sounds** für BeatBitch einreichst.

**Sprachen** : [English](ASSET_CONTRIBUTIONS.md) · [Français](ASSET_CONTRIBUTIONS.fr.md) · Deutsch

---

## Warum ein separater Kanal

Schwere Binärdateien (GIFs, MP3) sind im Repo **gitignored** — sie sind
nicht auf GitHub versioniert. Du kannst sie also nicht über einen regulären
PR hinzufügen. Stattdessen reichst du sie über ein Issue mit externem
Link ein, und wir holen sie nach der Prüfung in einen privaten Bucket.

Die Code-Dateien (Config, JSON, Doku), die diese Assets referenzieren,
bleiben im Repo und durchlaufen den üblichen PR-Workflow.

## Was wir akzeptieren

- **Hintergrund-GIFs**: saubere Loops für den Session-Bildschirm, ≥ 720p,
  idealerweise < 5 MB pro Datei, ohne Wasserzeichen.
- **Ambiente-Sounds** (MP3): Drones, Pulse, Regen, Wellen, Pads — alles,
  was unter den Guidance-Beeps sitzen kann, ohne sie zu überdecken.
  Qualität ≥ 192 kbps, Dauer 30 s – 3 min, loop-tauglich.
- **Komplette Packs**: ein `mode → asset`-Mapping (rhythm / lick / biffle /
  hold / breath / hand…) mit redaktioneller Kohärenz (intim, Natur,
  Studio usw.). Packs leben in `assets/ambience_packs.json`.

## Was wir **nicht** akzeptieren

- Jedes Asset, für das du **Lizenz oder Erlaubnis nicht belegen kannst**.
  GIFs/Clips, die ohne ausdrückliche Zustimmung des Erstellers von Pornhub,
  Redgifs, OnlyFans, Twitter gescraped wurden, werden abgelehnt. Nicht aus
  Prüderie — aus rechtlicher Verantwortung, die App ist öffentlich.
- Dateien mit einem **Wasserzeichen** einer Seite, Marke oder eines
  Drittanbieter-Erstellers. Das verschmutzt visuell und setzt einem Takedown aus.
- Audio mit **verständlicher menschlicher Stimme** (Stöhnen OK, Worte nicht)
  — der TTS-Coach muss hörbar und eindeutig parsbar bleiben.
- Jeglicher Inhalt mit **Minderjährigen**, **inszenierter Nichteinwilligung**
  oder **Tieren**. Sofortige Ablehnung ohne Diskussion.

## Rechtlich saubere Quellen

Sichere Ausgangspunkte zur Beschaffung:

| Quelle | Typ | Bedingungen |
|---|---|---|
| **Freesound.org** | Ambiente-MP3 | Filter nach CC0 oder CC-BY (in CREDITS.md gutschreiben) |
| **Pixabay** / **Pexels** | SFW-Abstrakt-GIFs/Videos | Pixabay-/Pexels-Lizenz, frei für kommerzielle Nutzung |
| **YouTube Audio Library** | Pads, Drones | Public Domain oder CC, im Einzelfall prüfen |
| **Eigene Aufnahmen / Kreationen** | Alles | Du bist der Autor, klare Rechte |
| **Generative KI** (Stable Diffusion, AnimateDiff, Suno, Riffusion…) | Alles | Du hast den Prompt verfasst, aber prüfe die Lizenz des Modells |
| **Reddit / Twitter / OnlyFans mit schriftlicher Zustimmung des Erstellers** | GIFs | DM-Screenshot in der Einreichung erforderlich |

## Wie einreichen

1. **Bereite dein Pack vor**:
   - Benenne die Dateien sauber (kebab-case, beschreibendes Englisch oder
     Französisch: `deep-drone.mp3`, `intimate-rhythm-loop.gif`).
   - Füge eine `CREDITS.md`-Datei im Pack-Root hinzu, die **jede Datei**,
     ihre Quelle und Lizenz/Erlaubnis auflistet.
   - Komprimiere zu `.zip` oder `.tar.gz`.
2. **Hoste das Archiv** auf einem beliebigen Dienst: Google Drive, Dropbox,
   Mega, WeTransfer, transfer.sh… alles außer direkt auf GitHub. Der Link
   muss **mindestens 30 Tage** zugänglich bleiben.
3. **Öffne ein Issue** mit dem
   *[Asset contribution](https://github.com/bbstudioapp/beatbitch/issues/new?template=asset_contribution.md)*-Template.
   Füge den Hosting-Link ein und fülle das Inventar aus (Dateiname,
   Quelle, Lizenz für jede Datei — oder verweise auf deine CREDITS.md).
4. Auf unserer Seite prüfen wir die Lizenzen, laden herunter, laden in den
   privaten R2-Bucket hoch, aktualisieren `assets/ambience_packs.json`
   falls relevant, committen. Der Beitrag erscheint im nächsten Release.

## Empfohlenes `CREDITS.md`-Format

```markdown
# Credits

## deep-drone.mp3
- Source: https://freesound.org/people/foo/sounds/123456/
- Author: foo
- License: CC0

## intimate-rhythm-loop.gif
- Source: own work (Stable Diffusion + AnimateDiff)
- Author: <dein Handle>
- License: CC0
```

## Ablehnungen & Feedback

Wenn der Beitrag abgelehnt wird (meist: unklare Lizenzierung), bekommst
du eine Antwort im Issue mit dem, was fehlt. Du kannst korrigieren und
erneut öffnen. Ablehnungen wegen nicht belegbarer Lizenz sind systematisch
— nicht verhandelbar.
