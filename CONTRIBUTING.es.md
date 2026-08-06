# Contribuir a BeatBitch

Puedes escribir en francés, inglés, alemán o español, en cualquier sitio — issues, PRs, commits.

**Idiomas** : [English](CONTRIBUTING.md) · [Français](CONTRIBUTING.fr.md) · [Deutsch](CONTRIBUTING.de.md) · Español

---

## Por dónde empezar

Lo más simple es abrir un issue con la plantilla correcta. Las plantillas guían la redacción y hacen las preguntas adecuadas desde el principio.

➡ **[Abrir un issue](../../issues/new/choose)**

| Plantilla | Cuándo usarla |
|---|---|
| 🐛 **[Bug report](.github/ISSUE_TEMPLATE/bug_report.md)** | Crash, comportamiento inesperado, sonido roto, drift de audio, etc. |
| 💡 **[Feature request](.github/ISSUE_TEMPLATE/feature_request.md)** | Nuevo modo, nueva UX, idea de evolución de carrera, etc. |
| ✍ **[Content contribution](.github/ISSUE_TEMPLATE/content_contribution.md)** | Frases del coach, escenarios, apodos, nuevo idioma, nuevo coach. |
| 🎞 **[Asset contribution](.github/ISSUE_TEMPLATE/asset_contribution.md)** | Pack de GIFs de fondo o sonidos de ambiente (MP3). |

> Las contribuciones editoriales (frases, escenarios, apodos, traducciones) son **bienvenidas sin tocar el código** — la plantilla Content guía hacia el formato JSON que consume directamente el generador.
>
> Para las contribuciones de assets binarios (GIFs / MP3), lee primero **[docs/ASSET_CONTRIBUTIONS.md](docs/ASSET_CONTRIBUTIONS.md)** — la licencia y la justificación de la fuente son obligatorias.

---

## Código — workflow Git

El repo sigue un **GitFlow híbrido**:

- Ramas `fix/`, `chore/`, `docs/`, `feat/` → **PR hacia `develop`**
- Bumps de versión `release/x.y.z` → **PR hacia `main`** (dispara el workflow de auto-release, build APK firmado + Release GitHub)
- `develop` se resincroniza desde `main` después de cada release

`main` y `develop` están protegidas: sin push directo, todo pasa por PR (no se requieren approvals, pero se exige historial lineal).

### Convenciones de commit

Conventional Commits, en inglés o francés — el historial ya mezcla ambos:

```
feat(career): add hand+rhythm combo support
fix(beep): éviter le double trigger de hold_beep
docs(roadmap): acter Phase 6
chore(deps): bump flutter_tts to 4.2.0
```

---

## Setup local

Todo el código Flutter vive en **[`rhythm_coach/`](rhythm_coach/)**. El setup completo (deps, run, build, tests, regenerar los bips placeholder) está documentado en [`rhythm_coach/README.es.md`](rhythm_coach/README.es.md) y [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md) (este último detalla la arquitectura interna).

Inicio rápido:

```bash
cd rhythm_coach
flutter pub get
flutter run             # dispositivo / emulador Android
flutter analyze         # debe devolver "No issues found!"
```

> ⚠ Los **assets binarios pesados** (GIFs de fondo, MP3 de ambiente) están gitignorados y se distribuyen fuera del repo. La app funciona sin ellos (placeholder animado + silencio); pide acceso si quieres trabajar con los ambientes reales.

---

## Internacionalización

La app se entrega en **francés, inglés, alemán y español**. Para añadir otro idioma (ARB de UI + frases del coach + sesiones + ambientes), el procedimiento completo está en la sección *Internationalisation* de [`rhythm_coach/CLAUDE.md`](rhythm_coach/CLAUDE.md).

> El contenido editorial está muy marcado (registro crudo, tono dominante). Una traducción literal no funciona — prevé una **adaptación por un hablante nativo**.

---

## Licencia

Al contribuir aceptas que tu aportación se publique bajo la licencia del repo, **[PolyForm Noncommercial 1.0.0](LICENSE)** (uso personal / estudio / modificación permitidos, uso comercial prohibido sin acuerdo escrito).

---

## Otros recursos

- **[Privacidad](docs/PRIVACY.md)** — cómo la app maneja (o más bien no maneja) los datos
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — workflow de release auto
- **[Releases](../../releases)** — APKs firmados + SHA256
