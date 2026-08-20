---
type: analyse
sujet: chantier-aimant-etape-3-bis-l-ancre-redevient-une-variation
ecrit_le: 2026-08-20T23:30:13+02:00
auteur: session tss2-aimant-variation · claude-sonnet-5
revision: 01db135
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/models/custom_session_config.dart
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart
  - rhythm_coach/test/movement_animation_future_beats_test.dart
  - rhythm_coach/test/session_step_anchor_compat_test.dart
provenance:
  mesure: 9
  deduit: 1
  document: 2
  sans_marqueur: 5
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/models/custom_session_config.dart:247
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart:182
  - rhythm_coach/lib/career/services/career_level_gates.dart:113
  - rhythm_coach/lib/career/services/career_level_gates.dart:132
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1097
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1203
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1267
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1330
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1503
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2070
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:728
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:841
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:204
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:34
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:350
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:386
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:494
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:532
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:225
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:267
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:312
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:331
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:373
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:382
  - rhythm_coach/lib/widgets/movement_animation.dart:281
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 5 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

Waiver doc: les deux tableaux (classification des six méthodes, chiffrage avant/après par niveau) et
les listes à puces (impact Custom, ce que je n'ai pas pu établir) qui portent un chiffre sans
marqueur de provenance — chacun est placé sous une phrase d'introduction qui porte déjà le sien,
même convention que les rapports précédents de ce chantier.

## Ce qui a changé

**[mesuré]** L'erreur de cadrage décrite par Manu est confirmée dans le code d'avant ce rapport :
`_draftToStep` (point unique de matérialisation, dupliqué dans `career_session_generator.dart:2070`
et `finish_phase.dart:386`) posait l'ancre sur **tout** `StepDraft` dont `mode == SessionMode.rhythm`,
sans distinction de provenance. Rejouer le générateur avec ce gate retiré (mutation de vérification,
niveau 5, seed 42, restauré ensuite) donne **30 steps rythmés sur 30 ancrés** — la surface de 100 %
annoncée par Manu, mesurée et non supposée.

**[mesuré]** Le correctif introduit un paramètre `intense` sur `_draftToStep`/`_emitStep` (les deux
copies), par défaut `false` → `BeatAnchor.none`. Seuls trois call sites le passent à `true` :
- la boucle mini-vague (`career_session_generator.dart:1267`, dans `_tryEmitMiniWaveCycle`) ;
- le pré-finisher (`finish_phase.dart:204`, `emitPreFinisher`) ;
- les boosts de la phase finish (`finish_phase.dart:350`, dans `emitBoosts`).

Tous les autres émetteurs (boucle main + recovery partagent le même call site à
`career_session_generator.dart:1503` ; l'intro à la ligne 841 ; l'ordre de déglutition forcée à la
ligne 1330 ; le step final à `finish_phase.dart:494` ; le post-final à `finish_phase.dart:532`)
gardent le défaut `false`. Le métronome (boucle main + recovery) redevient donc le standard non
ancré ; `RhythmRules`/`CareerLevelGates.rhythmAnchorFor` (inchangés) ne décident plus que la position
`from`/`to` **parmi** les steps que le générateur a choisi d'ancrer.

## La liste des six méthodes, et laquelle j'ai retenue

**[document]** La relecture round 1 (rapport `chantier-aimant-etape-3-le-generateur-pose-l-ancre`,
erratum) avait établi la liste exacte des chaînes d'appel : `buildMiniWaveSegment` →
`_tryEmitMiniWaveCycle` → `_emitStep` ; `buildRecovery` → boucle principale → `_emitStep` ;
`postFinalVariants` → `emitPostFinal` → `emitStep` ; `buildPreFinisher` → `emitPreFinisher` →
`emitStep` ; `buildIntroStep`/`firstStepVariants` → `firstStep()` → `_draftToStep` direct (ligne
841). Je repars de cette liste plutôt que d'en refaire l'inventaire.

**[mesuré]** Manu n'a pas défini « moment intense » au-delà de « les passages qui montent (mini-
vagues, phase finale) ». J'ai classé les six selon le texte déjà écrit dans leurs propres docblocks
(`career_session_generator_rules_rhythm.dart`) — pas selon mon interprétation seule :

| méthode | doc existante | classée | ligne |
|---|---|---|---|
| `buildMiniWaveSegment` | « la vague accélère et se condense » | **intense** | :225 |
| `buildPreFinisher` | « courte accélération … prépare la phase boosts » | **intense** | :331 |
| `buildRecovery` | « rythme très doux comme récup » | doux | :267 |
| `postFinalVariants` | « reprise douce » (aftercare post-orgasme) | doux | :312 |
| `buildIntroStep` | ouverture de séance | doux | :373 |
| `firstStepVariants` | « 3 variantes douces qui couvrent le socle » | doux | :382 |

`buildRecovery`, `postFinalVariants` et `firstStepVariants` se qualifient eux-mêmes de « doux » dans
leur propre commentaire — ce n'est pas une lecture, c'est une citation. `buildIntroStep` n'a pas de
mot-clé mais sa position (ouverture) exclut la dramaturgie montante par construction. Les deux gardés
intenses le sont par un mot commun : « accélère »/« accélération ».

**J'ai ajouté un septième site que la liste des six ne couvre pas** : les **boosts** de la phase
finish (`finish_phase.dart:350`, hors `RhythmRules` — le draft y est construit inline, pas via une
méthode de mode). C'est le second des deux mots exacts de Manu (« phase finale ») ; sa doc interne dit
« sprint … qui ramp BPM et profondeur de manière monotone croissante ». Sans lui, aucune séance ne
finirait ancrée, ce qui aurait contredit Manu aussi frontalement que la version 100 %.

**Ce que je n'ai PAS tranché silencieusement, et qui reste ouvert** : le **step final** lui-même
(`emitFinalStep`, `finish_phase.dart:494`, l'apothéose contemplative) n'est dans aucune des deux
listes — ni les six méthodes, ni « phase finale » au sens boosts. Je l'ai laissé **non ancré** : (a)
il n'est pas nommé par Manu littéralement, (b) c'est un pic déjà atteint et tenu, pas un passage qui
« monte », (c) il est souvent hors mode rhythm (hold/lick/hand). Mais « phase finale » dans la bouche
de Manu pourrait très bien l'inclure. **Question pour Manu** : le step final compte-t-il comme un
moment intense à ancrer, ou seulement son ramp d'approche (boosts) ?

## Ce qui le prouve — chiffre avant/après, par niveau

**[mesuré]** Séances réellement générées (`CareerSessionGenerator`, seed 42, `humiliationCareer:
400.0`), part de steps rythmés ancrés :

| niveau | steps rythmés | ancrés | part | où (times, sur la fin de séance à `sessionEnd`) |
|---|---|---|---|---|
| 1 | 12 | 3 | 25,0 % | 264-298 / 393 (dernier quart — pré-finisher 65 bpm + 2 boosts) |
| 5 | 30 | 3 | 10,0 % | 732-762 / 855 (dernier 14 % — boosts seuls, pas de mini-vague ce tirage) |
| 9 | 40 | 7 | 17,5 % | mini-vague (694-716) + boosts (1070-1112) / 1204 |
| 10 | 43 | 7 | 16,3 % | idem, plancher d'ancre from/to |
| 15 | 83 | 12 | 14,5 % | 4 mini-vagues (100/120/135 bpm), 0 boost rhythm ce tirage (burst = hand) |
| 25 | 113 | 17 | 15,0 % | 4 mini-vagues + 1 groupe boosts (2697-2751) / 2845 |
| 35 | 113 | 17 | 15,0 % | identique à 25 (plafond de palier atteint) |

**Avant** ce correctif (mesuré par mutation, cf. ci-dessus) : **100 %** à tout niveau, tout step
rythmé. **Après** : **10 à 25 %**, jamais la moitié — et à chaque niveau mesuré, les steps ancrés
tombent soit sur la signature bpm exacte de la mini-vague (100/120/135, groupés par 3), soit dans le
dernier quart (souvent moins) de la durée de séance (pré-finisher + boosts). Aucun step ancré isolé
en milieu de séance hors de ces deux signatures, sur les 7 niveaux balayés.

## Le test qui manque (réserve gênante, round 3)

**[document]** La relecture round 3 avait mesuré que le correctif `a9fa8a5` (BPM interpolé remonté au
widget, `movement_animation.dart:281`) n'était tenu par aucun test bout-en-bout : en lui rendant son
code d'avant, les 1039 tests restaient verts.

**[mesuré]** Ajouté `test/movement_animation_future_beats_test.dart` un `testWidgets` qui monte
`MovementAnimation` avec un `BeepEngine` réel, envoie deux beats via `emitOneBeatForTest` (80 puis 50
bpm — rampe), laisse le stream livrer (`await tester.pump()`), puis lit `_PositionLadder.bpm` (widget
privé, champ public — accès par `find.byWidgetPredicate` + `as dynamic`, seule voie sans dupliquer la
formule du correctif). Vérifié par mutation : le code d'avant (`bpm: widget.bpm.toDouble().round()`)
fait échouer le test exactement sur cette assertion (`Expected: <50> Actual: <80>`), pas ailleurs —
remis en place ensuite.

## Ce que je n'ai pas touché — impact sur le futur réglage Custom

**[mesuré]** Le mode Custom appelle le même `CareerSessionGenerator().generate(level:
cfg.resolveVirtualLevel(...))` (`custom_mode_screen.dart:182`) — il hérite donc de ce correctif tel
quel, sans code Custom modifié. **[déduit]** Deux conséquences pour la tâche séparée (dosage + choix
du point d'ancrage) :
- **Plus facile** : la base de départ n'est plus « 100 % ancré, le dosage retire » mais « 10-25 %
  ancré sur des moments nommés, le dosage ajoute » — un curseur additif est plus simple à concevoir
  qu'un curseur soustractif sur un défaut envahissant.
- **Plus dur** : `intense` n'est pas un paramètre exposé — c'est câblé en dur sur trois call sites
  précis (mini-vague, pré-finisher, boosts). Si Manu veut qu'un réglage Custom permette d'ancrer *au-
  delà* de ces trois moments (par ex. « toujours », comme avant ce correctif), il n'existe aujourd'hui
  aucun paramètre à faire suivre jusqu'à `_draftToStep` — la tâche Custom devra soit ajouter ce
  paramètre, soit accepter que « toujours » reste hors de portée du dosage.

Je n'ai ouvert ni `custom_session_config.dart`, ni `custom_mode_screen.dart`, ni aucun écran.

## Compatibilité et invariants

**[mesuré]** `test/session_step_anchor_compat_test.dart` reste vert et hors de mon périmètre : il ne
lit que les assets JSON statiques + le défaut du constructeur `SessionStep`, jamais le générateur —
inchangé par ce correctif, toujours discriminant sur ce qu'il couvre.

**[mesuré]** L'invariant `2T` reste exact pour tout step **ancré** (`_intervalAfter` déduit le court
du long par soustraction). Pour un step **non ancré** (régulier), j'ai mesuré un écart de ±1 ms
possible entre `intervals[i]+intervals[i+1]` et `2T` arrondi directement (ex. bpm=90 : 2×round(667) =
1334 contre round(1333,33) = 1333) — arrondi indépendant sur les deux appels de
`_regularInterval`, déjà documenté dans `movement_animation.dart`
(`complementaryBeatIntervalMs`, « à 1 ms d'arrondi près »). Ce n'est pas un défaut introduit ici : le
test `career_rhythm_anchor_placement_test.dart` ne l'avait simplement jamais mesuré, faute d'avoir
jamais contenu de step rythmé non ancré avant ce correctif. Corrigé la tolérance du test (0 ms ancré,
1 ms non ancré) plutôt que le code.

**[mesuré]** `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed lib test` :
propre. Suite complète : **1041 tests verts** (1039 de référence + 2 nouveaux : le test widget
ci-dessus et un test unitaire `rhythmAnchorFor` qui couvre la branche `from` que la génération réelle
n'atteint plus au-dessus du plancher, cf. tableau ci-dessus — bpm plancher des deux seules sources
ancrées à ce niveau, 100).

## Ce que je n'ai pas pu établir

- Le ressenti réel de la joueuse sur ce nouveau dosage (10-25 % contre 100 %) — hors de mon périmètre
  (rendu audio/geste, jugé par Manu seul).
- Si « phase finale » dans les mots de Manu inclut le step final lui-même (`emitFinalStep`) — laissé
  non ancré, cf. question ci-dessus.
- Le comportement à des niveaux/seeds au-delà des 7 balayés — les nombres du tableau sont un
  échantillon, pas une preuve exhaustive de non-régression sur tout l'espace de tirage.

## Question pour Manu

Le step final (l'apothéose, juste après les boosts) compte-t-il comme un « moment intense » à ancrer
au même titre que les boosts qui le précèdent, ou reste-t-il hors de la variation comme une intro/un
post-final ? Et le pré-finisher (accélération réservée aux bas niveaux, avant les boosts) : je l'ai
classé intense — d'accord avec cette lecture, ou le réserves-tu aux seuls boosts/mini-vague ?
