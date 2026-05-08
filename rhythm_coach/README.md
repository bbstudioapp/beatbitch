# BeatBitch

![version](https://img.shields.io/badge/version-0.1.0-orange)
![platform](https://img.shields.io/badge/platform-Android-3ddc84)
![offline](https://img.shields.io/badge/100%25-offline-blue)

> Coach vocal rythmique immersif. Le téléphone est posé sur le côté, tu n'as pas besoin de regarder l'écran : tout passe par la voix et les bips de guidage.

> An immersive rhythmic voice coach. The phone lies on its side — no need to watch the screen. Everything is driven by voice and guidance beeps.

---

🇫🇷 **[Français](#français)** &nbsp;|&nbsp; 🇬🇧 **[English](#english)**

---

## Français

### Captures d'écran

> _Captures à venir — l'app est en alpha privée._

<p>
  <em>placeholder</em> · accueil · session · sons · profil · badges
</p>

### Fonctionnalités

- **Coach vocal TTS féminin**, ton ferme, voix locale (aucune synthèse réseau).
- **8 modes de jeu** : rythme, lick, biffle, hold, breath, beg, freestyle, hand.
- **Mode Carrière** : 20+ niveaux, 6 branches de spécialisation, milestones d'apprentissage, encore enchaîné, sessions bâclées, badges de progression.
- **Scénarios libres** : sessions JSON éditables, punitions et commentaires aléatoires extensibles sans toucher au code.
- **Vérif caméra des holds** (expérimental, opt-in) : détection on-device via Google ML Kit, jamais d'image envoyée nulle part.
- **Multi-langue** : infrastructure prête (FR livré, EN/autres langues = ajout d'assets).
- **Adult gate 18+** non-skippable au premier lancement, onboarding 3 écrans.

### 100 % offline · pas de télémétrie

Aucune donnée ne quitte ton téléphone. Permission `INTERNET` non déclarée. ML Kit tourne en local. Voir [PRIVACY.md](PRIVACY.md).

### Installation (side-load Android)

L'app n'est **pas distribuée sur le Play Store** — installation manuelle uniquement.

1. Télécharger l'APK depuis la page Releases du dépôt (lien à venir).
2. Vérifier le SHA256 publié à côté de l'APK :
   ```bash
   sha256sum BeatBitch-0.1.0.apk
   ```
3. Sur le téléphone : autoriser l'installation depuis sources inconnues pour ton gestionnaire de fichiers / navigateur.
4. Ouvrir l'APK, valider l'installation.
5. Au 1er lancement : adult gate 18+, puis onboarding 3 étapes.

> ⚠ Android 9+ requis. App testée sur Android 13/14.

### Build local (développeurs)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # doit retourner "No issues found!"
flutter test
flutter run           # device Android connecté
flutter build apk --release
```

Le contenu éditorial vit dans `assets/` (sessions JSON, punitions, commentaires aléatoires, packs d'ambiance, banque de phrases carrière). Voir [CLAUDE.md](CLAUDE.md) pour la doc d'architecture détaillée.

### Vie privée

Voir [PRIVACY.md](PRIVACY.md) — version courte : aucune collecte, tout est local, `allowBackup="false"`.

---

## English

### Screenshots

> _Coming soon — the app is in private alpha._

<p>
  <em>placeholder</em> · home · session · sounds · profile · badges
</p>

### Features

- **Female TTS voice coach**, firm tone, local voice only (no network synthesis).
- **8 play modes**: rhythm, lick, biffle, hold, breath, beg, freestyle, hand.
- **Career mode**: 20+ levels, 6 specialization branches, learning milestones, chained encore, quickie sessions, progression badges.
- **Free scenarios**: editable JSON sessions, extensible punishments and random comments without touching code.
- **Hold camera check** (experimental, opt-in): on-device detection via Google ML Kit — no image ever leaves the device.
- **i18n infrastructure ready** (French shipped; English / other locales = asset drop-in).
- **18+ adult gate** non-skippable on first launch, 3-step onboarding.

### 100% offline · no telemetry

No data leaves your phone. The `INTERNET` permission is not declared. ML Kit runs locally. See [PRIVACY.md](PRIVACY.md).

### Install (Android side-load)

The app is **not distributed on the Play Store** — manual install only.

1. Download the APK from the repo Releases page (link coming soon).
2. Verify the SHA256 published next to the APK:
   ```bash
   sha256sum BeatBitch-0.1.0.apk
   ```
3. On the phone: allow installs from unknown sources for your file manager / browser.
4. Open the APK and confirm the install.
5. First launch: 18+ adult gate, then 3-step onboarding.

> ⚠ Android 9+ required. Tested on Android 13/14.

### Local build (developers)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # should return "No issues found!"
flutter test
flutter run           # connected Android device
flutter build apk --release
```

Editorial content lives in `assets/` (JSON sessions, punishments, random comments, ambience packs, career phrase bank). See [CLAUDE.md](CLAUDE.md) for detailed architecture docs.

### Privacy

See [PRIVACY.md](PRIVACY.md) — short version: no collection, everything is local, `allowBackup="false"`.

---

## Bug reports

Open an issue on the repo. Please include device model, Android version, and steps to reproduce.
