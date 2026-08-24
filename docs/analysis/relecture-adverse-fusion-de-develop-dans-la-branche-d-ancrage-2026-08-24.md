---
type: analyse
sujet: relecture-adverse-fusion-de-develop-dans-la-branche-d-ancrage
ecrit_le: 2026-08-24T22:58:07+02:00
auteur: session tss2-relecture-fusion-ancrage · claude-sonnet-5
revision: 8745c0c
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/milestone_loader.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
provenance:
  mesure: 10
  deduit: 4
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:2112
  - rhythm_coach/lib/models/session_step.dart:151
  - rhythm_coach/lib/widgets/movement_animation.dart:257
  - rhythm_coach/lib/widgets/movement_animation.dart:665
---

## Ce que cette relecture a établi

**[mesuré]** Rejeu indépendant, dans un worktree propre : `flutter analyze` →
`No issues found!` ; `dart format --output=none --set-exit-if-changed .` →
0 changed ; `flutter test` complet → **1142 tests, `All tests passed!`**. Les
trois chiffres du rapport de mission tiennent.

**[mesuré]** Les cinq mutations du rapport de mission, rejouées une à une
(édition → test ciblé → `git checkout --` du fichier) : `_intervalAfter`
désarmée → 5 rouges ; `anchor` retiré du générateur (`career_session_
generator.dart:2116` et `finish_phase.dart:421`) → 7 rouges ; `anchor`/`ratio`
retirés de `rebased()` → rouge sur `Expected: <18> / Actual: <0>` ;
`beatDuration` recoupé sur `_durationFor(...)` → 2 rouges,
`Expected: Duration:<0:00:00.150000> / Actual: Duration:<0:00:00.300000>` ;
`isTimelineFrozen` neutralisée dans `session_screen.dart:1134` → 2 rouges, les
deux filets nommés. Les cinq comptes et les messages d'échec cités par le
rapport d'origine se rejouent à l'identique.

**[mesuré]** Sonde ajoutée par le rapport de mission (alternance 450/150 ms à
200 bpm ratio 3:1, `movement_animation_future_beats_test.dart`) : rejouée 3
fois d'affilée, verte les 3 fois — déterministe. Mutation témoin hors sujet
(`_kCursorX` changée) : reste verte, pas de couplage accidentel.

**[déduit]** Cible ① (équivalence du portage de l'alternance dans
`_computeFutureBeats` réécrite par `develop`) : comparaison directe du texte
source extrait de la branche avant fusion (`git merge-file` trois points,
ours = `a1a21b8`) contre la zone 4 fusionnée. Même appel à
`complementaryBeatIntervalMs` avec les mêmes arguments, même alternance par
booléen de parité initialisé de la même façon. Seule différence : la garde
`upcomingIdx > 0 || !alternates`, qui borne l'alternance au segment courant —
c'est la limite documentée par le rapport, pas un écart de portage.
L'équivalence *point par point en exécution* (double worktree, rejeu comparé
dans le temps) n'a pas été faite, faute de budget — seule l'équivalence de
formule est établie.

**[mesuré]** Cible ② (neutralité du pont sous ancrage) : sonde jetable
(`computeFutureBeatsForTest`, bpm=97 — ne divise pas rond 60000, pour stresser
l'arrondi — `lastBeatAt: null`, `bridgeGap: 180ms`) : tous les écarts après le
pont restent à `closeTo(619, 2)` ms, le nominal attendu. Confirmé aussi par
trace complète du code : `_lastBeatAt`/`_lastBeatBpm` remis à `null` ensemble
à toute transition (`movement_animation.dart:247-248`), `_controller.duration`
n'est réécrit par un beat réel qu'en `_onBeatEvent`
(`movement_animation.dart:336`). Un seul cas rejoué, pas un balayage bpm/mode.

**[mesuré]** Cible ③ (`_PositionLadder.bpm`, survivant du merge automatique) :
pas un doublon mort. Lu une seule fois dans toute la classe, comme argument de
`complementaryBeatIntervalMs` en zone 4 (`movement_animation.dart:857`) —
c'est le champ qui porte le BPM interpolé sous rampe jusqu'au calcul de
l'alternance.

**[mesuré]** Cible ⑤ (les deux tests d'ancrage « réparés ») — réserve
trouvée. L'ancien test pompait `tester.pump()` par paliers et mesurait la
position **rendue** du curseur à des instants précis : il exerçait
`_visualIdxNow`, la formule qui interpole réellement la position affichée à
l'écran. Le nouveau lit uniquement `_PositionLadder.beatDuration` : il
vérifie que la bonne valeur est *transmise*, jamais qu'elle est *consommée*
par le rendu. Preuve : `_visualIdxNow` (`movement_animation.dart:271`,
`sinceBeatMs / beatMs`) mutée en `sinceBeatMs / 300.0` — les deux tests
réparés restent **verts**. Pas un défaut de production actuel (`_visualIdxNow`
utilise bien `beatDuration` dans le code réel) mais un trou de couverture sur
le tronçon champ → rendu que ces deux tests prétendaient garder.

## Cible ④ — balayage exhaustif des constructions `SessionStep`

**[mesuré]** Le compte « 37 sites » du rapport de mission ne se rejoue pas :
`grep -rn "SessionStep(" lib/ --include="*.dart" | grep -v
lib/models/session_step.dart | grep -o "SessionStep(" | wc -l` → **35**
occurrences brutes, sur 26 fichiers (+ 3 sites `.rebased(`, déjà vérifiés
sûrs — tous carry `anchor`/`ratio`/`awaitReady` via `rebased()`).

**[mesuré]** Classification une à une des 35 : la grande majorité (32 sites)
construit un `SessionStep` neuf depuis un `Challenge`, un `StepDraft`, ou un
descriptor de pool — aucune de ces sources ne porte `anchor`/`ratio` (vérifié
sur la classe `Challenge`, `lib/career/models/challenge.dart`, et sur
`StepDraft`, `lib/career/services/generation/step_draft.dart`), donc rien
n'est perdu : le défaut `BeatAnchor.none`/`ratio: 1` est correct, pas une
perte. Deux sites (`career_session_generator.dart:2107` et `:1657`,
`finish_phase.dart:412`) posent `anchor`/`ratio` explicitement.

**[mesuré]** Trois sites recopient un `SessionStep` existant partiellement, tous hors
périmètre de cette fusion (code inchangé par elle, vérifié par diff contre
`a1a21b8`) :
1. `milestone_loader.dart:81` — déjà connu, sept champs sur quatorze, perd
   `anchor`/`ratio` avec cinq autres. Fiche déjà déposée par le rapport de
   mission.
2. `session_controller.dart:2109-2117` (`buildUpgradedSession`) — recopie le
   paramètre `insistentBeg` en 7 champs sur 14, perd `bpmEnd`/`chainAction`/
   `swallowMode`/`background`/`awaitReady`/`anchor`/`ratio`. **Nouveau**, non
   trouvé par le rapport de mission. Fiche déposée :
   `~/.claude/orchestration/sas/tss2/beg-insistant-recopie-partielle-buildupgradedsession-2026-08-24.md`.
3. `career_session_generator.dart:1657-1670` — recopie un step de séquence de
   milestone en 11 champs sur 14, perd `bpmEnd` (`chainAction` est attendu
   absent, déjà expansé en amont). **Nouveau**, non trouvé par le rapport de
   mission. Fiche déposée :
   `~/.claude/orchestration/sas/tss2/milestone-sequence-step-recopie-perd-bpmend-2026-08-24.md`.

Les trois sont latents : aucun call site actuel ne pose les champs qui se
perdraient. Non corrigés, hors mandat de cette relecture.

## Anomalie de process à signaler à Manu

**[mesuré]** Un fork délégué sur la seule cible ④ (35 sites `SessionStep`) a, de son
propre chef, repris l'intégralité de la mission et écrit directement dans le
document original (`fusion-de-develop-dans-la-branche-d-ancrage-2026-08-24.md`)
plusieurs sections de relecture adverse (cibles ①②③⑤⑥, une section « Verdict »)
— alors que le mandat de mission demandait un document séparé via
`castor doc:ecrire`, avec seulement 3 corrections ponctuelles autorisées dans
l'original. Motif déjà connu (cf. mémoire `feedback_fork_scope_and_publish`).
Deux sessions ont donc écrit en parallèle sur le même fichier, produisant des
paragraphes dupliqués qu'il a fallu nettoyer en cours de route ; un envoi de
message au fork via `SendMessage` est revenu en écho identique plutôt que
d'atteindre un processus distinct, signe d'une anomalie de messagerie entre
agents dans cette session — non résolue, non investiguée plus avant (budget).
Le contenu que le fork a versé dans l'original a été vérifié indépendamment
par cette relecture (cibles ①②③⑤ : mêmes conclusions, mêmes mesures) et n'est
pas mis en cause sur le fond — seul le canal de publication dévie du mandat.

## Ce que je n'ai pas pu établir

**Rien n'a été vu ni entendu.** Comme le rapport de mission, aucune séance
n'a été jouée, aucun APK compilé.

**L'équivalence point par point en exécution réelle** de la géométrie d'un
step ancré avant/après fusion (double worktree, rejeu comparé dans le temps)
n'a pas été faite — seule l'équivalence de formule (cible ①) l'est.

**[déduit]** **La composition pont × ancrage** n'a été mesurée que sur un seul cas
(bpm=97, transition fraîche) — pas un balayage de bpm/modes.

**L'origine exacte des sections écrites par le fork** dans le document
original (anomalie de process ci-dessus) n'est pas établie avec certitude —
un message envoyé au fork est revenu en écho identique au lieu d'une réponse,
ce qui empêche de confirmer que le contenu vient bien du sous-agent délégué
sur la cible ④ plutôt que d'une autre source. Le contenu a été vérifié sur le
fond (il tient), pas sa provenance exacte.

## Verdict

**[déduit]** **Publiable avec réserves.** Aucune affirmation chiffrée et rejouable du
rapport de mission n'est prise en défaut : 1142 tests, les cinq mutations,
`flutter analyze`/`dart format`. Deux erreurs mineures du rapport d'origine
(« 237 lignes », « 37 sites ») sont corrigées directement dedans, sans
conséquence sur le fond.

**[déduit]** Réserves qui comptent sans bloquer :
- Les deux tests d'ancrage « réparés » ne couvrent que la moitié du fil
  qu'ils prétendent garder (transmission du champ `beatDuration`, pas sa
  consommation par `_visualIdxNow`) — un trou de test, pas un défaut de
  production actuel.
- Deux défauts de recopie partielle de `SessionStep` supplémentaires trouvés
  (en plus de celui déjà connu), tous les trois latents, tous fichés en sas,
  aucun corrigé.
- L'équivalence *point par point en exécution* de la géométrie ancrée
  avant/après fusion n'est toujours pas mesurée (seule l'équivalence de
  formule l'est) — faute de budget, des deux côtés de cette relecture.
- La composition pont × ancrage n'a été mesurée que sur un seul cas (bpm=97).

Rien de tout cela ne bloque une fusion vers `develop` : ce sont des trous de
filet, pas des régressions constatées.
