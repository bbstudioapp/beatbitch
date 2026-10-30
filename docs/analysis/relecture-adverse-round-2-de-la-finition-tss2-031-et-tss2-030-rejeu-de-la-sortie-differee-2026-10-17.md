---
type: analyse
sujet: relecture-adverse-round-2-de-la-finition-tss2-031-et-tss2-030-rejeu-de-la-sortie-differee
ecrit_le: 2026-10-17T20:40:11+02:00
auteur: session tss2-relecture2-arriere-plan-2 · claude-opus-5-5
revision: d79294e
branche: fix/arriere-plan-punition-enchainement
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/mode_selection_screen.dart
  - rhythm_coach/lib/services/capability_tracker.dart
  - rhythm_coach/test/session_arriere_plan_demarrage_test.dart
provenance:
  mesure: 11
  deduit: 4
  document: 3
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:964
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:154
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:169
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:432
  - rhythm_coach/lib/screens/mode_selection_screen.dart:61
  - rhythm_coach/lib/services/capability_tracker.dart:382
---

# Relecture adverse, second tour — rejeu de la sortie différée d’un fail

[document] Branche `fix/arriere-plan-punition-enchainement`, diff `7c2b752..d79294e` seul. Consigne : réfuter, pas valider. Rien fusionné, rien poussé, ni code ni test modifiés ; sonde jetable (copie du banc, 7 cas) supprimée, mutations restaurées par copie (`cmp`), arbre propre.

## Verdict par commit

- [mesuré] `cbce790` (correctif R1) — **publiable avec réserves**. R1 est fermée pour le fail, la pause, « Terminer maintenant », l'état et l'horloge : sur le code de `7c2b752`, les 3 tests de l'auteur et 3 cas de la sonde sont rouges (fail lancé pendant le rejeu, pause acceptée, `running` après `stop()`, horloge relancée après `dispose()`, `canTriggerFail` vrai dans la fenêtre) ; tous verts sur la tête. Elle reste ouverte pour l'ambiance (R7).
- [mesuré] `c81d564` (banc R3) — **publiable**. Mutation `mayJump: true` rejouée : 4 rouges, dont les deux assertions d'identité `_step0`.
- [document] `a0587b9` (commentaires seulement) — **publiable**. Une ligne de commentaire ; `capability_tracker.dart:382` `_ceilFrom` ne garde que le minimum, le second `onFail()` ne change rien.
- [mesuré] `d79294e` (rapport) — **publiable avec réserves**. Les rouges et les mutations annoncés sont retrouvés. Faux sur un point : « `dispose()` passe par la même garde que `stop()` » ne vaut que pour l'horloge. Le rapport ne dit rien de l'ambiance relancée (R7).

## Réserves

1. **R7 — mineure, à trancher avant fusion.** [mesuré] `stop()` ou `dispose()` pendant la fenêtre : `_restorePreviousLoop` appelle encore `_syncAmbienceToCurrentMode()` après le `await applying`. Il passe donc avant la garde posée en sortie de `_restorePreviousLoop`. Mesure : un `playForMode` sur la tête, deux sur `7c2b752`. [déduit] L'`AmbienceEngine` est partagé (`mode_selection_screen.dart:61`) : une ambiance peut repartir sur le menu après « quitter ». La sortie au premier plan a le même trou, déjà présent avant ce diff.
2. **R8 — mineure.** [mesuré] Mutation témoin : le `finally` de `_replayDeferredFailExit` sans contrôle de génération (`if (true)`) laisse le banc vert (20/20). [déduit] Ce contrôle ne compte que pour `stop()` + `start()` + nouveau fail pendant la latence de `applyStep` : il est juste, mais rien ne le garde.
3. **R9 — mineure.** [mesuré] `dispose()` dans la fenêtre : le `_notify()` du `finally` (`session_controller_fail_flow.dart:164`) lève « A SessionController was used after being disposed ». Sur `7c2b752`, la même assertion venait d'un autre point. [déduit] Assertion de débogage, sans effet en release.
4. **R10 — préexistante, inchangée.** [mesuré] Un rejeu qui lève (erreur de `applyStep`) relâche `_failActive`, donc pas de boutons morts. Mais la séance reste en `running`, l'horloge figée (1,37 s → 1,37 s). Même mesure sur `7c2b752`.

## Pistes réfutées

- [mesuré] `_failActive` collé à vrai : non. Ni après un rejeu qui lève (R10), ni après `pause()` + `resume()` dans la fenêtre (les deux refusés, puis `running`, horloge qui avance), ni après un retour en arrière-plan pendant le rejeu (`paused`, reprise au bouton, `canTriggerFail` vrai). Ce dernier cas est vert aussi sur `7c2b752`.
- [mesuré] Fail légitime après le rejeu : accepté, il sort en `running`.
- [document] Pendant le rejeu, `resume()` ne peut pas entrer deux fois : tout ce qui précède `_state = running` est synchrone (`session_controller.dart:964`). Les gardes ajoutées ne touchent ni le mode musical (`_triggerMusicalFail`, mini-punition coupée par `_accrueMiniPunishmentTick`) ni le défi (`triggerFail` sort).
- [mesuré] Premier plan : suite complète 1430 verts (2 min 26 s), `flutter analyze` sans remarque, `dart format --set-exit-if-changed .` 0 fichier modifié, banc ×3 à 20/20.
- [mesuré] Mutation ajoutée : la sortie différée reçoit l'ancienne génération au lieu de `replayGen` → 2 rouges, sur l'horloge qui ne repart pas.

## Ce que je n'ai pas pu établir

[déduit] La largeur réelle de la fenêtre sur le S21 et qu'un humain l'atteigne ; qu'une ambiance soit audible sur le menu après R7 (faux moteur au banc) ; la punition de tenue, couverte seulement par la suite ; le comportement réel de `notifyListeners` après `dispose()` en release. Rien joué sur téléphone, aucun son, aucune compilation Android.
