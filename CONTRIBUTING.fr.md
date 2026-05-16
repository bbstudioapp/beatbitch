# Contribuer à BeatBitch

Tu peux écrire en français, en anglais ou en allemand, partout — issues, PRs, commits.

**Langues** : [English](CONTRIBUTING.md) · Français · [Deutsch](CONTRIBUTING.de.md)

---

## Par où commencer

Le plus simple est d'ouvrir une issue avec le bon template. Les templates guident la rédaction et posent les bonnes questions dès le départ.

➡ **[Ouvrir une issue](../../issues/new/choose)**

| Template | Quand l'utiliser |
|---|---|
| 🐛 **[Bug report](.github/ISSUE_TEMPLATE/bug_report.md)** | Crash, comportement inattendu, son qui foire, audio qui drift, etc. |
| 💡 **[Feature request / Idée](.github/ISSUE_TEMPLATE/feature_request.md)** | Nouveau mode, nouvelle UX, idée d'évolution carrière, etc. |
| ✍ **[Content contribution](.github/ISSUE_TEMPLATE/content_contribution.md)** | Phrases coach, scénarios, surnoms, nouvelle langue, nouveau coach. |
| 🎞 **[Asset contribution](.github/ISSUE_TEMPLATE/asset_contribution.md)** | Pack de gifs de fond ou de sons d'ambiance (MP3). |

> Les contributions éditoriales (phrases, scénarios, surnoms, traductions) sont **les bienvenues sans toucher au code** — le template Content guide vers le format JSON consommable directement par le générateur.
>
> Pour les contributions d'assets binaires (gifs / MP3), lis d'abord **[docs/ASSET_CONTRIBUTIONS.md](docs/ASSET_CONTRIBUTIONS.fr.md)** — la licence et la justification de la source sont obligatoires.

---

## Code — workflow Git

Le repo suit un **GitFlow hybride** :

- Branches `fix/`, `chore/`, `docs/`, `feat/` → **PR vers `develop`**
- Bumps de version `release/x.y.z` → **PR vers `main`** (déclenche le workflow release auto, build APK signé + Release GitHub)
- `develop` est resynchronisée depuis `main` après chaque release

`main` et `develop` sont protégées : pas de push direct, tout passe par PR (0 approval requis mais l'historique reste linéaire).

### Conventions de commit

Conventional Commits, en anglais ou français — l'historique en mélange déjà :

```
feat(career): add hand+rhythm combo support
fix(beep): éviter le double trigger de hold_beep
docs(roadmap): acter Phase 6
chore(deps): bump flutter_tts to 4.2.0
```

---

## Setup local

Tout le code Flutter vit dans **[`rhythm_coach/`](rhythm_coach/)**. Le setup complet (deps, run, build, tests, regénération des bips placeholder) est documenté dans [`rhythm_coach/README.fr.md`](rhythm_coach/README.fr.md) et [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md) (le second détaille l'architecture interne).

Quick start :

```bash
cd rhythm_coach
flutter pub get
flutter run             # device / emulator Android
flutter analyze         # doit retourner "No issues found!"
```

> ⚠ Les **assets binaires lourds** (gifs de fond, mp3 d'ambiance) sont gitignorés et distribués hors-repo. L'app fonctionne sans (placeholder animé + silence) ; demande l'accès si tu veux travailler avec les ambiances réelles.

---

## Internationalisation

L'app est livrée en **français, anglais et allemand**. Pour ajouter une autre langue (ARB UI + phrases coach + sessions + ambiances), la procédure complète est dans la section *Internationalisation* de [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md).

> Le contenu éditorial est très typé (registre cru, ton dominateur). Une traduction littérale ne marchera pas — prévoir une **adaptation** par locuteur natif.

---

## Licence

En contribuant tu acceptes que ton apport soit publié sous la licence du repo, **[PolyForm Noncommercial 1.0.0](LICENSE)** (usage personnel / étude / modification autorisés, usage commercial interdit sans accord écrit).

---

## Autres ressources

- **[Vie privée](docs/PRIVACY.fr.md)** — comment l'app traite (ou plutôt ne traite pas) les données
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — workflow de release auto
- **[Releases](../../releases)** — APK signés + SHA256
