---
type: analyse
sujet: punition-courbe-en-retard
ecrit_le: 2026-10-17T10:07:01+02:00
auteur: session tss2-punition-courbe · claude-opus-5-5
revision: 59f21f9
branche: fix/punition-courbe
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
provenance:
  mesure: 9
  deduit: 8
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:986
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:136
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:354
  - rhythm_coach/lib/screens/session_screen.dart:905
  - rhythm_coach/lib/widgets/movement_animation.dart:1267
  - rhythm_coach/lib/widgets/movement_animation.dart:641
---

## Verdict

[mesuré] Cause établie, correctif livré sur `fix/punition-courbe` (`59f21f9`), un choix d'affichage reste à Manu (section « Choix à faire par Manu »). Pendant tout le flow fail (« JE PEUX PAS » comme mini-punition), `SessionScreen` donnait à la courbe les steps **de la séance**, lus après une horloge de séance arrêtée, alors que le moteur jouait la punition. La courbe annonçait donc le prochain step de la séance, qui ne serait pas joué. Sa frontière, épinglée en horloge murale, défilait jusqu'au curseur puis passait derrière lui, et à partir de là toute la courbe devant le curseur dessinait ce step-là. Avec une respiration comme step suivant de la séance, la courbe « reste en breath » pendant que le curseur suit le rythme de la punition : l'action n'apparaît qu'au curseur, donc « super en retard ».

## Le signal

[mesuré] Banc : `rhythm_coach/test/session_punishment_breath_screen_test.dart`, deux cas ajoutés (« punition » et « mini-punition »). `SessionScreen` monté, vrai `SessionController`, vrai `BeepEngine` sans échantillons (aucun son, mode et positions tenus comme en production), lecture des points peints par `_TrajectoryPainter`. Séance : rythme head→throat à 0 s, respiration à 4 s. Punition déclenchée à 2,5 s : un seul step, rythme tip→full à 90 BPM pendant 8 s. Pour chaque image prise entre 0,8 s et 4 s après le début de la punition, le point le plus profond peint entre 1 et 3 s devant le curseur doit atteindre au moins `throat`.

[mesuré] Rouge sur le code d'avant correctif (`be6d477`), sur cette assertion. Images restées en haut, en ms depuis le début de la punition : de 1509 à 3316 ms, toutes à `0.00` (tip). Deuxième passe, après la mise en place du correctif puis sa suppression par mutation : de 1370 à 3260 ms pour « punition », de 2066 à 3942 ms pour « mini-punition ». Vert avec le correctif, deux relances comprises.

## Les sondes, une variable à la fois

[mesuré] Sonde 1 : step suivant de la séance à 60 s (57 s devant). Pendant toute la punition (rythme, puis tenue à 4 s, puis rythme à 8 s), la courbe suit la punition. Elle n'annonce jamais le changement de step de la punition : la tenue apparaît sur la courbe à l'image où le moteur y passe (à 10093 ms après le FAIL, `0.38 4.00 4.00 4.00`), pas avant.

[mesuré] Sonde 2 : même punition, une seule différence, une respiration de séance à 5 s (FAIL à 3049 ms de séance). Le moteur passe au rythme de la punition 4068 ms après le FAIL. Dès 4922 ms, soit 0,85 s après le début de la punition, la courbe vaut `0.00` à 1, 2 et 3 s devant le curseur, alors que le curseur descend à `full` (y = 0,60) à chaque battement. Les seules images où elle s'écarte de `0.00` (vers 6333 ms, 7732 ms, puis pendant la tenue) montrent une ligne qui part du curseur et retombe sur la ligne plate.

[mesuré] Sonde 3 : scénario de la sonde 2, correctif en place. La courbe dessine le rythme de la punition d'un bout à l'autre ; la tenue apparaît quand le moteur y passe (`2.33 4.00 4.00 4.00`), comme dans la sonde 1.

## Hypothèses

| Hypothèse [mesuré] | Prédiction qui la réfute | Verdict |
|---|---|---|
| H1 — pendant le flow fail, la courbe lit la timeline de la séance (steps et horloge figée) au lieu de la punition | changer le seul step suivant de la séance ne change rien à la courbe pendant la punition | **confirmée** : sonde 1 contre sonde 2 ; couper les steps de séance pendant `failing` suffit à faire suivre la punition (sonde 3, test vert) |
| H2 — l'écran ne reçoit pas les steps de la punition, faute de notification | le mode reçu par `MovementAnimation` diffère du mode du moteur | **infirmée** : à chaque image le mode reçu égale celui du moteur, `stepSerial` suit (2, 3, 4, 5) |
| H3 — la respiration d'avant-punition reste affichée | le mode reçu reste `breath` au début de la punition | **infirmée** : `rhythm` dès la première image de la phase punition |
| H4 — l'extrapolation d'horloge de la courbe dérive | l'`elapsed` reçu avance pendant le flow fail | **infirmée** : `elapsed` reçu figé (2842 ms, 3049 ms) ; extrapolation bornée à 250 ms (`movement_animation.dart:1267`) |

## Le mécanisme, lignes citées

[document] `rhythm_coach/lib/screens/session_screen.dart:902-914`, avant correctif :

```dart
upcomingSteps: ctrl.isTimelineFrozen
    ? const []
    : resolveUpcomingMovementSteps(
        steps: ctrl.session.steps,
        defaultMode: ctrl.session.defaultMode,
        afterSecond: ctrl.elapsedSeconds,
        ...
```

[document] `isTimelineFrozen` (`session_controller.dart:986-987`) vaut `isChallengeActive || _inPostChallengeBreath || awaitingPostureReady` : le flow fail n'y figure pas. Or `triggerFail` arrête l'horloge de séance (`session_controller_fail_flow.dart:136`, `_stopwatch.stop()`) puis passe en `failing` (`:149`) ; la mini-punition fait de même (`:468`, `:480`). La punition tourne sur son propre `Stopwatch` local (`:354`), jamais exposé à l'écran.

[document] `movement_animation.dart:641-649`, `boundaryAt` : la frontière d'un step à venir est placée à `now + (startSecond × 1000 − elapsedMs)`. Si une épingle plus précoce existe pour ce `startSecond`, elle l'emporte (`:646`), et l'instant retenu est réépinglé (`:647`). La frontière du premier step à venir est calculée avant la boucle (`:678`), donc épinglée même hors de la fenêtre de 3 s.

[déduit] Horloge figée : à chaque recalcul, `now + (start − elapsed)` avance avec `now`, l'épingle non. La frontière défile donc en temps mural, à une seconde par seconde, jusqu'au curseur, puis passe derrière. Au-delà de la frontière, le segment courant devient le step à venir pour tout le reste de la fenêtre (`:730-783`). La courbe dessine alors le step suivant de la séance tant que dure le flow fail.

[déduit] Pourquoi « dès le début » : la frontière atteint le curseur `start − elapsed` secondes après le FAIL. Avant la punition viennent la phrase de fail puis une respiration de 8 à 15 s, ou de 3 à 5 s si l'endurance projetée est haute (`session_controller_fail_flow.dart:197-198`). Dès que le step suivant de la séance tombe dans ce délai, la punition commence avec une courbe qui montre déjà ce step.

## Le correctif

[document] `session_screen.dart:905` : `upcomingSteps: ctrl.isTimelineFrozen || ctrl.isFailing ? const [] : …`. C'est la règle déjà écrite pour les défis (« un défi joue des segments absents de `session.steps` [...] rien à annoncer tant qu'elle est figée »), étendue au flow fail. `isFailing` est l'état qui porte l'arrêt de l'horloge (`_state == SessionState.failing`) : le gel est dérivé de l'état, pas déclaré par un drapeau.

[déduit] Je n'ai pas mis `isFailing` dans `isTimelineFrozen` : `_onTick` (`session_controller.dart:1472`) recule `_timelineOffset` d'un tick tant que ce getter est vrai. Aucun ticker ne tourne pendant `failing` aujourd'hui, mais un tick qui passerait par là reculerait l'horloge de séance.

[mesuré] `flutter analyze` : « No issues found! ». Suite complète : 1358 tests verts (1356 au départ, plus les deux cas ajoutés). Le test du commit `be6d477` laisse une minuterie simulée en attente au démontage (délai de transition d'un `applyStep` relancé par le saut de section) ; corrigé dans `59f21f9` par un `pump` de 2 s avant le démontage. Sur le code d'avant correctif, l'assertion tombe avant ce contrôle : le rouge vient bien de l'assertion.

## Choix à faire par Manu

[déduit] Ce qui ne se discute pas : la courbe n'annonce plus un step de la séance pendant une punition. Ce qui reste un choix visible, c'est ce qu'elle doit annoncer à la place.

- **Option A — livrée.** Pendant tout le flow fail, la courbe n'annonce rien au-delà du step en cours, comme pendant un défi. Le rythme de la punition est dessiné à l'heure. En revanche, chaque changement de step de la punition n'apparaît qu'à l'image où le son change, avec le pont habituel, sans les 3 s d'avance de la courbe normale. Si Manu juge encore « en retard » les passages d'un step de punition au suivant, c'est cette absence d'anticipation.
- **Option B.** Annoncer les steps de la punition sur l'horloge de la punition, comme la courbe normale. Il faut exposer la liste et le chronomètre de `_runPunishment` (aujourd'hui locaux, `session_controller_fail_flow.dart:354-355`) et les passer à la courbe pendant la phase punition. Deux sous-choix : (1) pendant la respiration d'avant-punition, rien n'est annonçable sans changer le moment où la punition est tirée (`:215`, après la respiration, avec les valeurs vives de la séance) ; (2) en fin de punition, la reprise n'est connue qu'après `_skipToNextSection` : l'annoncer demanderait de calculer le saut plus tôt.

## Ce que je n'ai pas pu établir

[déduit] Le step de séance qui suivait le FAIL de Manu sur le téléphone : aucune trace. « Reste en breath » colle à une respiration de séance, mais tout step de séance produit le même défaut, avec sa propre forme.

[déduit] Rien n'a été mesuré sur le téléphone (non branché) : le rendu réel, avec de vrais échantillons et une vraie phrase de fail, n'est pas vu.

[déduit] Les « sauts similaires » cités par Manu : dans la sonde 2, la seule partie de la courbe qui bouge est le raccord entre le curseur (qui suit les bips) et la ligne plate. C'est compatible avec des sauts, mais je ne l'ai pas mesuré image par image.

[déduit] Pendant la phrase de fail, le moteur est en pause et la courbe continue de dessiner le step de séance en cours. Je ne l'ai pas mesuré (synthèse vocale simulée, phrase instantanée dans le banc). Comportement antérieur, que le correctif ne change pas, sauf qu'il retire l'annonce.

[mesuré] Hors périmètre, déposé au sas (`tss2-019`) : à la reprise, une frontière épinglée avant le FAIL est restée dans le passé, et la courbe annonce le step suivant de la séance trop tôt (environ 2,3 s dans la sonde). Préexistant : identique sur le code d'avant correctif. Disparaît quand on neutralise l'épingle. Même moment que `tss2-011`, mécanisme différent.
