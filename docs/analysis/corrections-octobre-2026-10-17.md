---
type: analyse
sujet: corrections-octobre
ecrit_le: 2026-10-17T12:25:23+02:00
auteur: session tss2-corrections · claude-opus-5-5
revision: 56266ca
branche: fix/corrections-octobre
porte_sur:
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/services/ambience_engine.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/beep_engine_hold_swing_pause_test.dart
  - rhythm_coach/test/finish_music_test.dart
  - rhythm_coach/test/session_music_controller_test.dart
  - rhythm_coach/test/session_punishment_breath_screen_test.dart
  - rhythm_coach/test/session_reprise_punition_courbe_test.dart
provenance:
  mesure: 16
  deduit: 7
  document: 6
  sans_marqueur: 2
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:545
  - rhythm_coach/lib/services/ambience_engine.dart:331
  - rhythm_coach/lib/services/beep_engine.dart:678
  - rhythm_coach/lib/widgets/movement_animation.dart:854
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 2 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

# Corrections d'octobre — lot des relectures du 17/10

[document] Branche `fix/corrections-octobre`, partie de `chore/fusion-octobre` @ `58ed4e3`. Six commits, aucun
choix de comportement laissé à Manu. Rien d'entendu ni de vu sur le téléphone.

## Bilan

| # | Défaut | Verdict | Commit |
|---|---|---|---|
| 1 | Courbe : épingle de frontière périmée à la reprise (`tss2-019`) | corrigé | `8b10083` |
| 2 | Écran en retard d'un délai de transition à la reprise (`tss2-011`) | corrigé | `fecf23d` |
| 3 | Tenue balancée muette après une pause (`tss2-021`) | corrigé | `c96bbe4` |
| 4 | Musique de finish lancée malgré un fail pendant son démarrage | corrigé | `1ef5068` |
| 5a | M7 / M8 non gardées (musique de finish) | test ajouté | `5fbb5ac` |
| 5b | M2 punition-courbe non gardée (phrase, respiration) | test ajouté | `56266ca` |

Waiver doc: tableau de bilan — chaque ligne renvoie à sa section, marquée.

[mesuré] Fin de lot : `flutter analyze` « No issues found! », suite complète 1374 tests verts
(1361 au départ + 13), 2 min 11 s.

## 1. Courbe : épingle de frontière périmée à la reprise

[mesuré] **Cause rejouée.** `_PositionLadderState._boundaryPins` (horloge murale) garde l'épingle
posée avant le gel ; pendant le gel l'écran passe une liste vide, l'épingle ne sert plus ; à la reprise
la même seconde revient dans la liste, `boundaryAt` garde l'épingle passée. La tenue est peinte
~1,2 à 1,7 s trop tôt, ou la frontière est déjà derrière le curseur et la courbe saute tout le rythme.

[mesuré] **Les défis ont-ils le défaut ?** Oui, mais seulement quand une seconde revient : l'excision
du défi rebase les steps (`_excisChallengeFromSession`), une épingle périmée ne mord que si un step
rebasé tombe sur une seconde épinglée avant le défi (le step d'après la fenêtre l'est toujours). Banc
construit sur ce cas : tenue peinte à ~3,1 s au lieu de ~13,3 s. L'**attente de posture** (même gel,
`isTimelineFrozen`, sans rebase) a le défaut sans condition. La mini-punition aussi (route
`_restorePreviousLoop`).

[document] **Correctif** (`movement_animation.dart`, `_recompute`) : une épingle n'est gardée que pour une
frontière encore dans `upcomingSteps`. Le gel vide la liste, donc toutes les épingles tombent ; la
reprise repart de positions fraîches. Rien ne change tant que la liste ne perd pas de seconde.

[mesuré] **Test** `session_reprise_punition_courbe_test.dart`, 4 routes : FAIL + saut de section,
mini-punition, attente de posture, défi refusé. Chaque image après la reprise : la tenue ne doit pas
être peinte avant `son instant − elapsed − 600 ms`, et pas directement après le curseur. Code d'avant :
4 rouges sur « Images en avance » ; avec correctif : 4 lancements × 4 verts.

[mesuré] Deux pièges du banc, rencontrés et levés : (a) une assertion sur des points discrets entre 1
et 2 s rend un faux vert sur un plateau de tenue (points espacés de 1,8 s) ; (b) à pas de `pump` fixe
le ticker simulé (−200 ms par tick sous gel) et le `Stopwatch` réel divergent et l'horloge « gelée »
glisse d'environ un tiers ; la tranche avance désormais l'horloge simulée du temps réel écoulé.

[déduit] **Rapprochement avec la réserve « `_recompute` consomme `_pausedAt` pendant la pause »**
(relecture `courbe-reprise-pause`). Même famille — des instants muraux qui survivent à un arrêt de
l'horloge de séance — mais un autre trou : la pause garde la liste pleine et compense par
`_resumeClock`, donc ce correctif ne la touche pas. La réserve reste ouverte et non sondée.

[déduit] **Non établi.** Le rendu sur téléphone. Les autres rebases de timeline (régénération post-défi,
« Utilise-moi ») qui pourraient remplacer un step par un autre **sur la même seconde sans liste vide
entre les deux** : l'épingle survivrait. Non construits.

## 2. Écran en retard d'un délai de transition à la reprise

[mesuré] **Cause rejouée.** `applyStep` pose le mode tout de suite puis attend son délai (600 ms
tenue → rythme) ; `_restorePreviousLoop` l'attendait avant toute notification. Mesure : l'écran
montre le rythme 571 à 674 ms après le moteur (mini-punition et FAIL sans section suivante).

[document] **Correctif** (`session_controller_fail_flow.dart`) : `_notify()` entre le lancement d'`applyStep` et
son attente. Les deux routes (FAIL, mini-punition) passent par là.

[mesuré] **Test** (même fichier, 2 cas) : écart moteur → écran < 400 ms. Code d'avant : rouge ×2 ;
mutation « `_notify()` retiré » : rouge (590 et 653 ms), restaurée par copie, `cmp` vert ; avec
correctif : 3 lancements verts.

[mesuré] Vérifié en marge, sans défaut : pendant la respiration d'avant-punition, l'écran montre bien
la respiration (38 images sur 38).

[déduit] **Non établi.** La route `_skipToNextSection` n'avait pas ce retard (step appliqué sans attente, cf.
fiche) : non remesurée. Le lien avec les « sauts d'une demi-seconde » de Manu.

## 3. Tenue balancée muette après une pause

[mesuré] **Cause rejouée.** `resume()` ne relançait que `_startHoldMoves()`. Moteur seul et
`SessionController.pause()/resume()` : aucun bip après la pause.

[document] **Correctif** (`beep_engine.dart`) : les allers-retours d'une tenue ancrée gardent leur progression
comme les mouvements de tenue (`_holdElapsedMs` figé par `pause()`), et `resume()` les reprend là où
ils s'étaient arrêtés, décalés de la pause. La condition d'ancrage est partagée par `applyStep` et
`resume()` (`_holdSwings`). Le coup de départ (position + nappe de tenue) n'est pas rejoué à la
reprise, comme pour une tenue non ancrée.

[mesuré] **Test** `beep_engine_hold_swing_pause_test.dart` (moteur, contrôleur) : le 1er bip après la
pause est l'aller-retour suivant, à ±120 ms de son instant + la pause. Code d'avant : rouge « aucun
bip après la pause » ×2 ; mutation `resume()` revenu à `_startHoldMoves()` : rouge ; mutation « pas
de saut des allers-retours déjà joués » : rouge (rafale immédiate à la reprise) ; restaurées par
copie, `cmp` vert. Vert ×3 avec les tests voisins des tenues.

[déduit] **La courbe et le son.** La courbe ne dessine pas le balancement (le widget ne reçoit ni
`anchor` ni `ratio`, la boucle balancée n'émet pas de `BeatEvent`) : elle montre une tenue plate avant
comme après la pause. Le correctif ne crée pas de divergence ; l'absence du balancement à l'écran est
antérieure.

[déduit] **Non établi.** Une pause tombée exactement sur un bip : le bip à l'instant de la pause est sauté
(comparaison stricte, comme pour les mouvements). Le rendu sonore réel.

## 4. Musique de finish lancée malgré un fail pendant son démarrage

[mesuré] **Cause rejouée.** `fadeOutFinishMusic` sortait sans rien faire tant que `_finishPlaying`
était faux, donc pendant tout `startFinishPlayback` ; le démarrage aboutissait ensuite. Démarrage
simulé de 300 ms, fondu à 50 ms : `isFinishMusicPlaying` vrai.

[document] **Correctif** (`ambience_engine.dart`) : un fondu qui suit directement un démarrage encore en vol
incrémente `_finishGen`, ce qui fait arrêter le lecteur par le démarrage lui-même. Un fondu demandé
pendant un autre fondu reste sans effet, comme avant (sinon le premier s'interromprait à mi-volume).

[mesuré] **Test** `finish_music_test.dart` : rouge sur le code d'avant (`Actual: <true>`), mutation
de la ligne d'annulation : rouge, restaurée. Garde anti-vide : le fondu tombe bien pendant le
démarrage.

[déduit] **Non établi.** Le test lit le drapeau, pas l'arrêt du lecteur : `finish_music.mp3` n'est pas dans le
dépôt (R2), le vrai `startFinishPlayback` échoue en test. Le chemin d'arrêt (`_finishPlayer?.stop()`
sur génération changée) est celui que `stopFinishMusic` utilisait déjà. Un démarrage qui dépasse
`_startTimeout` (3 s) puis aboutit côté plateforme n'est pas couvert (préexistant, fiche
`tss2-023`).

## 5. Trous de tests

[mesuré] **M7** (garde `_music != null` du finish) : test dans `session_music_controller_test.dart`,
séance musicale avec `silentFinishStartTime` et `finalStepTime` ; mutation : rouge
(`Actual: [0:00:50]`).

[mesuré] **M8** (`_finishMusicStarted = false` sur fail) : deux tests dans `finish_music_test.dart`,
FAIL et mini-punition pendant la montée ; attendu `['start 16s', 'start 12s']`. Mutation ligne 99
(FAIL) : seul le test FAIL rougit (`['start 16s']`) ; mutation ligne 464 (mini-punition) : seul le test
mini-punition rougit. Restaurées par copie, `cmp` vert.

[mesuré] **M2 punition-courbe** : test dans `session_punishment_breath_screen_test.dart`, phrase de
fail allongée à 1,5 s par la synthèse simulée ; aucune image des phases `phrase` et `breath` ne doit
passer d'instant de séance à la courbe. Mutation M2 (garde réduite à `FailPhase.punishment`) : rouge
« phrase : 4 s, 60 s » ; garde retirée : rouge. Restaurées par copie. Le test lit la propriété
`upcomingSteps` reçue par `MovementAnimation`, pas la courbe peinte.

## Ce que je n'ai pas pu établir

- [document] Nettoyage des commentaires des fichiers touchés (commits « commentaires seulement ») : non fait,
  faute de budget de session.
- [déduit] Réserve `_recompute` / `_pausedAt` : non sondée (§1).
- [mesuré] Le saut de section garde la fraction de seconde du FAIL (`_skipToNextSection` avance de
  secondes entières : reprise à 4,5 s pour un step à 4 s). Préexistant, sans effet mesuré ici.
