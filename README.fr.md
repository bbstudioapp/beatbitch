# BeatBitch

![version](https://img.shields.io/badge/version-0.4.1-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Web-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)
![no tracking](https://img.shields.io/badge/no-tracking-success)
![license](https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-lightgrey)

> **Coach vocal rythmique immersif pour Android, Windows, Linux, iOS (PWA) & web.** Tu poses ton téléphone à plat sur le côté, tu lances la séance, tu fermes les yeux. Une voix te guide, des bips marquent le rythme, tu n'as plus besoin de regarder l'écran.

**Langues** : [English](README.md) · Français · [Deutsch](README.de.md)

---

## En 30 secondes

- Une **voix de coach** qui parle dans ta langue, en local — aucune synthèse réseau.
- Des **bips de guidage** calés au BPM pour rythmer chaque mouvement.
- 8 modes de jeu, un mode Carrière qui se débloque au fil des séances, des coachs avec des personnalités différentes.
- **100 % hors-ligne** sur Android : permission `INTERNET` non déclarée, rien ne sort de ton téléphone.
- **Pas de Play Store, pas de pub, pas d'achat in-app.** Distribution APK signé direct (Android), zip portable (desktop), web app installable (iOS / navigateur).

## 📥 Télécharger

➡ **[Page Releases](../../releases)** — APK signé + son SHA256.

> ⚠ Android 9 minimum. Testé sur Android 13/14.

## 📲 Installer sur Android (side-load, étape par étape)

Le **side-load**, c'est juste « installer une app sans passer par le Play Store ». Android le permet nativement, il faut juste autoriser ton navigateur ou ton gestionnaire de fichiers à le faire.

1. **Sur ton téléphone**, ouvre la [page Releases](../../releases) et télécharge le fichier `BeatBitch-X.Y.Z.apk` le plus récent.
2. (*Optionnel mais recommandé*) Vérifie l'empreinte SHA256 du fichier téléchargé — elle doit correspondre à celle publiée à côté de l'APK. Une appli comme **Hash Droid** sur F-Droid fait ça en 2 clics.
3. Ouvre le fichier APK dans tes téléchargements.
4. Android va te demander d'**autoriser cette source** : tape « Paramètres » → active l'autorisation pour ton navigateur (ou gestionnaire de fichiers). Reviens et confirme.
5. L'install démarre. Une fois fini, ouvre BeatBitch.
6. **Au 1er lancement** : confirmation 18+ (non-skippable), puis 3 écrans d'onboarding (pose du téléphone, volume, test de la voix).

> 💡 Tu peux désactiver l'autorisation « sources inconnues » après l'install — Android ne la rouvrira pas tant que tu ne mets pas l'app à jour.

## 🍎 Installer sur iPhone / iPad (PWA)

BeatBitch n'est **pas** disponible sur l'App Store (Apple n'autorise pas le contenu adulte). Sur iOS, on diffuse une **version web installable** (PWA). Une fois ajoutée à l'écran d'accueil, elle se comporte comme une vraie app : icône dédiée, plein écran, pas de barre Safari, fonctionne hors-ligne après le premier chargement.

1. Sur ton iPhone / iPad (iOS 16.4+), ouvre **Safari** (pas Chrome / Firefox — Apple bloque l'install PWA depuis ces navigateurs).
2. Va sur **[beatbitch.pages.dev](https://beatbitch.pages.dev)** et attends que la page soit entièrement chargée (l'app entière est téléchargée la première fois).
3. Tape le bouton **Partager** → **Sur l'écran d'accueil** → **Ajouter**.
4. Lance BeatBitch depuis l'écran d'accueil. Premier lancement : adult gate 18+, puis onboarding 3 étapes.

> Guide détaillé : **[docs/INSTALL-iOS.fr.md](docs/INSTALL-iOS.fr.md)**.
>
> ⚠ La version web/iOS utilise la **synthèse vocale native iOS** (pas les voix Android). La vérif caméra des holds et les notifications surprise ne sont pas disponibles. Le premier chargement requiert une connexion Internet ; tout le reste tourne hors-ligne depuis l'icône d'accueil.

## 🌐 Utiliser dans un navigateur desktop

Même URL que sur iOS — **[beatbitch.pages.dev](https://beatbitch.pages.dev)** fonctionne dans n'importe quel navigateur récent (Chrome, Edge, Firefox, Safari). Pratique pour essayer l'app avant d'installer l'APK ou le build desktop. La qualité vocale dépend du moteur TTS de ton OS.

## 🖥 Installer sur Windows desktop

Disponible depuis **v0.1.3**. C'est un zip portable, pas un installateur — l'app ne touche ni au registre Windows ni aux dossiers système.

1. Sur la [page Releases](../../releases), télécharge `BeatBitch-X.Y.Z-windows-x64.zip` (et son `.sha256` si tu veux vérifier l'intégrité).
2. Dézippe où tu veux : `C:\Users\toi\Documents\BeatBitch\`, une clé USB, peu importe.
3. Lance `rhythm_coach.exe`. Windows SmartScreen peut afficher un avertissement (le binaire n'est pas signé par un éditeur reconnu) → clique « Informations supplémentaires » → « Exécuter quand même ».
4. Premier lancement : adult gate 18+, puis onboarding 3 étapes (identique à Android).

> ⚠ **Fonctions désactivées sur Windows** : la vérif caméra des holds et les notifications surprise ne sont pas portées (les plugins natifs n'existent pas pour Windows). La voix coach utilise **Microsoft Julie** (SAPI) à la place des voix Android. Sessions, mode Carrière, coachs, badges, langues : tout fonctionne identique à Android.

## 🐧 Installer sur Linux desktop

Disponible depuis **v0.3.0**. C'est un `tar.gz` portable, pas un paquet `.deb`/`.rpm` — l'app reste dans son dossier, rien n'est installé dans le système.

1. Sur la [page Releases](../../releases), télécharge `BeatBitch-X.Y.Z-linux-x64.tar.gz` (et son `.sha256` pour vérifier l'intégrité).
2. Vérifie l'empreinte : `sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256`.
3. Décompresse où tu veux : `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Lance le binaire : `./BeatBitch-X.Y.Z-linux-x64/beat_bitch` (clic droit → *Autoriser l'exécution* dans ton gestionnaire de fichiers si nécessaire).
5. Premier lancement : adult gate 18+, puis onboarding 3 étapes (identique à Android).

> ⚠ **Fonctions désactivées sur Linux** : la vérif caméra des holds et les notifications surprise ne sont pas portées. La voix coach utilise la voix par défaut de **Speech Dispatcher** (typiquement `espeak-ng` sur Ubuntu/Debian — installe une voix française/anglaise via ton gestionnaire de paquets si la voix par défaut ne sonne pas bien). Sessions, mode Carrière, coachs, badges, langues : tout fonctionne identique à Android.

## 🔄 Mises à jour automatiques (Obtainium)

L'app Android reste **strictement hors-ligne** : elle ne va pas chercher d'update toute seule. Pour être prévenu quand une nouvelle version sort et l'installer en deux taps, utilise **[Obtainium](https://github.com/ImranR98/Obtainium)** — un store Android open-source qui surveille les pages GitHub Releases.

1. Installe Obtainium (dispo sur [F-Droid](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/) ou en APK direct depuis son repo).
2. Dans Obtainium : *Add App* → colle l'URL `https://github.com/bbstudioapp/beatbitch`.
3. À chaque nouvelle release, Obtainium détecte l'APK `BeatBitch-X.Y.Z.apk` et te propose la mise à jour.

> Aucun trafic réseau n'est généré par BeatBitch elle-même — c'est Obtainium qui interroge GitHub côté utilisateur, indépendamment de l'app. La promesse 100 % hors-ligne reste intacte.

## 🔒 C'est safe ?

- **APK signé** par la même clé à chaque release — Android refuse l'install si quelqu'un essaie de te refiler un APK trafiqué (la signature ne matchera pas).
- **Code source public** — tu peux relire ce qui tourne (ou le faire relire).
- **Aucune permission réseau** (Android) — ni `INTERNET`, ni `ACCESS_NETWORK_STATE`. L'app Android ne *peut* littéralement pas appeler un serveur.
- **`allowBackup="false"`** — pas de remontée vers Google Backup.
- **Caméra opt-in** — la vérif caméra des holds est désactivée par défaut, et le traitement reste 100 % on-device (Google ML Kit local). Aucune image ne quitte le téléphone.

Détails dans **[PRIVACY.md](docs/PRIVACY.fr.md)** ([version publiée](https://bbstudioapp.github.io/beatbitch/PRIVACY)).

## 🎮 Comment ça se joue

1. Pose ton téléphone à plat, sur le côté — pas besoin de l'avoir devant les yeux.
2. Choisis une séance prédéfinie ou laisse le mode Carrière t'en générer une.
3. Suis la voix. Les bips marquent le tempo (un grave + un aigu qui alternent, ou un seul si la séance demande de tenir une position).
4. Le bouton **« Je peux pas »** est toujours dispo si tu décroches. La coach prend le relais avec une punition courte, puis la séance reprend là où ça avait du sens.
5. À la fin, l'écran te dit ce que tu as débloqué (badges, niveaux carrière, milestones).

## 🐛 Trouver un bug, suggérer une idée, contribuer

Templates d'issues disponibles :
- 🐛 [Bug](.github/ISSUE_TEMPLATE/bug_report.md) · 💡 [Idée / feature](.github/ISSUE_TEMPLATE/feature_request.md) · ✍ [Phrases coach / scénarios / traduction](.github/ISSUE_TEMPLATE/content_contribution.md)

Tout est expliqué dans **[CONTRIBUTING.md](CONTRIBUTING.fr.md)**.

> Les contributions **éditoriales** (phrases coach, scénarios, surnoms, nouvelle langue) sont les plus précieuses et ne demandent **aucune compétence technique**. Le template Content guide vers le format à utiliser.
>
> Les contributeurs IA (ChatGPT, Claude, etc.) peuvent se référer à **[docs/CONTENT_GUIDE.md](docs/CONTENT_GUIDE.md)** — guide structuré des formats JSON acceptés par le générateur.

## 🛠 Curieux du code ?

Tout le projet Flutter vit dans **[`rhythm_coach/`](rhythm_coach/)** :
- **[Setup développeur](docs/DEVELOPMENT.fr.md)** — installer Flutter, run par plateforme (Android, Windows, web Chrome), customiser les assets sans coder
- **[Doc utilisateur Flutter](rhythm_coach/README.fr.md)** — features détaillées, install par plateforme
- **[Setup CI/CD](.github/RELEASE_SETUP.md)** — workflow de release auto

## 📝 Licence

Code et contenus éditoriaux sous **[PolyForm Noncommercial 1.0.0](LICENSE)**.

- ✅ Usage personnel, étude, modification, fork, redistribution non-commerciale.
- ❌ Vente, monetisation, fork « Premium » sur Telegram / Gumroad / store alternatif.

Les binaires hors-repo (gifs et mp3 d'ambiance) restent soumis aux droits de leurs sources d'origine.
