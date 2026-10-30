# Morceaux de séance

MP3 joués en fond d'une séance (champ `music` du JSON de séance). Hors dépôt :
le préfixe R2 `music/v1/` est synchronisé ici avant chaque build.

Aucun morceau n'est livré : la liste des séances n'en propose aucune avec musique.

`finish_music.mp3` : musique de la montée finale (hors séance musicale), même préfixe R2.
Sommet à 1:32 (92 s), calé sur le début du final.

## Musique de fin par coach

Une coach peut avoir son propre morceau de fin. Sans lui dans le bundle, et pour
toute séance sans coach, `finish_music.mp3` est joué.

| Coach    | Fichier                        | Sommet | Musique après le sommet |
|----------|--------------------------------|--------|-------------------------|
| Lina     | `finish_coach_01_lina.mp3`     | 101,4 s | 18 s |
| Hélène   | `finish_coach_02_helene.mp3`   | 113,2 s | 5 s |
| Jade     | `finish_coach_03_jade.mp3`     | 91,6 s | 27 s |
| Morgan   | `finish_coach_04_morgan.mp3`   | 90,2 s (estimé, sans creux net) | 30 s |
| Victoria | `finish_coach_05_victoria.mp3` | 77,3 s (estimé, sans creux net) | 42 s |
| Nyx      | `finish_coach_06_nyx.mp3`      | 107,0 s | 12 s |
| Marc     | `finish_coach_07_marc.mp3`     | 106,7 s | 13 s |
| Lilith   | `finish_coach_08_lilith.mp3`   | 97,3 s | 22 s |

Quand la musique s'arrête avant la fin de l'explosion, le silence est voulu.
Estimé : sans creux, sommet = plus forte montée de la bande basse entre 60 et 105 s.

Pour en brancher ou en remplacer un : déposer le MP3 sous `music/v1/` sur R2, puis ajouter
une ligne à `AmbienceEngine.coachFinishTracks` (`lib/services/ambience_engine.dart`),
clé = slug de la coach, sommet mesuré sur ce morceau (sortie du creux : saut de la loudness
momentanée `ffmpeg ebur128` derrière un passe-bas 150 Hz) :

```dart
'lina': (asset: 'audio/music/finish_coach_01_lina.mp3', peak: Duration(seconds: 92)),
```
