---
type: analyse
sujet: filet-de-securite-sur-la-garde-de-gel-d-horloge-pendant-une-attente-de-posture
ecrit_le: 2026-08-23T00:14:15+02:00
auteur: session tss2-filet-gel-posture · claude-opus-5
revision: e6b1b2b
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/controllers/posture_gate.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_break_fail_gate_test.dart
  - rhythm_coach/test/session_posture_freeze_upcoming_steps_wiring_test.dart
provenance:
  mesure: 16
  deduit: 9
  document: 5
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1705
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:217
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:934
  - rhythm_coach/lib/controllers/session_controller.dart:481
  - rhythm_coach/lib/controllers/session_controller.dart:938
  - rhythm_coach/lib/screens/session_screen.dart:1117
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/test/session_break_fail_gate_test.dart:179
  - rhythm_coach/test/session_break_fail_gate_test.dart:315
---

**[document]** La garde de gel d'horloge (`session_screen.dart:1134`) tait les instants à venir tant
que `isTimelineFrozen` est vrai, et le filet du 22/08 couvre deux de ses trois branches.

**[déduit]** Celle des postures imposées n'était gardée par rien. Ce document rapporte comment ce
trou a été mesuré, puis refermé.

## Le trou, rejoué avant d'être outillé

**[document]** La relecture du 22/08 annonçait que réécrire `awaitingPostureReady`
(`session_controller.dart:481`) en `false` inconditionnel laissait le filet vert.

**[mesuré]** Cette mutation ne laisse pas la **suite complète** verte : `timeout 1200 flutter test`
rend `exit 1` et `01:29 +1097 -3`. Les trois échecs sont dans `session_break_fail_gate_test.dart`
(`Expected: true / Actual: <false>`) : la ligne 179, qu'atteignent deux tests via `reachPostureGate`,
et la ligne 315.

**[déduit]** Le constat de la relecture est donc juste pour le fichier qu'elle relisait, et faux pour
la suite : le **getter** est gardé — trois tests lisent `ctrl.awaitingPostureReady` directement —, et
la mutation choisie heurtait ces gardes-là avant d'atteindre le câblage visé.

**[mesuré]** La mutation qui isole vraiment le câblage laisse la suite verte : retirer
`|| awaitingPostureReady` de `isTimelineFrozen` (`session_controller.dart:938`) en laissant le getter
intact rend `exit 0` et `01:30 +1100: All tests passed!`, zéro échec.

**[déduit]** Le trou existe donc, à un niveau plus fin que celui annoncé : le gel de posture est
tenu, l'agrégat qui le porte jusqu'à l'écran ne l'est pas. Un contributeur qui retire cette clause —
en la croyant redondante, ou en réécrivant l'expression — ne casse aucun test, et l'affichage se met
à situer des instants sur une horloge arrêtée pendant que la joueuse s'installe.

## Entrer en attente de posture

**[mesuré]** Le gel s'arme à la **sortie** d'un break qui impose une nouvelle posture. La séance de
la sonde porte `initialPose: Posture.free` et un seul `ScriptedBreak(time: 1, durationSeconds: 2,
newPose: Posture.kneeling)` ; l'attente s'ouvre à `elapsed` ≈ 3,1 s et ne se referme qu'au bouton.

**[document]** L'écran ne remplace `MovementAnimation` par un `SizedBox` que tant que `breakActive`
est vrai (`session_screen.dart:1117`).

**[mesuré]** `breakActive` est retombé quand l'attente s'ouvre : la sonde trouve bien un
`MovementAnimation` monté sur les quinze frames observées sous gel.

**[document]** `free` puis `kneeling` sont deux postures que le générateur tire réellement
(`_pickInitialPose` / `_pickBreakPose`, `career_session_generator.dart:1705` et `:929`), et la
structure posée — un `ScriptedBreak` avec `newPose`, suivi du step d'effort — est celle qu'il émet
(`:934`).

**[document]** La durée, elle, sort du domaine : le générateur tire 60 à 120 s
(`career_session_generator.dart:217-218`), la sonde en pose 2.

**[déduit]** C'est le prix de l'horloge du mur : le `Stopwatch` du controller n'est pas simulé par
`flutter_test`, et une pause d'une minute coûterait une minute de suite.

**[mesuré]** Aucun défi n'est armé dans cette séance : `isChallengeActive` reste faux sur toutes les
frames observées, et le test l'exige (`framesDefiActif == 0`). La branche posture est donc prouvée
seule, sans recouvrement avec le gel de défi que `stillHolds` reçoit en `otherSceneActive`.

**[déduit]** Le harnais est repris tel quel du filet du 22/08 (faux canaux `flutter_tts`,
`audioplayers` et leurs `EventChannel`, pigeon `wakelock_plus`, moteurs son en sous-classes
silencieuses). Une seule pièce y est ajoutée, empruntée à `session_break_fail_gate_test.dart` : un
faux moteur TTS qui pousse `speak.onStart` puis `speak.onComplete`, sans quoi l'anti-coupure de
`_checkSteps` diffère les steps et décale la sortie du break.

**[déduit]** Le scénario vit dans un fichier voisin
(`session_posture_freeze_upcoming_steps_wiring_test.dart`) plutôt qu'en second test du fichier
existant : celui-ci porte une `Session` const bâtie autour d'un défi et un en-tête qui décrit ce
scénario-là.

## La preuve

**[mesuré]** Rouge par mutation, la clause posture retirée de `isTimelineFrozen` :

```
Expected: empty
  Actual: ['horloge à 3134 ms : 2 instants annoncés, le premier à 15 s', …]
l'écran a annoncé des instants à venir pendant une attente de posture, sur 15 des 15 frames gelées
observées : horloge à 3134 ms : 2 instants annoncés, le premier à 15 s | …
```

**[mesuré]** Les quinze frames observées sous gel portent toutes une annonce : la sonde ne tient pas
sur une frame de chance.

**[mesuré]** La mutation témoin — retirer `isChallengeActive` du même agrégat, hors sujet ici
puisque la séance n'a pas de défi — laisse ce test **vert** (`exit 0`).

**[mesuré]** Le garde-fou anti-vide mord : forcer `upcomingSteps` à la liste vide sur toutes les
frames (`ctrl.isTimelineFrozen` remplacé par `true` au site d'appel) rend le test rouge sur
`Expected: a value greater than or equal to <10> / Actual: <0>`, message « hors gel, cette séance
doit annoncer des instants à venir ; sans cela le vide observé sous gel ne prouverait rien ».

**[mesuré]** La mutation du getter en `false` inconditionnel rend ce test rouge aussi, sur une autre
assertion : `Expected: a value greater than or equal to <15> / Actual: <0>`, message « le scénario
n'est jamais entré en attente de posture ».

**[déduit]** La sonde attrape donc les deux façons de casser la branche : le gel lui-même, et le fil
qui le mène à l'écran.

**[mesuré]** Déterminisme : 10 relances sur code intact, 10 × `exit 0` ; 10 relances avec la clause
retirée, 10 × `exit 1` et 15 frames annoncées à chaque fois.

## Coût

**[mesuré]** Le test seul : 7 s de scénario, 11,0 à 11,9 s de bout en bout avec le démarrage de
`flutter test`, sur les dix relances.

**[mesuré]** Sur la suite complète, le mur passe de `01:30` (1100 tests) à `01:32` (1101) — mesure
unique, non répétée. `timeout 1200 flutter test` rend `exit 0` et `1101` tests verts ; `flutter
analyze` rend `No issues found!` ; `dart format` ne change rien au fichier livré.

## Ce que je n'ai PAS pu établir

**[mesuré]** Le break de la sonde dure 2 s, contre 60 à 120 s en production. Rien ici ne dit que la
fenêtre se comporte pareil sur une pause longue.

**[mesuré]** L'attente est refermée par le bouton « JE SUIS EN PLACE ». Le second chemin de sortie —
le garde-fou anti-soft-lock de 90 s (`_readyTimeoutDuration`) — n'a pas été emprunté : trop long pour
un test en temps réel.

**[déduit]** La sonde lit l'argument `upcomingSteps` au moment où l'écran le passe, comme celle du
22/08. Elle ne dit rien de ce que `MovementAnimation` en fait ensuite.

**[mesuré]** Le report TTS de `_checkSteps`, qui décrémente lui aussi `_timelineOffset` sans passer
par `isTimelineFrozen`, reste hors couverture — la limite était déjà signalée le 22/08.

**[déduit]** Le gel de posture est prouvé sur le seul chemin qui l'arme aujourd'hui, la sortie de
break. Si un autre chemin venait à l'armer, rien ici ne le verrait.
