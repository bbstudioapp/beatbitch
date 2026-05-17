# BeatBitch

![version](https://img.shields.io/badge/version-0.4.1-orange)
![platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux-blue)
![offline](https://img.shields.io/badge/100%25-offline-blue)

> Coach vocal rythmique immersif. Le téléphone est posé sur le côté, tu n'as pas besoin de regarder l'écran : tout passe par la voix et les bips de guidage.

**Langues** : [English](README.md) · Français · [Deutsch](README.de.md)

---

## Captures d'écran

> _Captures à venir — l'app est en alpha privée._

<p>
  <em>placeholder</em> · accueil · session · sons · profil · badges
</p>

## Fonctionnalités

- **Coach vocal TTS féminin**, ton ferme, voix locale (aucune synthèse réseau).
- **8 modes de jeu** : rythme, lick, biffle, hold, breath, beg, freestyle, hand.
- **Mode Carrière** : 20+ niveaux, 6 branches de spécialisation, milestones d'apprentissage, encore enchaîné, sessions bâclées, badges de progression.
- **Scénarios libres** : sessions JSON éditables, punitions et commentaires aléatoires extensibles sans toucher au code.
- **Vérif caméra des holds** (expérimental, opt-in) : détection on-device via Google ML Kit, jamais d'image envoyée nulle part.
- **Multi-langue** : français, anglais et allemand livrés ; autres langues = simple ajout d'assets.
- **Adult gate 18+** non-skippable au premier lancement, onboarding 3 écrans.

## 100 % offline · pas de télémétrie

Aucune donnée ne quitte ton téléphone. Permission `INTERNET` non déclarée. ML Kit tourne en local. Voir [PRIVACY.md](PRIVACY.md).

## Installation (side-load Android)

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

## Installation (Windows desktop)

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

## Installation (Linux desktop)

Disponible depuis v0.3.0 — `tar.gz` portable, aucun paquet `.deb`/`.rpm`.

1. Télécharger `BeatBitch-X.Y.Z-linux-x64.tar.gz` depuis la page Releases.
2. Vérifier le SHA256 :
   ```bash
   sha256sum -c BeatBitch-X.Y.Z-linux-x64.tar.gz.sha256
   ```
3. Décompresser où tu veux : `tar -xzf BeatBitch-X.Y.Z-linux-x64.tar.gz`.
4. Lancer le binaire : `./BeatBitch-X.Y.Z-linux-x64/beat_bitch`.
5. Au 1er lancement : adult gate 18+, puis onboarding 3 étapes.

> ⚠ Fonctions désactivées sur Linux : vérif caméra des holds, notifications
> surprise. La voix coach utilise la voix par défaut de Speech Dispatcher
> (typiquement `espeak-ng`). Le reste — sessions, mode carrière, coachs,
> badges, i18n — fonctionne identique à Android.

## Mises à jour automatiques (Obtainium)

L'app reste **strictement hors-ligne** : elle ne va pas chercher d'update toute seule. Pour être prévenu quand une nouvelle version sort, utilise **[Obtainium](https://github.com/ImranR98/Obtainium)** — un store Android open-source qui surveille les pages GitHub Releases. *Add App* → colle `https://github.com/bbstudioapp/beatbitch`. Aucun trafic réseau n'est généré par BeatBitch elle-même : c'est Obtainium qui interroge GitHub côté utilisateur, indépendamment de l'app.

## Build local (développeurs)

```bash
cd rhythm_coach
flutter pub get
flutter analyze       # doit retourner "No issues found!"
flutter test
flutter run           # device Android / `-d windows` / `-d chrome` selon la cible
flutter build apk --release
flutter build windows --release
```

Le contenu éditorial vit dans `assets/` (sessions JSON, punitions, commentaires aléatoires, packs d'ambiance, banque de phrases carrière). Setup complet par plateforme + paths de personnalisation : **[`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.fr.md)**.

> ⚠ **Assets binaires externalisés** : les dossiers `assets/backgrounds/` (GIF/images de fond) et `assets/audio/ambience/` (MP3 d'ambiance) sont **gitignorés** — leurs fichiers ne sont pas versionnés dans le dépôt et doivent être rapatriés depuis un canal externe (à venir) avant `flutter build`. Le code se débrouille gracieusement si ces dossiers sont vides : le fond retombe sur un dégradé animé, l'ambiance sur du silence.

## Vie privée

Voir [PRIVACY.md](PRIVACY.md) — version courte : aucune collecte, tout est local, `allowBackup="false"`.

## Licence

Code et contenus éditoriaux (sessions JSON, phrases coach, commentaires aléatoires, surnoms, milestones, etc.) sous **[PolyForm Noncommercial License 1.0.0](../LICENSE)**.

- ✅ **Étudier, forker, modifier, redistribuer** pour usage non-commercial.
- ✅ **Contributions bienvenues** — nouvelles phrases coach, sessions, traductions, fixes de code, idées de spécialisation, etc. Ouvre une issue ou une PR.
- ❌ **Vente, monetisation, redistribution commerciale** interdites — pas de fork "BeatBitch Premium" sur Telegram, Gumroad ou un store alternatif.

Les binaires hors-repo (`assets/backgrounds/*.gif`, `assets/audio/ambience/*.mp3`) restent soumis aux droits de leurs sources d'origine et ne sont pas couverts par cette licence.

## Signalement de bugs

Ouvre une issue sur le dépôt. Merci d'inclure le modèle de téléphone, la version Android et les étapes pour reproduire.
