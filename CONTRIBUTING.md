# Contribuer à BeatBitch / Contributing to BeatBitch

🇫🇷 Tu peux écrire en français ou en anglais, partout — issues, PRs, commits.
🇬🇧 You can write in French or English, everywhere — issues, PRs, commits.

---

## Par où commencer / Where to start

Le plus simple est d'ouvrir une issue avec le bon template. Les templates
guident la rédaction et posent les bonnes questions dès le départ.

The easiest way is to open an issue with the right template. Templates guide
the wording and ask the right questions upfront.

➡ **[Ouvrir une issue / Open an issue](../../issues/new/choose)**

| Template | Quand l'utiliser / When to use |
|---|---|
| 🐛 **[Bug report](.github/ISSUE_TEMPLATE/bug_report.md)** | Crash, comportement inattendu, son qui foire, audio qui drift, etc. / Crash, unexpected behavior, broken sound, audio drift, etc. |
| 💡 **[Feature request / Idée](.github/ISSUE_TEMPLATE/feature_request.md)** | Nouveau mode, nouvelle UX, idée d'évolution carrière, etc. / New mode, new UX, career evolution idea, etc. |
| ✍ **[Content contribution](.github/ISSUE_TEMPLATE/content_contribution.md)** | Phrases coach, scénarios, surnoms, nouvelle langue, nouveau coach. / Coach lines, scenarios, nicknames, new language, new coach. |

> Les contributions éditoriales (phrases, scénarios, surnoms, traductions) sont
> **les bienvenues sans toucher au code** — le template Content guide vers le
> format JSON consommable directement par le générateur.
>
> Editorial contributions (lines, scenarios, nicknames, translations) are
> **welcome without touching code** — the Content template guides toward the
> JSON format the generator consumes directly.

---

## Code — workflow Git

Le repo suit un **GitFlow hybride** :

The repo follows a **hybrid GitFlow**:

- Branches `fix/`, `chore/`, `docs/`, `feat/` → **PR vers `develop`**
- Bumps de version `release/x.y.z` → **PR vers `main`** (déclenche le workflow
  release auto, build APK signé + Release GitHub)
- `develop` est resynchronisée depuis `main` après chaque release

`main` et `develop` sont protégées : pas de push direct, tout passe par PR
(0 approval requis mais l'historique reste linéaire).

`main` and `develop` are protected: no direct push, everything goes through PRs
(no approvals required, but linear history is enforced).

### Conventions de commit / Commit conventions

Conventional Commits, en anglais ou français — l'historique en mélange déjà :

```
feat(career): add hand+rhythm combo support
fix(beep): éviter le double trigger de hold_beep
docs(roadmap): acter Phase 6
chore(deps): bump flutter_tts to 4.2.0
```

---

## Setup local / Local setup

Tout le code Flutter vit dans **[`rhythm_coach/`](rhythm_coach/)**. Le setup
complet (deps, run, build, tests, regénération des bips placeholder) est
documenté dans [`rhythm_coach/README.md`](rhythm_coach/README.md) et
[`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md) (le second détaille
l'architecture interne).

All Flutter code lives in **[`rhythm_coach/`](rhythm_coach/)**. Full setup
(deps, run, build, tests, regenerating placeholder beeps) is documented in
[`rhythm_coach/README.md`](rhythm_coach/README.md) and
[`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md) (the latter details internal
architecture).

Quick start :

```bash
cd rhythm_coach
flutter pub get
flutter run             # device / emulator Android
flutter analyze         # doit retourner "No issues found!"
```

> ⚠ Les **assets binaires lourds** (gifs de fond, mp3 d'ambiance) sont
> gitignorés et distribués hors-repo. L'app fonctionne sans (placeholder
> animé + silence) ; demande l'accès si tu veux travailler avec les
> ambiances réelles.
>
> Heavy binary assets (background gifs, ambience mp3) are gitignored and
> distributed off-repo. The app runs fine without them (animated placeholder
> + silence); ask for access if you want to work with real ambiences.

---

## Internationalisation / i18n

L'app est prête multilingue, **seul le français est livré** aujourd'hui.
Pour ajouter une langue (ARB UI + phrases coach + sessions + ambiances),
la procédure complète est dans la section *Internationalisation* de
[`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md).

The app is multilingual-ready; **only French ships today**. Procedure to add
a language (UI ARB + coach lines + sessions + ambiences) is in the
*Internationalisation* section of
[`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md).

> Le contenu éditorial est très typé (registre cru, ton dominateur). Une
> traduction littérale ne marchera pas — prévoir une **adaptation** par
> locuteur natif.
>
> Editorial content is heavily styled (crude register, dominant tone). Literal
> translation won't work — plan a **native-speaker adaptation**.

---

## Licence / License

En contribuant tu acceptes que ton apport soit publié sous la licence du repo,
**[PolyForm Noncommercial 1.0.0](LICENSE)** (usage personnel / étude /
modification autorisés, usage commercial interdit sans accord écrit).

By contributing, you agree your contribution is published under the repo
license, **[PolyForm Noncommercial 1.0.0](LICENSE)** (personal / study /
modification allowed, commercial use forbidden without written consent).

---

## Autres ressources / Other resources

- **[Privacy / Vie privée](docs/PRIVACY.md)** — comment l'app traite (ou plutôt ne traite pas) les données / how the app handles (or rather doesn't) data
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — workflow de release auto / auto-release workflow
- **[Releases](../../releases)** — APK signés + SHA256
