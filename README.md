# BeatBitch

![version](https://img.shields.io/badge/version-0.1.1-orange)
![platform](https://img.shields.io/badge/platform-Android-3ddc84)
![offline](https://img.shields.io/badge/100%25-offline-blue)
![no tracking](https://img.shields.io/badge/no-tracking-success)
![license](https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-lightgrey)

> 🇫🇷 **Coach vocal rythmique immersif pour Android.** Tu poses ton téléphone à plat sur le côté, tu lances la séance, tu fermes les yeux. Une voix te guide, des bips marquent le rythme, tu n'as plus besoin de regarder l'écran.
>
> 🇬🇧 **Immersive rhythmic voice coach for Android.** Drop your phone flat on its side, start the session, close your eyes. A voice guides you, beeps mark the rhythm — no screen-watching needed.

---

🇫🇷 **[Français](#français)** &nbsp;|&nbsp; 🇬🇧 **[English](#english)**

---

## Français

### En 30 secondes

- Une **voix de coach** qui parle dans ta langue, en local — aucune synthèse réseau.
- Des **bips de guidage** calés au BPM pour rythmer chaque mouvement.
- 8 modes de jeu, un mode Carrière qui se débloque au fil des séances, des coachs avec des personnalités différentes.
- **100 % hors-ligne** : permission `INTERNET` non déclarée, rien ne sort de ton téléphone.
- **Pas de Play Store, pas de pub, pas d'achat in-app.** Distribution APK signé direct.

### 📥 Télécharger

➡ **[Page Releases](../../releases)** — APK signé + son SHA256.

> ⚠ Android 9 minimum. Testé sur Android 13/14.

### 📲 Installer (side-load, étape par étape)

Le **side-load**, c'est juste « installer une app sans passer par le Play Store ». Android le permet nativement, il faut juste autoriser ton navigateur ou ton gestionnaire de fichiers à le faire.

1. **Sur ton téléphone**, ouvre la [page Releases](../../releases) et télécharge le fichier `BeatBitch-X.Y.Z.apk` le plus récent.
2. (*Optionnel mais recommandé*) Vérifie l'empreinte SHA256 du fichier téléchargé — elle doit correspondre à celle publiée à côté de l'APK. Une appli comme **Hash Droid** sur F-Droid fait ça en 2 clics.
3. Ouvre le fichier APK dans tes téléchargements.
4. Android va te demander d'**autoriser cette source** : tape « Paramètres » → active l'autorisation pour ton navigateur (ou gestionnaire de fichiers). Reviens et confirme.
5. L'install démarre. Une fois fini, ouvre BeatBitch.
6. **Au 1er lancement** : confirmation 18+ (non-skippable), puis 3 écrans d'onboarding (pose du téléphone, volume, test de la voix).

> 💡 Tu peux désactiver l'autorisation « sources inconnues » après l'install — Android ne la rouvrira pas tant que tu ne mets pas l'app à jour.

### 🔄 Mises à jour automatiques (Obtainium)

L'app reste **strictement hors-ligne** : elle ne va pas chercher d'update toute seule. Pour être prévenu quand une nouvelle version sort et l'installer en deux taps, utilise **[Obtainium](https://github.com/ImranR98/Obtainium)** — un store Android open-source qui surveille les pages GitHub Releases.

1. Installe Obtainium (dispo sur [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/) ou en APK direct depuis son repo).
2. Dans Obtainium : *Add App* → colle l'URL `https://github.com/bbstudioapp/beatbitch`.
3. À chaque nouvelle release, Obtainium détecte l'APK `BeatBitch-X.Y.Z.apk` et te propose la mise à jour.

> Aucun trafic réseau n'est généré par BeatBitch elle-même — c'est Obtainium qui interroge GitHub côté utilisateur, indépendamment de l'app. La promesse 100 % hors-ligne reste intacte.

### 🔒 C'est safe ?

- **APK signé** par la même clé à chaque release — Android refuse l'install si quelqu'un essaie de te refiler un APK trafiqué (la signature ne matchera pas).
- **Code source public** — tu peux relire ce qui tourne (ou le faire relire).
- **Aucune permission réseau** — ni `INTERNET`, ni `ACCESS_NETWORK_STATE`. L'app ne *peut* littéralement pas appeler un serveur.
- **`allowBackup="false"`** — pas de remontée vers Google Backup.
- **Caméra opt-in** — la vérif caméra des holds est désactivée par défaut, et le traitement reste 100 % on-device (Google ML Kit local). Aucune image ne quitte le téléphone.

Détails dans **[PRIVACY.md](docs/PRIVACY.md)** ([version publiée](https://bbstudioapp.github.io/beatbitch/PRIVACY)).

### 🎮 Comment ça se joue

1. Pose ton téléphone à plat, sur le côté — pas besoin de l'avoir devant les yeux.
2. Choisis une séance prédéfinie ou laisse le mode Carrière t'en générer une.
3. Suis la voix. Les bips marquent le tempo (un grave + un aigu qui alternent, ou un seul si la séance demande de tenir une position).
4. Le bouton **« Je peux pas »** est toujours dispo si tu décroches. La coach prend le relais avec une punition courte, puis la séance reprend là où ça avait du sens.
5. À la fin, l'écran te dit ce que tu as débloqué (badges, niveaux carrière, milestones).

### 🐛 Trouver un bug, suggérer une idée, contribuer

Templates d'issues disponibles :
- 🐛 [Bug](.github/ISSUE_TEMPLATE/bug_report.md) · 💡 [Idée / feature](.github/ISSUE_TEMPLATE/feature_request.md) · ✍ [Phrases coach / scénarios / traduction](.github/ISSUE_TEMPLATE/content_contribution.md)

Tout est expliqué dans **[CONTRIBUTING.md](CONTRIBUTING.md)**.

> Les contributions **éditoriales** (phrases coach, scénarios, surnoms, nouvelle langue) sont les plus précieuses et ne demandent **aucune compétence technique**. Le template Content guide vers le format à utiliser.
>
> Les contributeurs IA (ChatGPT, Claude, etc.) peuvent se référer à **[docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md)** — guide structuré des formats JSON acceptés par le générateur.

### 🛠 Curieux du code ?

Tout le projet Flutter vit dans **[`rhythm_coach/`](rhythm_coach/)** :
- **[Doc dev complète](rhythm_coach/README.md)** — features détaillées, build local, tests
- **[Architecture](rhythm_coach/CLAUDE.md)** — flow d'une séance, moteur d'excitation, mode Carrière, i18n
- **[Setup CI/CD](.github/RELEASE_SETUP.md)** — workflow de release auto

### 📝 Licence

Code et contenus éditoriaux sous **[PolyForm Noncommercial 1.0.0](LICENSE)**.

- ✅ Usage personnel, étude, modification, fork, redistribution non-commerciale.
- ❌ Vente, monetisation, fork « Premium » sur Telegram / Gumroad / store alternatif.

Les binaires hors-repo (gifs et mp3 d'ambiance) restent soumis aux droits de leurs sources d'origine.

---

## English

### In 30 seconds

- A **voice coach** speaking your language, locally — no network synthesis.
- **Guidance beeps** locked to a BPM to drive every move.
- 8 play modes, a Career mode that unlocks as you go, coaches with distinct personalities.
- **100% offline**: `INTERNET` permission not declared, nothing leaves your phone.
- **No Play Store, no ads, no IAP.** Distribution is direct signed APK.

### 📥 Download

➡ **[Releases page](../../releases)** — signed APK + its SHA256.

> ⚠ Android 9 minimum. Tested on Android 13/14.

### 📲 Install (side-load, step by step)

**Side-load** just means "install an app outside the Play Store". Android supports this natively — you just need to allow your browser or file manager to do it.

1. **On your phone**, open the [Releases page](../../releases) and download the latest `BeatBitch-X.Y.Z.apk`.
2. (*Optional but recommended*) Verify the SHA256 hash of the downloaded file matches the one published next to the APK. An app like **Hash Droid** on F-Droid does it in two taps.
3. Open the APK from your downloads.
4. Android will ask you to **allow this source**: tap "Settings", enable the permission for your browser (or file manager), come back and confirm.
5. Install runs. Once done, open BeatBitch.
6. **First launch**: 18+ confirmation (non-skippable), then 3 onboarding screens (phone placement, volume, voice test).

> 💡 You can disable "unknown sources" again after installing — Android won't reopen it unless you update the app.

### 🔄 Automatic updates (Obtainium)

The app stays **strictly offline** — it doesn't reach out for updates by itself. To get notified when a new version ships and install it in two taps, use **[Obtainium](https://github.com/ImranR98/Obtainium)**, an open-source Android store that watches GitHub Releases pages.

1. Install Obtainium (available on [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/) or as a direct APK from its repo).
2. In Obtainium: *Add App* → paste the URL `https://github.com/bbstudioapp/beatbitch`.
3. On every new release, Obtainium picks up the `BeatBitch-X.Y.Z.apk` and prompts you to update.

> No network traffic comes from BeatBitch itself — Obtainium queries GitHub on the user side, independently of the app. The 100% offline promise stays intact.

### 🔒 Is it safe?

- **APK signed** with the same key on every release — Android refuses to install a tampered APK (signature won't match).
- **Source code public** — you can read what runs (or have it read for you).
- **No network permission** — neither `INTERNET` nor `ACCESS_NETWORK_STATE`. The app *literally cannot* call out to a server.
- **`allowBackup="false"`** — no Google Backup upload.
- **Camera is opt-in** — the hold camera check is off by default and processing is 100% on-device (Google ML Kit local). No image leaves the phone.

Details in **[PRIVACY.md](docs/PRIVACY.md)** ([published version](https://bbstudioapp.github.io/beatbitch/PRIVACY)).

### 🎮 How to play

1. Drop your phone flat, on its side — no need to keep it in sight.
2. Pick a preset session or let Career mode generate one for you.
3. Follow the voice. Beeps mark the tempo (a low + a high alternating, or just one if you have to hold a position).
4. The **"I can't"** button is always available if you drop off. The coach takes over with a short punishment, then the session resumes where it makes sense.
5. At the end, the screen tells you what you unlocked (badges, career levels, milestones).

### 🐛 Found a bug, got an idea, want to contribute?

Issue templates available:
- 🐛 [Bug](.github/ISSUE_TEMPLATE/bug_report.md) · 💡 [Idea / feature](.github/ISSUE_TEMPLATE/feature_request.md) · ✍ [Coach lines / scenarios / translation](.github/ISSUE_TEMPLATE/content_contribution.md)

Everything is explained in **[CONTRIBUTING.md](CONTRIBUTING.md)**.

> **Editorial** contributions (coach lines, scenarios, nicknames, new languages) are the most valuable and **need no technical skill**. The Content template guides you to the right format.
>
> AI contributors (ChatGPT, Claude, etc.) should refer to **[docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md)** — a structured guide to the JSON formats the generator consumes.

### 🛠 Curious about the code?

The full Flutter project lives in **[`rhythm_coach/`](rhythm_coach/)**:
- **[Full dev README](rhythm_coach/README.md)** — detailed features, local build, tests
- **[Architecture](rhythm_coach/CLAUDE.md)** — session flow, excitation engine, Career mode, i18n
- **[CI/CD setup](.github/RELEASE_SETUP.md)** — auto-release workflow

### 📝 License

Code and editorial content under **[PolyForm Noncommercial 1.0.0](LICENSE)**.

- ✅ Personal use, study, modification, fork, noncommercial redistribution.
- ❌ Sale, monetization, "Premium" fork on Telegram / Gumroad / alternative store.

Off-repo binary assets (background gifs and ambience mp3s) remain subject to their original sources' rights.
