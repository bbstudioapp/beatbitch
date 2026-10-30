---
type: analyse
sujet: relecture-adverse-de-la-seance-fantome
ecrit_le: 2026-10-17T17:03:19+02:00
auteur: session tss2-relecture-fantome · claude-opus-5-5
revision: 57ab7fc
branche: fix/seance-fantome
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/music_engine.dart
  - rhythm_coach/test/session_start_after_dispose_test.dart
provenance:
  mesure: 7
  deduit: 13
  document: 10
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1090
  - rhythm_coach/lib/controllers/session_controller.dart:1173
  - rhythm_coach/lib/controllers/session_controller.dart:1915
  - rhythm_coach/lib/controllers/session_controller.dart:2480
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:132
  - rhythm_coach/lib/screens/session_screen.dart:269
  - rhythm_coach/lib/services/music_engine.dart:87
---

# Relecture adverse — la séance fantôme

[document] Constat `tss2-013`. Relu : `37fb7f1` (banc), `fcf81f1` (correctif), `ca62921` (commentaires), `57ab7fc` (rapport de l'auteur), au-dessus de `ef73c5f`, branche `fix/seance-fantome`. Consigne : réfuter, pas valider. Rien n'a été modifié dans le code ni dans les tests ; mutations et sonde restaurées ou supprimées, `cmp` à l'appui, arbre propre.

## Le rouge

[mesuré] `session_controller.dart` de `37fb7f1` copié sur l'arbre, banc lancé, copie de la tête remise (`cmp` identique). Six échecs sur huit, les deux témoins verts. Messages lus un par un :

- `_tts.init`, wakelock, `music.start` : `Expected: <0> Actual: <1>`, « applyStep sur le BeepEngine partagé après dispose() » ;
- `_beep.init` et `detachAudio` : `Expected: empty`, `Actual` = huit clés `stats.*` plus `badge.tier.sansBroncher`, « une séance jamais jouée a écrit dans le profil » ;
- `_finish` : `Expected: Set:['stats.modes_used_mask']`, `Actual` plus large.

[mesuré] Vert sur la tête trois fois de suite : `+8: All tests passed!`, sept secondes par passage. `ca62921` ne change aucune ligne de code : le diff `fcf81f1..ca62921` privé des lignes de commentaire est vide.

[document] Le banc mesure la vraie fenêtre, pas une construction : il retient les vrais `await` de `start()` (portes dans `TtsService.init`, `BeepEngine.init`, le canal pigeon du wakelock, `port.play`) et appelle `dispose()` comme le fait l'écran — `SessionScreen.dispose()` (`session_screen.dart:269`) appelle `_controller.dispose()` directement. Deux constructions toutefois :

- [document] le cas `_finish` entre par `debugFinishSuccess()`, une porte de debug ; le vrai chemin est `_onTick` (`session_controller.dart:1453`), qui suppose un ticker vivant sur un contrôleur libéré ;
- [document] le faux lecteur `_GatedPort` ne modélise ni l'état « en lecture » ni la création paresseuse du lecteur réel : le banc ne peut pas voir une musique laissée en lecture.

## Couverture des chemins de `start()`

[document] Après la garde du wakelock (`session_controller.dart:1193`), `start()` n'attend plus rien : `_stopwatch.start()`, `_startTicker()`, `_checkSteps()` sont synchrones. Chaque `await` de `start()` est donc suivi d'une garde, sauf un.

[déduit] Le trou restant : la lecture `getMusicBeepAdvanceMs()` (l. 1173), suivie de `music.start(track)` sans garde. Le rapport de l'auteur dit qu'un `dispose()` à cet instant est « rattrapé par la garde après `music.start` ». Pas en production : le `MusicEngine` réel crée son lecteur à la demande (`music_engine.dart:87`), son `dispose()` n'avait donc rien à libérer, et `start()` crée ensuite un lecteur neuf qui joue. La garde de la l. 1177 ne fait que `return` : rien n'arrête ce lecteur, le morceau jouerait jusqu'au bout sans propriétaire. [déduit] La fenêtre est fermée en pratique : `SharedPreferences.getInstance()` est déjà en cache (l'écran lit ses réglages à l'ouverture), la lecture se résout en microtâches, et un `dispose()` déclenché par un frame ne peut pas s'y glisser. Fragilité, pas défaut atteignable.

[déduit] `dispose()` pendant `music.start` lui-même : le lecteur existe alors, `MusicEngine.dispose()` l'arrête et le libère ; un `play()` qui arrive après échoue côté natif (`audioplayers_android` : « Player has not yet been created or has already been disposed », intercepté par `MusicEngine`). Lu dans les sources du paquet, pas joué.

[mesuré] `stop()` pendant `start()` en vol (sonde jetable sur le banc, supprimée) : `SONDE[stop] state=SessionState.idle applied=2 elapsed=0:00:00.506531`. `stop()` annule le ticker avant ses `await`, `start()` le relance entre-temps : état `idle`, horloge qui court, bips envoyés. [document] Atteignable seulement par le bouton STOP des contrôles de debug (`session_screen.dart:1175`) ; en production `canPop` est vrai pendant `start()` depuis `idle`, le retour passe par `dispose()`. Présent avant le correctif, hors de son périmètre : fiche `tss2-028` au sas.

[mesuré] `start()` appelé sur un contrôleur déjà libéré : `beepInit=0 wakelock.enables=0 applied=0 errors=0`, état `idle`.

[document] Mise en arrière-plan pendant le décompte ou pendant `start()` : `pause()` sort sans rien faire tant que l'état est `idle`, et le minuteur du décompte n'est pas suspendu. Hors périmètre, non mesuré : fiche `tss2-027`.

[document] `detachAudio()` puis séance suivante : les trois appelants (`surprise_router.dart:228`, `career_screen.dart:1034`, `custom_mode_screen.dart:314`) partent d'une séance `finished` (bouton « encore » ou enchaînement automatique gardé par `isFinished`) ; `start()` du contrôleur détaché est fini depuis longtemps. La course « wakelock relâché par l'ancien après l'enable du nouveau » n'a pas de geste qui y mène.

## Écrivains de profil depuis un contrôleur libéré

[document] Écrivains du contrôleur : `_finish()` (stats, milestones, badges, capacités), `_onTick` et ses appelés (`recordHoldSecond`, `recordHoldFullCompleted`, `markModeUsed`), `_handleBeat` branché sur le `BeepEngine` partagé (`recordBeat`, `markModeUsed`, l. 698). Les écrivains de l'écran (`CareerProgressService.recordSessionCompleted`, `recordQuickieCompleted`) écoutent le contrôleur, et `ChangeNotifier.dispose()` vide ses écouteurs.

[déduit] Les écrivains de tick ne sont gardés par rien : ils ne courent que si un ticker survit. Le correctif ferme la source de tss2-013. Il en reste une : le flux de fail relance le ticker après un `await` sans revérifier (`session_controller_fail_flow.dart:132-140` et `362-365`), la famille de `tss2-025`. Un ticker relancé là sur un contrôleur libéré écrirait encore par tick ; la garde d'entrée de `_finish` bloque désormais la clôture. La phrase du rapport « aucune écriture ne part d'un contrôleur libéré » est donc trop large : vraie pour `start()` et pour l'entrée de `_finish`, pas pour un `_finish` déjà en vol ni pour les écrivains de tick.

[déduit] `_handleBeat` après libération : le `BeepEngine` ne bat que pendant une séance, et un nouveau contrôleur reprend `onBeat` à sa construction. Pas de chemin trouvé.

## Régression

[document] `_released` n'est posé que par `dispose()` et `detachAudio()`. Chaque séance (encore, cycle custom, Utilise-moi, surprise) pousse un `SessionScreen` neuf qui construit son propre contrôleur (`session_screen.dart:184`) : aucun ne rappelle `start()` sur un contrôleur détaché. `_finish` ne passe `_state` à `finished` qu'après ses écritures : l'enchaînement automatique et le bouton « encore », gardés par `isFinished`, ne peuvent pas détacher avant. Le mode musique a son propre contrôleur. Pas de régression trouvée.

[déduit] Seul cas silencieux : si la poussée de la séance suivante échoue après `detachAudio()` (`if (!context.mounted) return;`), l'écran reste sur un contrôleur détaché, et le bouton de relance des contrôles de debug ne fait plus rien. Debug seulement.

## Mutations

| Mutation [mesuré] | Résultat | Assertion rouge |
|---|---|---|
| M1 (auteur) : garde après `_beep.init` retirée | 2 rouges | wakelock 0 → 1, cas `_beep.init` et `detachAudio` |
| M2 (auteur) : garde d'entrée de `_finish` retirée | 1 rouge | clés ajoutées au profil |
| M3 (mienne) : garde de `_finish` descendue sous `_beep.stop()`, `_releaseMusic()`, `WakelockPlus.disable()` | **vert** | aucune |
| M4 (mienne) : `detachAudio()` pose `_released` après ses `await` | 1 rouge | wakelock 0 → 1, cas `detachAudio` |

[déduit] M3 restée verte : le banc garde les écritures de `_finish`, pas ses arrêts des services partagés. `_GatedBeep.stop()` est un no-op non compté, et le wakelock n'est pas vérifié dans ce cas. Un `_finish` libéré qui coupe le `BeepEngine` couperait la séance suivante ; rien ne le tient.

## Fin de tâche

[mesuré] `flutter test` complet, une seule fois : `+1407: All tests passed!`, sortie 0. `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed .` : 368 fichiers, 0 modifié.

[mesuré] Le rapport de l'auteur (`57ab7fc`) porte encore le bloc « AVERTISSEMENTS DU CONTRÔLE — 1 paragraphe porte un chiffre sans marqueur » et `sans_marqueur: 1`, alors que son compte rendu dit le contrôle propre.

## Verdict par commit

| Commit [déduit] | Verdict | Réserves, de la plus lourde à la plus légère |
|---|---|---|
| `37fb7f1` banc | publiable avec réserves | 1. M3 verte : arrêts des services partagés de `_finish` non tenus. 2. Cas `_finish` par la porte de debug. 3. Faux lecteur sans état de lecture. |
| `fcf81f1` correctif | publiable avec réserves | 1. Garde de la l. 1177 sans arrêt du lecteur, fenêtre fermée en pratique. 2. Écrivains de tick non gardés (relance du flux de fail, `tss2-025`). |
| `ca62921` commentaires | publiable | Balayage partiel du fichier, annoncé par l'auteur. |
| `57ab7fc` rapport | publiable avec réserves | 1. « rattrapé par la garde après `music.start` » faux en production. 2. « aucune écriture ne part d'un contrôleur libéré » trop large. 3. Avertissement du contrôle resté. |

## Ce que je n'ai pas pu établir

- [déduit] Le comportement natif d'un `play()` après `dispose()` sur web (PWA) et iOS : seules les sources Android d'`audioplayers` sont lues.
- [déduit] La largeur réelle des fenêtres sur téléphone ; aucun son joué, rien sur appareil.
- [déduit] Qu'un `dispose()` puisse vraiment tomber pendant l'`await _restorePreviousLoop()` du flux de fail : chemin lu, pas rejoué.
- [déduit] Qu'aucun écrivain de profil n'existe hors des fichiers lus (contrôleur et ses `part`, écran de séance, trois appelants de `detachAudio`).
- [déduit] La fin de la séance après `stop()` pendant `start()` (sonde arrêtée avant la durée).
