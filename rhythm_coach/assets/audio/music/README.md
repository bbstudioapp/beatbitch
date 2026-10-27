# Morceaux de séance

MP3 joués en fond d'une séance (champ `music` du JSON de séance). Hors dépôt :
le préfixe R2 `music/v1/` est synchronisé ici avant chaque build.

Aucun morceau n'est livré : la liste des séances n'en propose aucune avec musique.

`finish_music.mp3` : musique de la montée finale (hors séance musicale), même préfixe R2.
Sommet à 1:32 (92 s), calé sur le début du final.

## Musique de fin par coach

Une coach peut avoir son propre morceau de fin. Sans lui dans le bundle, et pour
toute séance sans coach, `finish_music.mp3` est joué.

| Coach    | Fichier attendu                | Sommet mesuré |
|----------|--------------------------------|---------------|
| Lina     | `finish_coach_01_lina.mp3`     | non branché : creux de 7 s, 101,4 s, 18 s après |
| Hélène   | `finish_coach_02_helene.mp3`   | non branché : creux de 8 s peu profond, 113,2 s, 5 s après |
| Jade     | `finish_coach_03_jade.mp3`     | 91,6 s (26,9 s après) |
| Morgan   | `finish_coach_04_morgan.mp3`   | non branché : aucun creux net |
| Victoria | `finish_coach_05_victoria.mp3` | non branché : aucun creux net |
| Nyx      | `finish_coach_06_nyx.mp3`      | non branché : creux de 8 s, 107,0 s, 12 s après |
| Marc     | `finish_coach_07_marc.mp3`     | non branché : creux de 4 s, 106,7 s, 13 s après |
| Lilith   | `finish_coach_08_lilith.mp3`   | non branché : creux de 4,5 s, 97,3 s, 22 s après |

Pour en brancher un : déposer le MP3 sous `music/v1/` sur R2, puis ajouter une
ligne à `AmbienceEngine.coachFinishTracks` (`lib/services/ambience_engine.dart`),
clé = slug de la coach, sommet mesuré sur ce morceau (fin du creux de ~2 s : saut de la loudness
momentanée `ffmpeg ebur128` derrière un passe-bas 150 Hz) :

```dart
'lina': (asset: 'audio/music/finish_coach_01_lina.mp3', peak: Duration(seconds: 92)),
```
