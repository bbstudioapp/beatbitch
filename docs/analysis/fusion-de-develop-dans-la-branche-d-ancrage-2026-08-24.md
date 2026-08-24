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
  mesure: 18
  deduit: 16
  document: 0
  sans_marqueur: 3
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2116
  - rhythm_coach/lib/models/session_step.dart:151
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/lib/services/step_resolution.dart:38
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 3 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

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

### `movement_animation.dart` — quatre zones, 237 lignes

**[mesuré]** C'est le fichier que le chantier de la courbe a le plus réécrit :
997 lignes à la base commune, 1055 côté branche, **1642 côté `develop`**.

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

**[déduit]** Sous le pont (aucun beat réel encore reçu), l'alternance est
arithmétiquement neutre : `_lastBeatBpm` vient d'être remis à nul, `bpm` vaut
donc `widget.bpm`, et le complément de `60000/bpm` dans un cycle `2T` vaut
`60000/bpm`. Le pont du chantier courbe n'est donc pas déformé.

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

Ce n'était donc pas l'ancrage qui était mort, mais la *sonde*. Les deux tests
lisent désormais `_PositionLadder.beatDuration` par la voie `dynamic` que
`movement_animation_future_beats_test.dart` — resté vert au travers du merge —
employait déjà. Ce qu'ils affirment est inchangé : l'affichage reçoit
l'intervalle **réel** du dernier battement, pas `60000/bpm`.

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

## Ce que le merge ne couvre pas

**[déduit]** Le balayage de toutes les constructions de `SessionStep`
(37 sites hors modèle) a trouvé un site de recopie partielle hors périmètre :
`milestone_loader.dart:81` expanse le `chainAction` d'une milestone en
recopiant sept champs sur quatorze, et perd `anchor`/`ratio` avec cinq autres.
Le défaut est latent (aucun `chainAction` de milestone JSON ne porte
aujourd'hui l'un de ces champs). Non corrigé : fiche déposée en
`~/.claude/orchestration/sas/tss2/milestone-loader-chainaction-recopie-partielle-2026-08-24.md`.

**[déduit]** L'alternance portée en zone 4 s'arrête au segment courant. Une
courbe qui traverse une frontière de step dessine le segment suivant à son
tempo nominal, même si ce step est ancré. C'est le comportement d'avant le
merge (la branche ne dessinait rien au-delà du step courant), pas une
régression — mais c'est une limite, et elle mérite d'être vue par Manu avant
que quelqu'un la prenne pour un défaut.

## Ce qui n'a pas été fait

Rien n'a été poussé, aucune PR ouverte, aucune fusion vers `develop` ou
`main`. Le travail attend sa relecture adverse.

## Ce que je n'ai pas pu établir

**Rien n'a été vu ni entendu.** Toutes les preuves ci-dessus sont des tests et
des mutations de code ; aucune séance n'a été jouée, aucun APK compilé (la
consigne de mission l'interdisait). Que la courbe ancrée *se voie* correctement
à l'écran après ce merge n'est pas établi.

**La composition pont × ancrage n'est pas couverte.** **[déduit]** L'argument
de neutralité du pont sous ancrage est arithmétique, pas mesuré : aucun test
n'exerce une transition de step qui arrive *sur* un step ancré et vérifie que
le pont synthétique du chantier courbe et l'alternance du chantier aimant se
composent sans à-coup. C'est le point de contact le plus neuf entre les deux
chantiers, et c'est celui qui a le moins de filet.

**L'équivalence visuelle avant/après merge n'est pas mesurée.** L'alternance a
été portée dans une fonction que `develop` a réécrite de fond en comble. Que la
géométrie produite pour un step ancré soit celle que la branche produisait
avant le merge n'a pas été vérifié point par point — seulement que les écarts
alternent aux deux bonnes valeurs.

**Le comportement au-delà de la première frontière de step n'a pas été
arbitré.** La limite est décrite plus haut ; savoir si un step ancré à venir
doit être dessiné ancré est une décision de Manu, pas une conséquence du merge.
