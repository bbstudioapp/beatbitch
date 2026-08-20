---
type: analyse
sujet: trajectoire-continuite-movement-animation
ecrit_le: 2026-08-20T17:27:02+02:00
auteur: session tss2-animations · claude-sonnet-5
revision: 7da60d2
branche: feat/movement-trajectory-continuity
porte_sur:
  - /home/emmanuel/perso/git/tss2-trajectory/rhythm_coach/lib/screens/session_screen.dart
  - /home/emmanuel/perso/git/tss2-trajectory/rhythm_coach/lib/widgets/movement_animation.dart
  - /home/emmanuel/perso/git/tss2-trajectory/rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - /home/emmanuel/perso/git/tss2-trajectory/rhythm_coach/test/movement_trajectory_continuity_test.dart
provenance:
  mesure: 9
  deduit: 7
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre: ⚠️ NON RENSEIGNÉ
---

> **Erratum — le classement des familles ci-dessous n'est plus celui du code.** [mesuré] Ce rapport
> est antérieur à `6ec7811`, qui a redressé `_familyOf` sur la correction de Manu : `beg` et `lick` sont
> **hors** bouche, et `suckle` se classe sur sa position (`head` bouche, `balls` hors bouche). Les
> chiffres de tests (« 6 tests », « 1021 ») sont également ceux d'avant : 8 et 1023. Les réserves
> listées en fin de document sur les gels et la performance sont réfutées par la mesure. Voir
> `docs/analysis/relecture-adverse-continuite-de-trajectoire-2026-08-20.md`.

Correctif de la trajectoire future du `MovementAnimation` : elle ne connaissait que la consigne
en cours et extrapolait son alternance from/to indéfiniment, sans jamais savoir qu'un changement de
step (de bpm, de position, ou de mode) arrivait. [document] Décision de Manu du 2026-08-20 (ticket
de tâche, non repris ici mot pour mot) : la ligne doit s'enchaîner sur la même courbe d'une consigne
à l'autre ; entre deux **modes**, elle remonte à `tip` (sortie complète) sauf quand les deux modes
appartiennent à la même famille bouche / pas-bouche ; affichage seulement, ni `BeepEngine` ni le
générateur de séances touchés.

[mesuré] Travail fait sur la branche `feat/movement-trajectory-continuity` (créée depuis
`origin/develop` = `7dc9746`), worktree `/home/emmanuel/perso/git/tss2-trajectory`. Un seul commit
local, `7da60d2`, **non poussé**.

## Le défaut mesuré avant correctif

[mesuré] Sonde ajoutée dans `test/movement_trajectory_continuity_test.dart` (via un point d'accès
`@visibleForTesting` posé dans `movement_animation.dart`, `computeFutureBeatsForTest` — passthrough
pur vers le calcul privé existant `_PositionLadder._computeFutureBeats`, aucun changement de
comportement à ce stade). Scénario : mode `rhythm`, alternance `head↔throat`, bpm 60 (beat =
1000 ms), consigne connue du test seule comme se terminant à 1800 ms. Exécuté sur le code
d'aujourd'hui (avant tout changement de `_computeFutureBeats`) :

```
Expected: empty
  Actual: [
    (idx: 1.0, isAnchor: false, t: 0.666),
    (idx: 3.0, isAnchor: false, t: 0.999),
    (idx: 1.0, isAnchor: false, t: 1.333),
  ]
EXIT=1
```

[mesuré] 3 points prédits après la fin de la consigne (1800 ms) continuent d'annoncer `head`/`throat`
(idx 1 et 3) — la trajectoire n'a structurellement aucun moyen de savoir qu'une autre consigne va
commencer. Sortie complète et code de sortie 1 capturés avant tout autre changement de code — cf.
`/tmp/probe_red.log`.

## Le classement bouche/pas-bouche retenu — et ce qui n'a pas pu être tranché seul

[déduit] La phrase de Manu donne deux familles pour 8 des 9 `SessionMode` : avec la bouche
(`rhythm`, `hold`, `beg`, `lick`), sans la bouche (`hand`, `biffle`, `breath`, `freestyle`). Le 9ᵉ,
`suckle`, n'y figure pas. Son doc-comment dans `session.dart:40-47` (« la bouche reste en place sur
la position visée ») et son classement déjà existant dans `_cursorStyleFor` (style « orb », groupé
avec `rhythm`/`hold`/`beg`, jamais avec `lick` ni `hand`) pointent vers « avec la bouche » — c'est
la lecture retenue dans `_MovementAnimationState._familyOf`. Conformément à la consigne, je n'ai pas
tranché cette ambiguïté seul : fiche déposée dans le sas,
`~/.claude/orchestration/sas/tss2/tss2-002-suckle-hors-classement-familles-trajectoire.md`.

## L'implémentation

[déduit] Deux fichiers changés, deux fichiers ajoutés :

- `lib/widgets/movement_trajectory_forecast.dart` (nouveau) — `resolveUpcomingMovementSteps` :
  fonction pure qui parcourt `session.steps`, saute les steps text-only et ceux déjà passés
  (`time <= afterSecond`), et résout mode/from/to/bpm effectifs en répliquant la règle de résolution
  de `BeepEngine.applyStep` (mode retombe sur `defaultMode` si non précisé ; bpm et from sont
  sticky ; `to` ne l'est **jamais**, y compris pour hold/beg/suckle qui prennent leur `from` depuis
  `step.to`). Duplication assumée et documentée en commentaire (une ligne, technique) : le widget
  n'a pas accès à l'état interne — privé — du moteur audio, et la consigne interdit de le toucher
  pour lui en donner l'accès.
- `lib/widgets/movement_animation.dart` — `MovementAnimation` reçoit deux nouveaux paramètres à
  défaut rétrocompatible (`elapsed = Duration.zero`, `upcomingSteps = const []`) ; `_PositionLadder`
  reçoit en plus `mode` (pour classer sa propre famille) ; `_computeFutureBeats` parcourt maintenant
  les segments (courant, puis chaque `upcomingSteps` dans la fenêtre de 3 s), insère un point
  `idx = tip` à la frontière quand la famille change, et repart sur le `to` du segment suivant un
  beat plus tard dans ce cas (direct, sans point `tip`, quand la famille est la même). `upcomingSteps`
  vide reproduit exactement l'ancien calcul (aucune régression sur le chemin historique — testé).
- `lib/screens/session_screen.dart` — calcule `upcomingSteps` via `resolveUpcomingMovementSteps` à
  chaque rebuild et passe `elapsed: ctrl.elapsed` ; seul point d'intégration touché, aucun autre
  fichier de `SessionController`/`BeepEngine`/génération de séance modifié.

[mesuré] `test/movement_trajectory_continuity_test.dart` (6 tests, 3 sur `_computeFutureBeats`, 3
sur `resolveUpcomingMovementSteps`) : le scénario ci-dessus, rejoué avec `upcomingSteps` peuplé,
passe désormais (plus aucun point `head`/`throat` après 1800 ms), la même famille (`rhythm→hold`)
enchaîne directement (aucun point `tip`), une frontière de famille (`rhythm→hand`) passe par `tip`.

## Vérifications

- [mesuré] `flutter analyze` → `No issues found!` (2,6 s).
- [mesuré] `timeout 1500 flutter test` (sortie redirigée, jamais pipée) → `1021 tests, All tests
  passed!`, exit 0 — 1015 tests de base (`origin/develop` au 2026-08-20) + 6 nouveaux.
- [mesuré] `dart format --set-exit-if-changed lib test` → exit 0 après une passe de reformatage
  automatique (2 fichiers reformatés, aucun changement sémantique).
- [mesuré] `free -h` avant la suite complète : 9,1 Gio disponibles — marge jugée suffisante, aucune
  compilation Android lancée par cette tâche.

## Ce que je n'ai pas pu établir

- **Rien vu en mouvement.** Aucune de ces vérifications ne prouve ce qui se voit à l'écran en
  animation réelle (fluidité de la remontée à `tip`, lisibilité du fondu, calage visuel sur un
  appareil). Testé uniquement au niveau du calcul pur des points de la courbe.
- [déduit] La frontière d'un step n'est connue qu'à la **seconde** près (`SessionStep.time: int`) —
  la trajectoire ne peut pas anticiper un changement de consigne à moins d'une seconde près, même si
  l'ancrage horloge murale / horloge de séance (`elapsed`, précision ms) est plus fin.
- [déduit] Cet ancrage est rafraîchi au rythme du tick du `SessionController` (200 ms,
  `session_controller.dart:49`) : dérive bornée à cette fenêtre, non mesurée en conditions réelles.
- [déduit] Aucun gel runtime n'est modélisé (report TTS, gate posture, gel de défi) : la prévision
  se base sur le `time` nominal des steps, pas sur ce que `SessionController._checkSteps` applique
  réellement au tick près. Une frontière prédite peut donc arriver un peu en avance ou en retard sur
  la vraie bascule — celle-ci reste gouvernée sans changement par le reset existant
  (`_lastBeatAt = null` sur tout changement réel de mode/position/tempo), qui efface la prévision et
  la refait dès le premier vrai bip du nouveau step.
- [déduit] Le cas `from == to` explicite dans un step rythmé/lick à venir (relevé aléatoirement par
  `BeepEngine._pickShallowerThan`, non déterministe) n'est pas répliqué dans le résolveur — la
  prévision affichera `from == to` telle quelle plutôt que la correction aléatoire du moteur.
- [déduit] Aucune mesure de performance : `resolveUpcomingMovementSteps` reparcourt toute la liste
  `session.steps` à chaque rebuild de `SessionScreen` (potentiellement plusieurs fois par seconde,
  tick à 200 ms) — pas jugé problématique vu la taille typique d'une séance, non mesuré.

## Fiche sas déposée

[document] `~/.claude/orchestration/sas/tss2/tss2-002-suckle-hors-classement-familles-trajectoire.md`
— ambiguïté sur le classement de `suckle`, hors-tâche de trancher seul, lecture retenue documentée
ci-dessus et dans le code (`_MovementAnimationState._familyOf`).
