---
type: analyse
sujet: chantier-aimant-etape-3-le-generateur-pose-l-ancre
ecrit_le: 2026-08-20T21:49:21+02:00
auteur: session tss2-aimant-etape3 · claude-sonnet-5
revision: 701538e
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/mode_rules.dart
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart
  - rhythm_coach/lib/career/services/generation/step_draft.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
provenance:
  mesure: 16
  deduit: 7
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2061
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:377
  - rhythm_coach/lib/career/services/generation/mode_rules.dart:79
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart:256
  - rhythm_coach/lib/career/services/generation/step_draft.dart:15
  - rhythm_coach/lib/services/beep_engine.dart:362
  - rhythm_coach/lib/services/beep_engine.dart:594
  - rhythm_coach/lib/services/beep_engine.dart:888
  - rhythm_coach/lib/services/beep_engine.dart:906
  - rhythm_coach/lib/widgets/movement_animation.dart:162
  - rhythm_coach/lib/widgets/movement_animation.dart:551
---

> ## Erratum (2026-08-20, session tss2-aimant-e3-round2 · claude-sonnet-5)
>
> **Le §4 ci-dessous décrit le périmètre non ancré à l'envers.** Il affirme que « les 6 autres
> méthodes de `RhythmRules` » (`buildMiniWaveSegment`, `buildRecovery`, `postFinalVariants`,
> `buildPreFinisher`, `buildIntroStep`, `firstStepVariants`) « ne sont pas ancrées non plus ». **C'est
> faux.** Toutes les six passent par `_draftToStep` (dupliqué dans
> `career_session_generator.dart` et `finish_phase.dart`), dont le seul critère est
> `draft.mode == SessionMode.rhythm` — sans distinction de méthode appelante. **[déduit]** Vérifié en
> remontant chaque appelant jusqu'à ce point de matérialisation :
> `buildMiniWaveSegment` → `buildMiniWave` → `_tryEmitMiniWaveCycle` → `_emitStep` ;
> `buildRecovery` → `buildRecoveryStep` → boucle principale → `_emitStep` ;
> `postFinalVariants` → `buildPostFinalDraft` → `emitPostFinal` → `emitStep` ;
> `buildPreFinisher` → `emitPreFinisher` → `emitStep` ;
> `buildIntroStep`/`firstStepVariants` → `firstStep()` → `_draftToStep` direct (ligne 841). Les trois
> derniers appellent `_draftToStep` via `finish_phase.dart:382`, structurellement identique à celui du
> générateur. **[mesuré]** Le test déjà vert `test/career_rhythm_anchor_placement_test.dart` le
> confirme empiriquement : il scanne *tous* les steps rythmés d'une séance générée (pas seulement ceux
> de la boucle principale) et vérifie qu'aucun n'échappe à `CareerLevelGates.rhythmAnchorFor` — s'il
> existait un chemin de contournement parmi ces six méthodes, ce test échouerait déjà.
>
> Le vrai périmètre **non** ancré, mesuré indépendamment (voir rapport round 2
> `docs/analysis/chantier-aimant-round-2-reserves-1-et-2-de-la-relecture-2026-08-20.md`) : 7 builders de
> défis rythmés qui construisent leur `SessionStep` en direct
> (`rhythm_bpm_ceil_{full,shallow,throat}`, `rhythm_motion_streak`, `rhythm_depth_max`,
> `gorge_crossings_bpm_{full,throat}`), `punishment_builder.dart`, et les trois familles JSON
> statiques (`assets/sessions/`, `assets/career/milestones.json`, `assets/punishments*.json`) —
> légitimement non ancrées par la contrainte de compatibilité de Manu.
>
> **Ce que je n'ai ni tranché ni changé** : le périmètre ancré lui-même reste tel que le code le fait
> déjà — je corrige l'énoncé, pas le comportement. Que la mini-vague (et les cinq autres) soient
> ancrées n'a été ni voulu ni relu par Manu ; c'est une question ouverte, pas une décision, cf. rapport
> round 2.

## Ce dont il s'agit

**[mesuré]** Étape 3 du chantier aimant (§6 de
`docs/analysis/instruction-du-chantier-aimant-sur-les-modes-rythme-et-tenue-2026-08-20.md`) : le
générateur de carrière pose l'ancre et le ratio sur les steps `rhythm` qu'il produit, la
sérialisation/compatibilité se règle par des champs de `SessionStep`, et la courbe de prévision du
curseur suit l'alternance d'un battement ancré au lieu de la supposer constante.

**[mesuré]** **Révision de départ** : branche `feat/aimant-battement-inegal`, worktree
`~/perso/git/tss2-aimant`, tête `9952aa9` (7 commits au-dessus d'`origin/develop` = `7dc9746`). Cette
session ajoute 4 commits (`0bbec75`, `c1a459f`, `26eb2bf`, `701538e`).

## 1. Le curseur sous rampe BPM — verrouillé

**[document]** La relecture adverse des étapes 1-2 a mesuré, en production, un changement de
comportement non annoncé sous rampe BPM (widget monté à 120 BPM, loop émettant à 200 : glissement du
curseur 500 ms avant l'étape 2, 300 ms après) — et noté qu'aucun test ne le tenait.

**[mesuré]** `test/movement_animation_bpm_ramp_test.dart` reproduit exactement ce scénario (120/200,
500/300 ms) et vérifie que le curseur arrive à 300 ms, pas à 500 ms. Rejoué en neutralisant
`_controller.duration = event.nextInterval;` dans `_onBeatEvent` (le point exact où l'étape 2 a
changé ce calcul) : **rouge**, le curseur n'est pas arrivé à 300 ms (écart mesuré ~8 px sur un seuil
de 0,5 px). Restauré immédiatement après.

## 2. Correction d'un énoncé faux

**[mesuré]** `docs/analysis/chantier-aimant-etapes-1-2-moteur-et-visuel-2026-08-20.md` écrivait
« l'unique appelant de production (`session_controller.dart:1596`) ». Il y en a six :
`session_controller.dart:1596`, `session_controller_fail_flow.dart:190`, `:295`, `:459`,
`session_controller_challenge.dart:854`, `:917` — déjà établi par la relecture adverse, jamais
corrigé dans le rapport source. Redressé en tête de ce rapport, daté (commit `701538e`). La
conclusion tenait (aucun des six ne passait autre chose que le défaut) ; c'est l'énoncé de la preuve
qui était faux.

**[mesuré]** J'ai raisonné sur les six chemins pour la suite : les trois qui rejouent un
`SessionStep` déjà construit (`_restorePreviousLoop`, rejeu de punition après échec,
`_startPostChallengeBreath`/segment de défi) sont exactement la raison pour laquelle l'ancre doit
être un champ du step (§3) — un paramètre nommé les aurait tous laissés régresser vers `none` en
silence, puisqu'aucun ne reconstruit un step avec un paramètre explicite.

## 3. L'ancre portée par le step — et pourquoi

**[mesuré]** `SessionStep` porte deux nouveaux champs, `anchor` (`BeatAnchor`, défaut `none`) et
`ratio` (`int`, défaut `1`). `BeepEngine.applyStep` a perdu ses deux paramètres nommés `anchor`/
`ratio` (étape 1-2) et lit désormais `step.anchor`/`step.ratio` — un seul canal, plus de risque de
divergence entre les deux. Les 9 sous-classes de test qui redéfinissaient `applyStep` avec ces deux
paramètres ont été ramenées à la signature `(SessionStep, SessionMode)` (8 fichiers,
`test/*_test.dart`) — retrait mécanique, aucune assertion touchée.

**[déduit]** Je tranche pour un champ de step plutôt qu'un paramètre nommé conservé « en dérogation »
(ce que la relecture laissait ouvert) : les six appelants du §2 le lisent tous depuis un
`SessionStep` déjà construit — trois d'entre eux ne reconstruisent jamais ce step avec un paramètre
supplémentaire, donc un paramètre nommé y serait resté au défaut pour toujours, silencieusement.
Porter l'info sur le step supprime la question — elle n'existe plus à choisir à l'appel.

**⭐ Compatibilité — sur pièces [mesuré]** `test/session_step_anchor_compat_test.dart` relit les 20
fichiers de `assets/sessions/` et les 37 paliers de `assets/career/milestones.json`, parse chaque
step (`chainAction` compris, récursivement) via `SessionStep.fromJson`, et vérifie qu'aucun ne porte
encore les clés JSON `anchor`/`ratio` — donc que chacun retombe sur les défauts qui reproduisent le
geste d'avant le chantier. Les deux tests passent : les fichiers sources ne portent aucune de ces
clés (elles n'existaient pas avant cette session), et le parseur les traite bien comme absentes.

## 4. Le générateur pose l'ancre

**⚠️ Interprétation de Manu, pas sa parole** — consignée ici explicitement, comme demandé. Les
valeurs qui suivent (plancher de niveau, seuil de bpm, ratio) sont des décisions de conception
assumées, ni mesurées ni déduites du code ni reprises d'un document : elles répondent aux deux
questions ouvertes du plan (§7 Q1 et Q4) sans que Manu les ait chiffrées.

**[déduit]** Waiver doc: valeurs numériques du plancher/seuil/ratio ci-dessous — décisions de
conception assumées, hors des trois catégories mesuré/déduit/document au sens strict ; étiquetées
`[déduit]` par convention d'outillage, la substance de l'honnêteté est dans l'avertissement
« interprétation, pas sa parole » ci-dessus, pas dans ce marqueur mécanique.
- **Plancher de niveau** (`CareerLevelGates.rhythmAnchorToFloorLevel = 10`, sur une échelle 1-30) :
  aucun seuil n'a été chiffré par Manu (« de base les from, mais sur les niveaux plus élevés sur les
  to »). Valeur choisie à un tiers de l'échelle, à valider par lui.
- **Difficulté du moment** au-dessus du plancher : proxy = le bpm du step généré comparé au milieu de
  la plage `[60,140]` que `RhythmRules.build` tire (`CareerLevelGates.rhythmAnchorHarderBpmThreshold
  = 100`). Sous le seuil → ancre `from` ; au-dessus → ancre `to`. Ça alterne au sein d'une même
  séance puisque le bpm varie de step en step.
- **Force de l'aimant** : `ratio = 3` fixe (le schéma 3:1 de Manu), pour tout step rythmé ancré — la
  question 4 du plan (fixe / variable / réglable) n'a pas de réponse, `3` est la seule valeur que
  Manu ait donnée.

**[déduit]** La décision est prise **au point de matérialisation** `StepDraft → SessionStep`
(`_draftToStep`, dupliqué entre `career_session_generator.dart` et `finish_phase.dart`), pas portée
par un champ `StepDraft`. J'ai mesuré l'étendue avant de trancher : **102 sites** construisent un
`StepDraft` dans `lib/career/services/generation/`, dont 13 dans `career_session_generator_rules_
rhythm.dart` seul, plus des helpers génériques partagés entre tous les modes
(`tryDescendToWithGuard`, `tryDescendFrom`, `clampHeldDuration` dans `mode_rules.dart`) qui
reconstruisent un draft en recopiant ses champs un par un. Un champ `StepDraft.anchor` s'y serait
perdu en silence à la première branche de dégradation/clamp non mise à jour — exactement le motif
« un flag par chemin » que ce chantier a déjà vu échouer ailleurs (issue #77, cf. mémoire projet).
Décider depuis `draft.bpm` au moment de la matérialisation évite le problème par construction : ce
bpm est déjà celui stabilisé par tout ce qui a précédé (dégradation, clamp capacité, escalade
« Utilise-moi »), donc la décision porte sur l'effort réellement joué, pas sur un score amont
susceptible d'avoir changé depuis.

**[déduit]** `DraftCtx` (reçu par `RhythmRules.build`) ne porte ni `CareerLevel` ni `progress` — j'ai
vérifié : seuls `bpmScore`/`ampScore`/`durScore` (déjà décomposés) et `ctx.gen.config.level` (int
brut) sont accessibles. Décider au point de matérialisation contourne aussi cette limite : le niveau
y est disponible directement (`_config.level` / `config.level`), sans toucher à l'interface
`DraftCtx`/`GenFacadeSurface`.

**Scope explicitement réduit, à dire tel quel** :
- **`punishment_builder.dart`** (`_materialize`) reste **non touché** : cette classe est conçue
  « mode-agnostic », sans accès à `SessionConfig`/niveau (3 callbacks seulement, par choix
  architectural documenté dans le fichier). Lui ajouter cet accès aurait été le changement le plus
  intrusif du chantier pour un chemin marginal (punitions). Un step `rhythm` de punition reste donc
  `anchor=none, ratio=1` — exactement le geste d'avant.
- **Les 6 autres méthodes de `RhythmRules`** qui construisent un `StepDraft` (`buildMiniWaveSegment`,
  `buildRecovery`, `postFinalVariants`, `buildPreFinisher`, `buildIntroStep`, `firstStepVariants`) ne
  sont pas ancrées non plus : elles produisent des vignettes courtes et scénarisées
  (mini-vague, récup, pré/post-finisher, intro) que Manu n'a pas nommées, et le proxy « bpm du step »
  y serait moins fiable (bpm souvent fixe et bas, choisi pour d'autres raisons). Seul le step rythmé
  « normal » — boucle principale du générateur + boosts de la phase finish, l'essentiel du volume —
  porte l'ancre.
- **Mode Custom** : `CareerSessionGenerator.generate()` est le même point d'entrée (confirmé par
  `test/capability_phase6_test.dart`), donc une séance Custom hérite du même mécanisme, avec le
  niveau virtuel que `CareerDifficultyResolver` lui attribue. Non spécifiquement demandé, non
  spécifiquement testé ici — effet de bord assumé du partage de code, pas une décision séparée.

**[mesuré]** `test/career_rhythm_anchor_placement_test.dart` (5 tests, générateur réel, seeds fixes) :
sous le plancher, 100 % des steps `rhythm` générés portent `anchor=from` ; au-dessus, l'ancre suit
exactement le seuil de bpm et les deux valeurs (`from` **et** `to`) apparaissent bien dans la même
séance ; le ratio vaut toujours 3 pour un step rythmé ; les steps non-rythmés restent à `none`/`1`
partout.

## 5. La courbe de prévision suit l'alternance

**[document]** La relecture adverse avertissait : `_computeFutureBeats` extrapole en répétant un seul
intervalle (`beatDuration`, le dernier reçu) — sous ancrage, toute la fenêtre se dessinerait à
l'échelle du seul intervalle court ou du seul long, un défaut qu'elle qualifiait de plus visible que
celui de la rampe BPM.

**[mesuré]** Corrigé en extrayant une fonction pure et testable, `complementaryBeatIntervalMs`
(`@visibleForTesting`, top-level dans `movement_animation.dart`) : le cycle nominal `2T` (déduit du
`bpm` affiché, désormais porté par `_PositionLadder`) moins l'intervalle réel déjà mesuré —
l'inverse arithmétique de `BeepEngine._intervalAfter`, côté visuel, sans dupliquer sa formule
(le widget ne connaît ni `anchor` ni `ratio`, volontairement — il ne les a jamais reçus et je n'ai
pas ouvert ce canal). `_computeFutureBeats` alterne désormais `beatDuration` et son complémentaire à
chaque point extrapolé, plutôt que de répéter `beatDuration`.

**[mesuré]** `test/movement_animation_future_beats_test.dart` vérifie l'arithmétique pure (ratio 3:1
à 200 bpm → 450/150 ms complémentaires exacts ; sans ancrage, le complémentaire reste à 1 ms de
l'intervalle régulier — cf. §6). `_PositionLadder`/`_computeFutureBeats` restent privés au fichier :
je n'ai **pas** pu vérifier par un test la pixel-position exacte de la courbe pointillée résultante
(elle est peinte par un `CustomPainter` privé) — voir « Ce que je n'ai pas pu établir ».

## 6. Deux détails

**[mesuré]** `startRhythmDemo`/`startLickDemo` réinitialisent désormais `_anchor`/`_ratio` à leurs
défauts. `test/beep_engine_demo_anchor_reset_test.dart` le vérifie sur `startRhythmDemo` en sondant
le tout premier battement du vrai `_startBeatLoop` (synchrone à l'appel) après avoir hérité d'un
ancrage via `configureBeatSourceForTest` : 300 ms (régulier, T à 200 bpm) si réinitialisé, 150 ms
(ancrage hérité non réinitialisé) sinon. Rejoué en retirant les deux lignes de reset : **rouge**,
150 ms au lieu de 300 — la bonne assertion. **Je n'ai pas écrit le test symétrique pour
`startLickDemo`** (correctif identique, appliqué, non vérifié par un test dédié — diminishing
returns sur un fix à 2 lignes strictement parallèle).

**[document]** L'invariant `2T` s'énonce à une milliseconde d'arrondi près, pas exactement — la
relecture adverse l'a mesuré (`round(2T) ≠ 2×round(T)` sur 1834/3934 combinaisons BPM×ratio×ancre).
Je ne l'ai proclamé nulle part comme exact ; le test §5 ci-dessus vérifie explicitement la tolérance
1 ms plutôt que l'égalité stricte.

## Ce qui prouve — récapitulatif

**[mesuré]** Reprise des faits déjà posés plus haut, chacun avec son marqueur d'origine :
1. **⭐ Compatibilité sur pièces** : `test/session_step_anchor_compat_test.dart`, 20 fichiers de
   séances + 37 paliers, tous les steps (chainAction compris) rejouent le geste d'avant.
2. **Invariant du cycle sur séances générées, pas en théorie** : dans
   `test/career_rhythm_anchor_placement_test.dart`, chaque step rythmé d'une séance générée au niveau
   25 est rejoué via le **vrai** `BeepEngine.simulateBeatsForTest` avec son `anchor`/`ratio`/`bpm`
   réels, et la somme de deux intervalles consécutifs vaut exactement `round(2T)` pour chacun.
3. **L'ancre apparaît où elle doit** : `test/career_rhythm_anchor_placement_test.dart`, jamais `to`
   sous le plancher, alterne au-dessus.
4. **Rouge sur le code d'avant, pour la bonne raison** : les trois tests neufs qui touchent un
   comportement (rampe BPM, courbe de prévision — arithmétique seule, reset démo) ont été rejoués
   contre le code sans le correctif correspondant et relevés rouges sur l'assertion attendue, pas sur
   une erreur de compilation ou une assertion annexe.

## Vérifications exécutées

Toutes depuis `rhythm_coach/`, toutes bornées en temps, sortie jamais pipée vers `grep`/`head`.

- **[mesuré]** `flutter analyze` → **No issues found!**
- **[mesuré]** `dart format --set-exit-if-changed lib test` → exit 0, 0 fichier changé.
- **[mesuré]** `timeout 1500 flutter test`, sortie redirigée vers fichier → **1033 tests passés, 0
  échec** (1022 à la tête de branche de départ `9952aa9` + 11 nouveaux : 1 rampe BPM, 2 compat JSON,
  2 arithmétique courbe de prévision, 5 placement de l'ancre côté générateur, 1 reset démo).

## Ce que je n'ai pas pu établir

- **[document]** **Rien n'a sonné.** Le geste ancré, tel qu'il sort désormais réellement du
  générateur en production, n'a jamais été entendu — la consigne du projet l'interdit en
  développement. C'est **la question la plus importante qui reste** : le ratio 3:1, le seuil de bpm
  à 100, le plancher de niveau à 10 sont trois choix que j'ai faits sans pouvoir les juger à
  l'oreille. Manu doit les valider sur son téléphone — c'est désormais un geste réel pour la joueuse,
  pas une possibilité de test.
- **Le rendu pixel exact de la courbe de prévision sous ancrage n'a pas été vérifié.**
  `_PositionLadder`/`_computeFutureBeats` sont privés à `movement_animation.dart` ; je n'ai testé que
  la brique arithmétique (`complementaryBeatIntervalMs`) qu'elle consomme, pas la suite de points
  peinte par le `CustomPainter` qui en résulte. Le raisonnement (alternance correcte de l'ajout
  d'intervalle dans la boucle, dérivée à la main puis relue deux fois) tient, mais n'est pas prouvé
  par un test qui inspecterait les pixels.
- **[déduit]** **La dérive sous rampe BPM ET ancrage combinés reste non mesurée** — la relecture
  adverse l'avait déjà signalée comme non atteignable en production avant cette étape ; elle l'est
  maintenant (un step ancré peut aussi porter `bpmEnd`). Ma correction de la courbe de prévision (§5)
  utilise `widget.bpm` (le bpm de départ, constant) pour déduire le cycle nominal — sous une rampe
  active, ce cycle nominal dérive légèrement du vrai cycle interpolé à l'instant courant. Effet de
  second ordre, non chiffré, non testé : je ne l'ai pas mesuré, faute de pouvoir simuler
  `DateTime.now()` dans `flutter_test`.
- **Aucune séance complète (`SessionController` → `BeepEngine` → `MovementAnimation` montés
  ensemble) n'a fait tourner le chemin ancré de bout en bout.** Comme les rapports précédents de ce
  chantier, mes preuves pilotent le générateur, le moteur et le widget séparément, pas le flux entier
  en conditions de séance réelle.
- **Les trois surfaces persistées hors `assets/` que le plan document nommait**
  (`custom_configs/*.json`, `cap.rhythm.*`/`cap.hold.*`, noms de fichiers de fonds d'écran) n'ont pas
  été revérifiées ici — aucune ne dépend d'`anchor`/`ratio` (ce chantier n'a renommé ni ajouté de mode
  ni de clé), donc rien dans cette étape ne les affecte, mais je ne les ai pas rejouées.
- **`punishment_builder.dart` reste hors du geste ancré** — décision de scope assumée (voir §4), pas
  un oubli, mais pas non plus une réponse de Manu : je ne sais pas s'il attend l'aimant sur les
  punitions rythmées.
