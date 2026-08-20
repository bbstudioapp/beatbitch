---
type: analyse
sujet: chantier-aimant-round-2-reserves-1-et-2-de-la-relecture
ecrit_le: 2026-08-20T22:41:07+02:00
auteur: session tss2-aimant-e3-round2 · claude-sonnet-5
revision: 2b1441f
branche: feat/aimant-battement-inegal
porte_sur:
  - docs/analysis/chantier-aimant-etape-3-le-generateur-pose-l-ancre-2026-08-20.md
  - rhythm_coach/lib/career/services/challenges/builders/rhythm_bpm_ceil_full_builder.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/final_picker.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart
  - rhythm_coach/lib/career/services/generation/step_builders.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/models/session.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart
  - rhythm_coach/test/movement_animation_future_beats_test.dart
provenance:
  mesure: 12
  deduit: 3
  document: 1
  sans_marqueur: 2
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/challenges/builders/rhythm_bpm_ceil_full_builder.dart:91
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1264
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2070
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:841
  - rhythm_coach/lib/career/services/generation/final_picker.dart:253
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:209
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:382
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:517
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart:266
  - rhythm_coach/lib/career/services/generation/step_builders.dart:231
  - rhythm_coach/lib/career/services/generation/step_builders.dart:281
  - rhythm_coach/lib/career/services/generation/step_builders.dart:348
  - rhythm_coach/lib/controllers/session_controller.dart:1447
  - rhythm_coach/lib/models/session.dart:226
  - rhythm_coach/lib/models/session_step.dart:153
  - rhythm_coach/lib/services/beep_engine.dart:1073
  - rhythm_coach/lib/services/beep_engine.dart:556
  - rhythm_coach/lib/services/beep_engine.dart:568
  - rhythm_coach/lib/services/beep_engine.dart:993
  - rhythm_coach/lib/widgets/movement_animation.dart:272
  - rhythm_coach/lib/widgets/movement_animation.dart:579
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart:33
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 2 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

**[déduit]** Waiver doc: les lignes des deux tableaux (périmètre non ancré, recomptage des familles
JSON) qui portent un chiffre sans marqueur de provenance — chacune est placée sous une phrase
d'introduction qui porte déjà le sien, même convention que la relecture adverse de l'étape 3.

## Verdict

**[mesuré]** Deux réserves gênantes de la relecture adverse de l'étape 3, traitées séparément.
Réserve 1 (courbe de prévision fausse sous rampe) : corrigée, selon l'arbitrage déjà tranché par
l'orchestrateur — le BPM interpolé remonte jusqu'au widget via `BeatEvent.bpm`. Réserve 2 (périmètre
annoncé faux) : le périmètre lui-même n'a pas changé, seul le rapport de l'étape 3 est redressé (erratum
en tête, daté) — et au passage, un chiffre de la relecture elle-même s'est révélé faux lui aussi.
`flutter analyze` propre, `dart format` propre, **1039 tests verts** (1038 + 1 nouveau test).

## Réserve 1 — la courbe de prévision sous rampe

**[document]** L'arbitrage vient de l'orchestrateur, pas de Manu : faire remonter le BPM interpolé
jusqu'au widget plutôt que borner le complément par le bas, parce que Manu a déjà validé que « le
curseur suit la vitesse réelle » et qu'un complément borné resterait faux, juste moins visible.

**[mesuré]** `BeepEngine.currentBpm` retournait `_bpm` (constant, le BPM de départ du step), jamais la
valeur interpolée par `_currentInterpolatedBpm(elapsedMs)` — celle qui sert réellement à calculer
l'intervalle de chaque battement (`_emitPositionBeat`, `_intervalAfter`). Le widget recevait donc
`widget.bpm` figé pendant toute la rampe, et `complementaryBeatIntervalMs` déduisait le cycle nominal
`2T` de ce BPM figé au lieu du BPM réel du moment.

**[mesuré]** Corrigé en ouvrant le canal déjà utilisé pour les battements : `BeatEvent` porte
désormais un champ `bpm` (le BPM interpolé ayant servi à calculer `nextInterval`, threadé depuis
`_emitPositionBeat`/`_startBiffleLoop` via `_notifyBeat`). Côté widget, `_MovementAnimationState`
retient ce BPM au dernier beat reçu (`_lastBeatBpm`) et le transmet à `_PositionLadder` à la place de
`widget.bpm` — repli sur `widget.bpm` tant qu'aucun beat n'est encore arrivé sur le step courant (reset
au changement de step, comme `_lastBeatAt`). Hors rampe, `_currentInterpolatedBpm` retourne `_bpm`
exactement comme avant : **aucun changement de comportement en dehors des steps à rampe**, vérifié en
lisant le code (le call site unique de `_PositionLadder` ne touche à rien d'autre que `bpm:`).

**Ce qui le prouve [mesuré]** : `test/movement_animation_future_beats_test.dart`, nouveau cas — un
step ancré (`anchor=from, ratio=3`) simulant une rampe 80→50 bpm (ralentissement de 37,5 %, au-delà du
quart qui fait passer le complément sous zéro, cf. relecture §4). Le second beat porte
`BeatEvent.bpm == 50.0` (le BPM interpolé de ce beat précis, pas les 80 affichés au montage du widget).
Nourri de ce BPM, `complementaryBeatIntervalMs` rend **600 ms**, exactement l'intervalle court réel à
50 bpm — positif et cohérent. Nourri du BPM de départ (80, ce que le widget utilisait avant ce
correctif), le même appel rend **−300 ms** : le défaut de la relecture, reproduit avec des valeurs
rondes.

**[mesuré]** Rejoué à l'envers pour vérifier le rouge : en repassant `_bpm.toDouble()` (constant) au
lieu de `currentBpm` (interpolé) dans `_notifyBeat`, le test échoue sur `expect(lastEvent.bpm, 50.0)`
avec `Actual: <60.0>` (`_bpm` valait son défaut de constructeur, jamais mis à jour par
`configureBeatSourceForTest`) — rouge sur la bonne assertion, pas une erreur de compilation. Restauré
immédiatement.

**[déduit]** Limite assumée, comme aux deux rapports précédents de ce chantier : `_PositionLadder` et
`_computeFutureBeats` restent privés au fichier, donc le fil que je viens de tracer (`_lastBeatBpm` →
`_PositionLadder.bpm` → `complementaryBeatIntervalMs`) est vérifié par lecture du code, pas par un test
qui inspecterait la suite de points réellement peinte par le `CustomPainter`. Je n'ai pas exposé
`_computeFutureBeats` pour lever cette limite — la relecture précédente avait déjà jugé que ce
changement de surface publique ne se prend pas de son propre chef, et rien dans cette réserve ne
change ce jugement, seule la source du BPM change.

## Réserve 2 — le vrai périmètre, chiffré, et un chiffre de la relecture elle-même corrigé

**[déduit]** Remonté chaque appelant des six méthodes de `RhythmRules` jusqu'à leur point de
matérialisation. Toutes passent par `_draftToStep` (dupliqué entre `career_session_generator.dart` et
`finish_phase.dart`), dont le seul critère est `draft.mode == SessionMode.rhythm` :
`buildMiniWaveSegment` → `buildMiniWave` → `_tryEmitMiniWaveCycle` → `_emitStep` ;
`buildRecovery` → `buildRecoveryStep` → boucle principale de tirage → `_emitStep` ;
`postFinalVariants` → `buildPostFinalDraft` → `emitPostFinal` → `emitStep` ;
`buildPreFinisher` → `emitPreFinisher` → `emitStep` ;
`buildIntroStep`/`firstStepVariants` → `firstStep()` → `_draftToStep` direct
(`career_session_generator.dart:841`). Les six sont donc bien ancrées — la relecture avait raison sur
ce point contre le rapport initial.

**[mesuré]** Confirmation empirique, sans nouveau test : `test/career_rhythm_anchor_placement_test.dart`
(déjà vert dans la suite) scanne *tous* les steps rythmés de `result.session.steps` sur une séance
générée réelle (mini-vague, recovery, pré-finisher, post-final et intro compris, puisque ce sont tous
des steps de la séance) et vérifie qu'aucun n'échappe à `CareerLevelGates.rhythmAnchorFor`. Un chemin de
contournement parmi les six méthodes ferait échouer ce test — il ne le fait pas.

**[mesuré]** Le périmètre non ancré, vérifié directement sur le code de chaque site :

| famille | site | statut |
|---|---|---|
| 7 builders de défis rythmés | `rhythm_bpm_ceil_{full,shallow,throat}`, `rhythm_motion_streak`, `rhythm_depth_max`, `gorge_crossings_bpm_{full,throat}` | `SessionStep(` construit en direct, zéro mention d'`anchor` dans les 7 fichiers → défaut `none`/`1` |
| punitions | `punishment_builder.dart` (`_materialize`) | idem, zéro mention d'`anchor` |
| séances statiques | `assets/sessions/*.json` (20 fichiers) | JSON sans clé `anchor`/`ratio` → défaut au parsing |
| paliers | `assets/career/milestones.json` (37 paliers) | idem |
| punitions JSON | `assets/punishments*.json` (4 fichiers) | idem |

**[mesuré]** Recompté indépendamment le volume de steps rythmés *fonctionnels* (ceux qui produisent
vraiment un bip — un step `isTextOnly` n'atteint jamais `BeepEngine.applyStep` au-delà du retour
anticipé, donc son `anchor` est sans effet) dans chacune des trois familles JSON :

| source | méthode de comptage | résultat |
|---|---|---|
| `assets/career/milestones.json` | mode explicite par step | **43** — confirme la relecture |
| `assets/punishments*.json` | mode explicite par step | **12** — confirme la relecture |
| `assets/sessions/*.json` | mode explicite **107** + mode omis héritant du `mode` de session **18** (non `isTextOnly`, `from`/`to`/`bpm` présents) | **125**, pas 107 |

**[mesuré]** **La relecture sous-comptait `assets/sessions/` de 18 steps.** `Session.mode` (clé JSON
`"mode"` au niveau session, pas `"defaultMode"`) sert de repli pour tout step qui omet sa propre clé
`mode` — `session_controller.dart:1447` : `step.mode ?? session.defaultMode`. 18 steps de
`assets/sessions/` omettent `mode` tout en portant `from`/`to`/`bpm` (donc pas `isTextOnly`) dans des
séances dont le `mode` de tête vaut `rhythm` : ils tournent bien en rythme, ils ne portent simplement
pas la clé JSON qui l'affiche. Compté au premier passage avec la mauvaise clé de repli (`"defaultMode"`
au lieu de `"mode"`), j'obtenais 254 — un sur-comptage cette fois, qui incluait 129 steps text-only sans
rapport avec le rythme. Le chiffre juste (125) vient d'exclure `isTextOnly` et de répliquer exactement
la règle de résolution du contrôleur.

**Erratum posé** dans `docs/analysis/chantier-aimant-etape-3-le-generateur-pose-l-ancre-2026-08-20.md`,
en tête, daté — le corps du rapport original n'a pas été touché ailleurs.

**Périmètre inchangé, décision non prise** : je n'ai rien retranché ni ajouté à ce que le code ancre
déjà. Que la mini-vague (et les cinq autres familles ancrées) le soient est peut-être heureux, mais ni
voulu ni relu par Manu — question ouverte, pas tranchée ici, comme demandé.

## Vérifications exécutées

Toutes depuis `rhythm_coach/`, toutes bornées en temps, jamais pipées vers `grep`/`head`.

- **[mesuré]** `flutter analyze` → **No issues found!**
- **[mesuré]** `dart format --set-exit-if-changed lib test` → exit 0, 0 fichier changé (301 fichiers).
- **[mesuré]** `timeout 1800 flutter test`, sortie redirigée vers fichier → **1039 tests passés, 0
  échec** (1038 après les deux commits de la relecture + 1 nouveau test de la réserve 1).

## Ce que je n'ai pas pu établir

- **La suite de points réellement peinte par le `CustomPainter` sous rampe.** Comme aux deux rapports
  précédents : `_PositionLadder`/`_computeFutureBeats` sont privés au fichier, le fil `_lastBeatBpm` →
  `bpm:` → `complementaryBeatIntervalMs` est vérifié par lecture du code et par un test qui reproduit
  l'arithmétique exacte avec les mêmes entrées, pas par un test qui inspecterait les pixels ou la liste
  de points elle-même.
- **Rien n'a sonné** — la consigne du projet l'interdit. Le geste sous rampe ancrée n'a jamais été
  entendu.
- **Le rendu réel d'un step de mini-vague/recovery/pré-finisher/post-final/intro ancré, à l'oreille ou
  à l'écran, dans une séance jouée de bout en bout.** Mes preuves restent les mêmes qu'aux rapports
  précédents : générateur, moteur et widget pilotés séparément, jamais montés ensemble en conditions de
  séance réelle.
- **Si un décompte similaire (mode omis, hérite du défaut de session) existe ailleurs que dans
  `assets/sessions/`** — je l'ai vérifié pour `milestones.json` et `punishments*.json` (aucun écart
  trouvé, comptage identique à la relecture) mais pas au-delà de ces trois familles.
