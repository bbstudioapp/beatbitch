---
type: analyse
sujet: correctif-tss2-031-et-tss2-030-la-sortie-d-un-fail-en-arriere-plan-attend-le-bouton-l-ecran-lit-le-cycle-de-vie-au-montage
ecrit_le: 2026-10-17T19:48:15+02:00
auteur: session tss2-arriere-plan-2 · claude-sonnet-5-5
revision: a0587b9
branche: fix/arriere-plan-punition-enchainement
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_arriere_plan_demarrage_test.dart
  - rhythm_coach/test/session_music_controller_test.dart
provenance:
  mesure: 11
  deduit: 4
  document: 10
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:966
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:142
  - rhythm_coach/lib/screens/session_screen.dart:292
---

## Constat

[document] tss2-031 : appli en arrière-plan pendant un fail ou une mini-punition, `pause()` sort (`_failActive`) et la sortie du flow repasse en `running` sans lire l'état d'arrière-plan : horloge, ticker, steps et bips repartent seuls. tss2-030 : un `SessionScreen` monté alors que l'appli est déjà en arrière-plan part avec `appInBackground` faux, aucun événement ne le corrige, `autoStart` lance la séance.

## Règle appliquée

[document] Décision de l'orchestrateur sous mandat (Manu a validé l'objectif « rien ne repart seul », pas le détail), dans le prolongement du mécanisme `onAppBackgrounded` / `onAppForegrounded` de tss2-027, sans second mécanisme.
- tss2-031 : à la sortie du flow, si l'appli est hors de l'avant-plan, la séance arrive en `paused` ; le saut de section, la restauration de la boucle, l'horloge, le ticker et le premier `_checkSteps` sont différés jusqu'au bouton de reprise existant, qui les rejoue tels quels. Le déroulé de la punition pendant l'absence n'est pas touché.
- tss2-030 : l'écran relaie au montage le cycle de vie courant, avec le même aiguillage que pour les événements.
- La garde est l'état `_appInBackground`, pas un nom de méthode ; premier plan inchangé.

## Reproduction (rouge avant correctif)

[mesuré] Banc `test/session_arriere_plan_demarrage_test.dart` étendu (vrai `SessionScreen`, vrai contrôleur, cycle de vie par `handleAppLifecycleStateChanged`, attentes en temps réel car le `Stopwatch` du contrôleur n'est pas simulé), rejoué sur un worktree jetable à `e6f8b5d` : 7 rouges, 3 témoins verts (mini-punition au premier plan, fail complet au premier plan avec saut de section, écran monté après le retour). Chaque test agrège ce qui a bougé depuis le repère (état, `applyStep`, horloge, écritures `stats.*`, voix / ambiance / bips non coupés), donc un seul message nomme toutes les fuites.
- Mini-punition : `Expected: empty / Actual: ['état finished au lieu de paused', 'applyStep ×1', 'horloge 0:00:01.34 → 0:00:03.20', 'profil écrit : [stats.total_seconds, stats.sessions_completed, …]', 'voix non coupée', 'ambiance non coupée', 'bips non coupés']`.
- Fail complet (phrase, respiration, punition, saut à la section de t=6) : mêmes fuites, horloge `0:00:00.66 → 0:00:07.08`.
- Départ pendant la restauration de la boucle (`applyStep` tenu par une porte) : état, horloge, profil et coupures, sans `applyStep` (la restauration précède le repère).
- tss2-030 : `['état finished au lieu de paused', 'applyStep ×1', 'horloge 0:00:00.000000 → 0:00:03.09', 'profil écrit : [stats.modes_used_mask, stats.total_seconds, stats.sessions_completed, …]']`.
- Les deux tests de sortie périmée tombent sur leur précondition (`Expected: paused / Actual: running`, « le banc n'a pas amené la séance en pause ») : ils ne sont prouvés que par mutation.

[mesuré] Ce qui se passe pendant l'absence, non modifié : la respiration puis la punition se déroulent jusqu'au bout appli en arrière-plan (le banc atteint la phase `punishment` après les trois événements `inactive`, `hidden`, `paused`) ; `pause()` y sort toujours.

## Correctif (`34503fe`, tests `c27fa7d` et `e7ab84f`, commentaires `d6c2816`)

[document] `session_controller_fail_flow.dart:142` `_leaveFailFlow(mayJump)` remplace les deux sorties (`triggerFail` : saut possible ; `_runMiniPunishmentFlow` : non). Appli hors de l'avant-plan : `_deferredFailExit` retient `_completeFailExit(mayJump)` et `_pauseAfterFail()` coupe voix, bips et ambiance puis pose `paused`. `_completeFailExit` (l. 151) est l'ancienne sortie ; elle relit `_appInBackground` après la restauration de la boucle, car `pause()` ignorait l'événement tant que `_failActive` était vrai (course sur l'`await` de `applyStep`).
[document] `session_controller.dart:966` `resume()` rejoue la sortie retenue avant son chemin ordinaire ; `:798` `start()` l'abandonne à la remise à zéro. `pause()` n'est pas modifié. Un nettoyage équivalent dans `stop()` a été retiré : sa mutation restait verte, le nouveau départ couvre déjà ce cas.
[document] `session_screen.dart:221` et `:292` `_relayLifecycle(WidgetsBinding.instance.lifecycleState)` à l'`initState`, même aiguillage que `didChangeAppLifecycleState` ; `null` et `detached` ne font rien. Un `start()` sur un contrôleur déjà marqué arrière-plan finit en `paused` par le mécanisme de tss2-027.

## Fenêtre du rejeu (relecture adverse, R1) — `cbce790`, `c81d564`, `a0587b9`

[mesuré] Constat de la relecture reproduit au banc (`rejeu de la sortie différée`, 3 tests rouges sur le code de `34503fe`) : `resume()` rejouait la sortie retenue après le `finally` du flow, donc sans `_failActive` ni contrôle de génération. Pendant les `await` de `_restorePreviousLoop`, un nouveau fail démarrait (`failPhase` = `breath` au lieu de `null`), `pause()` était acceptée (`paused` au lieu de `running`), `stop()` était annulé par la fin du rejeu (`running` au lieu de `idle`, « la fin du rejeu a relancé une séance arrêtée »). Mon premier rapport ne disait rien de cette fenêtre.
[document] `session_controller_fail_flow.dart` `_replayDeferredFailExit` : `resume()` réarme `_failActive` et une génération neuve (`++_failGen`) avant de rejouer la sortie, puis les relâche au `finally` si la génération est encore la sienne. `_leaveFailFlow` et `_completeFailExit` portent la génération ; `_completeFailExit` sort après la restauration quand `_isFailFlowAlive(gen)` est faux (`stop()`, `dispose()`). Même garde que la sortie au premier plan : `isFailFlowActive` vrai (boutons désactivés), `canTriggerFail` faux, `pause()` ignorée. La garde porte sur l'état, pas sur un nom de méthode.
[mesuré] Mutations, une à la fois, copie et `cmp` : `_failActive` non réarmé → 2 rouges (nouveau fail, `pause()`) ; contrôle de génération retiré après la restauration → 1 rouge (`stop()`).
[mesuré] R3 : le banc de la mini-punition différée joue sur `_jumpSession` (section à t=6) ; la mutation `mayJump: true` sur `_runMiniPunishmentFlow` rougit 4 tests, dont « le bouton rejoue la boucle d'avant la punition » et le témoin au premier plan (`_sectionStep` appliqué au lieu de `_step0`).
[document] R6 : `a0587b9` rétablit « (`onFail` est idempotent) » sur le double appel `_capabilityTracker?.onFail()`.

## Chemins vérifiés sans correctif

[mesuré] `_triggerMusicalFail` ne pose pas `_failActive` et laisse l'état en `running` : `pause()` s'applique. Test permanent `e7ab84f` (fail musical, arrière-plan, position du morceau poussée au-delà du souffle, retour) : la séance reste en pause, le souffle ne se termine pas, aucun `applyStep`, aucun `play` ; la suppression de `unawaited(pause())` dans `onAppBackgrounded` le rougit.
[mesuré] Défi : sonde jetable (supprimée), défi armé en phase `breath`, arrière-plan 3 s puis retour : état `paused`, phase, steps et horloge inchangés, puis `resume()` repart. [document] La sortie d'un défi est portée par `_updateChallengePhase` sous le ticker, que `pause()` annule ; `_finalizeChallengeAcquittals` ne rappelle `onPostChallengeRegen` que si l'état est `running`. Pas de test permanent sur ce chemin.

## Mutations

[mesuré] Chaque garde retirée seule, restauration par copie, `cmp` identique :
- sortie sans lecture de l'arrière-plan → 3 rouges (mini-punition ×2, fail complet) ; relecture après restauration retirée → 1 rouge (départ pendant la restauration) ;
- `resume()` ne rejoue pas la sortie → 2 rouges ; saut perdu au report (`mayJump` faux) → 1 rouge ; `start()` n'abandonne pas → 2 rouges ;
- `_pauseAfterFail` sans voix, sans bips, ou sans ambiance → 3 rouges chacune ;
- écran sans lecture du cycle de vie au montage → 1 rouge ; `unawaited(pause())` retiré → le témoin musical rougit.
[mesuré] Un premier lot lancé en parallèle par erreur (deux lanceurs sur les mêmes fichiers) a été jeté et refait un lanceur à la fois ; fichiers revérifiés égaux à `HEAD`.

## Vérifications finales

[mesuré] `flutter analyze` : No issues found ; `dart format --set-exit-if-changed .` : 0 ; suite complète : 1427 tests verts (1416 avant, 10 au banc d'arrière-plan, 1 musical).
[mesuré] Commit « commentaires seulement » `d6c2816` (`session_controller_fail_flow.dart`, plus la docstring du champ ajouté dans `session_controller.dart`) : code hors commentaires identique avant/après sur les deux fichiers (comparé après retrait des commentaires, 404 et 1372 lignes de code). Aucune référence de ticket ni de date trouvée dans les trois fichiers touchés.

## Reste ouvert

- [déduit] tss2-030 sur téléphone : en arrière-plan aucune frame ne se produit, l'écran poussé par l'enchaînement ne se construit probablement qu'au retour ; son `lifecycleState` serait alors déjà `resumed` et la séance enchaînée partirait seule au premier plan, sans que le correctif y change quoi que ce soit. Le correctif ne ferme que le cas d'un écran réellement monté hors de l'avant-plan (banc, autres plateformes). À trancher par Manu.
- [déduit] `inactive` compte comme arrière-plan, comme pour la pause existante : une joueuse qui tire le volet de notifications pendant une punition arrive en pause à sa sortie.
- [document] Hors mandat, inchangés : le déroulé de la punition en arrière-plan, le texte d'introduction toujours lu en arrière-plan, tss2-022, le volet de notifications qui relance le décompte, `music.pause()` du chemin en pause.

- [déduit] `dispose()` pendant le rejeu n'a pas de test propre : il passe par la même garde que `stop()` (`_failActive` retombe, la génération n'est plus vivante). Un fond re-saisi pendant le rejeu mène à `_pauseAfterFail`, dont les `await` ne sont pas gardés contre un `stop()` en vol ; la sortie au premier plan a la même limite.
- [document] R2 et R4 de la relecture (tss2-030 sur appareil, `inactive` au montage), tss2-022 et le volet de notifications : hors mandat de cette finition, inchangés.

## Ce que je n'ai pas pu établir

[déduit] Que les timers Dart tournent en arrière-plan sur le S21 (condition de la gravité de tss2-031) ; la valeur de `lifecycleState` à la construction d'un écran poussé pendant l'absence ; que `AmbienceEngine.playForMode` relance bien une ambiance mise en pause par `_pauseAfterFail` (faux moteurs au banc) ; que le vrai `BeepEngine` repart proprement sur `applyStep` après `stop()` puis `pause()`. Rien joué sur téléphone, aucun son entendu, aucune compilation Android.
