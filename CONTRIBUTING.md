# Contributing to BeatBitch

You can write in French, English or German, everywhere — issues, PRs, commits.

**Languages**: English · [Français](CONTRIBUTING.fr.md) · [Deutsch](CONTRIBUTING.de.md)

---

## Where to start

The easiest way is to open an issue with the right template. Templates guide the wording and ask the right questions upfront.

➡ **[Open an issue](../../issues/new/choose)**

| Template | When to use |
|---|---|
| 🐛 **[Bug report](.github/ISSUE_TEMPLATE/bug_report.md)** | Crash, unexpected behavior, broken sound, audio drift, etc. |
| 💡 **[Feature request](.github/ISSUE_TEMPLATE/feature_request.md)** | New mode, new UX, career evolution idea, etc. |
| ✍ **[Content contribution](.github/ISSUE_TEMPLATE/content_contribution.md)** | Coach lines, scenarios, nicknames, new language, new coach. |
| 🎞 **[Asset contribution](.github/ISSUE_TEMPLATE/asset_contribution.md)** | Background gifs pack or ambience sounds (MP3). |

> Editorial contributions (lines, scenarios, nicknames, translations) are **welcome without touching code** — the Content template guides toward the JSON format the generator consumes directly.
>
> For binary asset contributions (gifs / MP3), read **[docs/ASSET_CONTRIBUTIONS.md](docs/ASSET_CONTRIBUTIONS.md)** first — the license and source justification are mandatory.

---

## Code — Git workflow

The repo follows a **hybrid GitFlow**:

- `fix/`, `chore/`, `docs/`, `feat/` branches → **PR towards `develop`**
- `release/x.y.z` version bumps → **PR towards `main`** (triggers the auto-release workflow, builds signed APK + GitHub Release)
- `develop` is resynchronized from `main` after each release

`main` and `develop` are protected: no direct push, everything goes through PRs (no approvals required, but linear history is enforced).

### Commit conventions

Conventional Commits, in English or French — the history already mixes both:

```
feat(career): add hand+rhythm combo support
fix(beep): éviter le double trigger de hold_beep
docs(roadmap): acter Phase 6
chore(deps): bump flutter_tts to 4.2.0
```

---

## Local setup

All Flutter code lives in **[`rhythm_coach/`](rhythm_coach/)**. Full setup (deps, run, build, tests, regenerating placeholder beeps) is documented in [`rhythm_coach/README.md`](rhythm_coach/README.md) and [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md) (the latter details internal architecture).

Quick start:

```bash
cd rhythm_coach
flutter pub get
flutter run             # Android device / emulator
flutter analyze         # should return "No issues found!"
```

> ⚠ Heavy binary assets (background gifs, ambience mp3) are gitignored and distributed off-repo. The app runs fine without them (animated placeholder + silence); ask for access if you want to work with real ambiences.

---

## i18n

The app ships in **French, English and German**. To add another language (UI ARB + coach lines + sessions + ambiences), the complete procedure is in the *Internationalisation* section of [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md).

> Editorial content is heavily styled (crude register, dominant tone). Literal translation won't work — plan a **native-speaker adaptation**.

---

## License

By contributing, you agree your contribution is published under the repo license, **[PolyForm Noncommercial 1.0.0](LICENSE)** (personal / study / modification allowed, commercial use forbidden without written consent).

---

## Other resources

- **[Privacy](docs/PRIVACY.md)** — how the app handles (or rather doesn't) data
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — auto-release workflow
- **[Releases](../../releases)** — signed APKs + SHA256
