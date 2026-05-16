# Zu BeatBitch beitragen

Du kannst überall auf Französisch, Englisch oder Deutsch schreiben — Issues, PRs, Commits.

**Sprachen** : [English](CONTRIBUTING.md) · [Français](CONTRIBUTING.fr.md) · Deutsch

---

## Wo anfangen

Am einfachsten ist es, ein Issue mit dem passenden Template zu öffnen. Die Templates leiten die Formulierung an und stellen die richtigen Fragen von Anfang an.

➡ **[Ein Issue öffnen](../../issues/new/choose)**

| Template | Wann nutzen |
|---|---|
| 🐛 **[Bug report](.github/ISSUE_TEMPLATE/bug_report.md)** | Crash, unerwartetes Verhalten, kaputter Sound, Audio-Drift usw. |
| 💡 **[Feature request](.github/ISSUE_TEMPLATE/feature_request.md)** | Neuer Modus, neue UX, Karriereentwicklungsidee usw. |
| ✍ **[Content contribution](.github/ISSUE_TEMPLATE/content_contribution.md)** | Coach-Phrasen, Szenarien, Spitznamen, neue Sprache, neuer Coach. |
| 🎞 **[Asset contribution](.github/ISSUE_TEMPLATE/asset_contribution.md)** | Hintergrund-GIF-Pack oder Ambient-Sounds (MP3). |

> Redaktionelle Beiträge (Phrasen, Szenarien, Spitznamen, Übersetzungen) sind **willkommen, ohne den Code anzufassen** — das Content-Template führt zum JSON-Format, das der Generator direkt konsumiert.
>
> Für Beiträge binärer Assets (GIFs / MP3) lies zuerst **[docs/ASSET_CONTRIBUTIONS.md](docs/ASSET_CONTRIBUTIONS.de.md)** — Lizenz und Quellenangabe sind verpflichtend.

---

## Code — Git-Workflow

Das Repo folgt einem **hybriden GitFlow**:

- `fix/`-, `chore/`-, `docs/`-, `feat/`-Branches → **PR Richtung `develop`**
- `release/x.y.z`-Versionsbumps → **PR Richtung `main`** (triggert den Auto-Release-Workflow, baut signierte APK + GitHub-Release)
- `develop` wird nach jedem Release aus `main` resynchronisiert

`main` und `develop` sind geschützt: kein Direktpush, alles läuft über PRs (keine Approvals erforderlich, aber linear history wird erzwungen).

### Commit-Konventionen

Conventional Commits, auf Englisch oder Französisch — die Historie mischt bereits beides:

```
feat(career): add hand+rhythm combo support
fix(beep): éviter le double trigger de hold_beep
docs(roadmap): acter Phase 6
chore(deps): bump flutter_tts to 4.2.0
```

---

## Lokales Setup

Der gesamte Flutter-Code liegt in **[`rhythm_coach/`](rhythm_coach/)**. Das vollständige Setup (Deps, Run, Build, Tests, Regenerierung der Platzhalter-Beeps) ist in [`rhythm_coach/README.de.md`](rhythm_coach/README.de.md) und [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md) dokumentiert (Letztere beschreibt die interne Architektur).

Quick start:

```bash
cd rhythm_coach
flutter pub get
flutter run             # Android-Gerät / Emulator
flutter analyze         # sollte "No issues found!" zurückgeben
```

> ⚠ Die **schweren Binär-Assets** (Hintergrund-GIFs, Ambient-MP3) sind gitignored und werden außerhalb des Repos verteilt. Die App läuft auch ohne sie (animierter Platzhalter + Stille); fordere Zugang an, wenn du mit den echten Ambienten arbeiten willst.

---

## Internationalisierung

Die App wird in **Französisch, Englisch und Deutsch** ausgeliefert. Um eine weitere Sprache hinzuzufügen (UI-ARB + Coach-Phrasen + Sessions + Ambiente), findest du das vollständige Verfahren im Abschnitt *Internationalisation* von [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md).

> Der redaktionelle Inhalt ist stark stilisiert (derber Ton, dominantes Register). Eine wörtliche Übersetzung funktioniert nicht — eine **Adaption durch einen Muttersprachler** einplanen.

---

## Lizenz

Mit deinem Beitrag stimmst du zu, dass deine Mitwirkung unter der Repo-Lizenz **[PolyForm Noncommercial 1.0.0](LICENSE)** veröffentlicht wird (private / Studien- / Modifikationsnutzung erlaubt, kommerzielle Nutzung ohne schriftliche Zustimmung verboten).

---

## Weitere Ressourcen

- **[Datenschutz](docs/PRIVACY.de.md)** — wie die App die Daten verarbeitet (oder eben nicht)
- **[CI/CD-Setup](.github/RELEASE_SETUP.md)** — Auto-Release-Workflow
- **[Releases](../../releases)** — signierte APKs + SHA256
