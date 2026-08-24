# Étape 7 de la timeline — suppression du code mort

*Écrit le 2026-08-22, branche `fix/courbe-continuite-visuelle`, à partir de `4315c67`. Dernière étape
du chantier « timeline source unique » (`~/vault/specs/timeline_source_unique.md`, lignes 373-384).*

**Règle de l'étape : aucun comportement ne change.** Une seule chose supprimée — un paramètre inerte.
Les deux cibles nommées par la spec ne sont pas mortes, ou l'étaient déjà.

---

## 1. Les trois cibles

### `resolveUpcomingMovementSteps` — VIVANTE, conservée

La spec la donnait supprimable « si totalement remplacée par la timeline partagée ». Elle ne l'est
pas : l'étape 3 (`1ca2ca6`) a extrait la règle commune dans `step_resolution.dart`, et le résolveur
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

### `prevIdx` / `lastIdx` / `lastDir` / `candidateDir` — déjà supprimées par `d95a5ae`

- `lastIdx`, `lastDir`, `candidateDir` : **zéro occurrence** dans `lib/` et `test/`. `d95a5ae`
  (« supprimer l'hésitation entre deux destinations ») les a retirées de `_computeFutureBeats` en
  même temps que la visée alternée qu'elles servaient. La spec, écrite avant, les croyait encore là.
- `prevIdx` : **vivant**, mais ce n'est pas la même variable. Celui d'aujourd'hui
  (`movement_animation.dart:1101`) est local à `_scrollBeats`, introduit plus tard, et lu deux fois
  (lignes 1108 et 1112) pour décider de l'amortissement et calculer `anchorIdx`. Conservé.

Le seul `_candidateDirs` restant est dans `tts_service.dart` — les répertoires de voix Piper, aucun
rapport.

### `currentTo` — MORT, supprimé (`2b5b9a3`)

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

*Demandé parce que `027527d` avait corrigé le cœur d'un défaut sans laisser de test, si bien que la
spec écrite après lui l'ignorait — d'où une étape entière planifiée sur un défaut déjà mort.*

**Méthode** : les 23 commits `fix(...)` de `git log origin/develop..HEAD`, jugés **par lecture** sur
l'état actuel du dépôt (pas sur l'état au moment du commit : un fix peut avoir reçu sa sonde plus
tard). Pour chacun : combien de ses lignes ajoutées survivent dans `HEAD`, et une assertion existante
tomberait-elle si on défaisait la règle. **Aucune sonde n'a été écrite, aucun commit n'a été muté.**

| Commit | Sujet | Survie | Sonde |
|---|---|---|---|
| `cbbb282` | écrire tip→head là où le moteur relevait `from` | — | **gardé** — `content_from_equals_to_test.dart`, même commit |
| `e684c3f` | attente de confirmation aux rebases de timeline | — | **gardé** — `posture_await_ready_rebase_test.dart`, même commit |
| `c5aa1e6` | voir le silence d'un step réappliqué à l'identique | — | **gardé** — `movement_animation_step_serial_test.dart`, même commit |
| `6db535c` | borner l'extrapolation de l'horloge | — | **gardé** — « extrapolation entre deux ticks est bornée à un tick » |
| `64b216d` | poser à la frontière la position atteinte | — | **gardé** — sondes de frontière, même commit |
| `f4066de` | tenir la position d'une tenue jusqu'à la frontière | — | **gardé** — « une tenue garde sa position jusqu'à… » |
| `10e4b94` | interpoler depuis le début du segment | — | **gardé** — sondes d'interpolation, même commit |
| `270fc53` | faire tenir le passage par le bout dans le silence | — | **gardé** — « le passage par tip tient dans le gap » |
| `3a9bfb1` | prolonger le pont par son bip synthétique | — | **gardé** — sondes de pont, même commit |
| `69838e2` | poser l'arrivée du pont comme point de la courbe | — | **gardé** — idem |
| `a47433a` | faire jouer au pont la trajectoire annoncée | — | **gardé** — « pont de transition : … la trajectoire annoncée » |
| `7713526` | mémoïsation/défilement (commit de test) | — | **gardé** — c'est lui-même la sonde |
| `027527d` | garder la grille du battement au rattrapage | 8/8 | **gardé — rétroactivement**, par `4315c67` : « deux recalculs successifs posent les points aux mêmes instants » |
| `0913c42` | n'amortir que sur un changement de sens | 7/9 | **gardé — rétroactivement** : « sur un trajet continu…, [interpolation] linéaire » + « à frac=0.25 sur un extremum, easeInOutCubic diverge » |
| `2d620f8` | unifier le ladder de trajectoire | 97/137 | **gardé** — fondation de `_computeFutureBeats`, que tout `movement_trajectory_continuity_test.dart` exerce |
| `4028c72` | fusionner le curseur sur le premier point | 16/21 | **gardé** — sondes d'ancrage réalignées par `2b470cd` |
| `d49ceda` | ladder-mapper l'ancre gelée de transition | 28/28 | **incertain** — `frozenIdx`/`frozenAt` sont exercés par les sondes, mais aucune n'isole le mapping de l'ancre |
| `d95a5ae` | supprimer l'hésitation entre deux destinations | 5/5 | **incertain, penchant gardé** — « le 1er bip du step suivant tombe sur `to` » contredit la visée alternée, mais seulement si le scénario remplit `segFrom≠segTo && newFrom≠newTo` avec le même sens |
| `aae077d` | recompléter la fenêtre par la droite | 14/14 | **non gardé** — le drapeau `_windowUnfillable` et le rappel de `_recompute()` vivent dans `_PositionLadderState.build` ; les sondes de scroll testent la fonction pure `scrollBeatsForTest`, et les tests qui montent le widget ne pompent pas assez de frames pour vider la fenêtre par la droite |
| `2723163` | ne rien annoncer pendant un défi | 9/15 | ⚠️ **non gardé** — voir ci-dessous |
| `c498420` | ne rien annoncer tant que l'horloge est gelée | 8/14 | ⚠️ **à moitié** — voir ci-dessous |
| `ce676eb` | prédire la position que le moteur jouera | 1/6 | **sans objet** — annulé par le revert `3be2722` |
| `bf17123` | prédire l'alternance avec la règle du moteur | 0/33 | **sans objet** — annulé par le revert `3be2722` |

### Le trou qui mérite d'être nommé : le câblage de la garde de gel

`2723163` et `c498420` corrigent **la même ligne** — la garde de `session_screen.dart:1136` :

```dart
upcomingSteps: ctrl.isTimelineFrozen ? const [] : resolveUpcomingMovementSteps(…)
```

`challenge_timeline_forecast_test.dart` a été écrit pour ce défaut (`1f13b21`) et il est solide — mais
il asserte `ctrl.isTimelineFrozen` et la forme de la courbe brute, et il **reconstitue** l'appel du
résolveur dans un helper `_rawForecast` au lieu de monter l'écran. Son propre commentaire le dit :
« celle que `session_screen.dart` n'annonce que quand l'horloge tourne ».

Conséquence : **supprimer le ternaire ne ferait rougir aucun test.** La prémisse est gardée (le
résolveur ment pendant un défi, `isTimelineFrozen` vaut bien `true`), le câblage ne l'est pas. Aucun
test du dépôt ne monte `SessionScreen` hors de
`session_finished_duration_render_test.dart`.

`c498420` est à moitié couvert parce qu'il a aussi introduit le getter `isTimelineFrozen` dans
`session_controller.dart`, et **ce getter, lui, est bien asserté** (trois `expect`).

C'est le motif « fonction pure testée, câblage nu ». Il n'est pas comblé ici : le mandat de cette
étape excluait explicitement d'écrire des sondes.
