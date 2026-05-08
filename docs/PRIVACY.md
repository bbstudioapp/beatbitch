# Privacy Policy — BeatBitch

_Last updated: 2026-05-08 · App version 0.1.0_

🇫🇷 **[Français](#français)** &nbsp;|&nbsp; 🇬🇧 **[English](#english)**

---

## Français

### En une phrase

**BeatBitch est 100 % hors-ligne. Aucune donnée ne quitte ton téléphone.**

### Détails

- **Aucune télémétrie, aucun analytics, aucun crash reporter.** Pas de SDK tiers de tracking.
- **Aucun compte, aucune identification.** L'app ne te demande ni email, ni pseudo, ni numéro de téléphone.
- **Permission `INTERNET` non déclarée** dans le manifeste Android. Le système d'exploitation refuse donc toute tentative de connexion réseau, même hypothétique.
- **Permission `CAMERA`** : optionnelle, demandée uniquement si tu actives le toggle « Vérif caméra des holds » dans l'écran SONS. Le flux vidéo est traité **localement** par Google ML Kit (modèle on-device) pour détecter la position du visage. Aucune image, aucun landmark, aucune métadonnée n'est transmis à un serveur. Le flux n'est jamais enregistré sur le disque.
- **Stockage local uniquement** : tes préférences (volume, voix TTS, langue, calibration caméra) et tes statistiques de jeu (compteurs, badges, niveau, jauges d'humiliation/obédience) sont persistées via `SharedPreferences` dans le sandbox de l'app.
- **`android:allowBackup="false"`** dans le manifeste : aucune sauvegarde automatique vers le cloud Google. Si tu désinstalles l'app, tes données disparaissent avec.
- **TTS local uniquement** : la voix est synthétisée par le moteur Android Text-to-Speech installé sur ton appareil. Aucune synthèse réseau (les voix `-network` du moteur sont explicitement filtrées).
- **Audio** : l'app joue uniquement les bips et samples bundlés dans l'APK. Pas de streaming, pas de téléchargement.

### Modèle ML Kit

Au premier lancement, Google ML Kit peut télécharger automatiquement son modèle de détection de visages (~3 Mo) **via le service Google Play Services**, indépendamment de l'app. Ce téléchargement est géré par Android, pas par BeatBitch — l'app elle-même ne fait toujours aucun appel réseau. Le modèle reste ensuite local et fonctionne sans connexion.

### Contact

Bug, question, demande de précision : ouvre un issue sur le dépôt du projet. Pas d'email de support pour cette version alpha.

### Modifications

Cette politique peut évoluer si l'app gagne des fonctionnalités. Toute mise à jour sera annoncée dans le changelog de la release et la date en haut de ce fichier mise à jour.

---

## English

### In one sentence

**BeatBitch is 100% offline. No data ever leaves your phone.**

### Details

- **No telemetry, no analytics, no crash reporter.** No third-party tracking SDK.
- **No account, no identifier.** The app doesn't ask for email, username, or phone number.
- **`INTERNET` permission is not declared** in the Android manifest. The OS therefore refuses any network connection attempt, even hypothetical.
- **`CAMERA` permission**: optional, requested only if you enable the "Hold camera check" toggle in the SOUNDS screen. The video stream is processed **locally** by Google ML Kit (on-device model) to detect face position. No image, landmark, or metadata is transmitted to any server. The stream is never written to disk.
- **Local storage only**: your preferences (volume, TTS voice, language, camera calibration) and gameplay stats (counters, badges, level, humiliation/obedience meters) are persisted via `SharedPreferences` inside the app sandbox.
- **`android:allowBackup="false"`** in the manifest: no automatic backup to Google cloud. If you uninstall the app, your data is gone with it.
- **Local TTS only**: voice is synthesized by the Android Text-to-Speech engine installed on your device. No network synthesis (the engine's `-network` voices are explicitly filtered out).
- **Audio**: the app only plays the beeps and samples bundled inside the APK. No streaming, no downloads.

### ML Kit model

On first launch, Google ML Kit may automatically download its face detection model (~3 MB) **via Google Play Services**, independently of the app. This download is handled by Android itself, not by BeatBitch — the app still makes no network calls of its own. The model then stays local and works offline.

### Contact

Bug reports, questions, clarifications: open an issue on the project repo. No support email for this alpha version.

### Changes

This policy may evolve as the app gains features. Any update will be announced in the release changelog and the date at the top of this file will be updated.
