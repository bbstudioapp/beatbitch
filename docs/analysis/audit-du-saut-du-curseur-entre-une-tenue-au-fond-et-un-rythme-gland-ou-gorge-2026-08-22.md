---
type: analyse
sujet: audit-du-saut-du-curseur-entre-une-tenue-au-fond-et-un-rythme-gland-ou-gorge
ecrit_le: 2026-08-22T21:15:54+02:00
auteur: session tss2-audit-saut-tenue · claude-fable-5
revision: 8f69949
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/step_resolution.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
provenance:
  mesure: 14
  deduit: 20
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:939
  - rhythm_coach/lib/services/step_resolution.dart:45
  - rhythm_coach/lib/widgets/movement_animation.dart:1076
  - rhythm_coach/lib/widgets/movement_animation.dart:691
  - rhythm_coach/lib/widgets/movement_animation.dart:768
  - rhythm_coach/lib/widgets/movement_animation.dart:913
---

## 1. La question

Pourquoi le curseur saute-t-il, à l'œil sur le téléphone, quand une tenue `throat`/`full` est suivie d'un rythme `head`/`throat` ?

## 2. Verdict : un mécanisme reproduit, intermittent, qui ne couvre que la tenue `full`

[mesuré] Le son et l'image, montés **ensemble** en temps réel dans un test widget (sans carte son : les échecs du plugin audio sont avalés, les bips restent des `BeatEvent` datés), reproduisent un saut du curseur sur `hold full 2 s → rhythm head/throat 120 BPM` : −0,65 rangée en un échantillon (3,89 → 3,23) à 2116 ms, soit 113 ms après `applyStep` et 530 ms avant le premier bip, là où la descente annoncée est d'une rangée en 600 ms.

[déduit] La cause est dans `_scrollBeats` (`movement_animation.dart:1076-1118`) : il ne place jamais le curseur sur la position que `_computeFutureBeats` vient de calculer pour l'ancre, il la **re-dérive** par interpolation entre l'origine de l'ancre (`originT`/`originIdx`) et le **premier point futur** de la courbe.

[déduit] Pour un plateau de tenue, cette origine est le bip synthétique posé à la fin du pont d'entrée (`originAt = last`, l. 691), jamais rafraîchi ensuite faute de `BeatEvent` — elle a l'âge de la tenue.

[déduit] Quand la frontière annoncée est passée mais que le step n'est pas encore appliqué — le contrôleur applique au tick, jusqu'à 200 ms après l'instant nominal (`elapsedSeconds`, `session_controller.dart:939`) — le point de frontière `(T, full)` est dans le passé et n'est pas posé (`addPoint`, l. 768 : `dtMs < 0` → rien), donc le premier point futur est l'arrivée du rythme `(T + 600 ms, throat)`.

[déduit] Le curseur est alors posé sur la **corde** `(fin du pont d'entrée, full) → (T + 600, throat)`, à la fraction `âge_tenue / (âge_tenue + 600 ms)` : 76 % pour une tenue de 2 s, ~94 % pour une tenue de 10 s — de `full` à `throat` d'un coup, dans le silence, puis une reptation jusqu'au premier bip.

[mesuré] La valeur prédite par cette corde pour B est 3,242 ; la valeur lue est 3,233.

[déduit] Le déclencheur est un **recalcul** de la courbe tombant dans cette fenêtre `[T, T + δ]`. Les recalculs ne sont pas cadencés : ils partent quand la queue mémoïsée sort de la fenêtre de 3 s (`build`, l. 913-922), au plus toutes les 500 ms à 120 BPM. Le saut est donc intermittent, conditionné à la coïncidence entre un recalcul et le retard d'application (≤ 200 ms dans l'appli).

[mesuré] Sur trois relances à tenue de 6 s (D et F sur `full`, E sur `throat`), aucune n'est retombée dans la fenêtre : descente linéaire continue (D, F), plateau puis descente (E).

[déduit] Pour `hold throat → rhythm head/throat`, ce mécanisme ne produit aucun saut : la corde `(…, throat) → (T + 600, throat)` est plate.

[mesuré] E le confirme : plat à 3,000 jusqu'au premier bip, puis descente cubique vers `head`.

## 3. Un second saut, même racine, à l'entrée de la tenue

[mesuré] Scénario C (`rhythm mid/throat 90 → hold full → rhythm head/throat 120`) : à 2607 ms, 606 ms après l'application de la tenue, le curseur passe de 3,995 à 2,693 (−1,3 rangée), puis remonte en cubique jusqu'à 4,000 atteint à 3174 ms.

[déduit] Même racine : un recalcul tombé dans la dernière milliseconde du pont (`now < last` de moins de 1 ms) garde l'origine `(frozenAt, 2,497)` (l. 718-719) mais ne pose pas le point d'arrivée du pont (`addBridgePoint`, l. 741 : `dtMs > 0` faux quand `inMilliseconds` tronque à 0) ; le premier point futur devient la frontière suivante `(4000, full)` et le curseur est posé sur la cubique `(2001, 2,497) → (4000, 4)` à p = 0,30, soit 2,66.

[déduit] Probabilité faible (une fenêtre d'environ 1 ms par pont), mais c'est le même code, et la reptation dure ensuite jusqu'au recalcul suivant (567 ms ici).

## 4. Ce que la sonde a mesuré

[mesuré] Traces des six scénarios :
| Scénario | Tenue | Rebuild après `applyStep` | Résultat |
|---|---|---|---|
| A | full 2 s | immédiat | continu : 4→3 linéaire en 600 ms, 1er bip `throat` à +611 ms, puis 3→1 cubique |
| B | full 2 s | +200 ms | **saut −0,65** à T + 113 ms, avant le rebuild et avant le 1er bip |
| C | mid/throat 90 → full 2 s → head/throat 120 | immédiat | **saut −1,3** à la fin du pont d'entrée de la tenue ; la sortie de tenue est continue |
| D | full 6 s | +100 ms | continu |
| E | throat 6 s | +100 ms | continu (plat, puis 3→1) |
| F | full 6 s | immédiat | continu |

[mesuré] Dans les six scénarios, le premier bip du rythme tombe 604 à 630 ms après `applyStep` (gap annoncé 600 ms) et les suivants à 500 ± 10 ms : le moteur tient sa promesse, comme le 21/08.

[mesuré] Vitesse maximale hors saut : 0,44 à 0,51 rangée par échantillon (~40 ms) au milieu de la descente `throat → head` à 120 BPM.

[déduit] C'est la pente de `easeInOutCubic` (3 × 2 rangées / 500 ms), pas un défaut — mais à 120 BPM deux rangées en 500 ms peuvent se lire comme un saut à l'œil.

## 5. Ce qui est éliminé, et comment

[mesuré] Le pont tenue → rythme lui-même : continu dans A, D et F, dès que le rebuild suit l'application.

[déduit] La position transmise : `hold` range sa cible dans `from` (`step_resolution.dart:45-48`) ; le moteur (`_from`) et l'affichage (`ctrl.currentFrom` → `_beep.currentFrom`, `session_controller.dart:972`) lisent la même valeur, et le générateur n'émet des tenues qu'avec `from: null, to: <position>` (`career_session_generator_rules_hold.dart`, dix sites).

[déduit] La famille : `_familyOf` (l. 473) range `hold` et `rhythm` en `mouth` quelle que soit la position, donc `_bridgeViaTip = false`.

[mesuré] Aucun passage par `tip` dans les six traces.

[déduit] La bascule de `_controller.duration` 1800 ms → battement (l. 181-184) : `_controller.value` n'alimente que `pulseT` ; la position vient de `DateTime.now()` via `_visualIdxNow` et `_scrollBeats`.

[déduit] Le tirage aléatoire `from == to` (`beep_engine.dart:389-395`) : les rythmes du générateur portent tous un `from` explicite (`rules_rhythm.dart`, `punishment_builder.dart`, `position_pickers.dart`) ; après une tenue `full`, `from: head, to: throat` ne déclenche pas le tirage.

[déduit] L'horloge : `elapsed = _stopwatch.elapsed + _timelineOffset` (l. 927) est lue par la prévision et par la condition d'application (`elapsedSeconds`, l. 939) — même base, pas de décalage de frontière.

[déduit] Le layout : `animHeight` ne dépend que de la barre de stamina (`session_screen.dart:1036-1041`), et aucun widget de compte à rebours de tenue n'existe dans le code (`grep showCountdown` vide — la mémoire `feedback_hold_countdown_scope` est périmée sur ce point).

[document] Les deux hypothèses tuées le 21/08 (premier bip en retard ; descente par à-coups sans moteur) restent tuées ; la sonde les recoupe (§4, deux premiers constats).

## 6. Ce que je n'ai PAS pu établir

[mesuré] **Le cas `hold throat → rhythm head/throat`.** E est continu.

[déduit] Soit Manu l'a vu sur `full` seulement, soit le rythme qui suit sa tenue `throat` vise une autre position que `throat` — à lire dans une séance exportée du téléphone, pas à supposer.

[déduit] **La fréquence réelle sur l'appareil.** Elle dépend du retard d'application (tick de 200 ms plus le travail du tick : TTS, stats, caméra) et de la cadence des recalculs ; un δ plus grand sur le S21 rendrait le saut quasi systématique. Je n'ai ni son ni téléphone pour le mesurer.

[déduit] **Que B soit le saut vu par Manu.** C'est une reproduction sur cette machine, sans audio, avec un rebuild différé artificiellement de 200 ms. Le lien avec l'œil de Manu reste une déduction.

[déduit] **Le recalcul lui-même.** Je n'ai pas posé de compteur dans `_recompute` ; l'attribution « un recalcul est tombé dans la fenêtre » repose sur la coïncidence 3,233 lu / 3,242 prédit, pas sur un log.

## 7. Rejouer la sonde

[mesuré] Sonde jetable `test/probe_hold_to_rhythm_together_test.dart`, retirée de l'arbre après usage (copie non versionnée dans le scratchpad de la session). Principe : `BeepEngine` réel initialisé par `await tester.runAsync(beep.init)` ; chaque `applyStep(...).ignore()` lancé dans `tester.runAsync` pour que ses `Timer` soient réels ; `MovementAnimation` monté avec les getters du moteur et `resolveUpcomingMovementSteps`, comme `session_screen.dart:1119-1142` ; rebuild « tick » toutes les 200 ms, `pump(16 ms)` entre deux ; position du curseur lue sur le `Align` du curseur (même lecteur que `movement_animation_step_serial_test.dart`). Les tests « échouent » par des `MissingPluginException` rapportées après coup ; les traces sont dans la sortie (`print`). Huit secondes environ par scénario de 6 s ; échantillons espacés de 30 à 75 ms selon la charge de la machine.

## 8. Limites

[mesuré] Pas de carte son, pas de téléphone : rien n'a été vu ni entendu. Tout le « son » est la date des `BeatEvent` ; toute l'« image » est la position du curseur lue dans l'arbre de widgets. La conclusion tient par la lecture de `_scrollBeats` et par deux coïncidences numériques (3,242 / 3,233 ; 2,66 / 2,69).

## 9. Pour la suivante — rien n'est corrigé ici

[déduit] Deux directions, au choix de qui corrige : que `_scrollBeats` parte de la position d'ancrage calculée (`beats.first.idx`) quand `deltaT == 0` ; ou que `_computeFutureBeats` donne à l'ancre une origine fraîche (le point de frontière ou de plateau passé) plutôt qu'un bip synthétique vieux de toute la tenue. Une sonde rouge existe de fait (scénario B avec `expect(Δ par échantillon < 0,3)`), mais elle est intermittente ; la rendre déterministe demande de forcer un recalcul dans la fenêtre — à prouver rouge pour la bonne raison avant de la garder.

## État de reprise

[mesuré] Aucune modification de `lib/` ni de `test/` ; l'arbre est celui de `8f69949`. Compteur à la rédaction : ~175 000 jetons sur 250 000.
