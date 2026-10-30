---
type: analyse
sujet: relecture-adverse-round-2-de-la-seance-musicale
ecrit_le: 2026-09-23T23:24:12+02:00
auteur: session tss2-relecture-musique-2 · claude-opus-5-5
revision: 41f76c1
branche: feat/seance-musicale
porte_sur:
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers-6.6.0/lib/src/audioplayer.dart
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers_android-5.2.1/android/src/main/kotlin/xyz/luan/audioplayers/player/WrappedPlayer.kt
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers_darwin-6.4.0/darwin/audioplayers_darwin/Sources/audioplayers_darwin/WrappedMediaPlayer.swift
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers_web-5.2.0/lib/wrapped_player.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/music_clock.dart
  - rhythm_coach/lib/services/music_engine.dart
  - rhythm_coach/test/session_music_controller_test.dart
provenance:
  mesure: 5
  deduit: 17
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers-6.6.0/lib/src/audioplayer.dart:158
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers_android-5.2.1/android/src/main/kotlin/xyz/luan/audioplayers/player/WrappedPlayer.kt:298
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers_darwin-6.4.0/darwin/audioplayers_darwin/Sources/audioplayers_darwin/WrappedMediaPlayer.swift:271
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers_web-5.2.0/lib/wrapped_player.dart:134
  - rhythm_coach/lib/controllers/session_controller.dart:666
---

## Verdict : publiable avec réserves

[mesuré] R1 est levé sur tous les chemins que j'ai pu rejouer ou lire. Le rouge tombe sur le code d'avant et le vert tient après. Le câblage réel (`onPlayerComplete`) est juste sur Android, iOS et web d'après le code des plugins embarqués. Sur les trois, l'événement de fin arrive côté Dart avant le rapport de position 0. À `41f76c1` : suite complète 1178/1178, `flutter analyze` « No issues found! », `dart format --set-exit-if-changed .` 0 fichier changé.

[déduit] Les réserves : (1) le repère « Fin » sur le S21 reste la seule preuve du câblage réel, puisque M6 est toujours verte (`tss2-014`) ; (2) un trou de filet : la fin reçue pendant une pause (M8) n'est gardée par aucun test, alors que le code est juste ; (3) un risque antérieur au correctif, qu'il rend plus visible : `playerId` fixe, fiche `tss2-015`. Aucun défaut du correctif lui-même : je n'ai rien corrigé.

## 1. R1 est-il levé ?

[mesuré] Rejeu : `music_clock.dart` et `music_engine.dart` de `1f2f347`, sous `session_music_controller_test.dart` de `HEAD`. Résultat : 14 tests verts, 5 rouges, exactement les 5 tests R1 du rapport (fin du morceau, 0 avant la fin, FAIL qui déborde, stop dans la queue, pause/reprise dans la queue). Les deux fichiers ont été restaurés par `git checkout` et l'arbre est propre. Au vert, les 19 tests passent dans la suite complète.

| [mesuré] Mutation que j'ai posée (motif unique vérifié, `git diff` non vide, restaurée) | Sur 52 tests musique |
|---|---|
| M7 : `_ended = false;` retiré de `MusicClock.start` | rouge, 1 test : « la fin survit à une pause… start la remet à zéro » |
| M8 : `end()` ignoré en état `paused` | **verte** |
| M9 : `_peak = Duration.zero;` retiré de `MusicEngine.start` | **verte** |
| M-R2 : `_currentHoldFullDuration = 0;` retiré de `_triggerMusicalFail` | rouge, `Expected: <8>  Actual: <12>` |

- **Relance sur le même `MusicEngine`** : [déduit] `start()` depuis `finished` est accepté par le contrôleur et rappelle `music.start`. `_clock.start()` remet alors `_ended` à faux, et M7 le garde au niveau de l'horloge. Sans cela, l'horloge resterait en `waiting` : position 0 à vie, séance figée. Aucun test moteur ni contrôleur ne relance après une fin, et aucun écran ne relance un contrôleur fini (les deux appels à `start()` sont dans `session_screen.dart`, à l'ouverture). M9 est sans effet avec un seul morceau : le `_peak` resté du premier passage vaut la fin du même morceau.
- **Même `playerId`, contrôleurs successifs** : [déduit] risque antérieur au correctif, fiche `tss2-015`. La fin de lecture passe par le canal d'événements, que le dispose différé d'un ancien lecteur au même nom peut couper. Chevauchement non reproduit.
- **Seek** : [déduit] ni `MusicEngine` ni le contrôleur ne font de seek sur le morceau. Chemin inexistant.
- **Pause/reprise autour de la fin** : [déduit] une pause posée dans la queue est couverte (M4 du rapport). Une fin reçue pendant une pause ne peut arriver que si `pause` n'a pas atteint le lecteur (borne de 300 ms dépassée, ou fin tombée dans la même frame). Le code actuel pose alors `_ended` et la reprise ne relance pas le lecteur. Mais M8 est verte : si cette branche disparaissait, la reprise relancerait le morceau depuis 0 et R1 reviendrait. Trou de filet, pas un défaut.
- **FAIL dans la queue** : [déduit] le FAIL musical ne touche pas au lecteur. Un FAIL posé après la fin suit le même chemin que le test « FAIL dont le souffle déborde la fin » (`_onTick` termine à la durée et coupe le souffle). Pas de test propre à ce cas.
- **Une fin qui n'est pas la fin du morceau** : [document] sur Android, `WrappedPlayer.onError` renvoie `false` (`audioplayers_android` 5.2.1). MediaPlayer appelle alors `onCompletion`, donc `completions` se déclenche en plein morceau après une erreur de lecture. [déduit] Avec le correctif, l'horloge court alors seule depuis sa position extrapolée : les bips restent sur la grille et la séance se termine à 179 s, en silence. Avant, `getCurrentPosition` renvoyait `null` (lecteur plus `prepared`) et l'horloge extrapolait déjà. Neutre à légèrement meilleur.

## 2. Le câblage réel : l'événement arrive-t-il, et dans quel ordre ?

[document] Côté Dart (`audioplayers` 6.6.0) : `onPlayerComplete` = `eventStream.where(complete)`, sur un `StreamController.broadcast`. L'abonnement interne du plugin, posé dans le constructeur, passe avant celui de `AudioplayersMusicPort`. Il met l'état à `completed`, puis appelle `stopAndUpdate()` : l'arrêt du `FramePositionUpdater` est synchrone, la relecture de position attend un appel de plateforme. Notre écouteur reçoit donc l'événement **avant** le rapport que publie `stopAndUpdate`. Les positions viennent d'un sondage `getCurrentPosition` à chaque frame, non attendu : des réponses en vol peuvent arriver après l'événement, et `_ended` les ignore.

| [document] Plateforme (`pubspec.lock`) | Fin de lecture native | Ordre vu par Dart |
|---|---|---|
| Android 5.2.1 | `onCompletion` : `stop()` → `seekTo(0)`, **puis** `handleComplete` (même thread principal) | fin d'abord : un sondage traité après `onCompletion` répond après l'événement, un sondage traité avant rend la position de fin |
| iOS/macOS 6.4.0 | `onSoundComplete` : `eventHandler.onComplete()`, **puis** `seek(0)` | fin d'abord |
| Web 5.2.0 | `onEnded` : `await stop()` (`currentTime = 0`), **puis** `complete` après une microtâche | fin d'abord : le sondage tourne dans des callbacks de frame, qui ne s'intercalent pas dans une microtâche |

[déduit] Avec `ReleaseMode.stop`, que `load` pose, l'événement est émis sur les trois plateformes. Deux exceptions lues : iOS ne l'émet pas si `isPlaying` est faux (lecteur jamais relancé), et Android l'émet aussi après une erreur (voir plus haut). L'ordre « 0 puis fin », contre lequel `_peak` protège, n'apparaît dans aucun des trois codes : ce plancher est une défense, pas un chemin réel connu. Le canal d'événements ne dépend pas des frames. La fin arrive donc aussi écran éteint, alors que le sondage de position, lui, s'arrête.

## 3. Pendant la queue

[document] Dernier step du contenu : `breath` de 176 à 179 s (`session_montee_puissance.json`). En `breath`, `BeepEngine` joue un son unique (`_playBreathOneShot`) et ne lance pas de boucle. La queue réelle (de 178,85 à 179 s) est donc muette côté bips.

[déduit] Sur un contenu futur dont la séance dépasserait le morceau pendant un step rythmé, la grille continuerait : `beatTime` n'a pas de borne, et elle lit `music.position`, qui dépasse la fin. On aurait des bips calés sur un morceau qui ne joue plus. Côté écran, `elapsed` continue de monter jusqu'à `duration_seconds`, sans recul. Aucun test ne regarde les bips dans la queue.

## 4. Séance sans morceau

[mesuré] Le diff de production touche seulement `music_clock.dart` et `music_engine.dart`. `MusicClock` n'est construite que par `MusicEngine`, et `MusicEngine` seulement quand `session.music != null` (`session_controller.dart:666`). `elapsed` d'une séance sans morceau reste `_stopwatch.elapsed + _timelineOffset`. Le faux `_Beep` de `f68db0e` n'existe que dans les tests. Rien n'a changé pour une séance sans morceau, et la suite complète est verte.

## 5. Les essais du round 1

[déduit] Tous tiennent, et le correctif ne déplace aucun horaire. « Fin » devient l'essai décisif : il est le seul à juger à la fois le câblage réel (M6 verte) et l'ordre des événements sur le S21. Un câblage cassé répond « non », comme avant le correctif. « Continue », « Collés », « FAIL », « Sommet », « Web » et « Niveau » ne touchent pas au correctif, leur lecture ne change pas.

[déduit] J'ajoute « Souffle » : « JE PEUX PAS » entre 172 et 175 s, pour que le souffle de 7,9 s déborde 179 s. C'est le cas que le round 1 avait nommé (« un FAIL après ~171 s tombe dans le même trou »). Un build sans le correctif répond « non ». Le verrouillage d'écran ne sert pas d'essai : il met la séance en pause (`didChangeAppLifecycleState`), et une pause dans une queue de 0,15 s ne se vise pas à la main.

## Ce que je n'ai pas pu établir

- [déduit] Que le S21 émette l'événement et dans cet ordre : c'est une lecture de code, pas une mesure sur l'appareil. Le repère « Fin » tranche.
- [déduit] Que la version native réellement compilée soit celle du cache : je me suis fié au `pubspec.lock`, sans vérifier le binaire installé.
- [déduit] L'atteignabilité de `tss2-015` : non reproduite, elle dépend d'un canal de plateforme lent.
- [déduit] Le comportement web sur Safari iOS en PWA (onglet en arrière-plan, `ended` retardé) : non lu au-delà de `wrapped_player.dart`.
- [mesuré] M8 et M9 sont vertes, M5 et M6 le restent (rapport du correctif, non rejouées ici) : ces quatre lignes peuvent disparaître sans qu'un test tombe.
- [déduit] Le contenu réel de bout en bout (179 s, FAIL vers 172 s) n'est rejoué par aucun test : la géométrie de 100 s des tests reste une réduction.

## Essais sur le téléphone

[déduit] Un mot par réponse.
1. **Fin** : à 179 s, l'écran de fin s'affiche ? « oui » / « non ».
2. **Souffle** : « JE PEUX PAS » entre 172 et 175 s, l'écran de fin s'affiche à 179 s ? « oui » / « non ».
3. **Continue** : le morceau joue encore à 20 s ? « oui » / « coupé ».
4. **Collés** : de 115 à 150 s, un bip par temps sur la grosse caisse ? « collés » / « décalés ».
5. **FAIL** : « JE PEUX PAS » entre 134 et 140 s, la musique ? « continue » / « coupe ».
6. **Sommet** : même essai, « Voilà le sommet » ? « absent » / « dit en retard ».
7. **Web** : sur Safari iOS, le morceau ? « démarre » / « muet ».
8. **Niveau** (réglage) : bips et voix sur le morceau ? « bien » / « forts » / « faibles ».
