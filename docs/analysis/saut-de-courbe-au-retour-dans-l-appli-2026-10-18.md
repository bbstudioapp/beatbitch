---
type: analyse
sujet: saut-de-courbe-au-retour-dans-l-appli
ecrit_le: 2026-10-18T15:55:48+02:00
auteur: session tss2-courbe-retour · claude-opus-5-5
revision: 2ebaa87
branche: fix/courbe-retour-appli
porte_sur:
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/session_retour_courbe_test.dart
provenance:
  mesure: 7
  deduit: 2
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/widgets/movement_animation.dart:647
  - rhythm_coach/lib/widgets/movement_animation.dart:836
  - rhythm_coach/lib/widgets/movement_animation.dart:848
  - rhythm_coach/lib/widgets/movement_animation.dart:850
  - rhythm_coach/lib/widgets/movement_animation.dart:918
---

## Symptôme

[mesuré] Vidéo du S21 du 18/10 (essai `214445c`), suivie image par image : après la reprise, l'écran est en **rythme** Gland ↔ Gorge (pastille « SUCE » = `modeShortRhythm`, couleur de curseur « rythme », niveaux Gland et Gorge surlignés), mais le curseur reste à « Tout ». À chaque bip il saute à la position du bip (Gland à 3,18 s, 5,73 s et 8,32 s ; vers Gorge à 4,23 s, 7,02 s et 9,58 s), puis il redescend vers « Tout » en 0,3 à 1,2 s.

[déduit] La « période » d'environ 2,6 s est l'alternance Gland/Gorge du rythme (un bip toutes les 1,3 s environ), pas une horloge propre à la courbe. Le plateau « Tout » n'est pas l'origine du pont vers la consigne précédente (lecture de la fiche) : c'est la **consigne suivante**, affichée trop tôt.

## Cause

`lib/widgets/movement_animation.dart:832` à `82e3a7f` (`:838-840` après correctif) : `_PositionLadderState` datait la pause de la **première image qui montre** `paused`. Sur l'appareil, aucune image n'est construite en arrière-plan : cette image arrive au retour dans l'appli. `_resumeClock` (`:852-854`) ne décale donc les épingles de frontière (`_boundaryPins`, horloge murale) que de quelques millisecondes au lieu de toute l'absence. Une épingle ne recule jamais (`boundaryAt`, `:647`) : la frontière suivante reste dans le passé, et la courbe montre la consigne d'après jusqu'à ce que la séance l'atteigne. Chaque bip recalcule la courbe : le curseur repart de la position du bip, puis défile vers le plateau.

[mesuré] Sonde dans le banc, sans images pendant 10 s d'absence : pause appliquée `0ms`, épingle de la tenue à 8 s à `-6594ms` alors que la séance est à 4,5 s. Avec images pendant l'absence : pause `10062ms`, épingle à `+3452ms` (juste).

## Preuve

[mesuré] Banc `test/session_retour_courbe_test.dart` : `SessionScreen` réel, moteur de bips réel sur des canaux audio simulés, tenue « Tout » → rythme Gland ↔ Gorge → tenue « Tout » → rythme. On lit le premier point de la courbe peinte. Six cas : trois instants de sortie (pendant le rythme, pendant la tenue, en fin de tenue comme sur la vidéo), chacun après un vrai départ de l'appli (aucune image) et après une pause sans quitter l'appli (`inactive`, images). Sur le code d'avant, les trois cas « retour dans l'appli » sont rouges sur leur assertion (en rythme, le curseur est à `4.00` ; en tenue, il passe à `2.00`). Les trois cas « sans quitter l'appli » étaient déjà verts.

[mesuré] Correctif (`c89f34b`) : la pause date de l'instant où le temps de séance s'est arrêté, soit la dernière image construite (`_lastFrameAt`) plus le temps de séance écoulé depuis (`widget.elapsed - _lastFrameElapsed`, `:838-840`, `:922-923`). Les 6 cas sont verts. Remettre l'ancienne datation (`DateTime.now()`) rend rouges les trois cas « retour ». Les bancs voisins (pause, punition, arrière-plan) restent verts : 36 tests. `flutter analyze` ne trouve rien, `dart format` ne modifie aucun fichier, et la suite complète passe : 1 561 tests verts.

[mesuré] Une première version (`aa842cb`) datait la pause de la dernière image seule. Elle a fait tomber `movement_reprise_pause_test` (« tenue → rythme, pause longue ») : +265 ms dans une suite complète, et 1 rouge sur 4 lancements sous charge CPU. Sous la même charge, le code d'avant et la version finale passent 4 fois sur 4.

## Ce que je n'ai pas pu établir

- [document] Rien n'a été vérifié sur le S21 : ni compilation, ni installation, ni nouvelle vidéo. Seul un essai filmé dira si le plateau « Tout » disparaît.
- [déduit] La séance exacte de la vidéo n'est pas connue. Le banc rejoue l'enchaînement qu'on y voit (tenue « Tout » au retour, puis rythme Gland ↔ Gorge), avec un BPM de 46 choisi pour coller à l'écart entre les bips.
- [mesuré] Aucun test déterministe ne garde le terme `widget.elapsed - _lastFrameElapsed`. Le retirer (version `aa842cb`) laisse le banc de retour vert : seule la charge le fait tomber, et pas à chaque fois.
- [mesuré] J'ai essayé un cas « 500 ms de séance sans image avant la pause » dans `movement_reprise_pause_test`. Il est rouge sur les trois versions : −1 000 ms avec le code d'avant, +540 ms avec `aa842cb`, −306 ms avec la version finale. La cause n'est pas établie et le cas a été retiré (copie dans le scratchpad de la session).
- [document] Les autres horloges murales du widget (`_frozenAt`, `_lastBeatAt`) ne sont pas décalées par une pause. Aucun banc ne les a mises en défaut ici, mais rien ne les garde non plus.
