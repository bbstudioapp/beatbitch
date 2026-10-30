---
type: analyse
sujet: relecture-adverse-du-correctif-tss2-031-et-tss2-030-sortie-d-un-fail-et-ecran-monte-en-arriere-plan
ecrit_le: 2026-10-17T20:07:34+02:00
auteur: session tss2-relecture-arriere-plan-2 · claude-opus-5-5
revision: c6fbd1f
branche: fix/arriere-plan-punition-enchainement
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_arriere_plan_demarrage_test.dart
provenance:
  mesure: 13
  deduit: 5
  document: 14
  sans_marqueur: 0
sources_citees: []
relu_contre: ⚠️ NON RENSEIGNÉ
---

# Relecture adverse — sortie d’un fail en arrière-plan et écran monté en arrière-plan

[document] Branche `fix/arriere-plan-punition-enchainement`, commits `e6f8b5d..c6fbd1f`. Consigne : réfuter, pas valider. Rien fusionné, rien poussé, ni code ni test modifiés ; sondes et rouges dans des worktrees jetables, supprimés.

## Verdict par commit

- [mesuré] `34503fe` (correctif) — **publiable avec réserves**. Les deux défauts tombent au banc (7 rouges sur `e6f8b5d`, verts sur la tête ×3). Réserve majeure R1 : la sortie différée est rejouée hors de la garde `_failActive`, ce qui ouvre une fenêtre où « JE PEUX PAS » casse l'état de la séance.
- [mesuré] `c27fa7d` (banc) — **publiable avec réserves**. Rouges pour la bonne raison (messages lus) ; trou R3 : le non-saut de la mini-punition différée n'est gardé par rien.
- [mesuré] `e7ab84f` (témoin musical) — **publiable**. Vert avant et après le correctif, comme annoncé pour un témoin.
- [mesuré] `d6c2816` (commentaires seulement) — **publiable avec réserve mineure** R6 : code identique hors commentaires, un pourquoi technique utile retiré.
- [document] `c6fbd1f` (rapport) — **publiable avec réserves** : rouges et mutations M1/M2 retrouvés ; il ne dit rien de la fenêtre R1.

## Réserves classées

1. **R1 — majeure, à trancher avant fusion.** [mesuré] Sonde jetable (vrai `SessionScreen`, mini-punition, arrière-plan, retour, `applyStep` de la restauration tenu par le faux moteur) : pendant la reprise rejouée, `isRunning=true`, `isFailFlowActive=false`, `canTriggerFail=true`. Un `triggerFail()` tiré dans la fenêtre lance un nouveau flow (`failing/breath`) ; à la fin de la restauration, `_completeFailExit` repose `running` avec `failPhase=breath` et `isFailFlowActive=true`, l'horloge court pendant la respiration (1,71 s → 3,14 s) et la séance arrive à `finished` en plein flow. Même fenêtre avec `pause()` : la pause posée est écrasée, l'horloge repart (2,03 s → 3,25 s) et la séance va à `finished`.
   [document] Cause : `resume()` appelle `_completeFailExit` après le `finally` du flow, donc sans `_failActive` ni contrôle de génération ; `_restorePreviousLoop` pose `running` et notifie avant ses deux `await` (`applyStep`, `_syncAmbienceToCurrentMode`). Au premier plan, la même restauration se fait sous `_failActive` : bouton principal, « JE PEUX PAS », « Utilise-moi » et « Terminer maintenant » restent désactivés. Dans le chemin différé, les quatre sont actifs pendant la fenêtre ; « JE PEUX PAS » est visible en production, le bouton pause n'est qu'un réglage de debug.
   [déduit] Exposition : chemins sans saut seulement (mini-punition, fail complet sans section suivante) ; il faut taper « JE PEUX PAS » juste après la reprise. La largeur de la fenêtre sur le S21 n'est pas mesurée.
2. **R2 — moyenne, à trancher par Manu.** [déduit] tss2-030 sur téléphone : sans frame en arrière-plan (`paused`/`hidden`), l'écran poussé par l'enchaînement ne se construit qu'au retour ; la lecture au montage n'agit que si l'appli est `inactive` à ce moment (frames actives). Le banc construit l'écran malgré l'arrière-plan : son rouge tss2-030 ne prouve pas le gain sur l'appareil. L'auteur le signale déjà.
3. **R3 — mineure, trou de filet.** [mesuré] Mutation à moi : la sortie différée forcée à `mayJump: true` (mini-punition) laisse le banc vert, 17/17. [document] `_shortSession` n'a qu'un step : il n'y a rien où sauter, la mutation n'est pas posée. Le non-saut d'une mini-punition rejouée n'est gardé par aucun test du banc.
4. **R4 — mineure.** [document] `_relayLifecycle` au montage traite `inactive` comme l'arrière-plan. Sur le web, l'état vaut `resumed` au départ et passe à `inactive` sur `blur` de la fenêtre (source du moteur, `app_lifecycle_state.dart`) ; sur Android, `inactive` quand la fenêtre perd le focus. [déduit] Un écran monté dans cet état démarre en pause : un appui suffit, aucun son ne fuit, et c'est la sémantique déjà donnée aux événements par tss2-027. Je n'ai trouvé aucun parcours qui monte une séance juste après une boîte système.
5. **R5 — mineure.** [document] Le rapport de l'auteur ne mentionne pas la fenêtre R1 ; ses affirmations vérifiées tiennent par ailleurs.
6. **R6 — mineure.** [mesuré] `d6c2816` : seule ligne de code touchée, `await _beep.stop();` perd son commentaire de fin de ligne. [document] Retiré : « `onFail` est idempotent », le pourquoi du double appel `_capabilityTracker?.onFail()` dans `triggerFail` (branche retry puis flow) ; sans lui, le second appel ressemble à un double comptage.

## Pistes examinées

### 1. Rouge et vert
[mesuré] Worktree jetable à `e6f8b5d` avec les tests de la tête : 7 rouges, 38 verts. Messages lus : `état finished au lieu de paused`, `applyStep ×1`, horloge qui avance, `profil écrit : [stats.total_seconds, stats.sessions_completed, …]` pour la mini-punition, le fail complet, le départ pendant la restauration et l'écran monté en arrière-plan ; `running` au lieu de `paused` pour les deux tests de sortie périmée, rouges sur leur précondition. Tête : 45/45 trois fois de suite (banc et test musical).

### 2. `_deferredFailExit` rejoué par `resume()`
- [document] Rejoué deux fois : non, le champ est remis à `null` avant l'`await`, et un second `resume()` sort sur `_state != paused`.
- [document] Après `stop()` : `idle`, `resume()` ignoré, `start()` depuis `idle` remet le champ à `null`. Le nettoyage retiré de `stop()` est bien redondant : rien ne repasse en `paused` sans `start()`. Test « stop() l'abandonne » vert.
- [document] Nouveau `triggerFail`, « Terminer maintenant », fin de séance pendant la pause : impossibles (`canTriggerFail` et le bouton exigent `running`, ticker arrêté). Pendant la reprise rejouée : possibles, voir R1.
- [déduit] Saut de section : `_skipToNextSection` est évalué à la reprise sur une horloge et un `_nextStepIndex` figés pendant la pause ; le chemin avec saut n'a aucun `await` avant `running`.
- [document] Perte : arrière-plan pendant la restauration rejouée → `_pauseAfterFail` sans réarmer la sortie ; la reprise suivante passe par le `resume()` normal, la boucle est déjà appliquée.
- [document] Pause manuelle juste après une punition au premier plan : chemin inchangé, toujours sous `_failActive`.

### 3. Régression au premier plan
[document] Au premier plan, `_completeFailExit` est le code d'avant à l'identique (`mayJump` faux pour la mini-punition, comme avant) ; seule la relecture d'arrière-plan après la restauration est neuve. `_triggerMusicalFail`, défi (`isChallengeActive`), retry de jalon (avant `_failActive`) et Utilise-moi ne passent pas par `_leaveFailFlow`. `pause()` inchangé. [mesuré] Suite complète : 1427 tests verts, comme annoncé.

### 4. `_relayLifecycle` au montage
[document] Voir R4. `case null` ignoré : un état inconnu au montage ne bloque rien.

### 5. Profil
[mesuré] Chemins couverts par le banc (mini-punition, fail complet, départ pendant la restauration, écran monté en arrière-plan) : aucune clé `stats.*` écrite pendant l'absence. [déduit] Dans la fenêtre R1, la séance atteint `finished` : l'écriture au profil y est probable, non mesurée.

### 6. Commentaires seulement
[mesuré] Voir R6. Diff `d6c2816^..d6c2816` : toutes les lignes `+`/`-` sont des commentaires, sauf le commentaire de fin de ligne retiré.

### 7. Mutations et arbre
[mesuré] Une à la fois, restaurées par copie, `cmp` vérifié : M1 (auteur, sortie sans lecture de l'arrière-plan) → 3 rouges ; M2 (auteur, `resume()` ne rejoue pas) → 2 rouges ; M3 (moi, `mayJump: true` forcé) → 0 rouge, voir R3. `HEAD` : `git diff e6f8b5d..HEAD -- lib` ne montre que le correctif, arbre propre avant et après. [mesuré] `flutter analyze` : No issues found ; `dart format --set-exit-if-changed .` : 0 fichier modifié.

## Ce que je n'ai pas pu établir
- La largeur de la fenêtre R1 sur le S21 (latence réelle de `applyStep` et de l'ambiance), ni qu'un humain la touche.
- Que la séance écrive au profil dans la fenêtre R1 (non lu sur la sonde).
- Les deux défauts sur téléphone : timers Dart en arrière-plan, valeur de `lifecycleState` au montage, frames à `inactive`.
- Que le vrai `BeepEngine` et l'ambiance repartent proprement à la reprise rejouée : lu (`applyStep` relance la boucle après `pause()`, `_syncAmbienceToCurrentMode` relance l'ambiance), non joué.
- Que le test musical `e7ab84f` rougisse sans `unawaited(pause())` : mutation non rejouée.
- Une sortie retenue puis `dispose()` : non examiné au-delà de l'écran détruit.
- Si `onFail` du tracker est réellement idempotent (R6) : lu en partie seulement.
