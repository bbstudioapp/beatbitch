# Roadmap — `Rhythm Coach` → `BeatBitch`

**Estimation totale** : ~4-5 jours de travail effectif (étalable sur 2 weekends).

---

## Phase 1 — Rebranding **BeatBitch** ✅ DONE

| Action | État |
|---|---|
| Package Dart | ✅ `rhythm_coach` → `beat_bitch` (`pubspec.yaml`, 9 imports `package:` dans `test/`) |
| `applicationId` Android | ✅ `com.beatbitch.app` (namespace + applicationId dans `build.gradle.kts`). Dossier Kotlin migré `com/example/rhythm_coach/` → `com/beatbitch/app/` + `package` MainActivity |
| Description `pubspec.yaml` | ✅ `An offline rhythmic voice coach for Android.` |
| Label Android | ✅ `res/values/strings.xml` + `values-en/strings.xml` avec `app_name=BeatBitch`. Manifest référence `@string/app_name` |
| Icône launcher | ✅ `flutter_launcher_icons ^0.14.4` configuré. 3 sources (`assets/icon/app_icon.png`, `app_icon_foreground.png`, `app_icon_monochrome.png`). Mipmap legacy + adaptive foreground/background + monochrome Android 13+ générés. **Note** : monochromes regénérés manuellement post-launcher_icons à cause d'un bug du package qui aplatit l'alpha au resize |
| "Rhythm Coach" → "BeatBitch" | ✅ ARB FR+EN, code l10n, `widget_test.dart`, `web/manifest.json`, `README.md`, `CLAUDE.md` |

**Output** : app s'appelle BeatBitch partout, icône custom, `flutter analyze` clean, 81 tests passent, APK debug build OK.

> Le **dossier physique** du projet reste `rhythm_coach/` au niveau du repo `tss2` — le renommer en `beat_bitch/` est un `git mv` qu'on peut faire plus tard, ça touche les CI/scripts.

---

## Phase 2 — Config release Android (0.5-1 jour)

| Action | Détail |
|---|---|
| Keystore release | `keytool -genkey -v -keystore ~/.android/beatbitch-upload.jks -keyalg RSA -keysize 2048 -validity 10000`. Mot de passe **archivé hors repo** (1Password/keepass) — le perdre = ne plus pouvoir mettre à jour |
| `key.properties` gitignoré | À la racine `android/`, contient les chemins + mots de passe. Ajouter au `.gitignore` |
| `signingConfigs.create("release")` | Charger `key.properties` via `Properties()` dans `build.gradle.kts`, créer le bloc release, switcher `release { signingConfig = signingConfigs.getByName("release") }` |
| R8 + ProGuard | Activer `isMinifyEnabled = true`, `isShrinkResources = true`. Créer `android/app/proguard-rules.pro` avec `-keep` ML Kit + `flutter_local_notifications` (sinon les notifs et la détection visage cassent en release) |
| Pruner permission `INTERNET` | Retirer du manifest + supprimer le bloc `Image.network` dans `widgets/session_background.dart:84-100`. Tous les backgrounds sont déjà bundle-only |
| Script `tools/check_release.sh` | Run `flutter build apk --release`, vérifier signature avec `apksigner verify`, afficher SHA256. À runner avant chaque tag release |

**Output** : APK release signé, minifié, sans permission douteuse.

---

## Phase 3 — Adult gate & onboarding (1 jour)

| Action | Détail |
|---|---|
| `AdultConsentService` | Service léger style `LocaleService` : clé `app.adult_consent_accepted` dans `SharedPreferences`, getter/setter, écouté au boot |
| Dialog 18+ non-skippable | Au premier `ModeSelectionScreen.initState`, si `consent != true` → `showDialog(barrierDismissible: false)` plein écran. Texte : "≥18 ans", "contenu sexuel explicite", "fonctionne en vocal — pas en lieu public", bouton "J'accepte" |
| Onboarding 3 étapes | Sheet à la 1ère ouverture (clé `onboarding.shown`) après le consent : 1. téléphone latéral / 2. volume haut / 3. tester ma voix → push `SoundDemoScreen` |
| Snackbar caméra | Dans `SessionScreen.initState`, si toggle camCheck ON et `buildVerifierIfEnabled` retourne null → `SnackBar` "Vérif caméra inactive — relancer la calibration" + action vers `CameraTestScreen` |
| "À propos / version" | Section en bas de `ProfileScreen` (ou `SoundDemoScreen`), lit `package_info_plus`, affiche `BeatBitch v0.1.0 (build 1)`. Optionnel : lien vers GitHub repo |

**Output** : première utilisation propre, conforme aux attentes Reddit NSFW.

---

## Phase 4 — Polish & doc (0.5 jour)

| Action | Détail |
|---|---|
| `kDebugMode` sur les `debugPrint` non gardés | Concerne 5-6 fichiers (`session_loader.dart:36`, `surprise_alert_service.dart:550`, `surprise_notifications_bootstrap.dart:145`, `camera_motion_detector.dart:267,391`, `coach_loader.dart`, `milestone_service.dart`). `debugPrint` est neutre en release de toute façon mais à standardiser |
| README EN+FR | À la racine du repo : screenshots (placeholder), feature list, install instructions side-load, mention "100% offline / no telemetry", lien privacy policy, badge version |
| `PRIVACY.md` | 1 page : aucune donnée envoyée, `shared_preferences` local, `allowBackup="false"`, ML Kit on-device, contact pour bug reports |
| Mise à jour `CLAUDE.md` | Renommer toutes les occurrences `Rhythm Coach` → `BeatBitch` |

**Output** : repo public présentable.

---

## Phase 5 — Distribution (0.5-1 jour)

| Action | Détail |
|---|---|
| Build APK release final | `bash tools/check_release.sh` → APK signé + SHA256 |
| Screenshots | 3-5 captures : écran d'accueil, choix Carrière, écran de session avec barres debug ON, écran SONS, écran badges. Cadre propre, dark theme bien rendu |
| Vidéo démo 30s | Téléphone posé latéral filmé, audio capté propre, sous-titres EN. Outil : OBS + scrcpy. Pas besoin de contenu explicite, juste l'UX et le son |
| GitHub Release v0.1.0 | Repo dédié `beatbitch-releases` (public ou GitHub-only), upload APK + SHA256 + changelog. Tag `v0.1.0` |
| Privacy policy hostée | GitHub Pages depuis le repo (gratuit). URL stable nécessaire pour certains subs |

**Output** : un lien stable à coller dans le post Reddit.

---

## Phase 6 — Lancement Reddit (étalé sur 1 semaine)

| Étape | Quand |
|---|---|
| Lurker 2-3 subs cibles, lire les règles, vérifier karma min + flair self-promo | J-3 à J-1 |
| Préparer le post : titre, body court, NSFW tag, lien GitHub Release, vidéo embarquée | J-1 |
| Publier sur **un seul sub** d'abord (le plus tolérant au self-promo) | J0 |
| Réagir aux commentaires dans les 24h | J0-J1 |
| Si bon accueil, cross-post dans 2-3 autres subs alignés | J+3 |

**Subs candidats à valider** : r/SideloadedAndroid (focus indé hors Play Store, neutre sur le contenu), r/joi, r/jerkofftoabeat, r/edging — chacun a des règles strictes, lurke avant.

---

## Synthèse calendrier

| Bloc | Effort | Bloque la suite ? |
|---|---|---|
| Phase 1 — Rebranding BeatBitch | 1 j | Oui (le reste utilise le nouveau package) |
| Phase 2 — Release config | 0.5-1 j | Oui (APK signé requis pour distribution) |
| Phase 3 — Adult gate & onboarding | 1 j | Non (parallélisable avec phase 4) |
| Phase 4 — Polish & doc | 0.5 j | Non |
| Phase 5 — Distribution | 0.5-1 j | Oui (lien stable requis pour le post) |
| Phase 6 — Reddit | ~1 sem étalée | — |

**Chemin critique** : Phase 1 → 2 → 5 → 6 (~3 jours minimum). Phases 3 et 4 en parallèle de 5.
