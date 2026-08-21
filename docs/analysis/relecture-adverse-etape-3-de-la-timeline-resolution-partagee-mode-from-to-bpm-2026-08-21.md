---
type: analyse
sujet: relecture-adverse-etape-3-de-la-timeline-resolution-partagee-mode-from-to-bpm
ecrit_le: 2026-08-21T21:30:42+02:00
auteur: session tss2-relecture-etape3 · claude-sonnet-5
revision: 97649b6
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/step_resolution.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/beep_engine_step_resolution_characterization_test.dart
provenance:
  mesure: 13
  deduit: 1
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/services/beep_engine.dart:362
  - rhythm_coach/lib/services/step_resolution.dart:31
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart:39
---

*Relecture par `claude-sonnet-5` du travail de `claude-opus-5`. Consigne : chercher à réfuter, pas à
valider. Périmètre : `git diff d25b80b..97649b6` hors `docs/` — deux commits, `ec27f8f` (tests de
caractérisation) et `6dcdd2c` (extraction `resolveStepConfig`). Le cas `from == to` n'a pas été
tranché — ce n'est pas mon mandat, je vérifie seulement ce que le rapport du 2026-08-21 affirme à
son sujet.*

## Verdict

**Publiable avec réserves.** La promesse centrale de l'étape 3 — le son ne bouge pas, la règle
mode/from/to/bpm n'existe plus qu'à un endroit — résiste à toutes les tentatives de réfutation
listées ci-dessous, y compris la plus dure (rejouer les tests de caractérisation sur le code
d'avant l'extraction). Les réserves ne portent que sur la documentation d'accompagnement : un
comptage inexact et une preuve chiffrée non reproductible que j'ai dû reconstruire moi-même
autrement (cf. « Ce que je n'ai pas pu établir tel quel »).

## 1. Le son a-t-il bougé ?

**[mesuré]** J'ai muté `step_resolution.dart` trois fois, relancé le seul fichier de
caractérisation à chaque fois (`flutter test test/beep_engine_step_resolution_characterization_test.dart`),
puis restauré le fichier original (diff vide vérifié après chaque restauration). **[mesuré]**
Tableau sonde → mutation → verdict :
| # | Mutation | Rouges | Bonne raison ? |
|---|---|---|---|
| A | hold/beg/suckle : `from = step.to` → `from = step.from` (et inversion de la branche sinon) | 13/25, exactement le groupe « résolution from/to » | Oui — `Expected: Position.full / Actual: Position.tip` etc., sur les 8 tests hold/beg/suckle/hand/biffle/breath/freestyle/rhythm concernés ; les groupes mode/BPM/from==to restent verts |
| B | `step.mode ?? defaultMode` → `defaultMode` (ignore le mode explicite) | 9/25 | Oui — les tests « le mode du step gagne » et les variantes hold/beg/suckle (qui dépendent du mode résolu) tombent |
| C | retrait du `.clamp(kMinBpm, kMaxBpm)` sur le BPM | 2/25 | Oui — exactement les deux tests de clamp (plafond/plancher), rien d'autre |

Les trois mutations tombent rouges sur le sous-ensemble de tests qui teste précisément la règle
mutée, jamais au hasard ni par une erreur de compilation — la caractérisation discrimine
vraiment.

**[mesuré]** Geste le plus dur : rejouer la caractérisation sur le code d'AVANT l'extraction.
Worktree sur `d25b80b`, copie du fichier de test neuf (`ec27f8f`/`6dcdd2c` n'existaient pas encore
à ce commit), `flutter pub get`, `flutter test` : **25/25 verts**, mêmes valeurs attendues que sur
le code d'après (`+25: All tests passed!` dans les deux cas, aucune divergence de contenu entre
les deux runs). Le code d'avant l'extraction satisfait donc la même caractérisation que le code
d'après — c'est la preuve la plus directe que le comportement audible n'a pas changé.

**[mesuré]** Le fichier de test contient **25 tests**, pas 26 comme l'affirme
`docs/analysis/resolution-partagee-le-cas-from-egal-to-2026-08-21.md` (« 26 tests de
caractérisation »). Écart mineur, sans conséquence sur le fond — mais c'est la première affirmation
chiffrée du document, et elle est fausse.

## 2. Reste-t-il deux implémentations ?

**[mesuré]** Comparaison ligne à ligne de `applyStep` avant/après (`git show d25b80b:...` vs le
fichier actuel) : l'ordre des opérations est identique. `_bpm` est écrit au même endroit relatif
(juste après `_mode = mode`, avant le calcul de rampe `_bpmEnd`/`_loopDurationMs`) ; `_from`/`_to`
sont écrits au même endroit relatif (après ce calcul de rampe, avant le bloc `from == to`). Le
bloc `_pickShallowerThan` (lignes 396-402) est **strictement inchangé** — il n'apparaît même pas
dans le diff. Aucun effet de bord déplacé : le rafraîchissement `currentBpm: _bpm` /
`currentFrom: _from` passé à `resolveStepConfig` lit l'état **avant** mutation, exactement comme
le faisait le code conditionnel d'avant.

**[mesuré]** `grep -n "step.mode ?? sessionMode\|step.mode ?? defaultMode"` sur `beep_engine.dart`
et `movement_trajectory_forecast.dart` : aucun résultat. Aucune règle dupliquée n'a survécu à
l'extraction — `resolveStepConfig` est bien la seule implémentation restante.

## 3. L'exception `from == to` reste-t-elle scopée pareil ?

**[mesuré]** Le bloc qui déclenche `_pickShallowerThan` dans `beep_engine.dart` n'a pas bougé d'une
ligne (absent du diff). Il continue de se déclencher sur exactement `mode ∈ {rhythm, lick} && _to
!= null && _to == _from`, avec `_from`/`_to` post-résolution — donc sur les mêmes cas qu'avant, pas
un de plus.

**[mesuré]** Les 10 emplacements de contenu écrit à la main cités par le rapport existent tous,
avec exactement les valeurs annoncées — vérifié par script sur les JSON du dépôt (les milestones
sont sous la clé `sequence`, pas `steps`, ce qui a fait échouer ma première tentative de script ;
un second passage ciblé sur les 6 ids cités les a tous confirmés) :
- 6 milestones `intro_*` en `lick head/head` (`intro_hold_mid` t=38, `intro_biffle` t=28,
  `intro_encore` t=10, `intro_hold_full` t=44, `intro_full_pulse` t=40,
  `intro_surprise_notifs` t=10)
- `rapid_full` en `rhythm full/full` t=0 dans les 4 fichiers `punishments*.json` (fr/en/de/es)
- `session_advanced_demo_orig.json` t=0 (`head/head`) et `session_advanced_demo_ps1.json` t=0
  (`head/head`) et t=210 (`rhythm throat/throat`)

**[mesuré]** Le chiffrage de l'issue B (« effet nul sur 8/10, réel sur 2 ») est exact :
`_pickShallowerThan(p)` tire parmi `Position.values` d'index < `p.index`. Pour `head` → 1 candidat
(`tip`) ; pour `throat` → 3 candidats ; pour `full` → 4 candidats. Ça correspond position par
position aux 10 lignes du tableau. J'ai aussi vérifié que `step.time` est bien mutable en session :
`session_controller_challenge.dart:1004` fait `s.rebased(s.time - shift)` sur les steps futurs
après un défi — la réserve du rapport contre une clé dérivée de `step.time` est fondée.

Je n'ai rien trouvé qui contredise le chiffrage ou le classement des trois issues A/B/C ; je ne les
tranche pas, ce n'est pas mon mandat.

## Ce que je n'ai pas pu établir tel quel

**[mesuré]** Le rapport du 21/08 affirme « 0 différence sur 214 180 steps annoncés » entre l'ancien
et le nouveau corps de `resolveUpcomingMovementSteps`, comparés sur 600 séances générées — et
précise que la sonde qui a produit ce chiffre a été **jetée** (« elle embarquait une copie de
l'ancien code »). Je n'ai pas pu rejouer cette mesure telle quelle : elle n'existe plus. J'ai
reconstruit une preuve équivalente autrement — un test temporaire (non conservé, supprimé après
coup) qui réimplémente l'ancien corps de `resolveUpcomingMovementSteps` (copié de
`d25b80b`) et le compare au nouveau sur une exploration **systématique** (pas aléatoire) de tous
les couples mode × from × to (y compris toutes les égalités from==to) × bpm — **214 326 steps
comparés, 0 différence**, sauf sur les valeurs de BPM hors `[20, 300]` où j'ai délibérément vérifié
que le nouveau clampe et l'ancien non (seul changement de comportement reconnu par le rapport,
confirmé réel et isolé au BPM). Ce n'est pas la même mesure que celle du rapport (exploration
combinatoire contre génération de séances), donc ça ne confirme pas le chiffre « 214 180 » lui-même
— mais ça confirme, indépendamment, l'affirmation qu'il portait.

**[mesuré]** Je n'ai pas reproduit « 0 occurrence sur 600 séances générées (59 827 steps) » — le
chiffre de fréquence de `from == to` dans le contenu **procédural**. Regénérer 600 séances carrière
et compter les occurrences dépasse ce que j'ai jugé raisonnable dans le budget de cette relecture ;
je le signale comme non vérifié plutôt que de le recopier comme un fait. Ce que j'ai vérifié à la
place (les 10 emplacements écrits à la main, ci-dessus) couvre la partie du rapport qui étaie
directement la recommandation A.

**[déduit]** `step_resolution.dart` importe `beep_engine.dart` pour lire `kMinBpm`/`kMaxBpm`, et
`beep_engine.dart` importe `step_resolution.dart` pour appeler `resolveStepConfig` — un import
circulaire entre les deux fichiers. Ça compile et `flutter analyze` ne dit rien (Dart tolère les
cycles d'imports entre fichiers d'un même package), donc ce n'est pas un défaut ; mais ça
contredit un peu l'idée d'une fonction « pure » qui ne dépend de rien — elle dépend de deux
constantes portées par la classe qu'elle sert à découpler. Je ne l'ai pas corrigé : ce n'est pas un
bug, juste une remarque de conception qui n'engage aucune action.

## Exécution

**[mesuré]** Depuis `rhythm_coach/` : `flutter pub get` (OK), `timeout 300 flutter analyze` → *No
issues found!* (3.8s), `timeout 900 flutter test` (sortie redirigée vers fichier, jamais pipée) →
**1083 tests, `All tests passed!`, exit 0** — conforme au chiffre annoncé par l'auteur. Dépôt
propre après la relecture (`git status --short` vide, worktree de comparaison sur `d25b80b`
supprimé).

## Résumé

**[mesuré]** Rien dans ce périmètre ne réfute la promesse de l'étape 3. Les deux réserves qui
subsistent sont documentaires, pas fonctionnelles : un comptage de tests inexact (26 annoncés, 25
réels) et une preuve d'équivalence chiffrée jetée après usage, que j'ai dû reconstruire moi-même
pour vérifier l'affirmation qu'elle portait plutôt que le chiffre lui-même.
