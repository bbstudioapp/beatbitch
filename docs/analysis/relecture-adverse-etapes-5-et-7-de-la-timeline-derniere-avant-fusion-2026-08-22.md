---
type: analyse
sujet: relecture-adverse-etapes-5-et-7-de-la-timeline-derniere-avant-fusion
ecrit_le: 2026-08-22T00:26:41+02:00
auteur: session tss2-relecture-etapes5-7 · claude-sonnet-5
revision: c17950b
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/assets/sessions/session_advanced_demo_orig.json
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/step_resolution.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/challenge_timeline_forecast_test.dart
  - rhythm_coach/test/content_from_equals_to_test.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
  - rhythm_coach/test/movement_trajectory_plateau_test.dart
provenance:
  mesure: 13
  deduit: 4
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:937
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/lib/services/beep_engine.dart:394
  - rhythm_coach/lib/services/step_resolution.dart:53
  - rhythm_coach/lib/widgets/movement_animation.dart:364
  - rhythm_coach/lib/widgets/movement_animation.dart:798
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart:38
  - rhythm_coach/test/challenge_timeline_forecast_test.dart:118
  - rhythm_coach/test/content_from_equals_to_test.dart:36
  - rhythm_coach/test/movement_trajectory_continuity_test.dart:556
  - rhythm_coach/test/movement_trajectory_plateau_test.dart:77
---

*Relecture par `claude-sonnet-5` du travail de `claude-opus-5`. Consigne : chercher à réfuter, pas à
valider. Périmètre strict : les commits `2a26f98` (étape 5, sonde des plateaux) et `0b7fcfe` (étape 7,
retrait de `currentTo`), plus le relevé des `fix(...)` de la branche livré par `c17950b` (effectif :
cf. § 3). Dernière relecture du chantier « timeline source unique » avant fusion par Manu.*

## Verdict

**Publiable avec réserves.** Aucun bug trouvé dans le périmètre strict : le retrait de `currentTo`
est structurellement et empiriquement inoffensif, les trois sondes de plateau tombent rouges pour la
bonne raison, et les trois entrées du relevé rejouées par mutation (`52893b5`, et le duo `a02694e` /
`22a6cd8`) confirment exactement le verdict que l'auteur leur donnait. **Rien, selon moi, ne devrait
être bloqué avant fusion.** Les réserves portent sur deux points déjà honnêtement disclosés par
l'auteur lui-même, que je n'ai fait que confirmer sans les combler (mandat explicite : pas de nouvelle
sonde) : le trou de couverture sur la garde de gel de `session_screen.dart`, et les deux entrées du
relevé restées « incertain » que je n'ai pas mutées (hors de l'échantillon demandé).

## 1. Étape 7 — `currentTo` était-il vraiment mort ?

**[mesuré]** `grep -rn resolveUpcomingMovementSteps lib/ test/` ne retourne qu'un appelant de
production (`session_screen.dart:1136`) et six appels de test. Aucun appel dynamique, aucune branche
cachée : la signature n'a qu'un seul point d'entrée en dehors des tests.

**[mesuré]** Lecture de `resolveStepConfig` (`step_resolution.dart:53`) : `to: step.to` est retourné
**sans condition**, quel que soit le mode. Dans la boucle du résolveur
(`movement_trajectory_forecast.dart`), la variable locale `to` est réassignée depuis `resolved.to` en
tête de chaque itération, avant toute lecture — et si la boucle ne produit aucun résultat, elle n'est
jamais lue non plus. Le paramètre `currentTo` retiré ne pouvait influencer aucune sortie.

**[mesuré]** Preuve par exécution, pas seulement par lecture : j'ai rejoué une copie de l'ancienne
fonction (avec `currentTo`) sur six jeux de steps (liste vide, text-only, un step, une chaîne
d'héritage mode/bpm, un hold, une chaîne de trois transitions de mode) croisés avec six valeurs de
`currentTo` (`null`, et les cinq positions). Les 36 résultats sont strictement identiques à
`currentTo` fixé — mode, from, to, bpm, startSecond, transitionGap. Sonde jetable, jamais commitée,
supprimée après lecture.

**[mesuré]** `beep_engine.dart:394` confirme que le moteur audio applique la même règle sans
inheritance : `_to = resolved.to;` est également inconditionnel. La docstring corrigée par `0b7fcfe`
(« `to` n'est jamais hérité ») décrit donc bien le son, pas seulement l'affichage — l'ancienne
docstring (« hérite mode/from/to/bpm ») était fausse avant le refactor autant qu'après.

**[mesuré]** `ctrl.currentTo` reste utilisé à trois autres endroits
(`session_screen.dart:1071`, `session_screen.dart:1121`, `session_controller.dart:1414`) : le retrait
ne concerne que l'argument nommé passé à `resolveUpcomingMovementSteps`, rien n'est orphelin en amont.

**[déduit]** Le compte de tests inchangé (« exactement 1097 avant/après ») n'est pas suspect : retirer
un paramètre mort d'une signature ne supprime aucun test, seulement des arguments dans des appels
existants — c'est le résultat attendu d'un nettoyage pur, pas un signe que la couverture aurait
disparu avec lui.

## 2. Étape 5 — les trois sondes de plateau tombent-elles pour la bonne raison ?

Rejoué moi-même sur le code réel : mutation → run ciblé sur `test/movement_trajectory_plateau_test.dart`
→ lecture du message d'échec → restauration (`git diff` vide confirmé après chaque mutation).

**[mesuré]** *Sonde 1 — la série.* `break` ajouté juste après le premier point d'un segment plat
(`movement_animation.dart`, boucle de `_computeFutureBeats`) pour simuler « un step stable ne pose
qu'un point figé ». Résultat : les quatre tests de mode tombent tous sur `Expected: a value greater
than or equal to <2> / Actual: <1>` — exactement l'assertion `points.length, greaterThanOrEqualTo(2)`,
pas un effet de bord.

**[mesuré]** *Sonde 2 — la grille.* Le rattrapage par multiples entiers du battement
(`nextTime = nextTime.add(Duration(milliseconds: (steps * segBeatMs).round()))`) remplacé par un reset
naïf `nextTime = now`. Résultat : seul le test « deux recalculs successifs posent les points aux mêmes
instants » tombe, avec le message `la grille du plateau a bougé` — les quatre tests de série restent
verts (attendu : cette mutation ne casse que l'alignement entre deux calculs, pas un calcul isolé).

**[mesuré]** *Sonde 3 — le câblage mode → durée.* `_durationFor` muté pour faire retourner à
`hold`/`beg` la même durée que `suckle` (1200 ms au lieu de 1800 ms). Résultat : seul le test de
câblage tombe, sur `les pastilles suivent _durationFor(mode, bpm) du step monté` — les autres restent
verts. Les trois mutations discriminent exactement ce que l'auteur annonçait, rien de plus large.

**[mesuré]** *Le cas `breath` (intervalle 3200 ms, fenêtre 3000 ms) ne ment pas.* Sonde jetable :
`computeFutureBeatsForTest` en mode `breath` sur les mêmes paramètres que le test produit `t=0ms`
(ancre), `t=1195ms` (seul point visible dans la fenêtre) et `t=4395ms` (point hors fenêtre, généré par
`_extraBeatsBeyondWindow` pour prolonger la courbe jusqu'au bord, jamais rendu à l'écran).
`points.length >= 2` est donc vrai — la série interne existe bel et bien — mais un seul point tombe
dans la zone visible. Le test mesure la série interne, pas le rendu ; il ne contredit pas l'observation
« une seule pastille visible » fichée en `tss2-006` et volontairement non corrigée (réglage esthétique
de Manu). Sonde jetable, jamais commitée.

## 3. Le relevé des `fix(...)` — contrôle par sondage

**[document]** Le rapport porte sur les `fix(...)` de `git log origin/develop..HEAD` (23 au total) et
annonce 16 entrées « gardé », 2 « sans objet » (révertées par `6bb44f8`), 2 « incertain », et 3
« non gardé »/« à moitié » — dont le duo `a02694e`/`22a6cd8` qui corrige la même ligne, la garde
`ctrl.isTimelineFrozen ? const [] : resolveUpcomingMovementSteps(…)` de `session_screen.dart:1134`.

**[mesuré]** *Échantillon 1 — un « gardé ».* `52893b5` (contenu : remplacer `head→head` par `tip→head`
dans deux sessions JSON, deux steps où le moteur relevait déjà `from`). J'ai réintroduit `from: "head"`
au step `t=0` de `session_advanced_demo_orig.json` (annulant le fix). `content_from_equals_to_test.dart`
tombe immédiatement : le `Set` trouvé contient une entrée en trop
(`session_advanced_demo_orig.json » steps/0`) par rapport à l'ensemble exact attendu. La sonde
parcourt tout le contenu écrit à la main, pas seulement les deux fichiers touchés par ce commit — elle
aurait attrapé une régression n'importe où. Restauré, `git diff` vide confirmé.

**[mesuré]** *Échantillon 2 — le duo `a02694e`/`22a6cd8`.* J'ai supprimé le ternaire de
`session_screen.dart:1134` (toujours appeler `resolveUpcomingMovementSteps`, même horloge gelée) et
lancé la suite complète (`flutter test`, sans filtre). Résultat : **`All tests passed!`, 1097 tests
verts** — aucun test ne rougit. Ceci confirme exactement l'affirmation du rapport : « supprimer le
ternaire ne ferait rougir aucun test ». Restauré immédiatement, `git diff` vide confirmé.

**[mesuré]** Le rapport précise que `22a6cd8` est « à moitié » couvert parce qu'il a aussi introduit le
getter `isTimelineFrozen` dans `session_controller.dart`, séparément asserté. `grep -n
isTimelineFrozen test/` confirme trois `expect(ctrl.isTimelineFrozen, ...)` dans
`challenge_timeline_forecast_test.dart` (lignes 118, 124, 183) — le getter est bien gardé, seul son
câblage dans `session_screen.dart` ne l'est pas. Le rapport ne surclasse pas sa propre couverture.

**[déduit]** Ces deux échantillons — un « gardé » qui tombe bien rouge, un « non gardé » qui reste bien
vert après mutation — vont dans le sens du relevé plutôt que contre lui. Je n'ai pas échantillonné les
deux entrées « incertain » (`05b25cd`, `44df1e1`) : hors du périmètre de sondage fixé par la consigne
(trois entrées), je ne me prononce pas dessus au-delà de ce que le rapport dit lui-même.

## Ce que je n'ai pas pu établir

- **[déduit]** Je n'ai vérifié par mutation que trois entrées du relevé de 23 commits (`52893b5`,
  `a02694e`, `22a6cd8`) — les 20 autres, y compris les deux « incertain » (`05b25cd`, `44df1e1`),
  reposent uniquement sur la lecture de l'auteur, non recontrôlée ici.
- Je n'ai pas cherché à combler le trou de couverture sur la garde de `session_screen.dart:1134` — ni
  en écrivant un test montant l'écran, ni en jugeant si le coût d'un tel test serait justifié : hors
  mandat de cette relecture, comme il l'était pour l'auteur.
- Je n'ai pas rejoué la mutation « câblage du mode vers `beatDuration` » sur `beg` (seulement
  `hold`/`suckle`, comme le fait le test existant) : je n'ai aucune raison de penser que `beg` suivrait
  une autre règle (même branche du `switch` que `hold` dans `_durationFor`), mais je ne l'ai pas
  observé directement.

## Vérifications

**[mesuré]** Depuis `rhythm_coach/` : `flutter pub get` (OK), `flutter analyze` → **No issues found!**
(deux passages, avant et après les mutations, arbre restauré entre les deux), `flutter test` complet →
**1097 tests verts** (un passage avec la mutation de la garde de gel active ailleurs dans le fichier,
aucune régression en dehors de l'absence de rougissement déjà commentée), `dart format
--set-exit-if-changed lib/ test/` → **307 fichiers, 0 changé**. Toutes les commandes redirigées vers
fichier, jamais pipées. Arbre `git status --short` vide avant et après chaque mutation.

## Ce qui a été corrigé

**[déduit]** Rien. Aucun défaut n'a été trouvé dans le périmètre strict (étapes 5 et 7) ni dans
l'échantillon du relevé — les trois sondes rejouées, le retrait de `currentTo`, et les deux entrées
échantillonnées du relevé se comportent exactement comme annoncé. Rien à corriger, donc rien corrigé.
