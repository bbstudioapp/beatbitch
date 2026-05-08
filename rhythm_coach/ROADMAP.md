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
| Phase 2 — Release config ✅ | 0.5-1 j | Oui (APK signé requis pour distribution) |
| Phase 3 — Adult gate & onboarding ✅ | 1 j | Non (parallélisable avec phase 4) |
| Phase 4 — Polish & doc ✅ | 0.5 j | Non |
| Phase 5 — Distribution | 0.5-1 j | Oui (lien stable requis pour le post) |
| Phase 6 — Reddit | ~1 sem étalée | — |

**Chemin critique** : Phase 1 → 2 → 5 → 6 (~3 jours minimum). Phases 3 et 4 en parallèle de 5.
