---
type: analyse
sujet: chantier-aimant-etapes-1-2-moteur-et-visuel
ecrit_le: 2026-08-20T20:10:48+02:00
auteur: session tss2-aimant-moteur · claude-sonnet-5
revision: 640efcb
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/beep_engine_anchored_beat_test.dart
  - rhythm_coach/test/movement_animation_beat_interval_test.dart
provenance:
  mesure: 12
  deduit: 3
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1596
  - rhythm_coach/lib/models/session_step.dart:102
  - rhythm_coach/lib/services/beep_engine.dart:508
  - rhythm_coach/lib/services/beep_engine.dart:610
  - rhythm_coach/lib/widgets/movement_animation.dart:162
  - rhythm_coach/lib/widgets/movement_animation.dart:216
---

> **Correction (2026-08-20, session tss2-aimant-etape3 · claude-sonnet-5)** : ce rapport écrit plus
> bas « l'unique appelant de production (`session_controller.dart:1596`) ». C'est faux — la relecture
> adverse (`docs/analysis/relecture-adverse-des-etapes-1-et-2-du-chantier-aimant-2026-08-20.md`) en a
> compté **six** : `session_controller.dart:1596`, `session_controller_fail_flow.dart:190`, `:295`,
> `:459`, `session_controller_challenge.dart:854`, `:917`. La conclusion du rapport (« en production,
> `_anchor` reste `none` ») tenait malgré tout, faute d'appelant passant autre chose que le défaut —
> mais c'est sur les six chemins qu'il fallait raisonner, pas sur un seul.

## Ce dont il s'agit

**[mesuré]** Étapes 1 et 2 du chantier aimant (§6 de
`docs/analysis/instruction-du-chantier-aimant-sur-les-modes-rythme-et-tenue-2026-08-20.md`, branche
`docs/aimant-instruction`, non fusionnée) : le moteur audio sait produire un battement à intervalles
inégaux (ancré sur `from` ou `to`), et le visuel du curseur suit cet intervalle réel au lieu de
recalculer `60000/bpm`. Étapes 3 (générateur) et 4 (micro-mouvement des holds) non touchées.

**Révision jugée** : branche `feat/aimant-battement-inegal`, worktree `~/perso/git/tss2-aimant`, base
`origin/develop` = `7dc9746`. Deux commits, tête `640efcb`. Rien n'a été poussé, aucune PR ouverte.

## Ce qui a été fait

**[mesuré]** `BeepEngine._startBeatLoop` (`beep_engine.dart`) calcule désormais l'intervalle du
prochain battement à partir de la position qui vient d'être émise (`_intervalAfter`), pilotée par
deux champs internes `_anchor` (enum `BeatAnchor { none, from, to }`) et `_ratio` (`int`), réglables
via deux paramètres optionnels de `applyStep` (`anchor: BeatAnchor.none`, `ratio: 1` par défaut).
L'unique appelant de production (`session_controller.dart:1596`) ne passe ni l'un ni l'autre — en
production, `_anchor` reste toujours `none`, donc le geste ne change pas.

**[mesuré]** `_intervalAfter` déduit le court du long par soustraction (`fullCycleMs - longMs`) plutôt
que par deux arrondis indépendants — sinon, pour un BPM qui ne divise pas rond `60000` (ex. 77), les
deux arrondis pouvaient diverger de la somme voulue de ±1 ms. C'est un point que le plan (§2) ne
traite pas : il donne la formule continue, pas son arrondi. **[déduit]** L'invariant « la somme sur un
cycle vaut `2T` » tient donc exactement quel que soit le BPM, pas seulement sur les BPM ronds utilisés
par le test.

**[mesuré]** `BeatEvent` porte un nouveau champ `nextInterval` (`Duration`) — la durée jusqu'au
prochain battement. `MovementAnimation._onBeatEvent` (`movement_animation.dart`) pose
`_controller.duration = event.nextInterval` avant `.forward(from: 0)` ; `_buildForMode` lit
`_controller.duration` au lieu de recalculer `_durationFor(widget.mode, widget.bpm)`. Biffle et les
modes non synchronisés (hold/beg/breath/suckle/freestyle) restent inchangés — ils ne reçoivent jamais
de `BeatEvent` porteur d'un ancrage.

## Ce que j'ai mesuré (commandes exécutées)

Toutes depuis `rhythm_coach/`, toutes bornées en temps.

- **[mesuré]** `flutter analyze` → **No issues found!** sur la tête de branche.
- **[mesuré]** `dart format --set-exit-if-changed lib test` → exit 0, 0 fichier changé.
- **[mesuré]** `timeout 1500 flutter test`, sortie redirigée vers fichier (jamais de `| grep` :
  SIGPIPE tronque le run et rend un exit 0 trompeur) → **1020 tests passés, 0 échec.**

### Les tests discriminent-ils vraiment ?

**[mesuré]** **Étape 1** (`test/beep_engine_anchored_beat_test.dart`, 4 cas) : à `ratio=1` la suite
d'intervalles est constante et identique à `(60000/bpm).round()` ; à `ratio=3` ancre `from`,
alternance `1,5T`/`0,5T` ; ancre `to`, l'inverse ; et la somme de deux battements consécutifs vaut
exactement `2T` (arrondi), pour les trois configurations. Rejoué sur le commit de base (`7dc9746`,
worktree jetable créé puis supprimé) : **rouge** — échec de compilation, `BeatAnchor` et
`simulateBeatsForTest` n'existent pas encore.

**[mesuré]** **Étape 2** (`test/movement_animation_beat_interval_test.dart`, 1 cas) : pilote deux
battements consécutifs (court 50 ms, puis long 150 ms, `ratio=3` ancre `from`, bpm=600 donc
`T=100ms`) via une sonde de test sur `BeepEngine` (`configureBeatSourceForTest` +
`emitOneBeatForTest`, sans Timer ni audio réels) et vérifie que le curseur n'est **pas** arrivé sur
sa cible à 100 ms (la durée que l'ancien calcul aurait produite) mais l'**est** à 150 ms (la vraie
durée). Rejoué en isolant seulement `movement_animation.dart` (`git stash` de ce fichier,
`beep_engine.dart` restant à l'étape 1) : **rouge** — le curseur arrive dès 100 ms, calé sur l'ancien
`60000/bpm` constant. Les seuils de comparaison de position (`closeTo(..., 0.5)` pixel logique) ont
été élargis depuis un premier essai à `0.001` — trop strict, du bruit sub-pixel de calcul de courbe
faisait échouer même le code correct par endroits ; `0.5` reste largement assez fin pour discriminer
50 ms d'écart d'une transition à 50 ou 150 ms.

**[mesuré]** **Suite existante** : intégralement verte après les deux étapes, **sans modification
d'aucun test déjà présent** — seules 9 sous-classes de test qui redéfinissent `BeepEngine.applyStep`
(des faux moteurs silencieux) ont dû étendre leur signature pour rester des overrides valides (ajout
mécanique des deux nouveaux paramètres optionnels, comportement de ces faux inchangé).

### Une divergence chiffrée avec la consigne

**[mesuré]** La consigne du chantier annonce « 1023 tests verts sur origin/develop » comme référence.
Le commit de base réel de la branche (`7dc9746`, tip d'`origin/develop` au moment du `git fetch`)
compte **1015** tests, tous verts, avant toute modification de ma part. **[document]** Ce chiffre
concorde avec la mémoire du projet (`project_release_062.md` : « poussée le 20/08, 1015 tests
verts ») et pas avec les 1023 de la consigne. Je n'ai pas cherché plus loin l'origine de l'écart — il
ne change rien à l'invariant demandé (« la suite existante passe sans qu'on y touche »), qui est
vérifié : 1015 → 1020 (+4 étape 1, +1 étape 2), zéro test existant modifié en comportement.

## Ce qui prouve « aucune différence, ni vue ni entendue »

**[déduit]** Rien ne consomme encore `anchor`/`ratio` côté génération — `SessionStep` ne porte pas ces
champs (étape 3, hors périmètre). En pratique, le geste ancré n'est atteignable qu'en appelant
directement les sondes de test ; aucun chemin de production ne peut produire `_anchor != none`. C'est
la preuve principale demandée par la consigne, et elle tient par construction (absence de câblage),
pas seulement par la mesure des tests existants.

## La branche `feat/movement-trajectory-continuity`

**[déduit]** Cette branche (non fusionnée, non modifiée ici — lue via
`git diff 7dc9746...origin/feat/movement-trajectory-continuity`) touche le même fichier
`movement_animation.dart` : elle donne à `_computeFutureBeats` (la courbe de prévision pointillée des
battements à venir) la suite de la timeline de séance et le vrai gap de transition du moteur
(`BeepEngine.transitionGap`, une méthode statique qu'elle ajoute). Mon changement ne touche pas
`_computeFutureBeats` : cette fonction suppose toujours un `beatDuration` constant par segment de
step. Sans conséquence tant qu'aucun step réel ne porte d'ancrage (étape 3 non livrée), mais à
revisiter quand ce sera le cas — la courbe de prévision afficherait alors des points régulièrement
espacés pour un battement qui, à l'oreille, ne l'est plus.

## Ce que je n'ai pas pu établir

- **Le rendu du geste ancré à l'oreille n'a pas été jugé** — la consigne du projet interdit de faire
  sonner le contenu de l'app pendant le développement. **[document]** Le ratio « 3:1 » repris du
  schéma de Manu, une fois câblé en étape 3, reste à valider par lui sur son téléphone.
- **Aucune séance complète (`SessionController` → `BeepEngine` → `MovementAnimation` montés
  ensemble) n'a fait tourner le nouveau chemin.** Mes deux preuves pilotent chaque brique séparément
  et directement (sondes de test), pas le flux entier en conditions de séance.
- **L'écart entre les deux chiffres n'a pas été creusé davantage.** **[document]** La consigne annonce
  1023 tests verts sur `origin/develop` ; **[mesuré]** j'en ai compté 1015 sur le commit de base
  réel. Je n'ai pas cherché si c'est une confusion avec un autre commit ou un chiffre resté obsolète
  dans le document d'instruction.
- **L'effet du micro-mouvement sur `HoldVerifier`** reste une question de l'étape suivante,
  **[document]** décrite au §2 point 4 du plan, donc non regardée ici — y compris pour vérifier que
  rien dans mon changement ne l'affecte déjà (il ne devrait pas : `hold` n'appelle jamais
  `_startBeatLoop`).
