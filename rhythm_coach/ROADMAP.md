# Roadmap — `Rhythm Coach` → `BeatBitch`

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

## Phase 2 — Config release Android ✅ DONE

| Action | État |
|---|---|
| Keystore release | ✅ `android/key.properties` rempli + `key.properties.example` versionné comme template. Mot de passe archivé hors repo |
| `key.properties` gitignoré | ✅ `android/.gitignore` ligne 12 (`key.properties`, `**/*.keystore`, `**/*.jks`). `git check-ignore` confirme |
| `signingConfigs.create("release")` | ✅ `build.gradle.kts` charge `key.properties` via `Properties() + FileInputStream`, crée la config conditionnellement (`hasReleaseSigning`). Fallback debug propre si fichier absent → `flutter run --release` reste utilisable en CI / machine fraîche |
| R8 + ProGuard | ✅ `isMinifyEnabled = true`, `isShrinkResources = true`. `android/app/proguard-rules.pro` couvre ML Kit (`com.google.mlkit.**`, `com.google.android.gms.vision.**`, `com.google.android.odml.**`), flutter_local_notifications + Gson (TypeToken/TypeAdapter), `dontwarn` BouncyCastle/Conscrypt/OpenJSSE |
| Pruner permission `INTERNET` | ✅ Manifest ne déclare plus que CAMERA, POST_NOTIFICATIONS, USE_EXACT_ALARM, RECEIVE_BOOT_COMPLETED, VIBRATE. `Image.network` retiré de `session_background.dart` (commentaire ligne 65 traçant la suppression). Tous les backgrounds sont bundle-only |
| Script `tools/check_release.sh` | ✅ Workflow complet : précondition `key.properties`, `flutter build apk --release`, recherche `apksigner` (PATH → `local.properties` → `ANDROID_SDK_ROOT/HOME` → emplacements usuels), `verify --print-certs`, `sha256sum`, taille du fichier. Sortie colorée |

**Output** : APK release signé, minifié, sans permission douteuse. Workflow `check_release.sh` à exécuter avant chaque tag.

---

## Phase 3 — Adult gate & onboarding ✅ DONE

| Action | État |
|---|---|
| `AdultConsentService` | ✅ `lib/services/adult_consent_service.dart` (singleton + `SharedPreferences` clé `app.adult_consent_accepted`, init dans `main()`) |
| Dialog 18+ non-skippable | ✅ `lib/widgets/adult_gate_dialog.dart`, `barrierDismissible: false` + `PopScope(canPop:false)`, joue au 1er postFrame de `ModeSelectionScreen` si non accepté. Bouton « Quitter » → `SystemNavigator.pop`, « J'accepte » persiste le consent |
| Onboarding 3 étapes | ✅ `lib/widgets/onboarding_sheet.dart`, sheet modale (non dismissible), 3 pages : pose latérale / volume / tester ma voix. Dernier bouton push `SoundDemoScreen`. `OnboardingService` (clé `onboarding.shown`) marque l'affichage à la fermeture |
| Snackbar caméra | ✅ `SessionScreen.initState` : si `holdVerifier == null` ET toggle `cameraHoldCheck` ON → `SnackBar` `sessionCameraInactiveWarning` avec action `Calibrer` qui push `CameraTestScreen` |
| "À propos / version" | ✅ `package_info_plus ^9.0.0` ajouté à `pubspec.yaml`. Section `_AboutSection` en bas de `ProfileScreen`, affiche `BeatBitch v{version} (build {build})` + ligne « 100 % offline » |

**Output** : première utilisation propre, conforme aux attentes Reddit NSFW. `flutter analyze` clean, 81 tests passent, APK debug build OK.

**Polish post-phase 3** :
- Section Debug de l'écran SONS désormais wrappée par `kDebugMode` → invisible en release. Le toggle « Vérif caméra des holds » est dans cette section, donc indisponible en release (cohérent avec le statut alpha de la fonction caméra ; reste activable en build debug pour les tests).
- Bloc Identité (prénom + surnoms) extrait de SONS vers `lib/widgets/identity_section.dart` et ancré en haut de `ProfileScreen` (plus logique). `SoundDemoScreen` ne dépend plus de `UserProfileService`. `onboardingStep3` reformulé en deux paragraphes (voix sur SONS, prénom sur Profil).
- Texte de l'adult gate enrichi pour mentionner les GIFs visuels en arrière-plan (pas que l'audio). Étape 1 de l'onboarding nuancée : « garde un œil sur l'écran au début », pose latérale possible plus tard avec l'expérience.

---

## Phase 4 — Polish & doc ✅ DONE

| Action | État |
|---|---|
| `kDebugMode` sur les `debugPrint` non gardés | ✅ 5 sites wrappés : `surprise_notifications_bootstrap.dart:145`, `surprise_alert_service.dart:550`, `camera_motion_detector.dart:267+391`, `coach_service.dart:74`. Audit complet : tous les autres `debugPrint` de `lib/` étaient déjà gardés. `flutter analyze` clean, 81 tests passent |
| README EN+FR | ✅ `rhythm_coach/README.md` réécrit, bilingue avec ancres FR/EN, badges version/platform/offline, feature list, install side-load, mention 100 % offline / no telemetry, liens vers `PRIVACY.md` et `CLAUDE.md`, section screenshots placeholder |
| `PRIVACY.md` | ✅ `rhythm_coach/PRIVACY.md` bilingue : aucune donnée envoyée, `INTERNET` non déclaré, `CAMERA` opt-in (ML Kit on-device), `SharedPreferences` sandbox, `allowBackup="false"`, TTS local uniquement, note ML Kit model download via Google Play Services |
| Mise à jour `CLAUDE.md` | ✅ Le titre est `# BeatBitch` depuis la Phase 1. Aucune occurrence "Rhythm Coach" en branding résiduel. Seul `cd rhythm_coach` (chemin du dossier physique) conservé volontairement |

**Output** : repo présentable, branding cohérent, debug logs propres en release.

---

## Phase 5 — Repo public & CI/CD ✅ DONE

| Action | État |
|---|---|
| Compte GitHub dédié | ✅ `bbstudioapp` (séparé du compte principal). Email Proton `beatbitch@proton.me` + noreply `282851981+bbstudioapp@users.noreply.github.com` |
| SSH alias dédié | ✅ Bloc `Host github-bbstudio` dans `~/.ssh/config` avec clé `~/.ssh/id_ed25519_bbstudio`. Remote utilise `git@github-bbstudio:bbstudioapp/beatbitch.git` |
| Identité Git par-repo | ✅ `git config user.name "BB Studio"` + `user.email` noreply, scopés au repo (pas global) |
| Réécriture historique | ✅ `git filter-repo` : 38 commits passés en Conventional Commits, author + committer = BB Studio sur tout l'historique. Purge des binaires (gifs `assets/backgrounds/*.gif`, mp3 ambience `assets/audio/ambience/*.mp3`) → `.git` passé de **125 MB à 3 MB** |
| Externalisation assets binaires | ✅ `BackgroundsLoader` réécrit pour scanner `AssetManifest` au runtime (plus de `backgrounds.json`). `assets/backgrounds/*.{gif,png,jpg,jpeg,webp}` et `assets/audio/ambience/*.mp3` gitignorés. Code dégrade gracieusement quand vide (placeholder animé / silence). Doc CLAUDE.md + README. **Canal de distribution externe à concevoir** (R2 / Drive / S3 privé) |
| Workflow release auto | ✅ `.github/workflows/release.yml` — déclenché sur push `main` qui bumpe `version:`, lit pubspec, gate sur tag existant, JDK 17 + Flutter stable, tests + APK release signé + SHA256 + Release GitHub. 4 secrets : `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`. Doc dans `.github/RELEASE_SETUP.md` |
| Premier release publié | ✅ `v0.1.0` créé automatiquement par le workflow au premier push main, asset `BeatBitch-0.1.0.apk` + `.sha256`. `v0.1.1` suivi avec les fixs i18n (pack ambiance / streak quotidien / surnoms qui suivent la locale) |
| Licence | ✅ `LICENSE` racine = PolyForm Noncommercial 1.0.0 (usage perso/étude/modif autorisés, commercial interdit sans accord écrit) |
| README racine | ✅ Landing page courte sur `README.md` racine pointant vers `rhythm_coach/`, Releases et `RELEASE_SETUP.md` (la home GitHub n'affichait que `LICENSE` sinon) |
| Branche `develop` | ✅ Créée à partir de `main`, push tracking `origin/develop`. Workflow inchangé (release.yml ne tourne que sur main) |
| Branch protection | ✅ Ruleset GitHub `protect-main-develop` ciblant `main` et `develop` : restrict deletions, linear history, PR obligatoire (0 approvals), block force push, bypass list vide. Push direct rejeté côté serveur, tout passe par PR + auto-merge |

**Output** : repo `bbstudioapp/beatbitch` **public**, CI/CD opérationnel, garde-fous Git en place. Releases `v0.1.0` et `v0.1.1` auto-publiées.

**Workflow Git établi** : hybrid GitFlow — branches feature (`fix/`, `chore/`, `docs/`) → PR vers `develop`. Bumps de version (`release/x.y.z`) → PR vers `main` qui déclenche le workflow release. Sync `develop ← main` après chaque release pour aligner les branches.

**Reste à faire ici** :
- Concevoir le **canal externe** pour les assets binaires (gifs + mp3 ambience) et l'**étape de récupération** dans le workflow (curl/aws-cli avant `flutter build apk`).
- Optionnel : ajouter un `ci.yml` séparé qui tourne `analyze` + `test` sur les PR vers `develop`/`main`, et le cocher en *Required status checks* du ruleset.

---

## Phase 6 — Contenu marketing ✅ DONE

| Action | État |
|---|---|
| Screenshots | ✅ 11 captures curées (6 EN + 5 FR) couvrant accueil, carrière, session, sons, badges, profil, spécialisation, rappel surprise. `rhythm_coach/screenshots/` gitignoré (binaires lourds, hors historique) |
| Vidéo démo | ✅ 67s, capture screen recorder Samsung, status bar cropée (ffmpeg `crop=1080:2270:0:130`) + réencodage H.264 CRF 23 → `beatbitch_demo.mp4` 7,8 Mo. Hébergée sur Redgifs pour embed Reddit propre |
| Privacy policy hostée | ✅ `docs/PRIVACY.md` source canonique + `docs/index.md` landing → GitHub Pages `bbstudioapp.github.io/beatbitch/PRIVACY`. `rhythm_coach/PRIVACY.md` réduit en pointeur pour éviter la divergence |
| Description + Topics GitHub | ✅ |
| Issue templates | ✅ `.github/ISSUE_TEMPLATE/` — bug / feature / **content_contribution** (le plus important : guide les contributeurs vers le format JSON consommable par le générateur, avec coach cible + tier soft/medium/hard/boost/finale + placeholders `{name}`/`{coach}`) + `config.yml` exposant Privacy et Releases comme liens contact |

**Output** : repo prêt à montrer, visuels prêts à coller dans un post, contributions canalisées via templates structurés.

---

## Phase 7 — Lancement communauté

| Étape | État |
|---|---|
| Compte dédié créé | ✅ |
| 1er post publié sur sub cible | ✅ — caught par filtres anti-spam Reddit (compte neuf), modmail envoyé pour approbation manuelle |
| Réactions aux commentaires post-approbation | ⏳ |
| Cross-post éventuel sur subs alignés | ⏳ |
| Itération éditoriale selon retours (phrases coach, sons, langues) | ⏳ |

**État courant** : post invisible aux feeds tant que les mods n'ont pas approuvé manuellement, mais accessible via URL directe (vues + 1 up déjà reçus). Plan B si pas d'approbation sous une semaine : durcir le compte (karma + âge + avatar + email vérifié) puis repost.

---

## Synthèse

| Bloc | État |
|---|---|
| Phase 1 — Rebranding BeatBitch | ✅ DONE |
| Phase 2 — Release config | ✅ DONE |
| Phase 3 — Adult gate & onboarding | ✅ DONE |
| Phase 4 — Polish & doc | ✅ DONE |
| Phase 5 — Repo public & CI/CD | ✅ DONE |
| Phase 6 — Contenu marketing | ✅ DONE |
| Phase 7 — Lancement communauté | ⏳ EN COURS |
