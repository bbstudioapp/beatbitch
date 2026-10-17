# Relecture adverse — `fix/courbe-reprise-pause` @ `7a9456c` dans la fusion d'octobre (2026-10-17)

Relecteur : Fable 5.1. Branche partie de `feat/tenues-vivantes` @ `d5e2367`, 4 commits propres
(2 de code, 2 de commentaires) : `movement_animation.dart`, `session_screen.dart`, 2 tests. Relue telle
qu'elle est dans la fusion (HEAD `6ab1e82`). Consigne : réfuter, pas valider. Aucun appareil.
Périmètre exclu sur consigne : le déraillement de la courbe **en punition**, traité ailleurs.

## Ce que la joueuse vivait

Sortie de l'app (= `pause()`), retour, relance : la courbe repartait en avance sur le son et se
« rattrapait » d'un coup (rembobinage visuel, son juste). Cause : le défilement et les frontières
épinglées (`_boundaryPins`) sont en horloge murale ; pendant la pause la frontière passait dans le passé.

## Le correctif

`MovementAnimation.paused` (= `ctrl.isPaused`, `session_screen.dart:899`). Pendant la pause :
l'horloge de séance n'est plus extrapolée, le défilement est figé (`deltaT` compté jusqu'à `_pausedAt`,
`movement_animation.dart:912`). À la reprise, `_resumeClock` (`:840`) décale `_computedAt` et toutes
les épingles de la durée de la pause.

## Ce qui a été vérifié

| Vérification | Résultat |
|---|---|
| Commits `docs(courbe)` `90eb6ba` et `docs(seance)` `7a9456c` | 0 ligne de code différente hors commentaires |
| `movement_reprise_pause_test` (3 cas, temps réel, ~1,8 s + pause chacun) + `session_pause_courbe_wiring_test` | verts |
| Câblage cycle de vie : `paused`/`inactive`/`hidden` → `_controller.pause()` (`session_screen.dart:292-296`) | présent ; le test de câblage vérifie `paused` → vrai → `resumed` → faux via `handleAppLifecycleStateChanged` |
| Cohérence avec le moteur : `BeepEngine.pause()` fige `_holdElapsedMs`, le widget fige `movesOrigin` en temps de séance | les deux lectures restent alignées après la reprise |

## Mutations (restaurées par copie)

| Id | Ligne mutée | Résultat sur `movement_reprise_pause_test` |
|---|---|---|
| M1 | `:851` — `_resumeClock()` retiré de `_recompute` | rouge (1 cas) : gardée |
| M2 | `:831` — `_pausedAt` réarmé à chaque rebuild en pause (plus de front montant) | rouge (3) : gardée |
| M11 | `:912` — `deltaT` compté jusqu'à `now` même en pause | rouge (3) : gardée |

Les trois lignes du correctif sont tenues, chacune par le bon test.

## Ce que je n'ai pas pu établir

1. **Recalcul de géométrie pendant la pause.** `_recompute` appelle `_resumeClock`, qui consomme
   `_pausedAt` (`:840-847`) alors que le widget est encore en pause. Si une géométrie change pendant
   la pause (`rowCount`, `upcomingSteps`, `frozenAt`…) ou si le `build` refait le remplissage de
   fenêtre (`:917-924`), la suite de la pause n'est plus compensée : les épingles redeviennent
   fausses de la durée restante. M1 rouge prouve qu'un tel recalcul **arrive** dans le test, et le
   test reste vert : soit il tombe au dernier frame de la pause, soit ma lecture est fausse. Je n'ai pas
   construit la sonde (pause pendant une fenêtre non remplissable) qui trancherait.
2. **À-coup de reprise.** Au premier frame après `resume()`, `extrapolatedElapsed` (plafond 250 ms,
   `:1267`) avance jusqu'au tick suivant du contrôleur : ≤ 250 ms d'avance pendant ≤ 200 ms. La
   trajectoire n'est pas recalculée sur `elapsed` seul ; seule la langue du lick (`_tongue`, `:859`)
   peut bouger. Non mesuré.
3. **Pause pendant le gap d'entrée d'un step.** Le moteur poursuit `applyStep` après le gap et sonne
   pendant la pause (préexistant, sondé, sas `tss2-022`) ; la courbe, elle, est figée : son et image
   divergent le temps de la pause. Hors périmètre.
4. Le test de reprise est en **temps réel** (Stopwatch + `runAsync`, tolérance 150 ms) : sensible à la
   charge machine. Il a tenu sur 5 lancements ici (base + 4 mutations), machine partagée avec une autre
   session.
5. Rien vu sur le S21 : fusionné dans l'essai `8fbf608`, « à juger » depuis le 06/10.

## Verdict

**Publiable avec réserves.**

- Bloquante : aucune.
- À trancher par Manu : aucune.
- Mineures : (1) à sonder ou à écarter par une lecture contraire ; (2) ; (4) test temps réel.
