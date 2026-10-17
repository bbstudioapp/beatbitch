---
type: analyse
sujet: relecture-adverse-punition-courbe
ecrit_le: 2026-10-17T10:26:15+02:00
auteur: session tss2-relecture-punition · claude-fable-5-1
revision: 96a076a
branche: fix/punition-courbe
porte_sur:
  - docs/analysis/punition-courbe-en-retard-2026-10-17.md
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/session_punishment_breath_screen_test.dart
provenance:
  mesure: 11
  deduit: 7
  document: 9
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1036
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:149
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:480
  - rhythm_coach/lib/screens/session_screen.dart:905
  - rhythm_coach/lib/widgets/movement_animation.dart:646
---

## Verdict

[mesuré] **Publiable avec réserves.** La cause annoncée tient : pendant tout le flow fail, l'écran passait à la courbe les steps de la séance lus sur une horloge arrêtée, et couper cette liste suffit à faire suivre la punition. Rejoué ici sur le code d'avant (`6ab1e82`) : rouge sur l'assertion annoncée, message « images restées en haut » à `0.00` dès 880 ms (punition) et 2046 ms (mini-punition). Vert sur HEAD à trois relances. Aucune réserve bloquante ; deux à trancher par Manu, trois mineures.

## Ce qui a été rejoué

[mesuré] Banc : `rhythm_coach/test/session_punishment_breath_screen_test.dart`, les deux cas « la courbe dessine le rythme de la punition ». Mutations posées par copie dans le worktree, restaurées par copie, `cmp` vert après chacune, `git status` propre à la fin. Le fichier `movement_animation.dart` de HEAD est identique à celui de `6ab1e82` : seul `session_screen.dart` diffère côté code, donc remettre l'écran d'origine rejoue bien le code d'avant.

| Mutation [mesuré] | Attendu | Observé |
|---|---|---|
| M1 — écran d'origine (`6ab1e82`, sans `\|\| ctrl.isFailing`) | rouge | rouge, sur `flat isEmpty` ; images à `0.00` de 880 à ~3300 ms (punition), de 2046 à ~3900 ms (mini) |
| M2 — garde réduite : `ctrl.failPhase == FailPhase.punishment` | rouge | **vert** sur les deux cas |
| M3 — liste toujours vide (`true ? const [] : …`) | rouge ailleurs | rouge sur les deux tests de câblage existants (`horsGelAnnonce` à 0 au lieu de ≥ 1 et ≥ 10) |
| M5 — écran d'origine + épingle neutralisée (`movement_animation.dart:646` retirée) | inconnu | rouge, `0.00` dès 1061 ms (punition) et 918 ms (mini) |
| E — assertion : fenêtre élargie de [1 s, 3 s] à [0, 3 s], écran d'origine | inconnu | rouge ; images restées sous `throat` avec max 2.50 (punition) et 0.42 (mini) |
| Anti-vide — `_curveWindowEndMs` 4000 → 700 | rouge « aucune image » | rouge « aucune image du rythme de punition » |

[mesuré] Déterminisme : trois lancements sur HEAD, tous verts, 21 s chacun. Les deux tests de câblage existants (`session_frozen_upcoming_steps_wiring_test`, `session_posture_freeze_upcoming_steps_wiring_test`) sont verts sur HEAD.

[mesuré] Suite complète sur HEAD : 1358 tests verts (« All tests passed! »), 1 min 40 s, aucune autre suite en cours sur la machine au lancement.

## La cause tient-elle ?

[mesuré] Oui, pour ce que le correctif traite : les steps de la séance arrivaient à la courbe pendant `failing`, avec un `elapsed` figé. M1 le montre dans les deux routes, M3 et les tests de câblage montrent que le chemin normal (hors gel) reste gardé.

[mesuré] Nuance sur le mécanisme décrit par l'auteur. Le rapport attribue le symptôme à l'épingle de frontière (`boundaryAt`, `:641-649`) qui « défile jusqu'au curseur puis passe derrière ». M5 montre que l'épingle n'est pas nécessaire au rouge : sans elle, l'horloge figée place la frontière à distance constante devant le curseur (environ 1,25 s ici : 4 s de séance moins 2,5 s de FAIL et 250 ms d'extrapolation) et tout ce qui est au-delà dessine déjà la respiration. L'épingle aggrave (elle fait reculer la frontière jusqu'au curseur, donc toute la fenêtre), elle ne fonde pas le défaut. L'ordre de grandeur « dès le début » tient dans les deux lectures.

[mesuré] Les nombres de l'auteur (rouge de 1509 à 3316 ms sur le code d'origine) ne sont pas les miens (880 ms). Même assertion, même nature : la position du premier rouge dépend du moment où la frontière franchit la fenêtre, lui-même dépendant du temps réel du banc. Pas une contradiction.

## La garde `isFailing` couvre-t-elle tout ?

[document] `isFailing` est `_state == SessionState.failing` (`session_controller.dart:1036`). `_state` passe à `failing` dans `triggerFail` (`session_controller_fail_flow.dart:149`) et dans `_runMiniPunishmentFlow` (`:480`) ; il revient à `running` à `:243` et `:496`. Entre les deux : phrase de fail, respiration d'avant-punition, punition (la chaîne de tenues `deep_hold_chain` est une punition, jouée par `_runPunishment`), mini-punition, abandon par FAIL pendant la punition (`_abandonPunishment` complète le `Completer`, le flow continue jusqu'à `:243`). Le début de la punition, la respiration, la phrase : tous sous la garde.

[document] Monte-t-elle trop tard ? L'horloge s'arrête à `:136`, l'état bascule à `:149`, après `_stopTtsBounded()` (borne `_ttsStopTimeout`, `session_controller.dart:1238`) et `_beep.pause()`. Dans cet intervalle, aucun `_notify()` : l'écran garde sa liste précédente et la courbe réutilise ses propriétés, dont l'extrapolation d'`elapsed` bornée à `_kElapsedExtrapolationCap`. Les épingles qu'elle pose alors sont au plus tôt, c'est-à-dire aux vraies frontières d'avant le FAIL. Sans effet sur l'affichage de la punition ; c'est la matière de `tss2-019` (reprise), hors périmètre.

[document] Retombe-t-elle trop tôt ? `_state = running` suit `_skipToNextSection()` ou `_restorePreviousLoop()` et `_stopwatch.start()` ; la liste est recalculée au `_notify()` du `finally`, sur le nouvel `elapsed`. `_checkSteps()` est synchrone (`void`, `session_controller.dart:1618`) : pas de fenêtre entre la bascule et la notification. La reprise elle-même (`tss2-011`, `tss2-019`) est hors périmètre et inchangée.

[document] Un `notifyListeners` manquant ? Après `:149`, le premier `_notify()` est à `:169`, sans `await` entre les deux ; la mini-punition notifie à `:483` juste après la bascule. L'écran se reconstruit sur `context.watch<SessionController>()` (`session_screen.dart:685`) : il voit l'état `failing` à la première notification.

[document] Ce que la garde ne couvre pas, et c'est voulu : le « JE PEUX PAS » d'une séance musicale (`_triggerMusicalFail`, `:268`) ne quitte jamais `running`, et `elapsed` y suit la position du morceau (`session_controller.dart:951`), qui continue : la liste reste juste. Le break scénarisé n'affiche pas `MovementAnimation` (`session_screen.dart:887`). Les défis et l'attente de posture restent sous `isTimelineFrozen`.

[déduit] « Utilise-moi » : aucun flow dédié dans les contrôleurs ; le mode est fabriqué en steps de séance par la génération carrière (`session_controller_career_hooks.dart:311-458`). Il tourne donc sur l'horloge de séance, hors de ce correctif. Non rejoué.

## Effets de bord

[document] Défis : `triggerFail` sort immédiatement pendant un défi (`session_controller_fail_flow.dart:56`) ; un défi ne se tire que sous le ticker, coupé pendant `failing`. Les deux gels ne se superposent pas.

[document] Pause pendant une punition : `pause()` sort si l'état n'est pas `running` (`session_controller.dart:1289`), y compris quand l'application passe en arrière-plan. `isFailing` tient, la punition continue, la liste reste vide.

[document] Fin de séance pendant une punition : `_finish()` n'est atteint que par `_onTick` (ticker coupé) ou `debugFinishSuccess` (refusé hors `running`/`paused`). `stop()` met `_failActive` à `false` puis `idle` : le flow s'interrompt à son prochain `_isFailFlowAlive`.

[document] Séance musicale : aucun changement, voir ci-dessus.

## Réserves

[mesuré] **À trancher par Manu — le choix A/B** du rapport de l'auteur reste entier. Le test ne verrouille pas l'option A : il vérifie que la courbe atteint au moins `throat` entre 1 et 3 s devant le curseur pendant le rythme de la punition, ce qu'une option B (annoncer les steps de la punition) satisferait aussi. Le repère d'essai sur le téléphone donné par l'auteur est cohérent avec ce que le banc mesure.

[déduit] **À trancher par Manu — la forme de la garde.** Le correctif ajoute un état à une énumération (`isTimelineFrozen || isFailing`) là où la règle réelle est « l'horloge de séance est arrêtée pendant que le moteur joue autre chose ». Le trou bouché aujourd'hui avait exactement cette forme : un état qui arrête l'horloge sans figurer dans la liste. Le prochain flow qui arrêtera `_stopwatch` sans passer par ces états rouvrira le même trou. Dériver la condition de l'horloge elle-même (le `Stopwatch` et le cas musical) fermerait la famille, au prix d'un passage par la pause à relire. Pas un défaut du correctif livré.

[mesuré] **Mineure — couverture.** M2 reste vert : le test n'échantillonne la courbe que quand `failPhase == punishment`. La phrase de fail et la respiration d'avant-punition, pourtant couvertes par le correctif et citées par l'auteur comme le moment où la frontière passe derrière le curseur, ne sont gardées par aucune assertion. Une régression qui restreindrait la garde à la phase punition passerait la suite.

[mesuré] **Mineure — netteté sur la route mini-punition.** Sur l'écran d'origine, la mini-punition n'est rouge qu'à partir de 2046 ms (M1) : les images jugées entre 800 et 2000 ms sont satisfaites par le pont de transition rythme → rythme, pas par la courbe annoncée. Le réglage `_curveSettleMs` à 800 est calé sur le pont respiration → rythme de la route `triggerFail`. Le test discrimine quand même sur les images suivantes.

[déduit] **Mineure — commentaire.** Le commentaire au-dessus de `upcomingSteps` (`session_screen.dart:902-904`) dit « sur une horloge de séance figée » ; pendant un flow fail, l'horloge est arrêtée (`_stopwatch.stop()`), pas reculée tick à tick comme sous `isTimelineFrozen`. Le mot couvre les deux ; à garder tel quel ou préciser, sans conséquence.

## Ce que je n'ai pas pu établir

[déduit] Le rendu sur le téléphone : rien n'a été branché. La phrase de fail du banc est instantanée (synthèse simulée), donc la durée réelle de la phase phrase, et ce que la courbe y dessine (moteur en pause, `paused` faux, `elapsed` figé), restent non mesurés. M2 montre que le test ne le mesure pas non plus.

[déduit] Le passage de la frontière derrière le curseur : non mesuré directement. E (max 2.50 près du curseur sur l'écran d'origine, plat au-delà) est compatible avec un pont partant du curseur suivi d'une ligne plate, pas une preuve de l'instant du franchissement.

[déduit] Les « sauts » vus par Manu, et le step de séance qui suivait son FAIL : aucune donnée nouvelle.

[déduit] Le comportement de la courbe à la reprise (`tss2-011`, `tss2-019`) : non rejoué, déjà au sas, hors périmètre de cette relecture.
