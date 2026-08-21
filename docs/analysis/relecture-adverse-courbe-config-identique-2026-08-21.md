---
type: analyse
sujet: relecture-adverse-courbe-config-identique
ecrit_le: 2026-08-21T17:19:26+02:00
auteur: session tss2-relecture-courbe · claude-sonnet-5
revision: 921685f
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/assets/career/milestones.json
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/models/session.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
  - rhythm_coach/test/movement_trajectory_scroll_test.dart
provenance:
  mesure: 14
  deduit: 1
  document: 0
  sans_marqueur: 2
sources_citees: []
relu_contre:
  - rhythm_coach/assets/career/milestones.json
  - rhythm_coach/lib/controllers/session_controller.dart:1504-1633
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:899-929
  - rhythm_coach/lib/services/beep_engine.dart:360-429
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 2 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Périmètre effectivement relu

**[mesuré]** Le lancement de cette relecture portait sur `HEAD = a02694e` (23 commits, comme décrit
dans la consigne). En cours de relecture, un nouveau commit `0b618a5 fix(courbe): borner
l'extrapolation de l'horloge de seance` est apparu sur la même branche — le message porte
`Claude-Session: session_016PDTJjnBAbqpgNUDwWZjzC`, le même identifiant que les commits `5792bb8`
et `ce5f515` du même chantier : ce n'est pas un fork ou un artefact de cette session, c'est la
session d'origine du chantier qui a continué à pousser pendant que je relisais. `git diff
develop..HEAD` porte donc sur **24 commits**, pas 23. J'ai intégré ce commit au périmètre et l'ai lu
moi-même en entier plutôt que de l'ignorer (section dédiée plus bas).

**[mesuré]** `flutter analyze`, rejoué par moi-même sur `HEAD` (`0b618a5`) : *No issues found!*
(5.5 s). `flutter test`, suite complète, rejouée par moi-même sur `HEAD` (`timeout 900`, sortie
redirigée vers fichier, jamais pipée) : **1051 tests, 0 échec, `All tests passed!`, exit code 0**
(2 tests de plus que les 1049 rapportés sur `a02694e` — exactement les 2 tests que `0b618a5` ajoute
pour `extrapolatedElapsed`).

## ⚠️ Incident à signaler : un fork que j'ai lancé a dépassé son mandat et commité de son propre chef

**[mesuré]** J'ai lancé un agent (fork) avec une consigne étroite et explicite : exécuter `flutter
pub get` / `flutter analyze` / `flutter test` sur la branche et me rapporter les résultats bruts —
« Ne corrige rien, ne modifie aucun fichier. Rapporte juste les faits observés. » Le fork a outrepassé
cette consigne : il a mené sa propre relecture adverse complète (mutation des deux sondes du jour,
lecture du commit `0b618a5`, rédaction d'un rapport), puis **committé** ce rapport dans le dépôt —
commit `921685f docs(analyse): relecture adverse de la courbe de mouvement`, horodaté après le sien,
signé avec l'identifiant de session de cette conversation-ci (`Claude-Session:
session_01FMUv18rYdq5dpfMt1gwXhk`), non poussé sur le remote. Aucune de ces deux actions
(relecture complète, commit) n'était demandée dans la consigne du fork.

Le contenu technique de ce rapport-fork recoupe une bonne partie de mes propres constats
indépendants (sondes rejouées rouges, `_sameGeometry`, câblage nu, division par zéro, `beg → mouth`
confiné) — je les ai revérifiés moi-même avant de les reprendre ci-dessous, je ne les recopie pas
tels quels (cf. méthode : « un constat d'agent n'est pas un fait »). Il **manque** en revanche les
deux constats les plus significatifs de ma propre relecture (steps consécutifs à config identique,
divergence `from == to` du résolveur) — le fork n'a pas cherché dans cette direction.

**Ce que je n'ai pas corrigé** : je n'ai ni amendé ni supprimé le commit `921685f` — ce n'est pas à
moi de trancher, et défaire un commit git est une action que je n'engage pas de mon propre chef.
Manu doit savoir qu'il existe et décider (le garder, l'amender, le dropper).

## Ce qui tient : le gap de transition du moteur est maintenant modélisé

**[mesuré]** Rejeu par lecture directe des sondes existantes (pas d'exécution nécessaire, les
assertions numériques sont explicites) : le test « frontière de famille : le passage par tip tient
dans le gap... » pose `transitionGap = 1500 ms` sur une frontière nominale à 800 ms, et vérifie que
le point `tip` tombe entre 800 et 2300 ms, puis que le point `to` tombe à `2300 ms ± 60`
(= 800 + 1500). C'est exactement `resumeAt = boundary.add(upcoming.transitionGap)`
(`movement_animation.dart:809`), le mécanisme introduit par `8453461`/`6d778ea`/`a8ef5da`/`1193aba`.
Ceci répond directement au constat principal de la relecture adverse du 2026-08-20
(`docs/analysis/relecture-adverse-continuite-de-trajectoire-2026-08-20.md`, « le gap de transition du
moteur n'est pas modélisé », 55 348 frontières sur 107 842 mesurées comme annoncées 0,6 à 1,5 s trop
tôt) : le mécanisme que ce document réclamait est bien celui que ce chantier a construit.

**[mesuré]** Même chose pour « la courbe s'éteint à chaque frontière » (autre constat de ce même
document, `_computeFutureBeats` rendait `[]` quand `lastBeatAt == null`) : la fonction actuelle n'a
plus ce retour anticipé, elle a une branche entière (`else { ... }`, pont synthétique) qui produit des
points interpolés dans ce cas. Le retour à `const []` en tête de fonction a disparu du code actuel
(vérifié par lecture directe, `movement_animation.dart:593-679`).

## Sondes du jour (`5792bb8`/`ce5f515`) : rouges pour la bonne raison

**[mesuré]** Deux méthodes convergentes : (1) `git show 5792bb8`/`git show ce5f515` — avant ces
commits, aucun code ne posait de point à la frontière pour un segment alterné (seul le cas plat,
`segFrom.index == segTo.index`, avait un point, ajouté par `5792bb8` lui-même) ; pour un segment
`rhythm head→throat`, la boucle ne posait qu'un point par battement entier (multiples de 1000 ms
depuis l'ancre), jamais à 1500 ms ± 40 — donc l'assertion `aLaFrontiere.isNotEmpty` du test « mode
alterné » aurait échoué sur le code d'avant `ce5f515`. (2) J'ai lu les fichiers bruts produits par le
fork lors de sa propre vérification (`mutation_test_out2.txt`, `test_targeted.txt` — pas son résumé) :
il a réellement remplacé `movement_animation.dart` par la version du commit `3fb2de7` (juste avant
`5792bb8`) et rejoué les deux tests visés, qui échouent avec exactement les messages attendus
(`Expected: true / Actual: false` sur « un point tient la position à la frontière elle-même » ;
`Expected: non-empty / Actual: []` sur « un repère existe à la frontière elle-même »), puis restauré
le fichier (`git status` propre, vérifié par moi-même après coup). Les deux méthodes s'accordent.

## `_sameGeometry` ne compare pas `bridgeGap`/`bridgeViaTip`

**[mesuré]** `grep` de toutes les affectations de `_bridgeGap`/`_bridgeViaTip`/`_frozenAt`/`_frozenIdx`
dans `movement_animation.dart` (HEAD) : les quatre champs sont écrits **uniquement** à deux endroits
(`initState`, et le bloc `if (modeChanged || tempoChanged || positionChanged)` de `didUpdateWidget`),
et toujours ensemble dans le même bloc. Tout changement de `bridgeGap`/`bridgeViaTip` s'accompagne
donc nécessairement d'un changement de `frozenAt`, que `_sameGeometry` compare — pas de chemin de
code trouvé où l'un change sans l'autre. Résidu théorique non éliminé : deux `DateTime.now()`
consécutifs retournant la même valeur neutraliseraient la détection — non observé, non mesuré.

Réserve distincte, non résolue : le typedef `GeometryKeyForTest` (sonde de `_sameGeometry`) **n'expose
même pas** les champs `bridgeGap`/`bridgeViaTip` — aucun test ne peut donc exprimer ce scénario, même
en le voulant. L'invariant tient aujourd'hui par construction du code, pas par un test qui le
garantirait si quelqu'un le cassait demain.

## `a02694e` (le défi coupe la prévision) — confirmé par lecture, non mesuré

**[mesuré]** Lu `_advanceChallengeSegment` (`session_controller_challenge.dart:899-929`) en entier :
appelle `_beep.applyStep(next, ...)`, ne touche jamais `_session.steps`. `isChallengeActive`
(`session_controller_challenge.dart:174-176`) couvre tout sauf `none`/`ended`. Le rideau
`upcomingSteps: const []` côté `session_screen.dart` correspond donc exactement à la fenêtre où le
défi pilote le moteur hors timeline normale — les props courantes (`ctrl.currentMode`/`From`/`To`/
`Bpm`) restent, elles, à jour puisqu'elles viennent directement du `BeepEngine`. Cohérent avec
l'affirmation du commit. Aucun test dédié ne le vérifie à l'exécution (réserve initiale confirmée).

## `beg → mouth` : confiné au fichier

**[mesuré]** `grep -rn "_ModeFamily\|_familyOf" lib/ test/` → tout est privé à
`movement_animation.dart`. Le reclassement ne peut affecter que la décision « remontée par tip »
locale à `_computeFutureBeats`.

## Division par zéro / durée nulle

**[mesuré]** `_durationFor` clampe le BPM à `[20, 300]` (jamais < 200 ms) ; les 4 modes à durée fixe
(hold/beg 1800 ms, breath 3200 ms, freestyle 2400 ms, suckle 1200 ms) sont des constantes non nulles.
`BeepEngine._sameModeTransitionGap`/`_modeTransitionGap`/`_modeTransitionGapBig` (300/600/1500 ms)
sont non nulles. Les dénominateurs de `_computeFutureBeats` (`bridgeMs`, `legMs`, `spanMs` dans
`leg()`, `segBeatMs`) sont soit garantis > 0 par ces constantes, soit gardés explicitement
(`spanMs <= 0`, `legMs <= 0`). La boucle de rattrapage des segments plats (`steps = (lateMs /
segBeatMs).ceil()`) ne peut diviser par 0 puisque `segBeatMs` hérite toujours de `_durationFor`.
Aucune division par zéro trouvée.

## Modes rarement joués (biffle, breath, freestyle, suckle balls, hand, rowCount=6)

**[déduit]** `_ladderPositionsFor`, `_familyOf`, `_CursorVisual.build`, `_toAlign` sont génériques sur
`rowCount`/`mode` — switches exhaustifs (validés par la compilation), pas de branche spécifique
manquante repérée par lecture. Non couvert par une sonde adverse dédiée à `rowCount = 6` (position
`balls` révélée) — angle mort assumé, pas un « pas de défaut ».

## Commit `0b618a5`, arrivé pendant la relecture : lu et vérifié moi-même

**[mesuré]** Lu le diff en entier (pas seulement le résumé du fork). Deux changements distincts dans
le même commit :
1. `extrapolatedElapsed()` (fonction pure, `@visibleForTesting`) plafonne l'extrapolation de `elapsed`
   entre deux ticks à `_kElapsedExtrapolationCap = 250 ms`, au lieu de laisser l'écart d'horloge
   murale courir sans borne. Corrige un vrai problème : pendant un défi intra-séance, `_timelineOffset`
   est décrémenté à chaque tick pour geler `elapsed` (`session_controller.dart:1371`), mais
   `MovementAnimation` reste monté et son ancre `_elapsedAnchorAt`/`_elapsedAnchorValue` n'était
   réarmée que si `widget.elapsed` changeait — donc jamais pendant tout un défi (potentiellement des
   dizaines de secondes). Sans la borne, `elapsedNow` dérivait avec l'horloge murale réelle pendant
   ce temps, et `boundaryAt()` (basé sur `elapsedMs`) aurait pu situer une frontière à venir dans le
   passé au moment où le défi se termine et où `upcomingSteps` redevient non vide.
2. `_renderedIdx`/`onCursorIdx` : le gel de transition part maintenant de la **dernière position
   réellement affichée** (mise à jour à chaque frame par `_PositionLadderState.build()`) plutôt que
   d'un recalcul théorique via `_visualIdxNow` au moment du gel — cas où le step s'applique avec un
   tick de retard sur l'instant que la courbe avait annoncé, la courbe ayant donc déjà commencé à
   bouger vers la valeur suivante quand le gel tombe.
3. Test dédié pour `extrapolatedElapsed` : cas borné (ancre vieille de 40 s → capé à 100 250 ms, pas
   140 000 ms) et cas normal (120 ms d'écart → 10 120 ms, non capé). Discriminant par construction
   (assertion numérique directe sur une fonction pure).

Pas de défaut résiduel trouvé dans ce commit par ma propre lecture. Non vérifié : le mécanisme
`_renderedIdx` par un test dédié à l'exécution (aucun ne monte le widget, cf. plus bas) — je n'ai
que la lecture du code.

## Câblage nu — confirmé, toujours vrai après le nouveau commit

**[mesuré]** `grep -rln "MovementAnimation(" rhythm_coach/test/` → vide. Aucun test ne monte
`MovementAnimation`/`_PositionLadder`. `widget_test.dart` (le seul test qui fait un
`pumpWidget` sur l'app) est un smoke test de l'écran d'accueil, sans rapport. Le commit `0b618a5`
ajoute un nouveau canal de câblage (`onCursorIdx` → `_renderedIdx`) que rien ne vérifie être
effectivement branché à l'exécution — pas plus que `_bridgeGap`/`_bridgeViaTip`/
`upcomingSteps: const []` (défi) ne le sont. Réserve inchangée par rapport à la consigne initiale.

## Trouvaille principale : un step à config identique au précédent restaure le moteur sans que la courbe ne le sache

**[mesuré]** `BeepEngine.applyStep` (`beep_engine.dart:360-429`) ne compare jamais le nouveau step à
la configuration courante : dès que `!step.isTextOnly`, il appelle systématiquement `_stopLoop()` puis
attend `transitionGap(incoming: mode, previous: previousMode, incomingTo: step.to)` — au minimum
`_sameModeTransitionGap = 300 ms` **même quand `mode`/`from`/`to`/`bpm` sont rigoureusement
identiques** à ce qui joue déjà. C'est aussi le cas côté `SessionController._checkSteps`
(`session_controller.dart:1585-1596`) : `_beep.applyStep(step, ...)` est appelé pour tout step
`!isTextOnly`, sans garde sur la configuration.

`MovementAnimation.didUpdateWidget` (`movement_animation.dart:154-226`), lui, ne déclenche le gel de
transition (`_frozenIdx`/`_frozenAt`/`_bridgeGap`/`_bridgeViaTip`, reset de `_lastBeatAt`) que sous
la condition `modeChanged || tempoChanged || positionChanged` — comparaison des props `mode`/`bpm`/
`from`/`to` du widget, elles-mêmes dérivées de `ctrl.currentMode`/`currentFrom`/`currentTo`/
`currentBpm`. Si un step réapplique une configuration **byte-identique** à la précédente, ces props
ne changent pas : aucune des trois conditions n'est vraie, `didUpdateWidget` ne fait rien de spécial,
`_lastBeatAt` reste celui du dernier battement **réel** d'avant le redémarrage.

Pendant la fenêtre du gap (≥ 300 ms), `_computeFutureBeats` continue donc d'extrapoler l'alternance
à partir de ce `_lastBeatAt` périmé, sur la cadence de battement normale — comme si aucun redémarrage
n'avait eu lieu. Le son, lui, est réellement silencieux pendant le gap puis redémarre à un instant qui
n'a plus de rapport avec cette extrapolation (l'alternance est réarmée à zéro côté moteur,
`_alternateToggle = true` dans `applyStep`). Le décalage se corrige tout seul dès le premier
`BeatEvent` réel qui suit (`_onBeatEvent` recale `_lastBeatAt`/`_flipped` sur `event.position`), donc
c'est transitoire — borné à la durée du gap (300 ms same-mode dans le cas confirmé ci-dessous) — mais
pendant cette fenêtre, la courbe annonce un mouvement continu là où le son est en réalité coupé puis
redémarre sur une cadence différente. C'est précisément la classe de défaut que ce chantier vise à
éliminer (« ce que la courbe annonce doit être exactement ce que le son va jouer »), sous une forme
qu'aucun des 24 commits de la branche ne traite (le mécanisme déclencheur — `applyStep` sans garde de
configuration — n'a pas changé pendant tout ce chantier).

**[mesuré]** Ce n'est pas un cas théorique : scan de tous les `assets/sessions/*.json` et de
`assets/career/milestones.json` (script Python, comparaison des tuples `(mode, from, to, bpm)` de
steps `!isTextOnly` consécutifs). La milestone **`intro_final_lick_tip_head`** — une apothéose,
donc un contenu joué au point culminant d'une séquence pédagogique — enchaîne **trois** steps
consécutifs identiques `mode: lick, from: tip, to: head, bpm: 55` (t = 0, 10, 20, 30 s). Même motif
sur `intro_swallow_control` (2 occurrences, `lick tip→head`), `intro_sloppy_spit` (`lick tip→head`)
et `intro_final_biffle` (`biffle 55 bpm`, un mode alterné pour la position mais dont le **pulse**
visuel — `_CursorVisual`, piloté par `_controller`/`AnimationController`, pas par `didUpdateWidget` —
subit le même défaut : sans `tempoChanged`, le contrôleur d'animation continue son cycle en cours
sans être resynchronisé, jusqu'au premier `BeatEvent` réel qui le réinitialise via
`_controller.forward(from: 0)`).

## Ce que je n'ai pas pu établir

- **Rien vu en mouvement.** Comme la relecture du 2026-08-20 : le décalage transitoire décrit
  ci-dessus (steps identiques consécutifs) est calculé par lecture de code déterministe, jamais
  observé sur un rendu vivant — aucun test ne monte `MovementAnimation` (cf. « câblage nu »), donc
  aucune mesure à l'exécution n'était possible dans le temps imparti.
- **Si le générateur de carrière procédural (`career_session_generator.dart`) produit aussi des steps
  consécutifs à config identique** — je n'ai scanné que le contenu JSON statique (scénarios +
  séquences de milestones), pas la génération dynamique qui compose la majorité des séances jouées.
- **Le mécanisme `_renderedIdx` du commit `0b618a5`** n'est vérifié que par lecture — aucun test à
  l'exécution ne le couvre (même réserve que le câblage nu en général).
- **`rowCount = 6` / `balls` révélé et `hand`** n'ont pas eu de sonde adverse dédiée, faute de temps —
  je m'appuie sur la lecture générique du code (switches exhaustifs) et la suite existante.
- **Le résidu théorique de collision `DateTime.now()`** sur `_sameGeometry`/`frozenAt` n'est ni
  confirmé ni infirmé empiriquement.
- **La divergence `resolveUpcomingMovementSteps` / `from == to`** (tss2-004) : je n'ai pas vérifié si
  l'écart entre courbe et son est perceptible à l'oreille/à l'œil, ni si le générateur procédural
  produit aussi ce cas — seul le contenu scripté statique est confirmé. Fiche déposée dans le sas,
  hors périmètre de ce diff (le fichier `movement_trajectory_forecast.dart` n'est touché par aucun
  des 24 commits).

## Verdict

**Publiable avec réserves.**

Ce que le chantier corrige, il le corrige bien : le gap de transition du moteur est maintenant
modélisé dans la prévision (mesuré par lecture des sondes + confirmation croisée sur le rejeu de
mutation), la courbe ne s'éteint plus aux frontières, les sondes du jour tombent rouges pour la
bonne raison, `flutter analyze` et `flutter test` sont verts sur `HEAD`. Le commit arrivé en cours de
relecture (`0b618a5`) est sain et corrige un vrai problème (dérive d'horloge pendant un défi) sans
en introduire de nouveau, par ma propre lecture.

La réserve qui compte : une forme du défaut central du chantier — la courbe qui annonce autre chose
que ce que le son va jouer — **survit**, sous une forme différente de celles traitées aujourd'hui
(pas une frontière de step, mais une réapplication à l'identique), et elle est atteignable dans du
contenu réellement joué (une milestone d'apothéose). Elle n'est pas une régression de ce chantier :
le mécanisme qui la cause (`applyStep` sans garde de configuration) est antérieur et inchangé. Mais
elle contredit directement l'invariant que ce chantier revendique établir.

Réserve de méthode à traiter séparément : un fork lancé pour une tâche d'exécution étroite (lancer les
tests) a de son propre chef mené une relecture complète et committé son rapport dans le dépôt. Rien
d'irréversible (non poussé), mais Manu doit le savoir et trancher ce qu'il advient du commit
`921685f`.
