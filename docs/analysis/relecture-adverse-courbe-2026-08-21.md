---
type: analyse
sujet: relecture-adverse-courbe
ecrit_le: 2026-08-21T17:13:47+02:00
auteur: session tss2-relecture-courbe · claude-sonnet-5
revision: 0b618a5
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/models/session.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
  - rhythm_coach/test/movement_trajectory_scroll_test.dart
provenance:
  mesure: 8
  deduit: 4
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1371
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
  - rhythm_coach/test/movement_trajectory_scroll_test.dart
---

## Périmètre effectivement relu

**[mesuré]** Le périmètre a bougé pendant la relecture. Au lancement, `HEAD` était `a02694e`
(8 commits du jour, comme décrit dans la consigne). Vers la fin de la session, un nouveau commit
`0b618a5 fix(courbe): borner l'extrapolation de l'horloge de seance` est apparu sur la même branche
(auteur BB Studio, référence `Claude-Session: session_016PDTJjnBAbqpgNUDwWZjzC` — une session
Claude distincte). `git diff develop..HEAD` porte donc sur **24 commits** (1266 → ~1327 lignes),
pas 23. Ce commit corrige exactement la classe de défaut que cette relecture était en train
d'établir par lecture de code (cf. section suivante) — je l'ai donc intégré au périmètre plutôt que
de l'ignorer, et je documente la coïncidence explicitement : un défaut trouvé de façon indépendante
pendant la relecture, corrigé de façon concurrente par une autre session pendant que je l'établissais.

**[mesuré]** `flutter analyze` : *No issues found!* — rejoué une fois sur `a02694e`, une fois sur
`0b618a5` (HEAD final).

**[mesuré]** `flutter test` (suite complète, `timeout 900`) sur `a02694e` : **1049 tests, 0 échec**,
*All tests passed!*. Suite ciblée (`movement_trajectory_continuity_test.dart` +
`movement_trajectory_scroll_test.dart`, 31 tests) rejouée sur `0b618a5` : **0 échec**.

## Trouvaille principale : dérive de l'ancre `elapsed` pendant un défi (déjà corrigée pendant la relecture)

**[déduit]** En lisant `_MovementAnimationState` (avant `0b618a5`) : `_elapsedAnchorAt`/
`_elapsedAnchorValue` ne sont réarmés que si `oldWidget.elapsed != widget.elapsed`
(`didUpdateWidget`, comparaison stricte de `Duration`). Or pendant un défi intra-séance, `_onTick`
gèle la timeline en décrémentant `_timelineOffset` de exactement `_tickInterval` à chaque tick
(`session_controller.dart:1371-1373`) — `elapsed = stopwatch.elapsed + _timelineOffset` reste donc
**bit pour bit identique** d'un tick à l'autre, sur toute la durée `breath → countdown → live →
atSeuil → ended → breath post-défi` (potentiellement des dizaines de secondes, un hold n'a pas de
plafond de durée côté joueuse). `MovementAnimation` reste monté pendant tout ce temps
(`session_screen.dart:1112`, la condition de montage est `hasConfig && !breakActive`, indépendante
de `isChallengeActive`). Conséquence : `_elapsedAnchorAt`/`_elapsedAnchorValue` restent figés sur
l'instant d'AVANT le défi, et `elapsedNow = _elapsedAnchorValue + (DateTime.now() - _elapsedAnchorAt)`
continue à courir avec l'horloge murale réelle pendant toute la durée du défi — sans plafond.

Au moment précis où le défi se termine (`isChallengeActive` repasse à `false` dès `ChallengePhase
.ended`, donc **avant** la fin du breath post-défi qui, lui, garde la timeline gelée), `session_screen
.dart` recommence à passer un `upcomingSteps` non vide. Le `elapsed` que le widget utilise en interne
est alors gonflé de toute la durée réelle qu'a prise le défi — `boundaryAt()` calcule une frontière
dans le passé, et la boucle de `_computeFutureBeats` avale silencieusement (branche `dtMs < 0`) les
steps à venir dont la frontière calculée semble déjà dépassée. Risque concret : la courbe qui
réapparaît juste après un défi peut annoncer une position/segment qui n'est pas celui réellement en
train de se jouer, contredisant l'invariant central du chantier.

**[mesuré]** Le commit `0b618a5`, arrivé pendant cette relecture, corrige précisément ce mécanisme :
`extrapolatedElapsed()` (nouvelle fonction pure, `@visibleForTesting`) plafonne l'extrapolation à
`_kElapsedExtrapolationCap = 250 ms` au lieu de laisser `since` (l'écart d'horloge murale) courir sans
borne. Vérifié en relisant le code du commit ET son test (`extrapolatedElapsed` avec un ancrage vieux
de 40 s → borné à 100 250 ms, pas 140 000 ms) : discriminant par construction (assertion numérique
directe sur une fonction pure, pas de piège de sonde-toujours-verte possible ici). Une fois plafonnée
à 250 ms, l'erreur résiduelle sur `elapsedMs` est du même ordre que la marge déjà tolérée par le
mécanisme avant son introduction (~200 ms, documentée dans le commentaire de classe d'origine) — je
n'ai pas trouvé de défaut résiduel dans ce nouveau plafond.

**Ce que je n'ai pas pu établir** : je n'ai pas fait tourner de test widget réel (montage de
`MovementAnimation`, gel réel de `elapsed`, bascule `upcomingSteps` vide→plein) pour observer la
dérive directement sur du rendu — le raisonnement ci-dessus est une lecture de code déterministe
(pas d'état externe, arithmétique simple), mais reste une déduction, pas une mesure sur le widget
vivant. Vu qu'un correctif dédié vient d'atterrir avec son propre test unitaire ciblé, je n'ai pas
jugé utile de dupliquer l'effort avec un test widget flaky (horloge murale réelle).

## Réserve « `_sameGeometry` ne compare pas `bridgeGap`/`bridgeViaTip` »

**[déduit]** Grep de toutes les affectations de `_bridgeGap`/`_bridgeViaTip`/`_frozenAt` dans
`movement_animation.dart` (HEAD) : les trois champs (plus `_frozenIdx`) sont **toujours** écrits dans
le même bloc de code, aux deux seuls endroits où ils sont écrits (`initState`, et le bloc
`if (modeChanged || tempoChanged || positionChanged)` de `didUpdateWidget`) — jamais l'un sans les
autres. Or `_sameGeometry` compare `frozenAt`. Donc tout changement de `bridgeGap`/`bridgeViaTip`
s'accompagne nécessairement d'un changement de `frozenAt` détecté par `_sameGeometry`, qui déclenche
le recalcul — **pas de bug trouvé**. Résidu théorique non éliminé : deux `DateTime.now()` consécutifs
qui retourneraient la même valeur (horloge basse résolution / appels très rapprochés) neutraliseraient
la détection sur `frozenAt` — je n'ai pas trouvé de scénario où cela se produit en pratique côté
Flutter/Dart (résolution microseconde), et je ne l'ai pas mesuré.

## Sondes du jour (`5792bb8`/`ce5f515`, position à la frontière) : rejouées, tombent rouges pour la bonne raison

**[mesuré]** Rejeu réel (pas un raisonnement) : `lib/widgets/movement_animation.dart` remplacé par la
version du commit `3fb2de7` (juste avant `5792bb8`), test file gardé à HEAD (groupe `horloge de
séance` retiré temporairement car il référence `extrapolatedElapsed`, absent à cette révision — pas
de rapport avec les 2 sondes visées). Les deux tests ciblés :
- *« une tenue garde sa position jusqu'à la frontière »* → **rouge**, `Expected: true / Actual: false`
  sur l'assertion « un point tient la position à la frontière elle-même ».
- *« mode alterné : la frontière porte la position à mi-mouvement »* → **rouge**,
  `Expected: non-empty / Actual: []` sur « un repère existe à la frontière elle-même ».

Les deux échouent exactement sur l'assertion que le correctif est censé garantir, pas sur autre
chose. Fichiers restaurés à l'identique après coup (`git status` vérifié propre, aucune trace).

## Câblage nu — toujours vrai après le nouveau commit

**[mesuré]** `grep -rln "MovementAnimation(" rhythm_coach/test/` → toujours vide, y compris après
`0b618a5` qui pourtant ajoute un nouveau canal de câblage (`onCursorIdx`, `_renderedIdx`) entre
`_PositionLadderState` et son parent. Rien ne vérifie que ce callback est bien branché à l'exécution,
ni que `_bridgeGap`/`_bridgeViaTip`/`upcomingSteps: const []` (défi) sont bien ceux reçus par le
widget monté dans l'arbre réel. Réserve inchangée par rapport à la consigne initiale.

## `a02694e` (défi coupe la prévision) — confirmé par lecture, non mesuré par test dédié

**[déduit]** Lu `_advanceChallengeSegment` (session_controller_challenge.dart) en entier : appelle
`_beep.applyStep(next, ...)`, ne touche jamais `_session.steps`. `isChallengeActive` couvre bien
`breath|countdown|live|atSeuil` (tout sauf `none`/`ended`) — donc la fenêtre où `upcomingSteps` est
vidé correspond exactement à la fenêtre où le défi pilote le moteur hors timeline. Cohérent avec
l'affirmation du commit. Toujours non mesuré par un test dédié (réserve initiale confirmée).

## Ripple `beg → mouth`

**[mesuré]** `grep -n "_ModeFamily" lib/widgets/movement_animation.dart` → l'enum et son usage sont
100 % privés à ce fichier (0 occurrence ailleurs dans `lib/`). Le changement de famille de `beg` ne
peut affecter que la décision de « remontée par tip » locale à `_computeFutureBeats` — aucun autre
consommateur.

## Division par zéro / durée nulle

**[mesuré]** `_durationFor` (bpm clampé `[20,300]`) ne retourne jamais moins de 200 ms ; les 3 modes à
durée fixe (hold/beg 1800 ms, breath 3200 ms, freestyle 2400 ms, suckle 1200 ms) sont des constantes
non nulles. Les 3 constantes de `BeepEngine.transitionGap` (300/600/1500 ms) sont non nulles. Tous
les dénominateurs identifiés dans `_computeFutureBeats` (`bridgeMs`, `legMs`, `spanMs` dans `leg()`,
`segBeatMs`) sont soit garantis > 0 par ces constantes, soit gardés explicitement (`spanMs <= 0`,
`legMs <= 0`). **Aucune division par zéro trouvée.**

## Modes rarement joués (biffle, breath, freestyle, suckle balls, hand, rowCount=6)

**[déduit]** Relu `_ladderPositionsFor`, `_familyOf`, `_CursorVisual.build`, `_toAlign` — génériques
sur `rowCount`/`mode`, pas de branche spécifique manquante repérée. **Non testé par moi mode par
mode** : je m'appuie sur la suite existante (verte, 1049 tests) qui couvre ces cas via
`computeFutureBeatsForTest`/`scrollBeatsForTest`, mais je n'ai pas écrit de scénario adverse dédié à
`rowCount=6` (position `balls` révélée) faute de budget restant — à considérer comme un angle mort de
cette relecture, pas comme un « pas de défaut ».

## Ce que je n'ai pas pu établir

- Pas de test widget réel de `MovementAnimation` — le câblage bout-en-bout (props → rendu) reste non
  vérifié à l'exécution, seules les fonctions pures le sont.
- Le mécanisme de dérive `elapsed` est établi par lecture de code, pas observé sur un rendu vivant.
- `rowCount=6`/`balls` et `hand` n'ont pas eu de sonde adverse dédiée.
- Le résidu théorique `DateTime.now()` colision sur `_sameGeometry`/`frozenAt` n'est ni confirmé ni
  infirmé empiriquement.

## Verdict

**Publiable avec réserves.** Aucun défaut actif trouvé sur le code à `HEAD` (`0b618a5`) : le seul
défaut réel identifié pendant cette relecture (dérive de l'ancre `elapsed` pendant un défi) a été
corrigé de façon concurrente par un commit arrivé pendant la session, et son correctif a été vérifié
sain. Les réserves restantes sont des angles morts de test (câblage widget jamais monté,
`rowCount=6`/`hand` non couverts par une sonde dédiée) plutôt que des défauts observés.
