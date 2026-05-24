# Politique de confidentialité — BeatBitch

_Dernière mise à jour : 2026-05-08 · Version de l'app 0.1.0_

**Langues** : [English](PRIVACY.md) · Français · [Deutsch](PRIVACY.de.md)

---

## En une phrase

**BeatBitch est 100 % hors-ligne. Aucune donnée ne quitte ton téléphone.**

## Détails

- **Aucune télémétrie, aucun analytics, aucun crash reporter.** Pas de SDK tiers de tracking.
- **Aucun compte, aucune identification.** L'app ne te demande ni email, ni pseudo, ni numéro de téléphone.
- **Permission `INTERNET` non déclarée** dans le manifeste Android. Le système d'exploitation refuse donc toute tentative de connexion réseau, même hypothétique.
- **Permission `CAMERA`** : optionnelle, demandée uniquement si tu actives le toggle « Vérif caméra des holds » dans l'écran SONS. Le flux vidéo est traité **localement** par Google ML Kit (modèle on-device) pour détecter la position du visage. Aucune image, aucun landmark, aucune métadonnée n'est transmis à un serveur. Le flux n'est jamais enregistré sur le disque.
- **Stockage local uniquement** : tes préférences (volume, voix TTS, langue, calibration caméra) et tes statistiques de jeu (compteurs, badges, niveau, jauges d'humiliation/obédience) sont persistées via `SharedPreferences` dans le sandbox de l'app.
- **`android:allowBackup="false"`** dans le manifeste : aucune sauvegarde automatique vers le cloud Google. Si tu désinstalles l'app, tes données disparaissent avec.
- **TTS local uniquement** : la voix est synthétisée par le moteur Android Text-to-Speech installé sur ton appareil. Aucune synthèse réseau (les voix `-network` du moteur sont explicitement filtrées).
- **Audio** : l'app joue uniquement les bips et samples bundlés dans l'APK. Pas de streaming, pas de téléchargement.

## Modèle ML Kit

Au premier lancement, Google ML Kit peut télécharger automatiquement son modèle de détection de visages (~3 Mo) **via le service Google Play Services**, indépendamment de l'app. Ce téléchargement est géré par Android, pas par BeatBitch — l'app elle-même ne fait toujours aucun appel réseau. Le modèle reste ensuite local et fonctionne sans connexion.

## Contact

Bug, question, demande de précision : ouvre un issue sur le dépôt du projet. Pas d'email de support pour cette version alpha.

## Modifications

Cette politique peut évoluer si l'app gagne des fonctionnalités. Toute mise à jour sera annoncée dans le changelog de la release et la date en haut de ce fichier mise à jour.
