---
type: analyse
sujet: gap-de-transition-du-moteur-expose-dans-la-trajectoire
ecrit_le: 2026-08-20T18:31:03+02:00
auteur: session tss2-animations-round2 · claude-sonnet-5
revision: 5ee149f
branche: feat/movement-trajectory-continuity
porte_sur:
  - docs/analysis/relecture-adverse-continuite-de-trajectoire-2026-08-20.md
  - docs/analysis/trajectoire-continuite-movement-animation-2026-08-20.md
  - rhythm_coach/assets/career/milestones.json
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/beep_engine_transition_gap_test.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
provenance:
  mesure: 10
  deduit: 4
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1243
  - rhythm_coach/lib/services/beep_engine.dart:344
  - rhythm_coach/lib/widgets/movement_animation.dart:641
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart:56
---

Round 2 de relecture sur `feat/movement-trajectory-continuity` : traitement de la réserve gênante n°1
(gap de transition non modélisé) de `docs/analysis/relecture-adverse-continuite-de-trajectoire-2026-08-20.md`,
et complément mineur à la réserve n°2 (déjà corrigée dans un commit antérieur, `f8da372`).

## Réserve 1 — remesure avant tout changement de code

[mesuré] Sonde écrite contre le vrai `BeepEngine` (channels `audioplayers` mockés en no-op, aucune
simulation) : `applyStep` met 304 ms à retourner pour une transition même mode (rhythm→rhythm),
601 ms pour un changement de mode sans grand geste (rhythm→hold), 1501 ms pour un changement de mode
avec grand geste (hold→hand). Ces trois chiffres confirment, indépendamment, les 305 ms et 1502 ms de
`relecture-adverse-continuite-de-trajectoire-2026-08-20.md` et les constantes du code
(`_sameModeTransitionGap` 300 ms, `_modeTransitionGap` 600 ms, `_modeTransitionGapBig` 1500 ms). Le
décalage entre l'instant nominal du step et le premier bip réel est donc confirmé, pas seulement
déduit du code. La sonde était temporaire (`test/_probe_transition_gap_test.dart`), supprimée après
usage — elle n'apporte rien de plus que le test permanent `beep_engine_transition_gap_test.dart`
ajouté plus bas, qui teste la fonction pure sans horloge réelle.

## Arbitrage — décidé par l'orchestrateur, pas par Manu

[document] La consigne du round 2 tranchait explicitement l'architecture : exposer le gap depuis
`BeepEngine` en lecture seule, sans dupliquer une deuxième copie de `_needsBigGap` côté affichage.
Cette décision est celle de l'orchestrateur qui a écrit la tâche, pas une décision de Manu — elle est
consignée ici comme telle, pas comme un fait tranché en amont.

## Implémentation

[mesuré] `BeepEngine._needsBigGap` (`beep_engine.dart:327`) ne lisait déjà aucun état d'instance —
rendue `static` sans changement de signature côté appelant. Une nouvelle méthode statique
`BeepEngine.transitionGap({incoming, previous, incomingTo})` (`beep_engine.dart:347`) encapsule
exactement la logique qui vivait dans `applyStep` : même mode → 300 ms, sinon → 600 ou 1500 ms selon
`_needsBigGap`. `applyStep` (`beep_engine.dart:423`) appelle maintenant cette méthode au lieu de
dupliquer le calcul inline — comportement inchangé, revérifié par la même sonde après le refactor :
304/601/1501 ms à l'identique.

[mesuré] `UpcomingMovementStep` (`movement_trajectory_forecast.dart:10`) gagne un champ
`transitionGap` à défaut rétrocompatible (`Duration.zero`) — les `UpcomingMovementStep` construits à
la main dans les tests existants (hors résolveur) gardent un gap nul, donc un comportement inchangé.
`resolveUpcomingMovementSteps` (`movement_trajectory_forecast.dart:56`) calcule le gap réel via
`BeepEngine.transitionGap`, en trackant le mode résolu du step précédent (`previousMode`) avant
réassignation — pas de duplication de `_needsBigGap`.

[mesuré] `_computeFutureBeats` (`movement_animation.dart:641`) pose maintenant `resumeAt =
boundary.add(upcoming.transitionGap)` et l'utilise à la place de `boundary` nu, à la fois pour le
point `tip` (frontière de famille) et pour le premier point direct du segment suivant (même famille).
La remontée à `tip` — ce que Manu a demandé de voir — arrive donc à l'instant où le moteur démarre
réellement le nouveau mode, pas à l'instant nominal du step.

## Tests — rouges avant, verts après, vérifiés dans les deux sens

[mesuré] Deux tests ajoutés à `movement_trajectory_continuity_test.dart` (groupe
`_computeFutureBeats`) construisent un `upcomingSteps` avec un `transitionGap` explicite (600 ms
même famille, 1500 ms frontière de famille) et vérifient la position temporelle précise du premier
point du nouveau segment. Rejoués sur le code d'avant (`resumeAt` remplacé par `boundary`), les deux
échouent : le point tombe à 800 ms (l'instant nominal) au lieu des 1400/2300 ms attendus — capturé
avant le patch, pas raisonné. Après le patch, les deux passent.

[mesuré] Un troisième test, sur `resolveUpcomingMovementSteps`, vérifie que `transitionGap` vaut
300/600/1500 ms sur une séquence rhythm→rhythm→hold→hand. Rejoué avec le calcul remplacé par
`Duration.zero` (cassure volontaire), il échoue sur les trois assertions — capturé avant de remettre
le vrai calcul.

[mesuré] Un nouveau fichier `beep_engine_transition_gap_test.dart` (5 tests) verrouille
`BeepEngine.transitionGap` en tant que fonction pure, sans horloge réelle : même mode pour les 9
`SessionMode` (300 ms), changement de mode vers rhythm/hold (600 ms), changement de mode vers
lick/hand/biffle/breath/freestyle/suckle (1500 ms), beg avec/sans `to` (600/1500 ms), `previous: null`
(600 ms, cas jamais atteint en pratique mais couvert par la signature).

## Vérifications

[mesuré] Depuis `rhythm_coach/` : `flutter analyze` → « No issues found! ». `timeout 1500 flutter
test` (sortie redirigée vers `/tmp/test-round2.log`, jamais pipée) → `1031 tests, All tests passed!`,
exit 0 — 1023 tests de référence + 8 nouveaux (2 `_computeFutureBeats` + 1 `resolveUpcomingMovementSteps`
+ 5 `beep_engine_transition_gap_test.dart`). `dart format --set-exit-if-changed lib test` → a
reformaté 2 fichiers (lignes trop longues sur les nouveaux appels), puis exit 0 stable au second
passage.

## Un risque examiné et non corrigé — hors mandat, non observé aujourd'hui

[déduit] Si deux steps de bip consécutifs étaient plus rapprochés dans le temps que le
`transitionGap` du second, `resumeAt` du premier pourrait dépasser la frontière nominale du second et
produire un point dont le temps recule dans la séquence. Ce risque n'est pas nouveau dans son
principe — il existe dès que deux frontières sont rapprochées — mais mon changement l'active pour la
première fois puisque `_computeFutureBeats` ignorait jusqu'ici tout délai.

[mesuré] Sur les 37 milestones de `assets/career/milestones.json` (165 paires de steps de bip
consécutifs, `chainAction` déplié), l'écart minimal entre deux steps consécutifs est de 2000 ms —
au-dessus du plus gros `transitionGap` possible (1500 ms) avec 500 ms de marge, sur l'intégralité des
milestones.

[déduit] Côté générateur de carrière, `ctx.time += draft.duration!` (`career_session_generator.dart:1243`)
fait que l'écart entre deux steps consécutifs est la durée du step précédent ; les durées littérales
trouvées par recherche texte dans les règles vont de 4 à 30 s, toutes au-dessus du gap maximal. Cette
recherche n'est pas exhaustive : plusieurs règles calculent leur durée dynamiquement (`ctx.fastDur`,
`begDur`, `freeDur`, …) et je n'ai pas vérifié qu'aucune de ces valeurs calculées ne descend sous
1500 ms.

[déduit] Même si le cas se produisait, `addPoint` (`movement_animation.dart:617`) ignore
silencieusement un point dont l'instant est déjà passé (`dtMs < 0 → return true` sans rien ajouter) —
pas de crash, au pire un segment de courbe sauté. Je n'ai pas corrigé ce risque : il n'est observé
nulle part aujourd'hui, dans le même registre que les divergences déjà actées par la relecture
précédente (`from == to`, BPM hors bornes) comme non gênantes tant qu'elles ne se produisent jamais.

## Réserve 2 — déjà traitée avant ce round

[mesuré] `git log` montre que l'erratum en tête de `trajectoire-continuite-movement-animation-2026-08-20.md`
(classement corrigé, chiffres corrigés, renvoi vers la relecture) a été ajouté par le commit
`f8da372`, avant l'ouverture de ce round 2. Il manquait une date explicite dans le libellé de
l'erratum — ajoutée (« Erratum du 2026-08-20 »), seul changement apporté à ce document dans ce round.

## Hors périmètre — non touché, conformément à la consigne

[document] Les réserves non gênantes de la relecture (rampes de BPM affichées à tempo constant, BPM
non clampé, `from == to` non répliqué, `suckle` sur une hypothétique troisième position) restent
ouvertes : la relecture mesure qu'elles ne se produisent jamais aujourd'hui, et la consigne du round 2
demandait explicitement de ne pas les élargir.

## Ce que je n'ai pas pu établir

- **Rien vu en mouvement**, comme les deux rapports précédents. [déduit] Aucune de mes vérifications
  ne dit si le nouveau calage (0 décalage au lieu de 0,6–1,5 s) se voit mieux à l'œil sur un appareil
  réel — testé uniquement au niveau du calcul pur des points de la courbe.
- **Le plancher exact des durées calculées dynamiquement par le générateur de carrière**
  (`ctx.fastDur`, `begDur`, `freeDur` et assimilés) n'est pas vérifié — seul un plancher littéral de
  4 s est établi par recherche texte, pas une preuve exhaustive comme pour les milestones.
- **Un agent de recherche lancé pour vérifier ce même plancher côté générateur** n'a renvoyé, à deux
  reprises, aucun résultat exploitable (un texte sans rapport avec sa tâche) — j'ai contourné en
  vérifiant moi-même directement plutôt que d'insister sur ce canal.
- **Le cas où deux steps de bip partagent une frontière plus rapprochée que le `transitionGap`** n'est
  vérifié qu'en dehors du générateur de carrière (milestones, exhaustif) ; dans le générateur, seule
  une borne inférieure partielle (durées littérales) est établie.
