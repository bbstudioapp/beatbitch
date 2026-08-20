---
type: analyse
sujet: relecture-adverse-continuite-de-trajectoire
ecrit_le: 2026-08-20T17:59:50+02:00
auteur: session tss2-animations-relecture · claude-opus-5
revision: 2ffc3e8
branche: feat/movement-trajectory-continuity
porte_sur:
  - docs/analysis/trajectoire-continuite-movement-animation-2026-08-20.md
  - rhythm_coach/lib/career/services/milestone_loader.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
provenance:
  mesure: 28
  deduit: 14
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/milestone_loader.dart:72
  - rhythm_coach/lib/controllers/session_controller.dart:1372
  - rhythm_coach/lib/controllers/session_controller.dart:927
  - rhythm_coach/lib/screens/session_screen.dart:327
  - rhythm_coach/lib/services/beep_engine.dart:346
  - rhythm_coach/lib/services/beep_engine.dart:415
---

[mesuré] Relecture adverse de `feat/movement-trajectory-continuity` (3 commits au-dessus de
`origin/develop` = `7dc9746`) : `7da60d2` le code, `23a11d4` le rapport de l'auteur,
`6ec7811` le redressement des familles par l'orchestrateur. Consigne : chercher à réfuter.
Deux des pistes qui m'étaient données se réfutent par la mesure, une troisième était sous-estimée
et devient le constat principal.

## Ce qui passe

[mesuré] Depuis `rhythm_coach/`, sur `2ffc3e8` (mon commit de nettoyage, cf. plus bas) :
`flutter analyze` → `No issues found!` ; `timeout 1500 flutter test` → `1023 tests, All tests
passed!`, exit 0, sortie redirigée vers un fichier (jamais pipée) ; `dart format
--set-exit-if-changed lib test` → exit 0, `294 files (0 changed)`. Le chiffre de 1023 annoncé par
`6ec7811` est bon ; celui de 1021 du rapport `23a11d4` est celui d'avant `6ec7811`.

[mesuré] La décision 4 (« affichage seulement ») tient : `git diff --stat 7dc9746 HEAD` ne touche
côté code que `lib/screens/session_screen.dart` (+11, le seul point d'intégration),
`lib/widgets/movement_animation.dart` et le nouveau `lib/widgets/movement_trajectory_forecast.dart`.
Ni `BeepEngine`, ni `SessionController`, ni le générateur de séances, ni le calcul de durée.

### Les tests discriminent — vérifié en remettant le code d'avant

[mesuré] Les 2 tests de `6ec7811` rejoués sur l'ancien classement de familles (`_familyOf` de
`7da60d2` restauré) : 2 échecs, aux bons endroits — `lick est hors de la famille bouche` et
`suckle head reste dans la famille bouche, suckle balls en sort`, tous deux sur `Expected: true /
Actual: <false>` (le passage par `tip` attendu et absent). Le vice de la première écriture (vérifier
un passage par `tip` sur un step qui part déjà de `tip`) n'a pas de récidive : aucun des scénarios
n'emploie `tip`, ni au départ ni à l'arrivée, donc un point à `tip` ne peut venir que de la
frontière de famille.

[mesuré] Les 4 tests de `_computeFutureBeats` qui dépendent d'`upcomingSteps` rejoués sur le code
d'avant (`movement_animation.dart` de `7dc9746`, avec la seule sonde `computeFutureBeatsForTest`
greffée en passthrough) : 4 rouges, 4 verts — les 3 tests de `resolveUpcomingMovementSteps` (fichier
neuf, indépendant) et le test de rétrocompatibilité.

[déduit] Une nuance sur le test `suckle` : sa première assertion (`head` ⇒ pas de `tip`) est verte
dans les deux classements, elle ne discrimine pas contre l'ancien. C'est la seconde (`balls` ⇒
`tip`) qui porte la preuve. Prises ensemble les deux assertions épinglent bien la dépendance à la
position, ce qui est l'objet du commit.

### La rétrocompatibilité n'est pas une promesse, elle est mesurée

[mesuré] J'ai dumpé la sortie de `_computeFutureBeats` sur 6 480 combinaisons (3 modes à ladder ×
6 `from` × 6 `to` × 6 BPM {20, 45, 60, 90, 140, 300} × 2 `flipped` × 5 délais depuis le dernier
beat), `upcomingSteps` vide, une fois sur le code actuel et une fois sur celui de `7dc9746` :
**0 séquence de positions divergente, 0 différence de nombre de points**. Le seul écart porte sur
26 cas où un `t` bascule d'un cran de 50 ms — imputable à `DateTime.now()`, que le calcul lit deux
fois entre les deux exécutions (le point d'ancrage en dépend aussi). La rétrocompatibilité annoncée
est réelle.

[déduit] Elle se lit aussi dans le code : la boucle de rattrapage des beats déjà passés a été
remplacée par un `addPoint` qui rend `true` sans rien ajouter quand `dtMs < 0`, ce qui produit la
même suite. `upcomingSteps` vide ⇒ `nextBoundary` reste `null` ⇒ la branche de frontière n'est
jamais prise.

### Le résolveur est fidèle au moteur sur tout ce qu'il réplique

[déduit] Comparé ligne à ligne à `BeepEngine.applyStep` (`beep_engine.dart:346`) :
`isTextOnly` ignoré, `mode = step.mode ?? defaultMode`, `bpm` sticky, `from` sticky sauf pour
`hold`/`beg`/`suckle` qui le prennent dans `step.to`, `to` jamais sticky. Identique.

[mesuré] Le premier bip d'un nouveau step tombe sur `to` — mesuré sur le vrai `BeepEngine` :
`premier beat SessionMode.rhythm/Position.throat` pour un step `head→throat`. Le résolveur pose
`nextPos = segTo` à la frontière : même chose.

### Les gels d'exécution : la piste se réfute

[déduit] Les gels cités par la consigne et par le rapport (gate posture, défi, breath post-défi,
report TTS) sont tous implémentés en décrémentant `_timelineOffset` d'un tick à chaque tick
(`session_controller.dart:1372` et `:1549`). Or `elapsed = _stopwatch.elapsed + _timelineOffset`
(`:927`) et la frontière est calculée `now + (startSecond × 1000 − elapsedMs)` : pendant un gel,
`elapsedMs` est figé et `now` avance, donc la frontière prédite reste à distance constante — elle
n'arrive pas, exactement comme le step qu'elle annonce. La prévision suit les gels au lieu de les
ignorer.

[déduit] Le saut de timeline en avant du flow FAIL (`session_controller_fail_flow.dart:495`,
`_timelineOffset += delta`) est repris au rebuild suivant, `afterSecond: ctrl.elapsedSeconds`
filtrant les steps sautés.

[déduit] Ce qui reste vrai : un gel n'est pas **anticipé**. Si un défi va figer 20 s dans une
seconde, la ligne annonce la frontière suivante à sa distance nominale. Hors fenêtre de 3 s la
plupart du temps.

[mesuré] C'est pour ça que j'ai retiré le doc-comment qui annonçait le contraire (cf. `2ffc3e8`) : il faisait
croire à une limite qui n'existe pas, et le rapport de l'auteur l'a reprise comme réserve.

### La performance : la piste se réfute aussi

[mesuré] `resolveUpcomingMovementSteps` appelée 1 151 521 fois (une par seconde de séance sur
1 000 séances de carrière générées, niveaux 1/4/8/14/20, toutes les longueurs) : **2,0 à 2,7 µs par
appel**. La plus grosse séance rencontrée fait 285 steps. Au rythme du `SessionScreen` (tick de
200 ms, 5 rebuilds/s), ça fait de l'ordre de 13 µs de CPU par seconde de séance. Non problématique,
et cette fois mesuré.

[déduit] Reste une inélégance sans conséquence : la fonction résout tous les steps jusqu'à la fin de
la séance alors que seules les 3 premières secondes servent, et alloue jusqu'à 285 objets 5 fois par
seconde. Borner à la fenêtre serait une ligne.

## Le constat principal : le gap de transition du moteur n'est pas modélisé

[mesuré] Sur le vrai `BeepEngine`, le premier bip d'un step n'arrive pas à l'instant où le step est
appliqué :

```
step mode=rhythm -> premier beat rhythm/throat après 305 ms
step mode=rhythm -> premier beat rhythm/full   après 301 ms   (même mode)
step mode=hand   -> premier beat hand/full     après 1502 ms  (changement de mode)
```

[déduit] `applyStep` attend systématiquement avant de démarrer le loop
(`beep_engine.dart:415-428`) : 300 ms si le mode ne change pas (`_sameModeTransitionGap`), 1500 ms
si le nouveau mode demande un changement de geste (`lick`, `hand`, `biffle`, `breath`, `freestyle`,
`suckle`, `beg` libre), 600 ms sinon (`rhythm`, `hold`).

[déduit] `_computeFutureBeats` ne connaît aucun de ces gaps. À une frontière de même famille, il
pose le premier point du nouveau segment **à l'instant nominal de la frontière** ; à une frontière
de famille, il pose `tip` à l'instant nominal puis le premier point un beat plus tard. Dans les deux
cas le décalage avec le moteur va de 300 ms à 1 500 ms, sur une fenêtre de prévision de 3 000 ms.

[mesuré] Ce n'est pas un cas de bord. Sur les mêmes 1 000 séances (107 842 steps de bip) :

[mesuré] Répartition des gaps sur les 107 842 frontières :

| gap réellement appliqué [mesuré] | frontières |
|---|---|
| 300 ms (même mode) | 20 305 |
| 600 ms | 52 452 |
| 1 500 ms | 35 085 |

[mesuré] **55 348 frontières franchissent une frontière de famille** — soit une sur deux — et
**toutes** subissent un gap de 600 ms (26 712) ou 1 500 ms (28 636), jamais 300 ms. Autrement dit :
la remontée à `tip`, qui est précisément ce que Manu a demandé de voir, est annoncée 0,6 à 1,5 s
avant qu'elle ait lieu. [mesuré] 55 026 de ces frontières sont franchies depuis un segment où la
courbe est effectivement affichée.

C'est le seul point qui touche la décision 1 de Manu (« plus de mouvements annoncés qui n'auront pas
lieu ») de façon systématique. Je ne l'ai pas corrigé : le corriger demande soit de dupliquer une
deuxième règle du moteur (`_needsBigGap`) dans l'affichage, soit d'exposer le gap depuis
`BeepEngine` — un arbitrage d'architecture qui n'est pas le mien.

## Ce que le rapport `23a11d4` doit se voir corriger

[mesuré] Le rapport est antérieur à `6ec7811` et décrit un classement qui n'est plus celui du code.
Il écrit « avec la bouche (`rhythm`, `hold`, `beg`, `lick`) » et range `suckle` en bloc du côté
bouche. Le code range aujourd'hui `beg` et `lick` **hors** bouche, et `suckle` selon sa position.
Le message de commit de `7da60d2` porte la même erreur (« rhythm/hold/beg/lick/suckle vs
hand/biffle/breath/freestyle »), mais celui-là est de l'histoire git, on n'y touche pas.

[mesuré] Ses chiffres sont ceux d'avant : « 6 tests », « 1021 tests ». C'est 8 et 1023.

[mesuré] Sa section « Ce que je n'ai pas pu établir » liste comme réserves trois choses que la
mesure tranche : les gels (réfutés), la performance (mesurée négligeable), le cas `from == to`
(jamais produit, cf. plus bas). Elle ne mentionne pas le gap de transition.

C'est le document dont un relecteur pressé recopierait les conclusions. Il doit porter un renvoi
vers celui-ci, ou être redressé.

## Divergences réelles mais non observables

[mesuré] Sur les 107 842 steps de bip résolus des 1 000 séances :

- [mesuré] **`from == to` en `rhythm`/`lick`** (que le moteur corrige au hasard via `_pickShallowerThan`, et
  que le résolveur ne réplique pas) : **0 occurrence**. La divergence est théorique. Si elle se
  produisait, la ligne annoncerait un segment plat là où le moteur alternerait, et l'écart se
  propagerait aux steps suivants puisque le moteur écrit le résultat du tirage dans son `_from`
  sticky.
- **BPM hors des bornes du moteur** (`kMinBpm = 20`, `kMaxBpm = 300`) : **0 occurrence**. Le
  résolveur ne clampe pas là où `applyStep` clampe — une ligne d'écart, sans effet aujourd'hui.
- **Rampes de BPM intra-step** (`bpmEnd != bpm`) : **205 steps**, soit 0,19 %. Sur ceux-là la ligne
  annonce un tempo constant pendant que le moteur rampe. Le caractère sticky du BPM après le step
  est en revanche correctement répliqué (le moteur garde `step.bpm`, pas `bpmEnd`).

## Le classement de `suckle` par la position tient

[mesuré] `resolveUpcomingMovementSteps` donne à `suckle` un `from` issu de `step.to`, comme le
moteur. Il ne reste hérité que si `step.to` est nul — cas que je n'ai trouvé nulle part :
**0 `suckle` sans `to`** sur les 1 000 séances générées, et **0 sur les 6** steps `suckle` des
assets de milestones. Le générateur ne produit d'ailleurs que `head` ou `balls`
(`career_session_generator_rules_suckle.dart:88-95`). La position qui classe est donc toujours la
position effective, à la frontière comme sur le segment courant.

[déduit] Sur le segment courant, la question ne se pose même pas : le ladder n'est monté que pour
`rhythm`, `lick` et `hand` (`movement_animation.dart:270-274`), trois modes dont la famille ne
dépend pas de la position.

[déduit] La fragilité qui reste : `p == Position.head ? mouth : other` range `mid`, `throat` et
`full` hors bouche. C'est sans effet tant que `suckle` ne vise que `head` et `balls` — ce que Manu a
posé (« y a 2 aspire ») et ce que le générateur applique — mais un futur `suckle throat` basculerait
silencieusement du mauvais côté.

[mesuré] Le débordement que je soupçonnais — un step futur à `balls` (index 5) dessiné sur un ladder
à 5 lignes, donc sous le canvas — n'est pas atteignable : `intro_suckle_balls` requiert
`hold_balls`, qui requiert `lick_balls`, et c'est `lick_balls` qui commande `ballsRevealed`
(`session_screen.dart:327-332`). Hors carrière, `ballsRevealed` suit l'anatomie, que le générateur
exige aussi.

## Ce que le correctif ne fait pas, et que personne n'a écrit

[déduit] La courbe **s'éteint à chaque frontière**. `didUpdateWidget` remet `_lastBeatAt = null` dès
que le mode, le tempo ou la position change (`movement_animation.dart:154-157`) ;
`_computeFutureBeats` rend `[]` quand `lastBeatAt` est nul ; l'`AnimatedOpacity` qui porte la
trajectoire passe alors à `opacity: 0` (`:494`), et le painter ne dessine rien sous deux points.
La courbe se rallume au premier bip du nouveau step, donc après le gap ci-dessus. Comportement
préexistant, non introduit par ce travail — mais il borne ce qu'il apporte : la ligne prévoit
correctement la suite **avant** la bascule, elle ne la traverse pas. Le « plus de saut » de la
décision 1 est obtenu en éteignant la ligne, pas en la continuant.

[déduit] La trajectoire n'existe que 68 % du temps de séance — [mesuré] 779 955 s sur 1 151 521 s
passées en `rhythm`/`lick`/`hand`, les seuls modes qui montent le ladder.

## Ce que je n'ai pas pu établir

- **Rien vu en mouvement**, comme l'auteur. [déduit] Le décalage de 0,6–1,5 s est calculé, pas
  observé à l'œil. Aucune de mes mesures ne dit ce que ça donne à l'œil :
  ni la lisibilité de la remontée à `tip`, ni si le décalage de 0,6–1,5 s se remarque, ni si le
  fondu à chaque frontière gêne. Il faut une séance jouée sur appareil pour trancher, et c'est
  peut-être ce qui décidera si le constat principal mérite un correctif.
- **Le gap de 600 ms n'est pas mesuré directement.** J'ai mesuré 305 ms et 1502 ms sur le vrai
  moteur ; les 600 ms sont lues dans le même bloc de code (`_modeTransitionGap`) et comptées par
  simulation de `_needsBigGap`, pas observées.
- **Les séances hors carrière** (Custom, Utilise-moi, Musique, scénarios de debug) ne sont pas dans
  mes 1 000 séances. Les chiffres de fréquence ci-dessus valent pour la carrière ; les mécanismes
  (gap, familles, résolution) sont les mêmes puisque le moteur est le même.
- **Le comportement quand deux steps de bip partagent la même seconde** est raisonné, pas observé :
  je n'en ai trouvé aucun (0 sur 107 842) ni aucun step dans le désordre.
- **Le `chainAction`** est déplié en deux `SessionStep` au chargement
  (`milestone_loader.dart:72-90`) et par le générateur, donc visible du résolveur — vérifié par
  lecture, pas par exécution.

## Ce que j'ai corrigé moi-même

[mesuré] `2ffc3e8`, commit de nettoyage seul : retrait du doc-comment de
`resolveUpcomingMovementSteps` qui annonçait que les gels n'étaient pas modélisés (la mesure dit le
contraire), et de la phrase de `_familyOf` qui justifiait le classement de `suckle` par le nombre de
ses positions valides — un fait externe au code, qui deviendrait faux sans qu'une ligne bouge.
`flutter analyze` propre, `dart format` inchangé, 1023 tests toujours verts.

## Verdict

**Publiable avec réserves.**

Le travail fait ce qu'il annonce : la ligne s'enchaîne d'une consigne à la suivante, la remontée à
`tip` se produit au bon endroit, le classement des familles est celui que Manu a tranché, les tests
le prouvent (rouges avant, verts après, vérifié dans les deux sens), rien n'est touché hors
affichage, et la rétrocompatibilité est mesurée exacte sur 6 480 cas. Trois des inquiétudes du
rapport se réfutent à la mesure. [mesuré] Rétrocompatibilité exacte sur 6 480 cas, 1023 tests verts.

Réserves, la première gênante :

1. **Gênante — le gap de transition n'est pas modélisé.** [mesuré] Une frontière sur deux insère une
   remontée à `tip`, et toutes celles-là arrivent 0,6 à 1,5 s trop tôt sur une fenêtre de 3 s. C'est la
   décision 1 de Manu qui est en cause, pas un détail cosmétique. Ce que ça donne à l'œil reste à
   voir sur appareil ; ce qu'il faut décider, c'est si l'affichage duplique une deuxième règle du
   moteur ou si le moteur expose son gap. À Manu.
2. **Gênante — le rapport `23a11d4` décrit un classement qui n'est plus le code** et des chiffres
   qui ne sont plus les bons. Tant qu'il n'est pas redressé ou renvoyé vers celui-ci, il fabriquera
   la même erreur chez le prochain lecteur.
3. Non gênante — [mesuré] les rampes de BPM (0,19 % des steps) affichées à tempo constant.
4. Non gênante — le BPM non clampé et le `from == to` non répliqué : [mesuré] deux divergences avec
   le moteur qui ne se produisent jamais aujourd'hui (0 sur 107 842 steps), à connaître si le
   générateur change.
5. Non gênante — le classement de `suckle` sur `head` contre tout le reste : correct pour les deux
   positions qui existent, faux le jour où une troisième apparaît.
