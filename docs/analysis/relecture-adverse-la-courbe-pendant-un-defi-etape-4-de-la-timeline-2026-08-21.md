---
type: analyse
sujet: relecture-adverse-la-courbe-pendant-un-defi-etape-4-de-la-timeline
ecrit_le: 2026-08-21T22:58:26+02:00
auteur: session tss2-relecture-etape4 · claude-sonnet-5
revision: 67aa2c3
branche: fix/courbe-continuite-visuelle
porte_sur:
  - docs/analysis/la-courbe-pendant-un-defi-etape-4-de-la-timeline-2026-08-21.md
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/challenge_timeline_forecast_test.dart
provenance:
  mesure: 11
  deduit: 3
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1556
  - rhythm_coach/lib/controllers/session_controller.dart:937
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:1004
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:51
  - rhythm_coach/lib/widgets/movement_animation.dart:1052
  - rhythm_coach/lib/widgets/movement_animation.dart:289
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart:54
---

Consigne reçue : réfuter la thèse de l'auteur (`claude-opus-5`) — « le défaut est mort, corrigé en amont par `a02694e` ; ce travail n'est qu'un garde-fou ». Périmètre : trois commits — `38b814e` · `6bac1be` · `5f30d62` — un seul fichier de code, `rhythm_coach/test/challenge_timeline_forecast_test.dart`. Relecture unique (§15.1) : aucune ligne de production dans le diff `52893b5..HEAD` [document — vérifié aussi moi-même, `git diff 52893b5..67aa2c3 -- ':!*test*' ':!docs'` ne touche que des fichiers de l'étape 6 en cours à côté, jamais les miens].

## 1. Le défaut est-il vraiment mort ?

Chemins explorés au-delà de celui que le test couvre (armement → live → atSeuil) :

- **Sortie du défi (bascule vers le breath de récup)** : `_completeChallenge` pose `_challengePhase = ChallengePhase.ended` puis appelle `_startPostChallengeBreath()` (qui arme `_inPostChallengeBreath`) **avant** le seul `_notify()` de la fonction (`session_controller_challenge.dart:735-846`) [déduit]. Aucun `notifyListeners` n'expose donc un état intermédiaire où `isChallengeActive` serait déjà faux et `_inPostChallengeBreath` pas encore vrai — la bascule est atomique du point de vue de l'UI. Je n'ai pas pu construire de scénario où cette fenêtre fuit.
- **Attente de posture (`awaitingPostureReady`)** : mécanisme indépendant des défis, mais gelé par le même booléen `isTimelineFrozen` et donc protégé par le même ternaire unique dans `session_screen.dart`. Ce chemin n'est **pas exercé** par ce test (qui ne joue qu'un défi), seulement par construction du booléen partagé. Je n'ai pas pu établir qu'il est *testé* — seulement qu'il est protégé par la même expression.
- **FAIL pendant le défi** : `triggerFail()` est un no-op tant que `isChallengeActive` (`session_controller_fail_flow.dart:51`) [mesuré]. Le « je peux pas » du défi lui-même (relâchement pendant `live`/`countdown`) route vers `ChallengeOutcome.fail` puis vers **le même** `_completeChallenge` que le succès — pas de sortie parallèle qui contournerait l'excision/le gel. Je n'ai pas trouvé de deuxième chemin de sortie.
- **Défi interrompu par `stop()`** : `stop()` réécrit `_challengePhase = ChallengePhase.none` directement (`session_controller.dart:1290`) [mesuré] — la séance se termine, l'écran est démonté ; pas un cas où une courbe fausse resterait affichée.
- **Un 4ᵉ chemin de gel non couvert par `isTimelineFrozen`, cherché puis réfuté** : le `getter` lui-même documente une omission (`session_controller.dart:934-936`) — le report TTS de `_checkSteps` (un step à texte différé jusqu'à `_maxTtsDeferTicks = 25` ticks, soit 5 s, tant que `_tts.isSpeaking`, ligne 1556) décrémente aussi `_timelineOffset` **sans** passer par `isTimelineFrozen`. Hypothèse testée par lecture : si le step différé est `breath`/`biffle`/`freestyle`, le même mécanisme pourrait-il reproduire « collée en haut » ? **Réfutée** : `resolveUpcomingMovementSteps` exclut tout step dont `step.time <= afterSecond` (`movement_trajectory_forecast.dart:54`). Le défi gèle *avant* que l'horloge atteigne l'heure du step trigger (`time > afterSecond` reste vrai, d'où le step visible tout du long) ; le report TTS gèle *au moment même* où `time <= afterSecond` devient vrai (c'est sa condition de déclenchement) — le step différé n'entre donc jamais dans `upcomingSteps`. [déduit]. Je n'ai pas écrit de scénario exécuté pour confirmer ce point précis — voir « Ce que je n'ai pas pu établir ».

## 2. Le test est-il rouge pour la bonne raison ?

Les trois mutations annoncées, rejouées une à une sur `HEAD=5f30d62`, chacune restaurée avant la suivante :

| mutation | fichier:ligne | résultat |
|---|---|---|
| `isTimelineFrozen` amputé de `isChallengeActive` | `session_controller.dart:937` | rouge sur *« l'horloge de séance est gelée dès l'armement »* [mesuré] |
| excision sans `s.rebased(s.time - shift)` | `session_controller_challenge.dart:1004` | rouge sur *« les survivants ont reculé de 18 s »* — `Expected: [3, 33]`, `Actual: [21, 51]` [mesuré] |
| `breath` sorti du groupe `tip/tip` de `_ladderPositionsFor` | `movement_animation.dart:289` | rouge sur *« et y reste — la courbe collée en haut pendant le défi »* [mesuré] |

Les trois tombent exactement sur l'assertion que l'auteur annonce, aucune sur une autre. Relecture des 8 `expect()` restants du test : je n'ai pas trouvé de deuxième assertion non discriminante du genre `contains(tip)` — celle-là a déjà été remplacée par `6bac1be` (`skipWhile` + `everyElement`, contre l'ancienne paire `contains` + `.last == tip` qui ne prouvait pas la persistance).

## 3. La limite annoncée est-elle la seule ?

L'auteur signale que le test resterait vert si le ternaire `ctrl.isTimelineFrozen ? const [] : …` de `session_screen.dart` disparaissait. Vérifié **par lecture**, pas par mutation : le fichier de test n'importe pas `screens/session_screen.dart` (liste d'imports complète, lignes 17-35) [mesuré] — structurellement, aucune mutation de ce fichier ne peut faire échouer ce test. Je n'ai **pas** rejoué cette mutation en pratique : `session_screen.dart` est actuellement sous édition active de l'autre session (`git status` le montrait modifié, non commité, au moment de ma relecture — commité depuis dans `67aa2c3`, étape 6), et l'éditer même transitoirement présentait un risque de collision que j'ai choisi de ne pas prendre. Ce que je n'ai donc **pas pu établir** : que le test échoue réellement dans ce cas, seulement qu'il ne peut structurellement pas y réagir.

Un deuxième morceau non gardé, que l'auteur ne mentionne pas : ce test n'est pas un `testWidgets` — aucun `MovementAnimation` ni `SessionScreen` n'est jamais monté. Le mécanisme de mémoïsation qui décide si le ladder recalcule sa géométrie (`_sameGeometry` / `_sameUpcomingSteps`, `movement_animation.dart:1036-1066`) n'est donc jamais exercé par ce test — les valeurs `duringChallenge`/`const []` sont passées directement à `computeFutureBeatsForTest`, en cour-circuitant tout `didUpdateWidget`. `_sameUpcomingSteps` compare la longueur des deux listes en premier (ligne 1052) : la transition `[]` ↔ liste réelle est donc triviale à détecter comme « différente » et déclenche bien un recalcul [déduit]. Je n'ai pas trouvé de défaut là, mais c'est une portion réelle du chemin que ce test ne garde pas.

## 4. Les chiffres du rapport

La ligne `[3, 33]` du tableau des `startSecond` après excision est déjà vérifiée en pratique par la mutation 2 ci-dessus (rouge exactement sur ce point si on la casse) [mesuré].

Le tableau « La mesure » (`3.00 · 3.00 · 0.00 · 0.00 · 0.00` / `3.00 · 3.00 · 3.00 · 3.00`) n'est vérifié par le test qu'indirectement (via `everyElement`), pas comme une séquence exacte : je l'ai rejoué en instrumentant temporairement le test d'un `print()` juste avant les assertions, exécuté une fois, puis retiré (aucune trace dans le diff final — `git diff` sur le fichier est vide après restauration). Sortie obtenue : `lying=[3.0, 3.0, 0.0, 0.0, 0.0]`, `applied=[3.0, 3.0, 3.0, 3.0]` — identique au bit près à la table du rapport [mesuré].

## Vérifications d'environnement

Contre `HEAD=5f30d62` (avant que l'autre session committe `67aa2c3`, étape 6, qui ne touche aucun de mes fichiers) :
- `flutter pub get` : OK.
- `flutter analyze` : *No issues found!* [mesuré]
- `flutter test test/challenge_timeline_forecast_test.dart` : vert en baseline et après chaque restauration de mutation [mesuré].
- `flutter test` (suite complète) : **1085 tests, `All tests passed!`** [mesuré] — même chiffre que celui mesuré par l'orchestrateur sur `HEAD` avant mon lancement. Note : cette exécution partage l'arborescence de travail avec l'autre session ; un fichier de test à elle (`movement_trajectory_dots_visibility_test.dart`) était encore non commité à ce moment et n'a pas été repris par ce run (0 occurrence dans le log) — sans incidence sur le compte, qui correspond exactement au commité.

## Ce que je n'ai pas pu établir

- Que le test échouerait effectivement si le ternaire `ctrl.isTimelineFrozen ? const [] : …` de `session_screen.dart` disparaissait — je l'ai déduit de l'absence d'import de ce fichier dans le test, sans rejouer la mutation (fichier sous édition active de l'autre session au moment de la relecture).
- Qu'aucun autre chemin que les quatre explorés (récup, posture, sortie, FAIL, report TTS) ne peut geler la timeline sans passer par `isTimelineFrozen` — je n'ai cherché que ceux listés par la consigne plus un que j'ai trouvé moi-même (report TTS), pas balayé tous les appelants de `_timelineOffset`.
- Que le mécanisme de mémoïsation du ladder (`_sameGeometry`) se comporte correctement sur la transition réelle `[] ↔ upcomingSteps` en usage — vérifié par lecture du code (comparaison de longueur en premier), jamais par un test exécuté qui monte le widget.
- Que le report TTS de `_checkSteps` (4ᵉ chemin de gel, non couvert par `isTimelineFrozen`) ne peut vraiment jamais reproduire le symptôme — réfuté par lecture du garde `step.time <= afterSecond`, jamais prouvé en exécutant un scénario construit pour ce cas précis.

## Verdict

**Publiable.** La thèse de l'auteur tient à l'examen adverse : je n'ai trouvé aucun chemin où le défaut visé (courbe collée en haut pendant un défi) survit encore, y compris en cherchant activement au-delà du défi lui-même (récup, posture, sortie, fail, un 4ᵉ mécanisme de gel non documenté par `isTimelineFrozen`) — ce dernier a été réfuté par lecture, pas par exécution. Les trois mutations tombent sur la bonne assertion, sans assertion non discriminante résiduelle. Les chiffres du rapport sont exacts.

**Réserves** (aucune ne remet en cause le verdict, toutes documentent une limite que je n'ai pas pu combler dans ce périmètre) :
- la disparition du ternaire de `session_screen.dart` n'a été vérifiée que par lecture des imports, pas par mutation réelle — fichier sous édition active de l'autre session au moment de la relecture ;
- ce test ne monte aucun widget réel : la chaîne de mémoïsation du ladder (`_sameGeometry`) reste non exercée par lui, même si elle paraît correcte à la lecture ;
- le report TTS de `_checkSteps` gèle aussi la timeline sans passer par `isTimelineFrozen` — piste de résurgence cherchée et réfutée par lecture du garde `step.time <= afterSecond`, jamais prouvée par un test exécuté.
