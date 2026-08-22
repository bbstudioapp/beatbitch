---
type: analyse
sujet: reparation-du-saut-du-curseur-en-sortie-de-tenue
ecrit_le: 2026-08-22T21:56:08+02:00
auteur: session tss2-fix-saut-tenue · claude-opus-5
revision: 75524e8
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/movement_trajectory_hold_exit_test.dart
provenance:
  mesure: 12
  deduit: 15
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:939
  - rhythm_coach/lib/widgets/movement_animation.dart:1105
  - rhythm_coach/lib/widgets/movement_animation.dart:1298
  - rhythm_coach/lib/widgets/movement_animation.dart:741
  - rhythm_coach/lib/widgets/movement_animation.dart:780
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart:52
---

## 1. Ce que j'ai rejoué avant de corriger

[mesuré] J'ai reconstruit la boucle de `session_screen` dans un test widget jetable : une horloge de
séance réelle, un « tick » toutes les 200 ms qui applique les steps dus et recalcule ensemble
`elapsed` et `upcomingSteps` (comme le fait l'écran), et entre deux ticks des frames de 16 ms sans
changement de props. Scénario `rhythm mid/throat 90 → hold full 2 s → rhythm head/throat 120`,
position du curseur relevée à chaque frame sur l'`Align` du curseur.

[mesuré] Le saut est là : le curseur descend régulièrement de 4,000 à 3,838 entre 10 000 et 10 103 ms,
puis passe à **3,246 en un échantillon de 22 ms** à 10 125 ms — 125 ms après la frontière annoncée et
**20 ms avant** que le step ne soit appliqué.

[mesuré] Il est intermittent : sur quatre relances du même scénario, deux montrent ce saut en sortie
de tenue (0,59 rangée), une montre à la place un saut de 1,42 rangée à l'entrée de la tenue, une ne
montre ni l'un ni l'autre.

[déduit] La cause décrite par l'audit du 22/08 est confirmée par ce rejeu : la valeur lue (3,246) est
celle de la corde qui part du bip synthétique de fin de pont d'entrée, vieux de toute la tenue, et
rejoint le premier point futur `(frontière + 600 ms, throat)`.

## 2. Le maillon que le rapport ne nommait pas : `extrapolatedElapsed`

[déduit] Le rapport laissait ouverte la question de savoir comment une frontière déjà passée peut
rester dans `upcomingSteps`. `resolveUpcomingMovementSteps` retire un step dès que
`step.time <= elapsed.inSeconds`, et `boundaryAt` le situe à `now + (startSecond × 1000 − elapsedMs)` :
au moment d'un rebuild de l'écran, les deux coïncident exactement et la frontière est toujours dans
le futur.

[déduit] Ce qui ouvre la fenêtre, c'est `extrapolatedElapsed` (`movement_animation.dart:1298-1310`) :
entre deux notifications du contrôleur, l'horloge de séance vue par la trajectoire avance en temps
réel — bornée à 250 ms — pendant que `upcomingSteps`, figé avec les props du dernier rebuild, contient
encore le step franchi. La fenêtre n'existe donc **qu'entre deux rebuilds de l'écran**, et seul un
recalcul déclenché sans rebuild — la garde de remplissage de `_PositionLadder.build` — peut y tomber.
C'est ce qui rend le saut intermittent.

## 3. La direction choisie

[document] Le §9 de l'audit proposait deux directions : faire partir `_scrollBeats` de la position
d'ancrage calculée (`beats.first.idx`) quand `deltaT == 0`, ou donner à l'ancre une origine fraîche.

[déduit] J'ai écarté la première. Elle ne corrige que la frame du recalcul : à `deltaT == 0` le curseur
vaudrait 4,000, et dès la frame suivante `_scrollBeats` re-dérive de nouveau depuis l'origine périmée
et le repose à 3,24. Le saut ne serait pas supprimé, seulement retardé d'une frame — et rendu plus
brutal, puisqu'il partirait alors de la bonne valeur.

[déduit] J'ai pris la seconde, sous une forme un peu plus large que « le point de frontière » :
`_computeFutureBeats` retient le **dernier repère de la trajectoire tombé dans le passé** — celui que
`addPoint` refuse de poser (`:780`, `dtMs < 0`) ou celui que `addBridgePoint` laisse tomber
(`:741`, `dtMs > 0` faux) —
et le donne comme origine à l'ancre, à condition qu'il soit postérieur à l'origine courante. Le curseur
est alors interpolé entre le dernier point réellement franchi et le premier point à venir, ce que la
géométrie mémoïsée faisait déjà d'elle-même une fois ce point sorti par la gauche.

[déduit] La propriété visée n'est pas « le curseur reste sur `full` » mais « **un recalcul ne déplace
pas le curseur** » : c'est elle qui vaut pour tous les plateaux, et c'est elle que la sonde vérifie.

## 4. La preuve rouge

[mesuré] Sonde 1 — sortie de tenue (`movement_trajectory_hold_exit_test.dart`, premier test). Elle
compare deux lectures du **même instant** : la position rendue par une géométrie calculée 200 ms plus
tôt, quand la frontière était encore 50 ms dans le futur, et celle rendue par un recalcul au même
instant, quand la frontière est 150 ms dans le passé. Sur le code d'avant :

```
Expected: a numeric value within <0.05> of <3.75>
  Actual: <3.2432432432432434>
   Which: differs by <0.5067567567567566>
le recalcul repose le curseur ailleurs que là où la géométrie précédente l'affichait
```

[déduit] 3,2432 est exactement la valeur du rejeu bout-en-bout (3,246) et de la prédiction de l'audit
(3,242) : les trois chemins tombent sur la même corde.

[mesuré] Sonde 2 — entrée de tenue (second test du même fichier). Sur le code d'avant :

```
Expected: a numeric value within <0.05> of <4.0>
  Actual: <2.693023981607519>
   Which: differs by <1.306976018392481>
le curseur retombe sur la corde qui part du gel de transition au lieu de rester sur l'arrivée du pont
```

[déduit] 2,693 est au millième la valeur relevée par l'audit pour ce cas (§3).

[mesuré] Les deux sondes sont déterministes : la première ne dépend d'aucune horloge réelle, la
seconde balaie la fenêtre de troncature d'une milliseconde par pas de 50 µs plutôt que de parier sur
l'instant d'exécution. Les deux sont vertes après la correction.

## 5. Ce que la correction change, mesuré bout en bout

[mesuré] Rejeu du scénario complet, saut maximal entre deux échantillons consécutifs, en sortie de
tenue (fenêtre 9,9–10,5 s) : avant, sur quatre relances, 0,041 · 0,590 · 0,041 · 0,592 ; après, sur
six relances, 0,042 · 0,044 · 0,043 · 0,041 · 0,046 · 0,042.

[mesuré] Même relevé à l'entrée de la tenue (fenêtre 8,0–8,4 s) : avant, 0,253 · 0,201 · 1,417 ·
0,183 ; après, 0,179 · 0,240 · 0,181 · 0,170 · 0,098 · 0,198.

[déduit] Le résiduel de 0,04 rangée par échantillon en sortie de tenue est la pente normale de la
descente `full → throat` en 600 ms, pas un saut.

[mesuré] Cas d'entrée isolé, en balayant la fenêtre de troncature : 2,693 avant, 4,000 après, sur les
17 points du balayage.

[mesuré] Suite complète : 1099 tests verts (1097 de référence plus les deux sondes), `flutter analyze`
rend « No issues found! ».

## 6. Le moteur de bips n'est pas touché

[mesuré] Aucune ligne de `beep_engine.dart` n'est modifiée. La correction tient dans
`_computeFutureBeats` et n'a d'effet que sur l'origine d'interpolation du curseur.

[déduit] Rien dans le chemin corrigé ne touche à la date des `BeatEvent` ni au démarrage des boucles :
`_computeFutureBeats` lit `lastBeatAt` et `bridgeGap`, il ne les écrit pas.

## 7. Ce que je n'ai PAS pu établir

[déduit] **Que ce soit le saut que Manu voit.** Comme l'audit, je n'ai ni téléphone ni carte son. La
chaîne « corde mesurée dans un test → orbe qui saute à l'œil » reste une déduction. Ce qui est nouveau,
c'est que la mesure est maintenant reproduite par trois chemins indépendants qui donnent la même valeur.

[déduit] **La fréquence réelle sur l'appareil.** Elle dépend de la cadence des recalculs de la garde de
remplissage et de l'écart entre deux rebuilds de l'écran, tous deux liés à la charge du S21. Mes
relances donnent une sortie de tenue affectée dans la moitié des cas sur cette machine ; ce chiffre ne
transporte pas.

[mesuré] **Le cas d'une tenue à la gorge.** Non traité : la corde `(…, throat) → (frontière + 600,
throat)` est plate, donc ce mécanisme ne produit aucun saut là, et mon rejeu n'en montre pas. Si Manu
en voit un après une tenue `throat`, il vient d'ailleurs et cette correction ne le referme pas.

[déduit] **Un saut de deux rangées vu dans mon rejeu, à ~1,2 s après l'entrée du rythme.** Il est
présent avant comme après la correction. Ma sonde ne fournit pas de `BeepEngine`, donc `lastBeatAt`
reste nul et `_flipped` est piloté par le cycle de l'`AnimationController` interne
(`_isExternallyDriven` faux) : chaque bascule change `_sameGeometry` et inverse `from`/`to` d'un coup.
En séance l'écran fournit toujours le moteur et `_flipped` bascule sur `BeatEvent`, en même temps que
`lastBeatAt`. Je le tiens donc pour un artefact de ma sonde, sans l'avoir prouvé — je n'ai pas remonté
de moteur réel pour le vérifier.

[déduit] **`beats.first.idx` (`yNow`) n'est lu par aucun affichage.** `originIdx` est toujours renseigné,
donc `_scrollBeats` prend systématiquement la branche qui l'ignore ; seul `computeFutureBeatsForTest`
l'observe. C'était déjà vrai avant cette correction, qui ne l'aggrave ni ne le répare. À signaler, pas
à nettoyer ici.

## 8. Portée

[déduit] La correction est générale à tout plateau dont l'origine d'ancre vieillit sans `BeatEvent`
pour la rafraîchir — `hold`, `beg`, `suckle`, `biffle`, `breath`, `freestyle` — et à tout pont dont
l'arrivée tombe sous la milliseconde. Elle ne change rien quand un point futur existe déjà entre
l'origine et l'instant courant, ce qui est le cas courant en rythme.
