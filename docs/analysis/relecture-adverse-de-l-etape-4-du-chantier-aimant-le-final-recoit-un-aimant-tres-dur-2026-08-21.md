---
type: analyse
sujet: relecture-adverse-de-l-etape-4-du-chantier-aimant-le-final-recoit-un-aimant-tres-dur
ecrit_le: 2026-08-21T00:50:33+02:00
auteur: session tss2-aimant-e4-relecture · claude-opus-5
revision: f30b2fd
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/final_picker.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_hold.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/capability_tracker.dart
  - rhythm_coach/lib/services/hold_verifier.dart
  - rhythm_coach/lib/widgets/mode_badge_row.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/beep_engine_hold_swing_test.dart
  - rhythm_coach/test/capability_tracker_test.dart
  - rhythm_coach/test/career_hold_final_anchor_placement_test.dart
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart
  - rhythm_coach/test/session_controller_hold_verifier_swing_test.dart
  - rhythm_coach/test/session_step_anchor_compat_test.dart
  - rhythm_coach/test/session_step_anchor_replay_test.dart
provenance:
  mesure: 18
  deduit: 2
  document: 1
  sans_marqueur: 3
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/career_level_gates.dart:113
  - rhythm_coach/lib/career/services/career_level_gates.dart:157
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2088
  - rhythm_coach/lib/career/services/generation/final_picker.dart:141
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:394
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:524
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_hold.dart:248
  - rhythm_coach/lib/controllers/session_controller.dart:1467
  - rhythm_coach/lib/controllers/session_controller.dart:2111
  - rhythm_coach/lib/controllers/session_controller.dart:2199
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:1005
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:456
  - rhythm_coach/lib/models/session_step.dart:12
  - rhythm_coach/lib/models/session_step.dart:189
  - rhythm_coach/lib/services/beep_engine.dart:370
  - rhythm_coach/lib/services/beep_engine.dart:463
  - rhythm_coach/lib/services/beep_engine.dart:775
  - rhythm_coach/lib/services/beep_engine.dart:812
  - rhythm_coach/lib/services/beep_engine.dart:920
  - rhythm_coach/lib/services/beep_engine.dart:93
  - rhythm_coach/lib/services/capability_tracker.dart:192
  - rhythm_coach/lib/services/capability_tracker.dart:295
  - rhythm_coach/lib/services/capability_tracker.dart:413
  - rhythm_coach/lib/services/capability_tracker.dart:444
  - rhythm_coach/lib/widgets/mode_badge_row.dart:38
  - rhythm_coach/lib/widgets/movement_animation.dart:227
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 3 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

Waiver doc: les trois énumérations numérotées (les mutations restées vertes, les réserves, les
questions ouvertes) — chacune développe une phrase d'introduction qui porte déjà son marqueur,
même convention que les rapports précédents de ce chantier.

> Relecture adverse de `91bd0c1` · `21e1775` · `f30b2fd` (diff `75df1ef..HEAD`), branche
> `feat/aimant-battement-inegal`, worktree `tss2-aimant`. Consigne : chercher à réfuter.
> Auteur relu : `claude-sonnet-5`. Aucune fusion, aucun envoi.

## Verdict

**Publiable avec réserves**, deux gênantes et une non gênante — détaillées en fin de document.
Le code fait ce que le rapport annonce ; ce qui manque, ce sont les tests qui le tiendraient
en place, et la mesure de ce que le désarmement caméra coûte réellement.

## Ce que j'ai revérifié moi-même

**[mesuré]** Depuis `rhythm_coach/` : `flutter analyze` rend « No issues found! » ;
`dart format --set-exit-if-changed lib test` rend « Formatted 304 files (0 changed) » ;
`flutter test` (sortie dans un fichier, jamais pipé) rend **1055 tests verts, exit 0**.
Le chiffre annoncé par l'auteur est exact.

## Piste 1 — la portée du désarmement caméra

**[mesuré]** La règle est `mode == hold && step.anchor != BeatAnchor.to`. La seule source d'un
step `hold` portant `anchor == to` est `_draftToStep` (ses deux copies), et seulement sur le final.
J'ai balayé **1600 séances générées** — 8 variantes (base, `intense`, `useMe`, `quickie`,
`encoreChainIndex: 2`, humiliation 0, humiliation 60, sans aucun unlock) × 8 niveaux × 25 seeds :
**zéro step `hold` ancré ailleurs que sur le final**. Le périmètre ne fuit pas par la mini-vague,
ni par le pré-finisher, ni par les boosts, ni par les modes de séance.

**[mesuré]** Aucun des 20 fichiers de `assets/sessions/` ne porte la clé `anchor` (grep sur tout
`assets/`). Les trois sites qui reconstruisent un `SessionStep` champ à champ — rebase après beg
insistant, `buildPostChallengeRegenSession`, décalage post-défi — recopient `anchor` **et** `ratio` :
un final ancré le reste après ces chemins, et reste donc désarmé, ce qui est cohérent.

**[mesuré]** La contre-vérification demandée (« qu'une tenue à micro-mouvement ne se fasse pas
rappeler à l'ordre ») est verte : `CameraMotionDetector` n'a qu'un seul consommateur en séance,
`HoldVerifier`. Aucun autre mécanisme ne sanctionne un mouvement pendant une tenue.

**[mesuré] Ce que le désarmement coûte, en revanche, est plus large que ce que le rapport laisse
entendre.** Sur 542 finals `hold` ancrés générés (humiliation 0 à 80, niveaux 10 à 30), la durée
du final va de **10 s à 37 s**, médiane 16 s ; à humiliation 400 elle vaut 80 s. Les quatre
allers-retours occupent 8 s. Le reste — de **2 s à 72 s** de tenue à `full` — n'est plus vérifié
du tout. Et ce n'est pas un cas de bord : dans l'échantillon, **au-dessus du niveau 10, 100 % des
séances ont un final `hold` ancré**. La caméra cesse donc de vérifier le plus long hold de la
séance, à la position la plus profonde, dans toutes les séances des joueuses au-dessus du plancher.

**[document]** Le rapport de l'auteur qualifie cela de « limite assumée » et de « portion statique
après les 4 swings » — la formulation minimise : ce n'est pas une portion, c'est la tenue entière,
et elle est systématique.

## Piste 2 — les axes `hold.throat.streak` et `hold.full.streak`

**[mesuré]** `_ConfigState.heldPos` ne lit que `mode`, `to` et `from` — jamais `bpm`. Le test ajouté
dans `capability_tracker_test.dart` **casse quand on neutralise la règle** : en faisant reconnaître
un hold seulement quand `bpm == null`, il rougit sur `Expected: <20.0> / Actual: <null>`, ce qui est
exactement l'assertion `holdFullStreak`. **Aucun autre test de la suite ne rougit sous cette
mutation** — ce test neuf est le seul filet sur cet axe.

**[mesuré]** Les autres lecteurs de `bpm` dans le tracker sont tous gardés en amont par
`mode == rhythm`, par `isCrossingPattern` (qui exige rhythm ou lick) ou par `isBiffle`. Le
`bpm: 60` neuf que porte un final `hold` ne contamine donc aucun axe BPM.

**[mesuré]** Il ne se voit pas non plus à l'écran : `ModeBadgeRow` n'affiche le badge BPM que pour
rhythm, lick, hand et biffle ; `MovementAnimation._durationFor` rend 1800 ms fixes pour un hold quel
que soit le BPM, et `didUpdateWidget` ne relance le contrôleur sur un changement de tempo que pour
les modes calés sur le beat.

## Piste 3 — les deux tests « réalignés »

**[mesuré]** Aucune assertion n'a été supprimée ni affaiblie sans contrepartie.

`session_step_anchor_replay_test.dart` remplace un littéral `expect(s.ratio, 3)` par un ratio choisi
d'après le mode du step. L'assertion reste, elle se précise : elle affirmait « tout step ancré porte
le ratio rythmé », ce qui n'était vrai que tant que seul rhythm s'ancrait.

`career_rhythm_anchor_placement_test.dart` ajoute un `continue` qui sort le final `hold` éligible du
contrôle « les modes non rythmés ne sont jamais ancrés ». C'est le seul moyen de garder le test, et
ce qu'il cesse de couvrir est repris ailleurs : **[mesuré]** neutraliser la branche `hold` de
`_draftToStep` fait rougir `career_hold_final_anchor_placement_test` sur
`Expected: BeatAnchor:<BeatAnchor.to> / Actual: BeatAnchor:<BeatAnchor.none>`.

## Piste 4 — le compte de swings, et ce qu'aucun test ne tient

**[mesuré]** La séquence pure rend bien 8 beats — 4 allers-retours — et passer la constante de 4 à 3
fait rougir le test qui exerce la valeur de production (`Expected: <8> / Actual: <6>`).

**[mesuré] Mais trois mutations restent vertes sur les 1055 tests.** Chacune casse quelque chose que
le rapport présente comme acquis :

1. Neutraliser la bascule elle-même dans `applyStep` (`if (false && _anchor == BeatAnchor.to …)`,
   donc le final ancré ne joue plus jamais d'aller-retour) : **1055 verts**. Aucun test ne relie un
   step ancré au swing réellement joué — `beep_engine_hold_swing_test` interroge une fonction pure
   exposée pour le test, que rien n'oblige à être appelée.
2. Remplacer l'appel à `shouldArmHoldVerifier` par le code d'avant
   (`if ((step.mode ?? session.defaultMode) != SessionMode.hold) return;`) : **1055 verts**. La règle
   du désarmement est testée, son branchement ne l'est pas — et c'est ce branchement qui décide si la
   caméra rappelle à l'ordre pendant des allers-retours que l'app vient d'ordonner.
3. Mettre `holdFinalAnchorRatio` à 2 et `holdFinalAnchorBpm` à 137 : **1055 verts**. Les assertions
   du générateur se comparent à la constante elle-même, et le test du moteur passe 9 et 60 à la main.
   Rien ne relie donc l'illustration montrée à Manu (9:1 à 60 bpm ⇒ 1800 ms / 200 ms) au geste que
   le final joue réellement.

**[déduit]** Le motif est le même trois fois : ce qui est testé, ce sont des fonctions pures ; ce qui
les relie à la production ne l'est pas. C'est le sixième cas de ce chantier où un test passe aussi
bien avec le défaut que sans.

**[mesuré]** Deux autres faits sur le compte de 4, à signaler sans les trancher :
- Sur un final de 10 s — 74 des 542 finals mesurés durent moins de 12 s — les 8 s de swings ne
  laissent que **2 s** de tenue immobile. « Ensuite on reste sur le hold normal » vaut alors deux
  secondes. Le compte est absolu, il ne s'adapte pas à la durée du final.
- Après un FAIL en plein final, `_restorePreviousLoop` rejoue `applyStep` sur le même step et
  relance **4 nouveaux allers-retours**. Le compte est par application de step, pas par final.

**[mesuré]** À l'inverse, rien ne déborde : `_stopLoop` incrémente `_loopGen` avant chaque nouveau
step, donc un final tronqué par le step suivant n'y laisse aucun Timer.

## Piste 5 — la seconde position

**[mesuré]** `to.index - 1` sous le gate `to.index > 0` ne sort jamais des bornes de l'énumération.
Sur les 1400 séances balayées, la position du final `hold` est `full` dans 100 % des cas, et les
variantes finales de `HoldRules` sont tip, head, mid, throat et full — `balls` n'y figure pas.

**[déduit]** Un hold `to: balls` venu d'ailleurs — un JSON qui porterait la clé `anchor`, que
`SessionStep.fromJson` sait lire — ferait balancer entre `balls` et `full`, deux positions qui ne
sont pas un cran de profondeur l'une de l'autre. Inatteignable aujourd'hui.

## Piste 6 — la bande morte des niveaux 3-4

**[mesuré]** Le final ancré réutilise le plancher de l'étape 3, qui vaut 10. Aux niveaux 3 et 4,
respectivement 26 et 34 séances sur 40 portent au moins une ancre, contre 40 sur 40 aux niveaux
1, 2, 8 et 9. Le final ancré n'apparaît jamais sous le niveau 10 : **il ne comble pas la bande
morte, et il ne la subit pas non plus** — elle lui est simplement antérieure.

## Piste 7 — compatibilité et invariants

**[mesuré]** `session_step_anchor_compat_test` lit les 20 fichiers de `assets/sessions/` et les
37 paliers de `milestones.json` et vérifie `anchor == none` / `ratio == 1` : vert. L'étape 4 ne
touche ni le loader, ni le défaut du constructeur, ni aucune clé persistée.

**[mesuré]** L'invariant `2T` du cycle est vérifié pour la nouvelle séquence par un test dédié qui
balaie les ratios 2, 3, 9 et 20.

## Ce que je n'ai pas pu établir

- **Rien n'a sonné** (consigne du projet). La force de l'aimant, l'amplitude d'un cran, 3 ou 4
  allers-retours : ce sont des jugements de Manu, je ne les touche pas.
- **Le swing joué pour de vrai.** Aucun harnais du projet ne pilote `applyStep` avec ses Timers et
  ses gaps ; je n'ai pu établir le comportement que par lecture de code et par la séquence pure.
  C'est précisément ce que la mutation 1 ci-dessus rend visible.
- **Ce que le désarmement caméra coûte en usage réel** : je n'ai pas mesuré à quelle fréquence la
  caméra est effectivement active en séance. Sans elle, le désarmement ne change rien ; avec elle,
  il vaut sur toute la durée du final.
- **Le comportement pause/reprise en plein swing**, que l'auteur signale déjà : je n'ai pas non plus
  trouvé de harnais qui pilote `pause()` sur ce chemin.

## Les réserves

**Gênantes.**

1. **Trois points de jonction ne sont tenus par aucun test** (mutations 1, 2 et 3 de la piste 4).
   Le final peut cesser de swinguer, la caméra peut se remettre à sanctionner les allers-retours,
   les valeurs peuvent dériver — les 1055 tests restent verts. Ce n'est pas un défaut de
   comportement aujourd'hui : c'est l'absence de ce qui empêcherait demain d'y revenir sans le voir.
2. **Le désarmement caméra porte sur tout le final, pas sur ses 8 premières secondes**, dans 100 %
   des séances au-dessus du niveau 10, sur 10 à 80 s de tenue à `full`. Le rapport le mentionne
   comme une limite ; il n'en donne ni l'étendue ni la fréquence, qui changent la nature de la
   question posée à Manu.

**Non gênante.**

3. **Sur un final court, il ne reste que 2 s de tenue immobile** après les swings. Le fait est
   mesuré, la décision appartient à Manu — et le rapport de l'auteur ne pose pas la question.

## Questions ouvertes, pour Manu — je ne les tranche pas

1. Sur un final de 10 s, les allers-retours occupent 8 s et il reste 2 s de tenue. Faut-il que le
   compte s'adapte à la durée du final, ou que ces finals-là ne s'ancrent pas ?
2. La caméra ne vérifie plus rien pendant tout le final ancré. Réarmement après les swings, ou on
   accepte que l'explosion ne soit pas vérifiée ?
3. Après un FAIL en plein final, la tenue repart pour 4 allers-retours. Voulu, ou faut-il qu'elle
   reprenne immobile ?

## Hors périmètre, fiché au sas

`awaitReady` n'est recopié par aucune des trois reconstructions champ à champ de `SessionStep`
(rebase beg insistant, regen post-défi, décalage post-défi), alors que `anchor` et `ratio` le sont.
Défaut préexistant, sans rapport avec l'étape 4 : fiche déposée dans
`~/.claude/orchestration/sas/tss2/`.
