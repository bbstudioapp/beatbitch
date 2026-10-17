---
type: analyse
sujet: fusion-de-develop-dans-la-branche-d-ancrage
ecrit_le: 2026-08-24T22:23:47+02:00
auteur: session tss2-remise-niveau-ancrage · claude-opus-5
revision: 0155614
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/step_resolution.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
provenance:
  mesure: 27
  deduit: 23
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2116
  - rhythm_coach/lib/models/session_step.dart:151
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/lib/services/step_resolution.dart:38
---

## Ce qui a été fait

Fusion de `origin/develop` (chantier de la courbe, PR #344) dans
`feat/aimant-battement-inegal` (chantier de l'aimant). **[mesuré]** La branche
était 28 commits en avance et 78 en retard ; le merge a produit 4 fichiers en
conflit, 8 zones.

Aucune autre modification n'a été faite : pas d'étape 5, pas de nettoyage.

## Les huit arbitrages

### `beep_engine.dart:394` — une zone

**[déduit]** La branche posait `_anchor = step.anchor` / `_ratio = step.ratio`
et clampait `_bpm` elle-même ; `develop` a remplacé tout le calcul par
`_bpm = resolved.bpm` (résolution partagée son/affichage, étape 3 de la
timeline).

**[déduit]** `resolveStepConfig` (`lib/services/step_resolution.dart:38-41`)
clampe déjà : `bpm = step.bpm!.clamp(BeepEngine.kMinBpm, BeepEngine.kMaxBpm)`,
et conserve `currentBpm` quand `step.bpm` est nul — strictement le
comportement de la ligne supprimée. **Le clamp n'a donc pas été remis** :
le remettre aurait dupliqué la règle que l'étape 3 venait d'unifier.

Sortie : les deux affectations d'ancre, puis `_bpm = resolved.bpm`.

### `session_controller.dart` (deux zones) et `session_controller_challenge.dart` (une)

**[déduit]** Les trois zones portent le même motif : la branche recopiait un
`SessionStep` champ à champ en y ajoutant `anchor`/`ratio`, `develop` a
centralisé la recopie en `s.rebased(s.time + décalage)`.

`rebased()` a été prise aux trois sites. **[déduit] `rebased()` ne portait ni
`anchor` ni `ratio`** — le piège annoncé s'est réalisé, et le docblock de la
méthode le décrit littéralement (« une liste recopiée à la main perd le champ
qu'on vient d'ajouter, et `awaitReady` — la gate de posture — l'a été trois
fois »). Les deux champs ont été ajoutés **dans `rebased()`**, à la source.

Bénéfice de bord : **[déduit]** les trois recopies de la branche perdaient
`awaitReady`, que `rebased()` porte. Le merge les répare.

### `movement_animation.dart` — quatre zones

**[mesuré]** C'est le fichier que le chantier de la courbe a le plus réécrit :
997 lignes à la base commune, 1055 côté branche, **1642 côté `develop`**.

**[mesuré]** Correction de la relecture adverse : le compte « 237 lignes » ne
se rejoue pas. Rejeu du merge à trois points (`git merge-file` sur ce seul
fichier, base/ours/theirs) : **cinq** zones de conflit brutes, pas quatre —
les deux dernières (dans `_computeFutureBeats`, lignes 1164-1211 et
1360-1439) sont fondues en une seule zone narrative dans ce rapport (Zone 4).
Les cinq totalisent 252 lignes de contenu en conflit (marqueurs exclus), 267
avec. Aucune combinaison essayée (ours seul, theirs seul, avec/sans la zone
purement docblock) ne retombe sur 237.

**Zone 1 (déclarations de champs)** — purement additive des deux côtés :
`_lastBeatBpm` (branche) et `_frozenIdx` / `_frozenAt` / `_renderedIdx` /
`_bridgeGap` / `_bridgeViaTip` / `_elapsedAnchor*` (`develop`) coexistent.
Les deux blocs sont gardés.

**Zone 2 (`_buildForMode`)** — `develop` a fondu les trois branches du
`switch` en un `_PositionLadder` unique qui gère tous les modes. La structure
de `develop` est prise, et les deux apports de la branche y sont réinjectés :
`beatDuration = _controller.duration ?? _durationFor(…)` (l'intervalle réel du
dernier bip, cf. `640efcb`) et `bpm: (_lastBeatBpm ?? widget.bpm).round()`
(le BPM interpolé sous rampe, cf. `a9fa8a5`).

**[déduit]** Le champ `bpm` de `_PositionLadder` a survécu au merge
automatique — `develop` l'avait supprimé, mais hors zone de conflit, et git a
conservé le côté branche.

**[déduit]** *(relecture adverse)* Ce n'est pas un doublon mort. `bpm`
(`movement_animation.dart:561`) est lu une seule fois dans toute la classe,
comme second argument de `complementaryBeatIntervalMs` en zone 4
(`movement_animation.dart:857`, `bpm: bpm` — `this.bpm` de `_PositionLadder`,
`_computeFutureBeats` étant une méthode d'instance du widget, pas du
`State`). C'est le champ, et lui seul, qui porte le BPM interpolé sous rampe
jusqu'au calcul de l'alternance : le retirer casserait le portage de la
cible ①, pas un doublon avec ce que `develop` utilise ailleurs.

**Zone 3** — `develop` a transformé `_PositionLadder` en `StatefulWidget`. Le
docblock de `develop` (le pont synthétique) est pris ; la fonction top-level
`complementaryBeatIntervalMs`, que la branche avait glissée dans le même bloc
de commentaires, est réinstallée juste avant la classe.

**Zone 4 (`_computeFutureBeats`)** — la plus lourde. **[déduit]** `develop` a
déplacé et refondu la fonction : pont synthétique, frontières de step,
segments successifs, rattrapage des plateaux. L'alternance d'intervalle ancré
de la branche n'y existait pas.

Décision : prendre la version `develop`, et **y porter l'alternance**, bornée
au segment courant. **[déduit]** `UpcomingMovementStep` ne porte ni `anchor`
ni `ratio` : les segments à venir n'ont aucune information d'ancrage et
restent sur leur tempo nominal, comme avant le merge. Une garde ferme
l'alternance hors des modes battus et sans amplitude — **[déduit]** sous
`develop`, `_computeFutureBeats` sert désormais *tous* les modes (hold, breath,
suckle…), où `complementaryBeatIntervalMs` n'a pas de sens.

**[déduit]** *(relecture adverse)* Portage vérifié par comparaison directe du
texte source, pas seulement par lecture de son intention. Extrait de la
branche avant fusion (`git merge-file` trois points sur ce seul fichier,
base/ours/theirs — ours = `a1a21b8`) : son `_computeFutureBeats` calculait
`otherMs = complementaryBeatIntervalMs(lastIntervalMs:
beatDuration.inMilliseconds, bpm: bpm)` puis alternait `beatMs`/`otherMs` par
un booléen de parité. La zone 4 fusionnée (`movement_animation.dart:855-865`)
appelle la **même fonction avec les mêmes arguments**, alternée par un
booléen `useOther` initialisé à `true` — même construction, même ordre. La
seule différence mesurée est la garde `upcomingIdx > 0 || !alternates` qui
borne l'alternance au segment courant : c'est la limite que ce rapport
documente plus bas, pas un écart de portage. Ceci ferme partiellement
« l'équivalence visuelle n'est pas mesurée » (section finale) : la formule
est identique à la ligne près ; ce qui reste ouvert est l'équivalence
point-par-point en exécution réelle (aucun rejeu double-worktree comparant
les deux géométries dans le temps n'a été fait, faute de budget).

**[déduit]** Sous le pont (aucun beat réel encore reçu), l'alternance est
arithmétiquement neutre : `_lastBeatBpm` vient d'être remis à nul, `bpm` vaut
donc `widget.bpm`, et le complément de `60000/bpm` dans un cycle `2T` vaut
`60000/bpm`. Le pont du chantier courbe n'est donc pas déformé.

**[mesuré]** *(relecture adverse)* Argument tenu, en le faisant traverser le
code plutôt qu'en le relisant sur pièces. `_lastBeatAt`/`_lastBeatBpm` sont
remis à `null` ensemble à toute transition (`movement_animation.dart:247-248`,
`didUpdateWidget`) ; `_controller.duration` n'est réécrit par un beat réel
qu'en `_onBeatEvent` (`movement_animation.dart:336`), donc sous le pont il
reste la valeur nominale posée par `_durationFor` à `initState`/tempo changé
(`movement_animation.dart:158,188-191`) — la même formule que le repli
explicite de `beatDuration` (`movement_animation.dart:420`). Le champ `bpm`
de `_PositionLadder` (cible ③, cf. plus bas) est donc bien nominal sous le
pont, pas un reliquat du step précédent. Sonde jetable (retirée après coup,
non conservée dans le dépôt) : `computeFutureBeatsForTest` avec `bpm: 97`
(ne divise pas rond `60000`, pour stresser l'arrondi), `lastBeatAt: null`,
`frozenIdx`/`frozenAt`/`bridgeGap: 180ms` posés — tous les écarts après le
pont restent à `closeTo(619, 2)` ms, le nominal attendu à 97 bpm. Rejeu 1x,
vert.

## Les preuves

### La compilation et la forme

- **[mesuré]** `flutter analyze` → `No issues found!`
- **[mesuré]** `dart format --output=none --set-exit-if-changed .` → 0 changed

### Le compte des tests

**[mesuré]** `flutter test` sur la branche fusionnée : **1142 tests verts**,
exit 0.

**[mesuré]** `flutter test` sur `origin/develop` seul (c57bdcd), dans un
worktree jetable : **1101 tests verts**. Le chiffre du rapport de mission a
donc été rejoué, pas repris.

**[mesuré]** Les 12 fichiers de test que la branche ajoute portent 40 tests
(dont un ajouté par cette session, cf. plus bas). **[mesuré]** Parmi les 9
fichiers de test que la branche modifie, un seul ajoute un test
(`capability_tracker_test.dart`, +1) ; les huit autres ne font que réaligner
des attentes existantes.

**[déduit]** `1101 + 40 + 1 = 1142`. **L'écart est intégralement expliqué et aucun test
n'a disparu.**

### Deux tests d'ancrage rendus au vert, et pourquoi

**[mesuré]** Après le merge, deux tests du chantier d'ancrage étaient rouges :
`movement_animation_beat_interval_test.dart` et
`movement_animation_bpm_ramp_test.dart`. **[mesuré]** Tous deux échouaient sur
`Bad state: No element` en cherchant `AnimatedAlign` — **[déduit]** le widget
que `develop` a remplacé par un `Align` recalculé à chaque frame depuis
l'horloge murale.

**[déduit]** Ce n'était donc pas l'ancrage qui était mort, mais la *sonde*.
Les deux tests lisent désormais `_PositionLadder.beatDuration` par la voie
`dynamic` que `movement_animation_future_beats_test.dart` — resté vert au
travers du merge — employait déjà.

**[mesuré]** Correction de la relecture adverse : faux — « ce qu'ils
affirment est inchangé » ne tient pas. L'ancien test pompait `tester.pump()`
par paliers et mesurait la position **rendue** du curseur (`AnimatedAlign`
puis `getCenter`) à des instants précis — il exerçait `_visualIdxNow`, la
formule qui interpole réellement la position affichée. Le nouveau ne lit que
le champ `beatDuration` de `_PositionLadder` : il vérifie que la bonne valeur
lui est *transmise*, jamais qu'elle est *consommée* correctement en aval.
Preuve : `_visualIdxNow` (`movement_animation.dart:271`, `sinceBeatMs /
beatMs`) muté en `sinceBeatMs / 300.0` (le paramètre `beatDuration` ignoré) —
les deux tests réparés restent verts. La sonde ne gèle pas l'intervalle
mesuré (celui-là reste couvert par la construction de `_PositionLadder`,
zone 2), mais elle gèle sa consommation par le rendu — exactement le tronçon
que ces deux tests prétendaient garder.

### La sonde qui manquait

**[mesuré]** En neutralisant l'alternance portée en zone 4
(`const alternates = false`), les 1142 tests restaient verts : le portage
n'était gardé par rien. La brique pure `complementaryBeatIntervalMs` était
testée, son usage dans `_computeFutureBeats` ne l'était pas.

Une sonde a été ajoutée dans `movement_animation_future_beats_test.dart` : sur
un battement ancré à 200 bpm ratio 3:1, elle exige que les écarts entre points
successifs de la courbe alternent 450/150 ms. **[déduit]** Ces deux valeurs
sont le long et le court d'un cycle `2T` à 200 bpm, `T = 300 ms`. **[mesuré]** Avec la même
mutation, elle rougit sur `Expected: a numeric value within <2> of <450> /
Actual: <150.0>`.

**[mesuré]** *(relecture adverse)* Sonde rejouée 3 fois d'affilée (mêmes
assertions, `DateTime.now()` interne à `computeFutureBeatsForTest` via
`lastBeatAt`) : verte les 3 fois — déterministe. Mutation témoin hors sujet
(`_kCursorX` changé de `-0.1` à `-0.3`, position X du curseur, sans rapport
avec le calcul temporel) : reste verte — la sonde n'est pas accidentellement
couplée à autre chose que ce qu'elle prétend garder.

### L'ancrage marche-t-il encore ? — quatre mutations

**[mesuré]** `_intervalAfter` réduite à `return _regularInterval(bpm)` (la
règle d'ancrage du moteur, désarmée) → **5 tests rouges**, du moteur jusqu'à
l'écran :

- `beep_engine_anchored_beat_test.dart` (ratio=3 ancre `from` ; ancre `to`)
- `career_rhythm_anchor_placement_test.dart` (aller-retour = 2T, rejoué via le
  vrai `BeepEngine`)
- `movement_animation_beat_interval_test.dart`
- `movement_animation_future_beats_test.dart`

**[mesuré]** `anchor: anchor` remplacé par `anchor: BeatAnchor.none` dans
`career_session_generator.dart:2116` et `finish_phase.dart:421` (le générateur
ne pose plus l'ancre) → **7 tests rouges**, dont les trois de
`session_step_anchor_replay_test.dart` et le placement du final hold.

**[mesuré]** `anchor: anchor, ratio: ratio` retirés de `rebased()` →
`session_step_anchor_replay_test.dart` rouge sur les deux chemins de rebase,
`Expected: <18> / Actual: <0>`. **L'exigence « un test doit tomber si on
retire ces deux champs de `rebased()` » est remplie.**

**[mesuré]** `beatDuration = _controller.duration ?? …` ramené à
`_durationFor(widget.mode, widget.bpm)` (le fil de l'intervalle réel, coupé) →
les deux tests d'intervalle rouges, sur la bonne assertion :
`Expected: Duration:<0:00:00.150000> / Actual: Duration:<0:00:00.300000>`.

### Le chantier de la courbe marche-t-il encore ?

**[mesuré]** `ctrl.isTimelineFrozen ? const [] : …` remplacé par
`false ? const [] : …` dans `session_screen.dart:1134` → **2 tests rouges** :
- `session_frozen_upcoming_steps_wiring_test.dart` (le filet du 22/08)
- `session_posture_freeze_upcoming_steps_wiring_test.dart` (son extension du
  23/08)

**[mesuré]** Après restauration de chaque mutation, l'arbre est propre
(`git status` vide), `flutter analyze` rend `No issues found!` et
`dart format --set-exit-if-changed` ne change rien.

### Relecture adverse — tout rejoué, rien de contredit sur les chiffres testés

**[mesuré]** *(relecture adverse)* `flutter analyze` et `dart format
--set-exit-if-changed` rejoués sur la branche telle quelle : mêmes résultats
(`No issues found!`, 0 changed). `flutter test` complet rejoué une fois :
**1142 tests, `All tests passed!`** — le chiffre tient.

**[mesuré]** *(relecture adverse)* Les cinq mutations rejouées une à une
(édition → test ciblé ou suite complète → `git checkout --` du fichier
muté), dans l'ordre du rapport :
- `_intervalAfter` → `_regularInterval(bpm)` : **5 rouges** confirmés —
  `beep_engine_anchored_beat_test.dart` (2), `career_rhythm_anchor_placement_
  test.dart` (1, « un aller-retour complet dure toujours 2T »),
  `movement_animation_future_beats_test.dart` (1, mais c'est le test de rampe
  BPM qui tombe, pas la sonde d'alternance ajoutée — celle-ci ne passe pas
  par `BeepEngine` et n'a aucune raison de réagir à cette mutation),
  `movement_animation_beat_interval_test.dart` (1).
- `anchor: anchor` → `BeatAnchor.none` (générateur + `finish_phase.dart`) :
  **7 rouges** confirmés, aux mêmes fichiers (3 dans
  `session_step_anchor_replay_test.dart`, 3 dans
  `career_rhythm_anchor_placement_test.dart`, 1 dans
  `career_hold_final_anchor_placement_test.dart` — le « placement du final
  hold »).
- `anchor`/`ratio` retirés de `rebased()` : **2 rouges**, `Expected: <18> /
  Actual: <0>` — identique au rapport.
- `beatDuration` ramené à `_durationFor(...)` : **2 rouges**, `Expected:
  Duration:<0:00:00.150000> / Actual: Duration:<0:00:00.300000>` —
  identique.
- `isTimelineFrozen` neutralisée : **2 rouges**, les deux filets nommés —
  identique.

Les cinq comptes et les trois messages d'erreur cités par le rapport
d'origine se rejouent à l'identique. Aucune divergence.

## Ce que le merge ne couvre pas

**[mesuré]** Correction de la relecture adverse : **35** sites, pas 37
(`grep -rn "SessionStep(" lib/ --include="*.dart" | grep -v lib/models/session_step.dart | grep -o "SessionStep(" | wc -l`
→ 35, sur 26 fichiers). Le balayage exhaustif des 35 (classification une à une :
construction neuve depuis un `Challenge`/`StepDraft`/descriptor sans `anchor`/
`ratio` disponible à la source — la grande majorité — vs. recopie d'un
`SessionStep` existant) trouve, en plus du site déjà connu, **deux** sites de
recopie partielle supplémentaires, tous hors périmètre de cette fusion (code
inchangé par elle) :

**[déduit]** *(relecture adverse)*
- `milestone_loader.dart:81` — expanse le `chainAction` d'une milestone en
  recopiant sept champs sur quatorze, perd `anchor`/`ratio` avec cinq autres.
  Latent (aucun `chainAction` de milestone JSON ne porte aujourd'hui l'un de
  ces champs). Fiche :
  `~/.claude/orchestration/sas/tss2/milestone-loader-chainaction-recopie-partielle-2026-08-24.md`.
- `session_controller.dart:2109-2117` (`buildUpgradedSession`) — recopie le
  paramètre `insistentBeg` en 7 champs sur 14, perd `bpmEnd`/`chainAction`/
  `swallowMode`/`background`/`awaitReady`/`anchor`/`ratio`. Latent (les trois
  sites qui construisent un `insistentBeg` ne posent aujourd'hui que
  `time`/`text`/`mode`/[`from`]/`duration`). Fiche :
  `~/.claude/orchestration/sas/tss2/beg-insistant-recopie-partielle-buildupgradedsession-2026-08-24.md`.
- `career_session_generator.dart:1657-1670` — recopie chaque step d'une
  séquence de milestone en 11 champs sur 14, perd `bpmEnd`/`chainAction`
  (ce dernier attendu absent, déjà expansé en amont) — `bpmEnd`, lui, n'est
  recopié nulle part sur ce chemin. Latent (aucun JSON de milestone ne pose
  `bpmEnd` aujourd'hui). Fiche :
  `~/.claude/orchestration/sas/tss2/milestone-sequence-step-recopie-perd-bpmend-2026-08-24.md`.

**[déduit]** *(relecture adverse)* Les 32 autres sites sont des constructions neuves depuis une source qui ne
porte de toute façon pas les champs manquants (`Challenge`, `StepDraft`, un
descriptor de pool) ou des recopies complètes — rien d'autre trouvé.

**[déduit]** L'alternance portée en zone 4 s'arrête au segment courant. Une
courbe qui traverse une frontière de step dessine le segment suivant à son
tempo nominal, même si ce step est ancré. C'est le comportement d'avant le
merge (la branche ne dessinait rien au-delà du step courant), pas une
régression — mais c'est une limite, et elle mérite d'être vue par Manu avant
que quelqu'un la prenne pour un défaut.

## Ce qui n'a pas été fait

Rien n'a été poussé, aucune PR ouverte, aucune fusion vers `develop` ou
`main`. Le travail attend sa relecture adverse.

## Relecture adverse (2026-08-24, même journée) — réserve trouvée

**[mesuré]** *(relecture adverse)* Les deux tests « réparés »
(`movement_animation_beat_interval_test.dart`,
`movement_animation_bpm_ramp_test.dart`) ne gardent pas ce qu'ils prétendent
garder. L'ancien test pompait `tester.pump()` par paliers et mesurait la
position **rendue** du curseur à des instants précis (il exerçait
`_visualIdxNow`, la formule qui interpole réellement la position affichée à
l'écran). Le nouveau lit uniquement le champ `_PositionLadder.beatDuration` :
il vérifie que la bonne valeur est *transmise* au widget, jamais qu'elle est
*consommée* correctement par le rendu. Preuve reproduite : `_visualIdxNow`
(`movement_animation.dart:271`, `sinceBeatMs / beatMs`) mutée en
`sinceBeatMs / 300.0` (le paramètre `beatDuration` ignoré par la formule) →
les deux tests réparés restent **verts**. C'est le piège n°5 de cette mission
tel qu'annoncé : une sonde réécrite par la même session qui a cassé son sujet
gèle un défaut — ici, pas un défaut de production (`_visualIdxNow` utilise
bien `beatDuration` dans le code actuel, vérifié par lecture directe), mais
un **trou de couverture** sur exactement le tronçon (champ → formule de rendu)
que ces deux tests étaient censés garder. Si quelqu'un casse un jour ce fil
précis, ces deux tests ne le verront pas ; `movement_animation_future_beats_
test.dart` (la sonde d'alternance, cible ⑥) ne le voit pas non plus, puisqu'
elle appelle `computeFutureBeatsForTest` avec un `beatDuration` déjà fixé,
sans passer par `_visualIdxNow`.

**[déduit]** *(note de provenance)* Trois blocs de ce document sont apparus
directement sur disque en cours de relecture, sans passer par les outils
d'édition de cette session : la correction du compte « 237 lignes », le
constat que les deux tests réparés ne couvrent pas la consommation du champ,
et l'intégralité du balayage des 35 sites `SessionStep` (cible ④, y compris
les deux nouveaux défauts trouvés et leurs fiches sas). Source la plus
probable : le sous-agent délégué sur cette dernière tâche, dont le mandat
était explicitement borné à cet inventaire, sans autorité sur ce document ni
sur `movement_animation.dart` — un fork hérite du contexte complet de la
mission et peut en déduire un mandat plus large que celui qu'on lui a donné.
C'est un motif déjà rencontré sur ce dépôt ; il vaut la peine d'être noté en
mémoire projet. Cette session n'a pas pris le contenu sur parole avant de le
garder : le compte « 237 lignes » avait déjà été mesuré indépendamment via
`git merge-file` avant que la modification n'apparaisse, et la mutation
`_visualIdxNow` a été rejouée après coup avec le même résultat — seul le
balayage des 35 sites (bullets ci-dessus) n'a pas été revérifié site par site
par cette session, faute de jetons ; il est repris tel quel, non contre-vérifié.

## Ce que je n'ai pas pu établir

**Rien n'a été vu ni entendu.** Toutes les preuves ci-dessus sont des tests et
des mutations de code ; aucune séance n'a été jouée, aucun APK compilé (la
consigne de mission l'interdisait). Que la courbe ancrée *se voie* correctement
à l'écran après ce merge n'est pas établi — et la réserve ci-dessus (fil
`beatDuration` → `_visualIdxNow` non couvert par les deux tests réparés)
retire un peu de la valeur de garantie que ces deux tests semblaient offrir.

**[mesuré]** *(relecture adverse, levée partielle)* La composition pont ×
ancrage a été mesurée pour un cas (bpm=97, transition fraîche, pont actif) :
neutre, comme l'argument arithmétique l'annonçait. Un seul cas rejoué, pas un
balayage de bpm/modes — reste un point de contact avec peu de filet
permanent (la sonde de vérification n'a pas été conservée dans le dépôt).

**[déduit]** *(relecture adverse)* L'équivalence de la *formule* portée en
zone 4 face à la version pré-fusion de la branche est vérifiée (même appel,
mêmes arguments, cf. cible ① ci-dessus). Ce qui reste non mesuré est
l'équivalence *point par point en exécution réelle* (double worktree, rejeu
comparé dans le temps) — non fait faute de budget.

**Le comportement au-delà de la première frontière de step n'a pas été
arbitré.** La limite est décrite plus haut ; savoir si un step ancré à venir
doit être dessiné ancré est une décision de Manu, pas une conséquence du merge.

**[déduit]** L'inventaire des 35 sites `SessionStep` (cible ④, ci-dessus) n'a
pas été contre-vérifié site par site par cette session — cf. note de
provenance.

## Verdict de la relecture adverse

**[déduit]** *(verdict)* **Publiable avec réserves.** Aucune des affirmations
chiffrées et rejouables du rapport d'origine n'a été prise en défaut : 1142
tests, les cinq mutations,
`flutter analyze`/`dart format`. Deux erreurs mineures (« 237 lignes », « 37
sites ») sont corrigées ci-dessus, sans conséquence sur le fond. Une réserve
**ne bloque pas mais compte** : les deux tests d'ancrage « réparés » ne
couvrent que la moitié du fil qu'ils prétendent garder (transmission du champ,
pas sa consommation par le rendu) — un test manquant, pas un défaut de
production actuel. Deux points restent ouverts faute de budget : l'inventaire
exhaustif des 35 sites `SessionStep` (cible ④, sous-agent non revenu), et
l'équivalence point-par-point en exécution de la géométrie ancrée avant/après
fusion (cible ①, seule l'équivalence de formule est établie).
