# BeatBitch

![version](https://img.shields.io/badge/version-0.2.0-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-blue)
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

1. Télécharger l'APK depuis la page Releases du dépôt.
2. Vérifier le SHA256 publié à côté de l'APK :
   ```bash
   sha256sum BeatBitch-X.Y.Z.apk
   ```
3. Sur le téléphone : autoriser l'installation depuis sources inconnues pour ton gestionnaire de fichiers / navigateur.
4. Ouvrir l'APK, valider l'installation.
5. Au 1er lancement : adult gate 18+, puis onboarding 3 étapes.

> ⚠ Android 9+ requis. App testée sur Android 13/14.

### Installation (Windows desktop)

Disponible depuis v0.1.3 — zip portable, aucun installateur.

1. Télécharger `BeatBitch-X.Y.Z-windows-x64.zip` depuis la page Releases.
2. Vérifier le SHA256 :
   ```powershell
   Get-FileHash BeatBitch-X.Y.Z-windows-x64.zip -Algorithm SHA256
   ```
3. Dézipper où tu veux (`Documents\BeatBitch\`, clé USB, etc.).
4. Lancer `rhythm_coach.exe`. Windows SmartScreen peut alerter (binaire non
   signé) → clique « Informations supplémentaires » → « Exécuter quand même ».
5. Au 1er lancement : adult gate 18+, puis onboarding 3 étapes.

> ⚠ Fonctions désactivées sur Windows : vérif caméra des holds, notifications
> surprise. La voix coach utilise Microsoft Julie (SAPI). Le reste — sessions,
> mode carrière, coachs, badges, i18n — fonctionne identique à Android.

### Mises à jour automatiques (Obtainium)

L'app reste **strictement hors-ligne** : elle ne va pas chercher d'update toute seule. Pour être prévenu quand une nouvelle version sort, utilise **[Obtainium](https://github.com/ImranR98/Obtainium)** — un store Android open-source qui surveille les pages GitHub Releases. *Add App* → colle `https://github.com/bbstudioapp/beatbitch`. Aucun trafic réseau n'est généré par BeatBitch elle-même : c'est Obtainium qui interroge GitHub côté utilisateur, indépendamment de l'app.

### Build local (développeurs)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # doit retourner "No issues found!"
flutter test
flutter run           # device Android / `-d windows` / `-d chrome` selon la cible
flutter build apk --release
flutter build windows --release
```

Le contenu éditorial vit dans `assets/` (sessions JSON, punitions, commentaires aléatoires, packs d'ambiance, banque de phrases carrière). Setup complet par plateforme + paths de personnalisation : **[`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md)**.

> ⚠ **Assets binaires externalisés** : les dossiers `assets/backgrounds/` (GIF/images de fond) et `assets/audio/ambience/` (MP3 d'ambiance) sont **gitignorés** — leurs fichiers ne sont pas versionnés dans le dépôt et doivent être rapatriés depuis un canal externe (à venir) avant `flutter build`. Le code se débrouille gracieusement si ces dossiers sont vides : le fond retombe sur un dégradé animé, l'ambiance sur du silence.

### Vie privée

Voir [PRIVACY.md](PRIVACY.md) — version courte : aucune collecte, tout est local, `allowBackup="false"`.

### Licence

Code et contenus éditoriaux (sessions JSON, phrases coach, commentaires aléatoires, surnoms, milestones, etc.) sous **[PolyForm Noncommercial License 1.0.0](../LICENSE)**.

- ✅ **Étudier, forker, modifier, redistribuer** pour usage non-commercial.
- ✅ **Contributions bienvenues** — nouvelles phrases coach, sessions, traductions, fixes de code, idées de spécialisation, etc. Ouvre une issue ou une PR.
- ❌ **Vente, monetisation, redistribution commerciale** interdites — pas de fork "BeatBitch Premium" sur Telegram, Gumroad ou un store alternatif.

Les binaires hors-repo (`assets/backgrounds/*.gif`, `assets/audio/ambience/*.mp3`) restent soumis aux droits de leurs sources d'origine et ne sont pas couverts par cette licence.

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

1. Download the APK from the repo Releases page.
2. Verify the SHA256 published next to the APK:
   ```bash
   sha256sum BeatBitch-X.Y.Z.apk
   ```
3. On the phone: allow installs from unknown sources for your file manager / browser.
4. Open the APK and confirm the install.
5. First launch: 18+ adult gate, then 3-step onboarding.

> ⚠ Android 9+ required. Tested on Android 13/14.

### Install (Windows desktop)

Available since v0.1.3 — portable zip, no installer.

1. Download `BeatBitch-X.Y.Z-windows-x64.zip` from the Releases page.
2. Verify the SHA256:
   ```powershell
   Get-FileHash BeatBitch-X.Y.Z-windows-x64.zip -Algorithm SHA256
   ```
3. Unzip wherever you like (`Documents\BeatBitch\`, USB stick, …).
4. Launch `rhythm_coach.exe`. Windows SmartScreen may warn (unsigned binary) →
   click *More info* → *Run anyway*.
5. First launch: 18+ adult gate, then 3-step onboarding.

> ⚠ Disabled on Windows: hold camera check, surprise notifications. The
> coach voice uses Microsoft Julie (SAPI). Everything else — sessions,
> Career mode, coaches, badges, i18n — works identically to Android.

### Automatic updates (Obtainium)

The app stays **strictly offline** — it doesn't reach out for updates by itself. To get notified when a new version ships, use **[Obtainium](https://github.com/ImranR98/Obtainium)**, an open-source Android store that watches GitHub Releases pages. *Add App* → paste `https://github.com/bbstudioapp/beatbitch`. No network traffic comes from BeatBitch itself — Obtainium queries GitHub on the user side, independently of the app.

### Local build (developers)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # should return "No issues found!"
flutter test
flutter run           # connected Android device / `-d windows` / `-d chrome`
flutter build apk --release
flutter build windows --release
```

Editorial content lives in `assets/` (JSON sessions, punishments, random comments, ambience packs, career phrase bank). Full per-platform setup + customization paths: **[`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md)**.

> ⚠ **Externalized binary assets**: the `assets/backgrounds/` (background GIFs/images) and `assets/audio/ambience/` (ambience MP3s) folders are **gitignored** — their files are not versioned in the repo and must be fetched from an external channel (TBD) before `flutter build`. The code degrades gracefully when these folders are empty: the background falls back to an animated gradient, ambience to silence.

### Privacy

See [PRIVACY.md](PRIVACY.md) — short version: no collection, everything is local, `allowBackup="false"`.

### License

Code and editorial content (JSON sessions, coach phrases, random comments, nicknames, milestones, etc.) released under the **[PolyForm Noncommercial License 1.0.0](../LICENSE)**.

- ✅ **Study, fork, modify, redistribute** for noncommercial use.
- ✅ **Contributions welcome** — new coach phrases, sessions, translations, code fixes, specialization ideas, etc. Open an issue or a PR.
- ❌ **No commercial use, sale, or paid redistribution** — no "BeatBitch Premium" fork on Telegram, Gumroad, or any alternative store.

Off-repo binary assets (`assets/backgrounds/*.gif`, `assets/audio/ambience/*.mp3`) remain subject to their original sources' rights and are not covered by this license.

---

## Bug reports

Open an issue on the repo. Please include device model, Android version, and steps to reproduce.
