---
type: analyse
sujet: relecture-ciblee-etape-3-bis-l-ancre-redevient-une-variation
ecrit_le: 2026-08-20T23:53:46+02:00
auteur: session tss2-aimant-3bis-relecture · claude-opus-5
revision: 969c6a3
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/models/career_generation_inputs.dart
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart
  - rhythm_coach/test/movement_animation_future_beats_test.dart
  - rhythm_coach/test/session_step_anchor_compat_test.dart
provenance:
  mesure: 21
  deduit: 2
  document: 1
  sans_marqueur: 3
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/models/career_generation_inputs.dart:75
  - rhythm_coach/lib/career/services/career_level_gates.dart:132
  - rhythm_coach/lib/career/services/career_level_gates.dart:21
  - rhythm_coach/lib/career/services/career_level_gates.dart:41
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1270
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1297
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1334
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1470
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1507
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1539
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1553
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1667
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2080
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:841
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:220
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:353
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:386
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:500
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:538
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:225
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:266
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:277
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:312
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:331
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:382
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:1016
  - rhythm_coach/lib/services/beep_engine.dart:583
  - rhythm_coach/lib/services/beep_engine.dart:590
  - rhythm_coach/lib/services/beep_engine.dart:636
  - rhythm_coach/lib/services/beep_engine.dart:702
  - rhythm_coach/lib/widgets/movement_animation.dart:191
  - rhythm_coach/lib/widgets/movement_animation.dart:281
  - rhythm_coach/lib/widgets/movement_animation.dart:387
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 3 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

Waiver doc: le verdict, le tableau des extrêmes par niveau, les réserves et les questions
ouvertes — chacun ne reprend qu'un chiffre déjà porté par une phrase marquée du corps.

## Verdict

**Publiable avec réserves — quatre, aucune gênante.** Le correctif fait ce qu'il annonce : l'ancre
quitte le métronome et se concentre sur les passages qui montent, sans fuir vers un autre mode. Je
n'ai trouvé aucun défaut qui déplace un comportement. Les réserves portent sur des chiffres annoncés
plus étroits que la réalité, une moitié de fil non testée, et deux citations imprécises.

## Piste 1 — la part ancrée est bien redescendue, la fourchette annoncée est trop étroite

**[mesuré]** Sur 130 séances réellement générées (13 niveaux × 10 graines, `humiliationCareer:
400.0`), la part de steps rythmés ancrés vaut **0 % au minimum, 15,5 % en médiane, 33,3 % au
maximum** — jamais la moitié, sur aucun tirage.

**[mesuré]** Le même comptage, gate `intense` retiré par mutation (restauré ensuite), donne **100 %
sur les 130 séances** (8776 steps ancrés contre 1369 après correctif) : le « avant » annoncé par
l'auteur est confirmé sur un échantillon 130 fois plus large que le sien.

**[mesuré]** Par niveau, les extrêmes de la part ancrée :

| niveau | min | max |
|---|---|---|
| 1 | 21,4 % | 33,3 % |
| 2 | 7,1 % | 33,3 % |
| 3 | 0,0 % | 11,1 % |
| 5 | 8,8 % | 29,0 % |
| 9 | 6,1 % | 22,7 % |
| 10 | 15,9 % | 22,7 % |
| 12 | 9,8 % | 23,2 % |
| 15 à 40 | 10,0 % | 20,0 % |

**[mesuré]** La fourchette « 10 à 25 % selon le niveau » du rapport est donc fausse aux deux bouts :
33,3 % au niveau 1-2 (petits dénominateurs, 3 ancrés sur 9 steps rythmés), et **0 % sur 4 tirages
sur 10 au niveau 3**, où la séance porte pourtant 16 à 19 steps rythmés.

**[déduit]** Les niveaux 3 et 4 forment une bande sans aucune source d'ancre fiable : le
pré-finisher s'arrête à `isLowLevelIntro` (niveau ≤ 2), la mini-vague commence à
`isMiniWaveEligible` (niveau ≥ 5) — il ne reste que les boosts du finish, qui sortent en `hand` une
fois sur quatre. Une séance entière peut donc ne jamais montrer l'aimant.

**[mesuré]** Aucune fuite : sur ces 130 séances, **zéro step non rythmé ne porte d'ancre** (ni
`lick`, ni `hand`, ni `beg`, ni `hold`, ni `breath`), et **zéro incohérence de `ratio`** (ancré ⇒ 3,
non ancré ⇒ 1).

**[mesuré]** La concentration annoncée tient : sur 1369 steps ancrés, **2 seulement** tombent avant
75 % de la séance sans autre step ancré à moins de 90 s — 67 et 70 bpm, 23 et 30 s de durée, soit la
signature exacte de `buildPreFinisher` (bpm 62-70, durée 22-30 s) sur des séances de niveau 2 courtes
où il tombe à 68 % du temps. Ce ne sont pas des ancres égarées, c'est le pré-finisher que Manu a
demandé d'ancrer.

## Piste 2 — le classement des six familles

**[mesuré]** Quatre des cinq citations de docblock sont exactes à la lettre :
`buildMiniWaveSegment` dit « la vague accélère et se condense » (:225), `buildPreFinisher` « courte
accélération … prépare la phase boosts » (:331), `postFinalVariants` « reprise douce » (:312),
`firstStepVariants` « 3 variantes douces » (:382).

**[mesuré]** La cinquième pointe à côté : le docblock « Rhythm très doux comme "récup en bouche" »
est attaché à `isRecoveryCandidate` (:266-273), pas à `buildRecovery` (:277) que le tableau du
rapport nomme. Le texte décrit bien la recovery rythmée — la conclusion tient, la référence non.

**[mesuré]** Les décisions de Manu sont tenues dans le code, revérifiées ligne à ligne :
`finish_phase.dart:220` passe `intense: true` au pré-finisher, `:353` aux boosts, `:500` (step final)
et `:538` (post-final) ne le passent pas, et les deux copies de `_draftToStep` ont `intense = false`
par défaut. Le final reste net, le pré-finisher monte.

**[mesuré]** Le générateur compte **six** sites `_emitStep`, pas un : seul `:1270` (mini-vague) passe
`true` ; `:1297` (breath post-vague), `:1470` (breath de récupération), `:1507` (boucle main +
recovery), `:1539` (fake breath) et `:1553` (chain action) gardent le défaut. Le rapport n'en nomme
qu'un ; les cinq autres sont bien au défaut, mais il ne les a pas listés.

**[mesuré]** `hold` n'est jamais ancré (gate `isRhythm`), et le serait-il que ça ne changerait rien :
`BeepEngine._intervalAfter` retombe sur l'intervalle régulier dès que `to == null || to == from`,
c'est-à-dire sur tout step tenu. La parole de Manu citait « rythme et hold » ; côté hold, il n'y a
matériellement rien à ancrer.

## Piste 3 — le test de `bd51e0c` tient, sur la moitié du fil

**[mesuré]** Mutation 1, code d'avant rendu au widget (`bpm: widget.bpm`) : rouge, sur la bonne
assertion (`Expected: <50> Actual: <80>`, avec le `reason` du test), et sur elle seule — les trois
autres tests du fichier restent verts.

**[mesuré]** Mutation 2, règle neutralisée (`_lastBeatBpm = event.bpm` retiré de `_onBeatEvent`) :
même rouge, même assertion.

**[mesuré]** Mutation 3, renverser une valeur par défaut : il n'y en a pas à renverser côté
événement — `BeatEvent.bpm` est `required`, un site de construction qui l'oublierait ne compilerait
pas. Le seul défaut en jeu est le repli `?? widget.bpm` du widget, et le test le distingue puisqu'il
monte à 80 bpm pour attendre 50.

**[mesuré]** En revanche, neutraliser l'interpolation elle-même (`_currentInterpolatedBpm` renvoyant
`_bpm` constant, rampe morte) laisse **la suite complète verte**. Aucun fichier de test ne pilote une
rampe réelle : `_bpmEnd` et `_loopDurationMs` n'apparaissent nulle part hors du moteur.

**[déduit]** Le test ferme exactement la réserve du round 3 — le fil `BeatEvent.bpm` → écran — et
rien de plus. Il ne prouve pas que `BeatEvent.bpm` porte le BPM *interpolé* : `emitOneBeatForTest`
court-circuite la boucle et lui passe le bpm en clair. La moitié moteur du correctif `a9fa8a5` reste
sans filet.

## Piste 4 — ce que le gate casse ailleurs : rien

**[mesuré]** `test/session_step_anchor_compat_test.dart` reste vert et discriminant : il ne lit que
les assets JSON et le défaut de `SessionStep.fromJson`, jamais le générateur.

**[mesuré]** L'invariant `2T` : la tolérance ±1 ms n'est ouverte que pour les steps non ancrés, et
elle est exacte — `_regularInterval` arrondit deux fois (bpm 90 : 2 × 667 = 1334 contre
round(1333,33) = 1333), là où `_intervalAfter` déduit le court du long par soustraction sur un step
ancré. La tolérance corrige le test, pas le geste.

**[mesuré]** Les six `_beep.applyStep` : deux construisent un step `breath` (aucune ancre à porter),
les quatre autres passent un step de la timeline tel quel ; l'excision de défi recopie `anchor` et
`ratio` (`session_controller_challenge.dart:1016`).

**[mesuré]** Défis : `challenge_segment_builder` ne pose jamais `anchor` — les segments de défi sont
non ancrés avant comme après ce correctif.

**[mesuré]** Custom : le même générateur, appelé avec `CustomOverrides(bpmRange: (40, 90))` au niveau
virtuel 25, sort 62 steps ancrés, tous en `from` à 90 bpm. Le mode Custom hérite du correctif sans
code modifié, comme l'annonce le rapport.

## Ce que j'ai corrigé

**[document]** Commit `969c6a3` — deux commentaires du test d'ancrage affirmaient un absolu que la
mesure dément : « les boosts de fin de séance sont toujours émis … il y a donc toujours au moins un
step ancré » (faux aux niveaux 3-4) et « la branche `from` … n'est jamais atteinte en génération
réelle à ce niveau » (fausse dès que Custom passe ses bornes BPM). Les deux sont désormais bornés à
leur périmètre. Aucune assertion touchée, aucun code de production touché.

## Vérifications

**[mesuré]** `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed lib test` :
301 fichiers, 0 modifié. Suite complète sur `411d019` : **1041 tests verts**, le chiffre annoncé est
juste. Suite complète après mon commit : 1041 tests verts.

## Réserves

- **R1 — non gênante.** La fourchette annoncée (10-25 %) est plus étroite que la mesure (0-33,3 %),
  et les niveaux 3-4 peuvent produire une séance entière sans aucune ancre. Compatible avec « une
  variation, pas un standard » ; à connaître avant de doser.
- **R2 — non gênante.** La moitié moteur du BPM interpolé (`_currentInterpolatedBpm` →
  `BeatEvent.bpm`) reste sans test : la neutraliser laisse la suite verte.
- **R3 — non gênante.** La citation du docblock « très doux » pointe `buildRecovery` alors que le
  texte est attaché à `isRecoveryCandidate`.
- **R4 — non gênante, documentaire.** Le rapport écrit « je n'ai ouvert ni
  `custom_session_config.dart`, ni `custom_mode_screen.dart` », alors que son propre en-tête les
  liste en `porte_sur` et cite `custom_session_config.dart:247` et `custom_mode_screen.dart:182` en
  `relu_contre`.

## Ce que je n'ai pas pu établir

- Si une séance sans aucune ancre (niveaux 3-4) gêne à l'usage — c'est du ressenti, jugé par Manu.
- Si `BeatEvent.bpm` porte bien le BPM interpolé sous une vraie rampe : aucun test ne pilote la
  boucle temporisée du moteur, et je n'en ai pas écrit un dans cette relecture.
- Le comportement au-delà des 130 séances balayées (13 niveaux × 10 graines, carrière seule + 5
  séances Custom) — c'est un échantillon, pas une preuve exhaustive.
- Ce que « moment intense » recouvre exactement : je n'ai fait que vérifier que le classement retenu
  ne contredit aucune décision écrite de Manu.

## Questions ouvertes pour Manu

1. Celles de l'auteur restent entières : le step final compte-t-il comme un moment à ancrer, et le
   pré-finisher est-il bien à sa place parmi les moments intenses ?
2. La mienne : aux niveaux 3-4, une séance sur deux environ ne montre aucune ancre du tout. Est-ce le
   dosage voulu pour une débutante, ou faut-il une source d'ancre dans cette bande ?
