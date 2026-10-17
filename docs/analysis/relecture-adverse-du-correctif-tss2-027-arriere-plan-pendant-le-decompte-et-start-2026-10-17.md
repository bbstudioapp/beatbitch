---
type: analyse
sujet: relecture-adverse-du-correctif-tss2-027-arriere-plan-pendant-le-decompte-et-start
ecrit_le: 2026-10-17T18:59:34+02:00
auteur: session tss2-relecture-arriere-plan · claude-opus-5-5
revision: a35c594
branche: fix/demarrage-arriere-plan
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_arriere_plan_demarrage_test.dart
provenance:
  mesure: 14
  deduit: 9
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:767
  - rhythm_coach/lib/controllers/session_controller.dart:892
  - rhythm_coach/lib/controllers/session_controller.dart:974
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:138
  - rhythm_coach/lib/screens/session_screen.dart:288
  - rhythm_coach/lib/screens/session_screen.dart:563
---

## Objet

[document] Relecture adverse de `249f413..a35c594` sur `fix/demarrage-arriere-plan` (tss2-027, séance qui démarre appli en arrière-plan) : `908b7cb` correctif, `5ccbcb5` tests, `71ce087` commentaires seulement, `a35c594` rapport de l'auteur. Consigne : chercher à réfuter. Rien fusionné, rien poussé, aucun son joué, aucune compilation Android.

## Verdicts

- `908b7cb` (correctif) : **publiable avec réserves**. Le défaut de la fiche est fermé sur les deux chemins rejoués, sans régression mesurée au premier plan ; deux portes de la même famille restent ouvertes hors mandat (R1, R2).
- `5ccbcb5` (tests) : **publiable avec réserves** (R6, R7).
- `71ce087` (commentaires seulement) : **publiable**.
- `a35c594` (rapport) : **publiable avec réserves** (R8).

## Réserves classées

**À trancher par Manu avant fusion (même famille, hors mandat, pas des régressions)**

- R1 [mesuré] Punition en arrière-plan : `pause()` sort pendant un fail (`_failActive`), et la sortie du fail repasse en `running` sans lire `appInBackground`. Sonde sur banc (séance de 120 s, punition de 4 s, `inactive/hidden/paused` pendant la respiration) : sortie du fail après 17,6 s réelles, `state=running appInBackground=true`, `applyStep` reparti (2 appels pendant la respiration, 4 en fin de sonde). Fiche `sas/tss2/tss2-031`.
- R2 [mesuré] Écran monté appli déjà en arrière-plan (tss2-030) : sonde avec `paused` posé avant `pumpWidget`, `autoStart` → `lifecycleState=paused framesEnabled=false appInBackground=false`, séance `running`, `stats.modes_used_mask` écrit. [déduit] Le banc force des frames que l'appareil ne produit pas en arrière-plan (`framesEnabled=false`) : sur téléphone, l'écran poussé par l'enchaînement ne se construirait qu'au retour, et la séance partirait alors seule mais au premier plan. Le déclenchement réel n'est pas établi.

**Mineures (conformes au mandat, coût d'usage à confirmer)**

- R3 [mesuré] `inactive` compte comme arrière-plan. Volet de notifications 500 ms pendant le décompte : décompte remis à 7, phrase de mise en place re-prononcée (+1 `speak`), séance `running` 7 s après le retour. Volet pendant `start()` en vol : la séance arrive en `paused` (0 step, horloge à 0) alors que la joueuse est au premier plan. [document] Sur le web, `blur` de la fenêtre donne `inactive` (`flutter_web_sdk/.../app_lifecycle_state.dart:93`) ; sur Android, la perte de focus de fenêtre aussi (`LifecycleChannel` : `noWindowsAreFocused`, `appIsInactive`, chaînes du jar d'embedding). Aucune boîte de permission n'est ouverte pendant `start()` : la seule demande (`Permission.camera.request()`) est faite par `CameraMotionService.buildVerifierIfEnabled` avant le `push` de l'écran (`custom_mode_screen.dart:250`).
- R4 [mesuré] Séance à morceau : retirer `await _music?.pause()` du chemin « en pause » laisse les 7 tests verts (mutation M3), et aucun autre test ne combine cycle de vie et musique (recherche dans `test/`). [déduit] `music.start(track)` précède la vérification : un arrière-plan survenu avant laisse sonner le morceau le temps de `WakelockPlus.enable()` (borné à 300 ms) plus la latence de la pause.
- R5 [déduit] Le texte d'introduction continue d'être lu en arrière-plan (état `_introPending`, `_prepCountdown == null` : le relais sort) ; rien ne démarre sans PRÊT. Inchangé par le correctif.

**Tests (`5ccbcb5`)**

- R6 [mesuré] Sur `249f413`, 6 rouges sur 7, témoin vert ; mais les 6 tombent sur la première assertion d'état de leur test (l. 159, 179, 209, 226, 241, 255). Le redémarrage à 7 (l. 184) et l'absence de rythme par défaut (l. 262) ne sont prouvés que par mutation. M2 rougit bien l. 262 (bonne assertion).
- R7 [déduit] Le banc pilote le vrai `didChangeAppLifecycleState` du vrai `SessionScreen` par `handleAppLifecycleStateChanged`, donc la bonne fenêtre côté Dart ; mais il pompe des frames pendant `paused`, ce que l'appareil ne fait pas, et le cas « `start()` appelé déjà en arrière-plan » appelle `ctrl.start()` directement, pas par un chemin d'écran. `inactive` seul n'est jamais joué.

**Rapport (`a35c594`)**

- R8 [mesuré] `relu_contre: session_controller.dart:1090` pointe, à la révision déclarée `71ce087`, sur `_accrueHoldSecond` (le code relu est à l. 767, 892, 974). Le message « le retour dans l'appli a relancé la séance seul » cité comme rouge de reprise tombe sur `249f413` parce que `start()` a fini en `running` en arrière-plan, pas à cause du retour.

## Régression au premier plan

- [document] `_configApplied` ne vaut `false` qu'entre la remise à zéro de `start()` et le premier step posé, et après `stop()` (`session_controller.dart:795`, `:1012` ; écritures à `true` à `:1269` et `session_controller_challenge.dart:918`). Pause manuelle, retour d'arrière-plan en `running`, sortie de défi, de punition (`_restorePreviousLoop` rejoue `applyStep`, pas `resume`), Utilise-moi et séance musicale reprennent tous après un step posé : la garde y est transparente.
- [mesuré] Mutation M4 (`resume()` ne relance jamais le moteur) sur les 8 fichiers de test qui appellent `resume()` : 1 rouge, `beep_engine_hold_swing_pause_test.dart:191` (« les allers-retours reprennent après pause() / resume() »). Une reprise légitime reste gardée.
- [document] Enchaînement Custom et carrière : `pushReplacement` d'un nouvel écran `autoStart: true` (`custom_mode_screen.dart:341`, `career_screen.dart:1132`) — nouveau contrôleur, d'où R2. La surprise est ouverte par une notification, donc au premier plan.

## Profil

- [mesuré] Dans les chemins couverts (décompte, `start()` en vol, retour avant la fin), aucune clé `stats.*` n'est écrite (tests l. 168, 213). [mesuré] Hors couverture, la sonde R2 écrit `stats.modes_used_mask` ; [déduit] R1 peut aller jusqu'à `finished`.

## Commit `71ce087`

- [mesuré] Code hors commentaires identique : comparaison après retrait des commentaires (en respectant les chaînes) et normalisation des blancs, `5ccbcb5` contre `71ce087` — 0 ligne d'écart sur `session_controller.dart` (1363 lignes de code) et sur `session_screen.dart` (2635). Aucune directive `ignore:` retirée.
- [mesuré] 23 blocs supprimés ou condensés échantillonnés dans `session_controller.dart`, dont tous ceux portant Android, Safari, plugin, QUEUE_FLUSH, race ou ordre : les pourquoi techniques sont conservés en version courte (borne d'attente TTS, `_stopTtsBounded`, `ttsSpeakTimeout` non aligné sur le watchdog, ordre `_updateChallengePhase`/break avant `_checkSteps`, course `flutter_tts` sur Android, `detachAudio`, stops séquentiels du `dispose`). Les 8 blocs supprimés sans remplacement sont du quoi ou du pourquoi fonctionnel. Retirés à raison : la calibration chiffrée des bornes TTS (dépend du contenu, peut devenir fausse sans que le code change), les renvois `issue #77` et `6ebdb84`.

## Mesures

- [mesuré] Banc `session_arriere_plan_demarrage_test.dart` : 7/7 verts sur la tête, ×3 ; 6 rouges sur `249f413` (worktree jetable).
- [mesuré] Mutations, chacune seule, restaurée par copie (`cmp` ok) : M1 fin de `start()` sans pause → 4 rouges (l. 209, 226, 241, 255) ; M2 `resume()` sans `_configApplied` → 1 rouge (l. 262) ; M3 `music.pause()` retiré → 0 rouge ; M4 `resume()` sans `_beep.resume()` → 1 rouge hors banc.
- [mesuré] `flutter analyze` : No issues found ; `dart format --set-exit-if-changed .` : 0 fichier changé ; suite complète : 1416 tests verts (2 min 20 s).

## Ce que je n'ai pas pu établir

- [déduit] Que les timers Dart tournent en arrière-plan sur le S21 et en PWA iOS, condition de la gravité de tss2-027 comme de R1 ; rien n'a été joué sur téléphone ni dans un navigateur.
- [déduit] Le déclenchement réel de R2 sur appareil (frames désactivées en arrière-plan) et la valeur de `lifecycleState` à la construction d'un écran poussé pendant l'absence.
- [déduit] Ce qu'entend la joueuse pendant la fuite de musique de R4 ; le chemin `_triggerMusicalFail` en arrière-plan ; les défis en arrière-plan.
- [déduit] Que R1 aille jusqu'à `finished` et écrive au profil (non attendu sur le banc).
