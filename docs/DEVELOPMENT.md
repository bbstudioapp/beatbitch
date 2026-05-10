# Development setup / Setup développeur

🇫🇷 Comment installer le projet, le lancer sur chaque plateforme cible, et où
toucher pour personnaliser le contenu sans coder.

🇬🇧 How to install the project, run it on every target platform, and where to
edit if you want to tweak content without writing code.

---

## 1. Prérequis / Requirements

| Outil / Tool | Version | Notes |
|---|---|---|
| **Flutter SDK** | ≥ 3.19 (stable) | `flutter --version` doit afficher au moins 3.19. Plus récent = ok. |
| **Dart SDK** | inclus dans Flutter | Pas à installer séparément. |
| **Git** | n'importe quelle version récente | |
| **Android Studio** *(Android only)* | dernière stable | Nécessaire pour le SDK Android, l'émulateur et `adb`. Le plugin Flutter d'IDE est facultatif — tu peux dev en VS Code ou éditeur de ton choix. |
| **Visual Studio 2022 Community** *(Windows desktop only)* | dernière | Workload **« Desktop development with C++ »** requis. Sans ça, `flutter build windows` échoue à la compilation native. |
| **Chrome** *(web only)* | n'importe quelle version récente | Pour `flutter run -d chrome` (mode dev). Le web n'est **pas** une cible release officielle (cf. `docs/index.md`), mais ça reste utilisable pour itérer rapidement sur l'UI. |

Vérification rapide après install :

```bash
flutter doctor
```

Tout ce que tu veux cibler doit afficher ✅. Les ❌ sur les plateformes que tu
ne cibles pas peuvent être ignorés.

---

## 2. Cloner et résoudre les dépendances / Clone and resolve deps

```bash
git clone git@github.com:bbstudioapp/beatbitch.git
cd beatbitch/rhythm_coach
flutter pub get
flutter analyze   # doit retourner "No issues found!"
flutter test      # ~80 tests unitaires
```

Tout le code Flutter vit dans **`rhythm_coach/`**. La racine du repo contient
juste les docs publiques, la licence, le workflow CI/CD et les templates GitHub.

---

## 3. Run par plateforme / Run per platform

Dans tous les cas, depuis `rhythm_coach/`.

### 3.1 Android

```bash
flutter run                       # device USB ou émulateur connecté
flutter build apk --release       # APK release (nécessite key.properties)
flutter build apk --debug         # APK debug, signé avec la clé Android par défaut
```

`adb devices` pour voir si ton téléphone est bien reconnu. Active le **mode
développeur** + **débogage USB** sur le téléphone. Premier lancement : Android
te demande d'autoriser l'ordi (boîte de dialogue sur le téléphone).

> Pour build un APK release signé hors CI, il te faut un `android/key.properties`
> avec ta keystore. Voir `android/key.properties.example` pour le format. La
> CI utilise un keystore dédié versé en secret GitHub (cf.
> `.github/RELEASE_SETUP.md`).

### 3.2 Windows desktop

```bash
flutter config --enable-windows-desktop   # une seule fois
flutter run -d windows                    # lance l'app en debug
flutter build windows --release           # build release dans build/windows/x64/runner/Release/
```

Le binaire final est `build/windows/x64/runner/Release/rhythm_coach.exe` + ses
DLLs Flutter et plugins. Pour le distribuer, **zipper l'intégralité du dossier
Release** — c'est ce que fait le job CI `release-windows` (cf.
`.github/workflows/release.yml`).

> ⚠ Sur Windows, plusieurs fonctionnalités sont **désactivées** par design :
> vérif caméra des holds, notifications surprise. Cf. `lib/services/platform_capabilities.dart`.
> Le TTS utilise Microsoft Julie (SAPI) avec rate 0.68 / pitch 1.22 forcés
> pour tous les coachs (les voix Android `fr-fr-x-*-local` n'existent pas
> sous SAPI).

### 3.3 Web (dev only — pas une cible release)

```bash
flutter config --enable-web         # une seule fois
flutter run -d chrome               # mode dev hot-reload
flutter build web --release         # build statique dans build/web/
```

Le web sert à itérer rapidement sur l'UI sans rebuild Android. **Ce n'est
pas une cible de distribution officielle** — l'hébergement NSFW publique
soulève des problèmes (TOS GitHub Pages / Cloudflare Pages, adult gate
fragile dans un navigateur, expérience dégradée sans notifs / vibration /
caméra ML Kit).

> Plusieurs APIs ne sont pas dispo sur web. Le code utilise déjà des
> guards `defaultTargetPlatform != TargetPlatform.android` pour la
> caméra et les notifs surprise — l'app charge mais ces fonctions sont
> masquées.

### 3.4 Linux (non testé, à activer au besoin)

```bash
flutter config --enable-linux-desktop
flutter run -d linux
flutter build linux --release
```

Pas de job CI Linux pour l'instant. `audioplayers`, `flutter_tts` (espeak),
`shared_preferences` marchent. Mêmes capabilities désactivées qu'en Windows.

### 3.5 macOS (bloqué)

Bloqué par Apple Developer ID + notarization (~99 $/an + Mac requis). Pas
prévu sauf demande explicite.

---

## 4. Personnaliser le contenu / Customize content

**Tout le contenu éditorial est dans `rhythm_coach/assets/`** sous forme de
fichiers JSON / MP3. Pas de modification de code requise pour ajouter une
session, une phrase, un coach, une langue.

### 4.1 Sessions Scénario

Path : `assets/sessions/*.json` — sessions prédéfinies du mode Scénario (pas
les sessions générées en Carrière, qui sont composées au runtime par
`CareerSessionGenerator`).

| Fichier | Description |
|---|---|
| `session_initiation.json` | 8 min, ton progressif. Démo douce. |
| `session_intense.json` | 10 min, intervalles. |
| `session_advanced_demo.json` | Démo des modes avancés (24 steps). |
| `session_camera_test.json` | Tests de la vérif caméra (5 holds tip→full). |
| `session_initiation_en.json` | Variante anglaise (locale = `en`). |

**Schéma** : une session est `{id, name, description, duration_seconds, mode,
lang, steps[], …}`. Détails complets dans `rhythm_coach/CLAUDE.md` section
*Modèles de données* + `lib/models/session.dart`.

**Ajouter une session** :
1. Crée `assets/sessions/ma_session.json` avec le schéma attendu.
2. Ajoute le path dans `lib/services/session_loader.dart` → liste `_assetPaths`.
3. Pas besoin de toucher `pubspec.yaml` (le dossier `assets/sessions/` est déjà
   déclaré).

### 4.2 Coachs

Path : `assets/career/coaches/`

| Fichier | Description |
|---|---|
| `coach_<id>.json` | Métadonnées coach (lang-indépendant) — id, name, archetype, specialties, modeWeights, voicePreset, etc. |
| `coach_<id>_<lang>.json` | Phrases TTS du coach pour la locale (FR, EN…). Pool par mode/tier (soft/medium/hard/boost/finale) + intros + transitions + recovery. |

Le contenu fait > 100 lignes par coach + > 200 phrases par locale. Les
contributeurs IA peuvent se référer à **[`docs/CONTENT_GUIDE.md`](CONTENT_GUIDE.md)**
qui décrit la structure attendue ligne par ligne.

**Ajouter un coach** :
1. Crée le `coach_<id>.json` (métadonnées).
2. Crée au moins un `coach_<id>_fr.json` (phrases FR).
3. Le coach apparaît automatiquement dans le sélecteur Carrière dès que les
   conditions de débloquage (`requirements`) sont remplies.

### 4.3 Punitions, commentaires, ambiances

| Fichier | Rôle |
|---|---|
| `assets/punishments.json` (+ `_en.json`) | Phrases de fail + mini-séquences punition. |
| `assets/random_comments.json` (+ `_en.json`) | Commentaires aléatoires intercalés dans les sessions. Cadence (`min/max_interval_seconds`) modifiable. |
| `assets/ambience_packs.json` (+ `_en.json`) | Packs d'ambiance (mapping `SessionMode → MP3`). Curé éditorialement. |
| `assets/nicknames.json` (+ `_en.json`) | Pool global de surnoms (override possible côté user dans Profil). |

Édition directe — aucune modification de code requise. Au prochain run, les
loaders consomment la nouvelle version.

### 4.4 Bips de guidage (audio)

Path : `assets/audio/*.mp3`

| Fichier | Usage |
|---|---|
| `tip_beep.mp3`, `head_beep.mp3`, `mid_beep.mp3`, `throat_beep.mp3`, `full_beep.mp3` | Sample par position (5 niveaux du plus aigu au plus grave). |
| `hold_beep.mp3`, `breath_beep.mp3`, `biffle_beep.mp3` | Samples de modes spécifiques. |
| `hand_down_beep.mp3`, `hand_up_beep.mp3` | Mode hand : coup descendant + coup remontant. |
| `freestyle_start.mp3`, `freestyle_end.mp3` | Marqueurs début/fin de mode freestyle. |
| `finale_chime.mp3` | Son d'orgasme du coach en fin de session. Variantes par catégorie dans `assets/audio/finale/` (vide à ce jour, fallback unique). |

**Remplacer un bip** : dépose un nouveau MP3 avec le **même nom de fichier**.
Aucune modif code. Pour un nouveau type de sample, étendre les constantes
dans `lib/services/beep_engine.dart`.

**Regénérer les placeholders** : `bash tools/generate_beeps.sh` (nécessite
`ffmpeg`). Les fréquences/durées sont en haut du script.

### 4.5 Backgrounds (GIF / images) et ambiences (MP3)

Path : `assets/backgrounds/` (gitignoré) et `assets/audio/ambience/` (gitignoré).

Les binaires lourds ne sont **pas** dans le repo public — ils sont fetchés
depuis Cloudflare R2 par la CI au moment du build (cf.
`.github/workflows/release.yml` step *Fetch external assets from R2*). En
local, ces dossiers sont vides et l'app dégrade gracieusement (placeholder
animé pour les fonds, silence pour l'ambiance).

Pour bosser avec les vraies ambiances en local : demander accès au bucket R2
(via une issue privée ou directement à l'auteur) ou déposer manuellement tes
propres MP3 dans `assets/audio/ambience/`.

### 4.6 Internationalisation (UI)

L'UI Flutter consomme `AppLocalizations.of(context).xxx` (généré depuis
`lib/l10n/app_<lang>.arb`). Pour ajouter une langue, créer un nouveau fichier
ARB + ajouter la locale à `kSupportedLocales` (`lib/services/locale_service.dart`)
+ créer les pendants éditoriaux par langue (sections 4.1–4.4).

Procédure complète : section *Internationalisation* de `rhythm_coach/CLAUDE.md`.

---

## 5. Tests / Tests

```bash
cd rhythm_coach
flutter test                          # tous les tests
flutter test test/coach_service_test.dart   # un fichier précis
flutter test --plain-name "encore"    # filtre par nom
```

Pas de tests UI / golden tests — uniquement des tests unitaires Dart purs
sur la logique métier (coach validation, nicknames, phrases, milestones,
session generator).

Au prochain release, un workflow `ci.yml` séparé tournera `analyze` + `test`
sur chaque PR vers develop/main et apparaîtra comme *required check*.

---

## 6. Workflow Git / Git workflow

Voir [`CONTRIBUTING.md`](../CONTRIBUTING.md) section *Code — workflow Git*.

En résumé :

- Branches `feat/`, `fix/`, `chore/`, `docs/`, `ci/` → PR vers **`develop`**
- Bumps de version `release/x.y.z` → PR vers **`main`** (déclenche le release
  workflow auto, build APK + zip Windows + Release GitHub)
- `main` et `develop` protégés (pas de push direct, linear history, PR
  obligatoire avec 0 approval requis)
- Back-merge auto `main → develop` après chaque release (workflow
  `back-merge.yml`)

---

## 7. Aller plus loin / Going further

- **[`rhythm_coach/CLAUDE.md`](../rhythm_coach/CLAUDE.md)** — architecture
  interne complète (controllers, services, BeepEngine, ExcitationEngine,
  HumiliationEngine, ObedienceEngine, mode Carrière, milestones, badges,
  i18n). C'est le doc de référence pour comprendre comment l'app fonctionne.
- **[`docs/CONTENT_GUIDE.md`](CONTENT_GUIDE.md)** — guide des formats JSON
  pour les contributeurs (humains ou IA) qui veulent ajouter des phrases /
  scénarios sans coder.
- **[`docs/ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md)** — règles pour
  les contributions de GIFs / MP3 (licence, source obligatoire).
- **[`.github/RELEASE_SETUP.md`](../.github/RELEASE_SETUP.md)** — secrets
  CI/CD, keystore Android, R2.
