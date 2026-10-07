# Relecture adverse — `fix/audio-suivi-position` @ `a785a67` (2026-10-07)

Correctif écrit par `claude-opus-5-5` en direct avec Manu, jamais relu. Base : `origin/develop` @ `c57bdcd`.
Consigne de la relecture : chercher à réfuter, pas à valider. Aucun appareil, aucune compilation Android.

## Ce que la joueuse vivait

Pendant les longues séances, des bips sont lâchés et les couleurs arrivent en retard.

## Cause annoncée, rejouée dans la source d'audioplayers 6.6.0

`AudioPlayer()` pose par défaut un `FramePositionUpdater` (`audioplayer.dart:171`). Son `start()`
(`position_updater.dart:78`) appelle `_tick` qui fait un `getCurrentPosition` (un aller-retour canal
natif) puis se replanifie à **chaque image** tant que `_isRunning`. Il n'y a aucune garde contre un
`start()` déjà en cours : chaque `resume()` (`audioplayer.dart:277`) ajoute une chaîne de rappels de
plus, et `stop()` n'annule que le dernier identifiant. Les chaînes meurent à l'image suivante quand
`_isRunning` repasse à faux, c'est-à-dire sur `pause()`, `stop()` ou l'événement `complete`.

Conséquence sur develop : la boucle d'ambiance (`ReleaseMode.loop`, jamais « complete ») interroge sa
position 60 fois par seconde pendant toute la séance ; chaque bip ajoute une chaîne tant que son
sample joue, et un `resume()` sur un lecteur de pool pas encore fini en ajoute une seconde.

**Mesure rejouée (test, lecteurs factices qui n'émettent jamais `complete`)** : 8 bips puis 40 images
= 360 appels `getCurrentPosition` ; l'ambiance seule sur 30 images = 26 appels. Sur le correctif : 0.

Lecteurs de position dans l'application sur develop : aucun. Les deux seuls `AudioPlayer(` de
`lib/` sont ceux de `beep_engine.dart:266` et `ambience_engine.dart:47` ; aucun `onPositionChanged`
ni `getCurrentPosition`. `MusicEngine` (qui lit `onPositionChanged`) n'existe que sur
`essai/punition-musique-jouet`, sur son propre lecteur : il n'est pas touché par ce correctif, et une
fusion future ne doit pas lui couper son `positionUpdater`.

## Preuve rouge

| Sonde | Code | Résultat |
|---|---|---|
| test du correctif sur les deux moteurs de develop | `beep_engine.dart` + `ambience_engine.dart` de develop | rouge sur `getCurrentPosition == 0` : 360 (bips), 274 (ambiance) ; `resume >= 8` vert |
| ambiance de develop seule, bips corrigés | `ambience_engine.dart` de develop | rouge sur la seule assertion ambiance : 26 |

Restauration par copie de fichier, `git status` propre après chaque sonde.

Le 274 de l'ambiance sur develop n'est pas celui d'un seul lecteur : le `BeepEngine` du premier test
n'est jamais libéré, ses chaînes continuent de tourner pendant le second test (26 + 8 × 30 ≈ 274).
Le test ambiance tombe pour sa propre raison (26 > 0, sonde 2), mais il hérite de l'état du test
précédent.

## Casse cherchée

- `positionUpdater = null` en cascade juste après le constructeur : `dispose()` de l'updater par défaut
  (aucun rappel armé, fermeture du stream), puis `seek`/`release`/`dispose` d'`AudioPlayer` sont
  tous null-safe (`?.update()`, `if (_positionUpdater != null)`). Rien ne lit `onPositionChanged`
  sur ces lecteurs.
- Le correctif ne touche ni la planification des bips ni le pool ; les 1 103 tests de la suite
  passent.

## Suite complète (branche)

`flutter pub get` OK · `flutter analyze` : « No issues found! » · `flutter test` : **1103 tests,
All tests passed!** (`timeout 900`, sortie lue dans un fichier).

## Ce que je n'ai pas pu établir

- Le **27 % du fil Dart** : aucune mesure possible sans appareil. Le mécanisme est confirmé dans la
  source du plugin ; son poids réel sur le S21 reste la parole de l'auteur et le ressenti de Manu.
- Sur l'appareil, le nombre de chaînes simultanées est borné par l'événement `complete` des
  samples courts ; le test, lui, ne l'émet jamais. Les 360 appels du test surestiment donc le cas
  réel ; ils prouvent l'existence du mécanisme, pas son ampleur.
- Que la disparition des bips lâchés vienne bien de cette charge et pas d'un autre goulot (le
  `seek` borné à 250 ms, le `MediaPlayer` natif qui ne répond plus en fin de séance, déjà
  documentés dans `_trigger`).

## Verdict : **publiable avec réserves**

1. Le test ambiance dépend d'un `BeepEngine` jamais libéré par le test précédent (ordre des tests) :
   ajouter `await beep.dispose()` en fin de premier test, ou libérer dans un `tearDown`.
2. À la fusion avec toute branche qui porte `MusicEngine`, vérifier que son lecteur garde son
   `positionUpdater` : il lit la position.
3. Le gain réel sur le téléphone n'est pas mesuré ici ; le jugement de Manu sur le S21 reste la seule
   mesure.
