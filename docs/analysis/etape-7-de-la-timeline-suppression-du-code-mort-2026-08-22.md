# Étape 7 de la timeline — suppression du code mort

*Écrit le 2026-08-22, branche `fix/courbe-continuite-visuelle`, à partir de `2a26f98`. Dernière étape
du chantier « timeline source unique » (`~/vault/specs/timeline_source_unique.md`, lignes 373-384).*

**Règle de l'étape : aucun comportement ne change.** Une seule chose supprimée — un paramètre inerte.
Les deux cibles nommées par la spec ne sont pas mortes, ou l'étaient déjà.

---

## 1. Les trois cibles

### `resolveUpcomingMovementSteps` — VIVANTE, conservée

La spec la donnait supprimable « si totalement remplacée par la timeline partagée ». Elle ne l'est
pas : l'étape 3 (`6dcdd2c`) a extrait la règle commune dans `step_resolution.dart`, et le résolveur
**appelle** cette fonction au lieu de la dupliquer. Il garde en propre la boucle (filtrage
text-only / steps passés, report de `mode`/`from`/`bpm` d'un step au suivant, calcul du
`transitionGap`).

```
lib/screens/session_screen.dart:1136       ← appelant de production
test/challenge_timeline_forecast_test.dart:199
test/movement_trajectory_continuity_test.dart:536,559,582,603
```

Un appelant de production et six appels de test. Supprimer sur la foi de la spec aurait cassé
l'annonce des steps à venir.

### `prevIdx` / `lastIdx` / `lastDir` / `candidateDir` — déjà supprimées par `44df1e1`

- `lastIdx`, `lastDir`, `candidateDir` : **zéro occurrence** dans `lib/` et `test/`. `44df1e1`
  (« supprimer l'hésitation entre deux destinations ») les a retirées de `_computeFutureBeats` en
  même temps que la visée alternée qu'elles servaient. La spec, écrite avant, les croyait encore là.
- `prevIdx` : **vivant**, mais ce n'est pas la même variable. Celui d'aujourd'hui
  (`movement_animation.dart:1101`) est local à `_scrollBeats`, introduit plus tard, et lu deux fois
  (lignes 1108 et 1112) pour décider de l'amortissement et calculer `anchorIdx`. Conservé.

Le seul `_candidateDirs` restant est dans `tts_service.dart` — les répertoires de voix Piper, aucun
rapport.

### `currentTo` — MORT, supprimé (`0b7fcfe`)

Troisième cible, non citée par la spec, signalée par la fiche `tss2-005` du sas. **Rejoué et
confirmé.**

`resolveStepConfig` retourne `to: step.to` **inconditionnel** ; `to = resolved.to;` s'exécute au début
de chaque itération, avant toute lecture de `to`. Ou bien la boucle tourne et la valeur d'entrée est
écrasée, ou bien elle ne tourne pas et la fonction rend une liste vide. Aucun chemin ne lit
`currentTo`.

Deux tests le prouvaient déjà sans qu'on l'ait lu ainsi : avec `currentTo: Position.head`, ils
attendent `result[0].to == Position.throat` puis `result[1].to == isNull`.

**Une nuance à porter au dossier** : ce paramètre était **déjà mort sur `origin/develop`** — `to =
step.to;` y était tout aussi inconditionnel. Ce n'est donc pas un mort *produit* par ce chantier,
mais un mort *déplacé* par lui derrière `resolveStepConfig`. Il est retiré ici sur mandat explicite,
pas au titre de la règle « ne supprimer que ce que le chantier a tué ».

Portée du retrait : la signature, l'appel de `session_screen.dart`, cinq arguments de test. Le
docstring qui promettait d'hériter `to` est corrigé — il était faux avant comme après.
`ctrl.currentTo` reste utilisé ailleurs (`session_screen.dart:1071,1121`, `session_controller.dart`) :
rien n'est orphelin en amont.

### Balayage complémentaire

Les six sondes `@visibleForTesting` de `movement_animation.dart` (`computeFutureBeatsForTest`,
`scrollBeatsForTest`, `sameGeometryForTest`, `GeometryKeyForTest`, `anchorAfterScrollForTest`,
`extrapolatedElapsed`) ont chacune au moins un test appelant. `flutter analyze` propre garantit par
ailleurs qu'aucun élément privé n'est inutilisé dans `lib/`.

## 2. Vérification

Depuis `rhythm_coach/` : `flutter pub get` ✓ · `flutter analyze` → **No issues found!** ·
`flutter test` → **1097 tests verts**, exactement le compte d'avant · `dart format` → 0 fichier
changé. Le compte identique est ici le point important : rien n'a disparu de la suite.

---

## 3. Second livrable — les correctifs de la branche sans sonde

*Demandé parce que `44ac50b` avait corrigé le cœur d'un défaut sans laisser de test, si bien que la
spec écrite après lui l'ignorait — d'où une étape entière planifiée sur un défaut déjà mort.*

**Méthode** : les 23 commits `fix(...)` de `git log origin/develop..HEAD`, jugés **par lecture** sur
l'état actuel du dépôt (pas sur l'état au moment du commit : un fix peut avoir reçu sa sonde plus
tard). Pour chacun : combien de ses lignes ajoutées survivent dans `HEAD`, et une assertion existante
tomberait-elle si on défaisait la règle. **Aucune sonde n'a été écrite, aucun commit n'a été muté.**

| Commit | Sujet | Survie | Sonde |
|---|---|---|---|
| `52893b5` | écrire tip→head là où le moteur relevait `from` | — | **gardé** — `content_from_equals_to_test.dart`, même commit |
| `4f92c0c` | attente de confirmation aux rebases de timeline | — | **gardé** — `posture_await_ready_rebase_test.dart`, même commit |
| `b2ec4fe` | voir le silence d'un step réappliqué à l'identique | — | **gardé** — `movement_animation_step_serial_test.dart`, même commit |
| `0b618a5` | borner l'extrapolation de l'horloge | — | **gardé** — « extrapolation entre deux ticks est bornée à un tick » |
| `ce5f515` | poser à la frontière la position atteinte | — | **gardé** — sondes de frontière, même commit |
| `5792bb8` | tenir la position d'une tenue jusqu'à la frontière | — | **gardé** — « une tenue garde sa position jusqu'à… » |
| `3fb2de7` | interpoler depuis le début du segment | — | **gardé** — sondes d'interpolation, même commit |
| `1193aba` | faire tenir le passage par le bout dans le silence | — | **gardé** — « le passage par tip tient dans le gap » |
| `a8ef5da` | prolonger le pont par son bip synthétique | — | **gardé** — sondes de pont, même commit |
| `6d778ea` | poser l'arrivée du pont comme point de la courbe | — | **gardé** — idem |
| `8453461` | faire jouer au pont la trajectoire annoncée | — | **gardé** — « pont de transition : … la trajectoire annoncée » |
| `9554682` | mémoïsation/défilement (commit de test) | — | **gardé** — c'est lui-même la sonde |
| `44ac50b` | garder la grille du battement au rattrapage | 8/8 | **gardé — rétroactivement**, par `2a26f98` : « deux recalculs successifs posent les points aux mêmes instants » |
| `cf70354` | n'amortir que sur un changement de sens | 7/9 | **gardé — rétroactivement** : « sur un trajet continu…, [interpolation] linéaire » + « à frac=0.25 sur un extremum, easeInOutCubic diverge » |
| `19db607` | unifier le ladder de trajectoire | 97/137 | **gardé** — fondation de `_computeFutureBeats`, que tout `movement_trajectory_continuity_test.dart` exerce |
| `86ec18d` | fusionner le curseur sur le premier point | 16/21 | **gardé** — sondes d'ancrage réalignées par `eee38a0` |
| `05b25cd` | ladder-mapper l'ancre gelée de transition | 28/28 | **incertain** — `frozenIdx`/`frozenAt` sont exercés par les sondes, mais aucune n'isole le mapping de l'ancre |
| `44df1e1` | supprimer l'hésitation entre deux destinations | 5/5 | **incertain, penchant gardé** — « le 1er bip du step suivant tombe sur `to` » contredit la visée alternée, mais seulement si le scénario remplit `segFrom≠segTo && newFrom≠newTo` avec le même sens |
| `5799bed` | recompléter la fenêtre par la droite | 14/14 | **non gardé** — le drapeau `_windowUnfillable` et le rappel de `_recompute()` vivent dans `_PositionLadderState.build` ; les sondes de scroll testent la fonction pure `scrollBeatsForTest`, et les tests qui montent le widget ne pompent pas assez de frames pour vider la fenêtre par la droite |
| `a02694e` | ne rien annoncer pendant un défi | 9/15 | ⚠️ **non gardé** — voir ci-dessous |
| `22a6cd8` | ne rien annoncer tant que l'horloge est gelée | 8/14 | ⚠️ **à moitié** — voir ci-dessous |
| `d17fda8` | prédire la position que le moteur jouera | 1/6 | **sans objet** — annulé par le revert `6bb44f8` |
| `3e1bcf9` | prédire l'alternance avec la règle du moteur | 0/33 | **sans objet** — annulé par le revert `6bb44f8` |

### Le trou qui mérite d'être nommé : le câblage de la garde de gel

`a02694e` et `22a6cd8` corrigent **la même ligne** — la garde de `session_screen.dart:1136` :

```dart
upcomingSteps: ctrl.isTimelineFrozen ? const [] : resolveUpcomingMovementSteps(…)
```

`challenge_timeline_forecast_test.dart` a été écrit pour ce défaut (`38b814e`) et il est solide — mais
il asserte `ctrl.isTimelineFrozen` et la forme de la courbe brute, et il **reconstitue** l'appel du
résolveur dans un helper `_rawForecast` au lieu de monter l'écran. Son propre commentaire le dit :
« celle que `session_screen.dart` n'annonce que quand l'horloge tourne ».

Conséquence : **supprimer le ternaire ne ferait rougir aucun test.** La prémisse est gardée (le
résolveur ment pendant un défi, `isTimelineFrozen` vaut bien `true`), le câblage ne l'est pas. Aucun
test du dépôt ne monte `SessionScreen` hors de
`session_finished_duration_render_test.dart`.

`22a6cd8` est à moitié couvert parce qu'il a aussi introduit le getter `isTimelineFrozen` dans
`session_controller.dart`, et **ce getter, lui, est bien asserté** (trois `expect`).

C'est le motif « fonction pure testée, câblage nu ». Il n'est pas comblé ici : le mandat de cette
étape excluait explicitement d'écrire des sondes.
