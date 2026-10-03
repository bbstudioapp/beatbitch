# Sons d'ambiance

Dépose ici des MP3 de loop d'ambiance (pluie, vent, vagues, drone…).

**Référencés par `assets/ambience_packs.json`** — si tu ajoutes un nouveau
pack ou modifies un mapping mode→fichier, édite ce JSON. Pas de modif
code nécessaire.

## Recommandations

- **Format** : MP3, mono ou stéréo, ~128 kbps suffit (économie de poids APK).
- **Durée** : entre 30 s et 2 min (lecture en boucle via `ReleaseMode.loop`).
- **Boucle propre** : le fichier doit pouvoir reboucler sans clic audible
  (fade-in/fade-out à 0 sur les 100 premières/dernières ms si possible).
- **Niveau** : pré-normaliser à -20 LUFS environ. Le moteur applique
  ensuite un volume max de 0.5 (cf. `AmbienceEngine.maxVolume`) pour
  rester sous les bips de guidage.

## Fichiers attendus par les packs livrés

| Pack    | Mode    | Fichier                  |
|---------|---------|--------------------------|
| intime  | rhythm  | `deep_drone.mp3`         |
| intime  | lick    | `warm_drone.mp3`         |
| intime  | biffle  | `heartbeat.mp3`          |
| intime  | hold    | `tension_drone.mp3`      |
| intime  | breath  | `warm_pad.mp3`           |
| nature  | rhythm  | `rain.mp3`               |
| nature  | lick    | `rain_light.mp3`         |
| nature  | biffle  | `rain.mp3`               |
| nature  | hold    | `wind.mp3`               |
| nature  | breath  | `ocean.mp3`              |
| studio  | rhythm  | `drone_low.mp3`          |
| studio  | lick    | `drone_low.mp3`          |
| studio  | biffle  | `drone_low.mp3`          |
| voix_homme | rhythm, freestyle | peu profond `homme_rythme_leger_1/2.mp3`, profond `homme_rythme_profond_1/2.mp3` |
| voix_homme | lick, suckle | `homme_lick_1/2.mp3` |
| voix_homme | biffle | `homme_biffle.mp3` |
| voix_homme | hold | peu profond `tenue_legere_1/2.mp3`, profond `tenue_profonde_1/2.mp3` |
| voix_homme | breath | `elle_souffle.mp3` |
| voix_homme | hand | `homme_main.mp3` |
| voix_femme | rhythm, freestyle | peu profond `femme_rythme_leger_1/2.mp3`, profond `femme_rythme_profond_1/2.mp3` |
| voix_femme | lick, suckle | `femme_lick_1/2.mp3` |
| voix_femme | biffle | `femme_biffle.mp3` |
| voix_femme | hold | peu profond `tenue_legere_1/2.mp3`, profond `tenue_profonde_1/2.mp3` |
| voix_femme | breath | `elle_souffle.mp3` |
| voix_femme | hand | `femme_main.mp3` |

Le pack `intime` est généré synthétiquement par
`tools/generate_ambience.sh` (sinusoïdes harmoniques + filtres ffmpeg,
loop propre via fades symétriques). Ré-exécute le script pour
régénérer ou pour ajuster les fréquences/durées.

Les packs `voix_homme` et `voix_femme` sont des boucles de ~48 s montées
à partir de sons générés par ElevenLabs.

Une piste peut lister plusieurs variantes, tirées au hasard, et les séparer
par palier de profondeur : `{"shallow": [...], "deep": [...]}` (profond =
throat, full, balls).

Si un fichier manque, le pack reste sélectionnable dans l'UI mais le
mode concerné jouera en silence. C'est volontaire (fail-safe).
