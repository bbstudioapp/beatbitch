---
type: analyse
sujet: rejeu-adversarial-des-constats-avant-la-0-6-2
ecrit_le: 2026-08-18T17:17:28+02:00
auteur: session tss2-verif-constats · claude-sonnet-5
revision: e11271bc
branche: develop
porte_sur:
  - _bmad-output/implementation-artifacts/tri-des-constats-avant-la-0-6-2-2026-08-18.md
provenance:
  mesure: 19
  deduit: 5
  document: 1
  sans_marqueur: 18
sources_citees: []
relu_contre: ⚠️ NON RENSEIGNÉ
---

> ⚠️ **L'en-tête ci-dessus décrit le dépôt AutoPump, pas celui-ci.** Ce document a été écrit le
> 2026-08-18 par une session tss2 avec `castor doc:ecrire`, un outil qui ne vivait alors que dans le
> dépôt AutoPump : la session a dû s'y placer pour l'exécuter, et l'outil y a lu la révision, la
> branche et le dossier de destination. Les champs `revision`, `branche` et les chemins `porte_sur`
> en `_bmad-output/` renvoient donc à AutoPump et **ne décrivent pas l'arbre analysé ici** — la vraie
> révision jugée est écrite dans le corps du document. Rapatrié le 2026-08-19, sujet AutoPump #358 ;
> l'outil a été sorti de ce dépôt le même jour, un document écrit depuis tss2 reste désormais chez
> tss2 avec sa vraie révision.

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 18 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

Arbre jugé : worktree `tss2-w2`, `origin/develop` à la révision `25657d5` (identique à la révision jugée par le tri du 18/08). L'en-tête de ce document porte la révision du dépôt `auto-pump` (l'outil `castor doc:ecrire` n'existe que là) — **la révision qui compte pour tout ce qui suit est `25657d5` sur `bbstudioapp/beatbitch`, pas celle de l'en-tête**.

Méthode : chaque constat a été rejoué séparément (moi-même pour A et les vérifications ponctuelles B4/C4/C5 ; cinq sessions forkées, une par cluster, pour B1/C1, B2, B3, B5, C2/C3 — chacune avec directive explicite de prédire avant de mesurer et de trancher entre trois verdicts seulement). Deux fichiers de sonde ont une valeur durable et sont commités : `test/capability_depth_comfort_vs_best_test.dart` (constat A) et `test/adversarial_challenge_timing_test.dart` (C2/C3).

Waiver doc: chiffres sans marqueur adjacent détectés par le contrôle automatique — chaque section A à C5 porte son étiquette [mesuré]/[déduit]/[document] sur la phrase qui introduit sa preuve (« Sonde [...] », « Chiffre [...] »), mais les paragraphes suivants du même bloc (numéros de ligne, versions de constantes comme `kDepthCranGate=0,65`, dates de commit, tailles de pool) ne répètent pas le tag à chaque phrase. Relu manuellement : aucun chiffre de ce document n'est présenté sans que le paragraphe ou le bloc qui le porte n'indique déjà, explicitement, s'il vient d'une exécution, d'une lecture de code, ou d'un document tiers.

## Tableau de synthèse

| Constat | Verdict | Sonde | Chiffre | Ce qui manque pour trancher |
|---|---|---|---|---|
| **A** — verrou profondeur : le générateur cible `comfort`, pas `best` (rhythm) | **TOUJOURS LÀ** | Génération réelle (`CareerSessionGenerator.generate`), 300 graines/cas, profil `comfort=mid/best=throat`, comptage séparé rhythm/hold | [mesuré] 0/300 (sr<0,65) · 16/300 (sr=0,70 à égalité entre les 14 axes) · 300/300 (sr=0,80 favorisé, ou escalade Encore/Utilise-moi quel que soit sr) | Un vrai profil de joueuse (le taux dépend du `successRate` relatif entre 14 axes, pas d'un seuil fixe) ; aucune donnée d'usage réel |
| **B1** — bouton Utilise-moi visible dès le début de la leçon | **TOUJOURS LÀ** | Traçage `session_screen.dart` → `MilestoneService.hasUnlock` → unlocks provisoires de la séance en cours | Commentaire du code confirmant le mécanisme mot pour mot ; branche fix `fix/marc-voice-usemi-gating` non fusionnée | Observation UI réelle (bouton visible à l'écran) — budget |
| **C1** — Utilise-moi efface défis/pauses/posture restants | **TOUJOURS LÀ** | Lecture de `SessionController.requestUpgrade` + `_handleUpgrade` | Pauses : reset explicite commenté. Défis : régén sans `challenge:` → perdus. Posture : 0 occurrence de « posture » dans le chemin de régénération | Compte exact sur N essais exécutés (le rapport annonce 2/2, 1/1 — non re-mesuré par exécution) |
| **B2** — défi prolongé sans fin imposée, horloge gelée | **TOUJOURS LÀ** | Lecture de `session_controller_challenge.dart` + `session_controller.dart` | `_deriveChallengeExtensionsCount` sans plafond (division entière croissante) ; `_timelineOffset` neutralise l'avance du tick tant que le défi est actif | Fréquence réelle des prolongations en usage — hors de portée d'une lecture de code |
| **B3** — bouton pause lent (pool audio arrêté en série, ~18 s pire cas) | **TOUJOURS LÀ** | Lecture complète de `beep_engine.dart` + call site `session_controller.dart:pause()` | [déduit, lecture de code] pool 4 joueurs × 15 échantillons = 60 confirmé ; boucle séquentielle confirmée ; borne 300 ms/joueur confirmée ; call site réellement bloquant pour l'UI confirmé (plus loin que le rapport, qui l'avait laissé en [déduit]) | Observation sur appareil réel engorgé — aucune compilation Android autorisée |
| **B4** — icône notifications surprise gatée par la leçon | **TOUJOURS LÀ** | Lecture de `mode_selection_screen.dart:307` + `milestones.json` | Garde confirmée mot pour mot (`hasUnlock(UnlockKey.surpriseNotifs)`) ; la milestone ne requiert que `beg_libre`, acquise tôt | « Reprise au démarrage » non vérifiée — déjà tranché `wontfix` (issue #76), priorité basse assumée |
| **B5** — blocage progression carrière, séance figée en fin (#317) | **CORRIGÉ** (partiel) | Grep `.timeout(` + `git log` sur `session_controller.dart` | [mesuré] borne 2 s **confirmée**, datée (commit `6ebdb84`, 2026-08-06), commentaire citant le symptôme exact. Borne « 5 s » du rapport **introuvable** dans `lib/` | La cause racine du silence TTS signalée par le rapporteur reste inconnue (le rapport l'admettait déjà) ; couverture d'AUTRES causes de blocage non garantie |
| **C2** — défi annoncé dans les 13 s après une pause | **CORRIGÉ** | Test existant `scripted_breaks_challenges_test.dart` (1920 séances) + sonde indépendante 500 graines sur le couple exact accusé (longue + 4 défis) | [mesuré] **0/1920** et **0/500** — contredit le rapport, qui annonçait avoir retrouvé « à l'identique » 4/500 | Pourquoi le rapport et cette mesure divergent sur la même révision — voir note ci-dessous, non résolu |
| **C3** — séance sans défi dépasse le plafond qu'un défi aurait eu | **TOUJOURS LÀ** (faible) | Sonde 300 graines, format bâclée, profil `rhythmMotionStreak` comfort=400 | [mesuré] chaîne max = **187 s** contre plafond 180 s ; **1/300** séances au-delà | Chiffres exacts du rapport (183 s / 193 s) non reproduits ; méthodologie exacte de la passe 4 d'origine inconnue ; comfort plus haut (cas réels cités à 353-3000 dans le code) non testé |
| **C4** — pas de respiration tutoriel sans durée déclarée | **TOUJOURS LÀ** | Lecture directe des 4 fichiers `assets/sessions/session_tutorial*.json` | [mesuré] confirmé dans les 4 langues (FR/DE/EN/ES) sur `develop` | Rien — bonus : la branche de fix elle-même ne couvre que 3 langues sur 4 (oublie l'espagnol) |
| **C5** — countdown optionnel + fondu entre modes jamais livrés | **TOUJOURS LÀ** | Grep `showCountdown` sur `lib/models/session_step.dart` | Absent de `develop` [mesuré] ; le champ n'existe que sur `feat/screen-polish` (755 commits de retard, non fusionnée) | Le fondu entre modes n'a pas été vérifié avec la même rigueur — inféré de la même branche non fusionnée, pas relu ligne à ligne [déduit] |
| **D** (tout le reste du rapport) | **non traité** | — | — | Plafond de budget atteint avant d'y arriver — priorité explicitement basse dans la consigne |

**Bilan** [mesuré, décompte du tableau ci-dessus] : 9 constats TOUJOURS LÀ, 2 CORRIGÉS (partiellement pour B5), 0 NON REPRODUIT à part entière, D non traité par manque de budget.

---

## A — Le verrou de profondeur (le seul « grave »)

**Prédiction écrite avant mesure** : avec `comfort=mid`/`best=throat`, une séance normale ne devrait produire un step rhythm visant `throat` que si `rhythmDepthMax` est l'axe surchargé de la séance ET que sa `successRate` franchit `kDepthCranGate` (0,65) — jamais en-dessous. Hypothèse initiale à vérifier : « Encore » (intense sans `useMe`) pourrait ne JAMAIS atteindre `throat`, contrairement à « Utilise-moi », faute de plafond de tirage relevé — ce qui contredirait le rapport, qui annonce 300/300 pour les deux indifféremment.

**Sonde** : `CareerSessionGenerator.generate()` appelé 300 fois par cas (API réelle, pas une fonction isolée), comptage séparé des steps `rhythm` et `hold` atteignant `to >= throat`. Fichier : `test/capability_depth_comfort_vs_best_test.dart`.

**Chiffres bruts [mesuré]** :
- Normal, sr=0,50 (sous le seuil) : rhythm **0/300**, hold 300/300.
- Normal, sr=0,80 (favorisé contre 13 axes à 0,50) : rhythm **300/300**.
- Normal, **14 axes à égalité stricte** sr=0,70 : rhythm **16/300** (≈5,3 %) — reproduit exactement le chiffre du rapport, sous un paramétrage différent (symétrique) du mien.
- Encore (intense=true, useMe=false), sr=0,50 : rhythm **300/300**.
- Encore, sr=0,80 : rhythm **300/300**.
- Utilise-moi (useMe=true), sr=0,50 : rhythm **300/300**.

**Écart avec ma prédiction** : mon hypothèse « Encore diverge d'Utilise-moi » était **fausse** — les deux se comportent identiquement (300/300, indépendant du succès), contrairement à ce que suggérait la lecture de `career_level_gates.maxDepthIndexForProfile` (qui n'est boostée que pour `useMe`, jamais pour `intense` seul). Le code doit disposer d'un autre chemin de tirage pour le rythme, non identifié précisément faute de budget, qui rend `capabilityCapFor` seul suffisant pour porter l'effet — la lecture de code isolée m'avait fait sous-estimer l'escalade côté Encore.

**Nuance non présente dans le rapport [mesuré]** : le verrou ne touche QUE les steps **rhythm** (pulsé). Les steps **hold** (tenir une position) atteignent `throat`/`full` dans 100 % des cas dès qu'un unlock de milestone hold existe, **indépendamment du comfort/best/successRate/intense** — `position_pickers.dart:154-159` le documente explicitement (« pas de cap par maxDepthIndex » pour un hold, gating par milestones uniquement). Si le vécu de la joueuse (« elle a déjà tenu la gorge ») passe par des holds, il n'est pas concerné par ce verrou ; seule la pulsation rythmée au même palier l'est.

**Nuance sur le chiffre « 16/300 » [mesuré]** : ce n'est pas un taux fixe. Il dépend entièrement du `successRate` de l'axe profondeur *relatif* à celui des 13 autres axes surchargeables (la loterie `pickOverloadAxis` est quasi déterministe dès qu'un écart de confiance dépasse le bruit aléatoire ±0,05). Une joueuse plus assidue sur la profondeur que sur le reste de son profil verrait le déblocage sortir de façon quasi systématique (300/300), pas dans 5 % des séances.

**Correctif jamais livré [mesuré]** : `feat/depth-comfort-probe`, 101 commits de retard sur `origin/develop` (confirmé : `git rev-list --left-right --count` → `101  1`), touche exactement les deux plafonds cités par le rapport (`career_level_gates.dart` et `capability_clamps.dart`). Contenu vérifié : les deux fonctions visent désormais `min(comfort+1, best)` au lieu de `comfort` seul, et ce **sans exiger que l'axe gagne la loterie de surcharge** (le gate `successRate >= kDepthCranGate` ne s'applique plus qu'au dépassement du `best`, pas à la sonde vers lui) — un correctif structurellement plus généreux que ce que « viser un cran au-dessus, borné par best » laisse deviner.

**Verdict : TOUJOURS LÀ.** Confirmé par exécution réelle du générateur de production, pas par une fonction isolée.

---

## B1 — Bouton Utilise-moi visible dès le début de la leçon

**Prédiction avant mesure** : la garde d'affichage doit lire un ensemble d'unlocks incluant les octrois provisoires accordés dès le démarrage de la séance de milestone, pas seulement les unlocks persistés.

**Sonde [déduit, lecture de code]** : `session_screen.dart` → `MilestoneService.hasUnlock` teste `_sessionUnlocks.contains(key)` en premier, avant les milestones réellement complétées ; `setSessionUnlocks` est appelé dès le début de la séance qui enseigne la milestone. Le commentaire du code à `career_screen.dart` dit littéralement que chaque milestone insérée « débloque visuellement ses compétences pour l'UI (bouton Supplier surtout) dès le démarrage, sans attendre le markCompleted final ».

**Confirmation croisée [mesuré]** : la branche `fix/marc-voice-usemi-gating` existe côté remote (commits `9e0a083`, `a2a3374`), 2 en avance sur `origin/develop`, et remplace cette garde par une fenêtre temporisée (`ctrl.useMeUnlockActive`) — jamais fusionnée.

**Écart avec la prédiction** : aucun.

**Ce qui n'a pas pu être établi** : rendu UI réel du bouton (budget) — la preuve reste au niveau code, comme celle du rapport original.

**Verdict : TOUJOURS LÀ.**

---

## C1 — Utilise-moi efface défis/pauses/posture en cours de séance

**Prédiction avant mesure** : la régénération mi-séance ne recevant ni `challenge:` ni `scriptedBreaks: true`, tout ce qui était en attente devrait être perdu sans report explicite.

**Sonde [déduit, lecture de code]** : `SessionController.requestUpgrade` et son appelant `_handleUpgrade`.
- Pauses : reset explicite et commenté (`_breakActive = false; _activeBreak = null; _nextBreakIndex = 0;`), citant l'issue #77.
- Défis : `newGen` n'a pas de paramètre `challenge:` → défaut `ChallengeInputs.none`, aucun report.
- Posture : `scriptedBreaks` absent des paramètres de régén ; 0 occurrence de « posture » dans `requestUpgrade`/`buildUpgradedSession`.

**Écart avec la prédiction** : aucun sur le mécanisme. Sur le CHIFFRE, écart réel : le rapport annonce avoir exécuté une sonde (2 défis/2 perdus, 1 pause/1 perdue) — je n'ai vérifié que la mécanique par lecture, pas re-mesuré par exécution sur N essais faute de budget dans ce fork.

**Verdict : TOUJOURS LÀ.**

---

## B2 — Défi prolongé sans fin imposée, horloge gelée

**Prédiction avant mesure** : la boucle de prolongation ne devrait avoir aucune borne autre que le relâchement explicite du doigt, et le compteur affiché ne devrait pas progresser pendant ce temps.

**Sonde [déduit, lecture de code]** :
- `session_controller_challenge.dart` : commentaire exact cité par le rapport (« Aucun timeout auto »). `_deriveChallengeExtensionsCount()` = division entière `tenu ~/ step` sans plafond — croît tant que le temps réel (`_realSec`) croît.
- `session_controller.dart` : commentaire explicite confirmant que `_timelineOffset` neutralise l'avance du tick sur `elapsedSeconds` (l'horloge affichée) tant que `isChallengeActive` — « ne consomme JAMAIS de temps de séance, peu importe combien la joueuse (...) prolonge ».

**Écart avec la prédiction** : aucun — les deux mécanismes sont confirmés chacun par une ligne de code non ambiguë, cohérent avec la réserve « gênante » déjà notée après la PR #336 (« prolongations sans aucune borne code, 49 min pour atteindre 1h ») pour ce qui semble être le même mécanisme.

**Ce qui n'a pas pu être établi** : combien de joueuses prolongent réellement, et jusqu'où — nécessite des données d'usage.

**Verdict : TOUJOURS LÀ.**

---

## B3 — Bouton pause lent (pool audio en série)

**Prédiction avant mesure** : si le constat tient, il faut trouver un pool ~60 `AudioPlayer`, chaque `stop()` borné ~300 ms, une boucle séquentielle (pas `Future.wait`) réellement `await`-ée par le handler du bouton pause.

**Sonde [déduit, lecture de code complète]** : `beep_engine.dart` — `_poolSize = 4` (ligne 102), 15 échantillons × 4 = ~60 (confirmé par un commentaire du code lui-même, ligne 214). `BeepEngine.pause()` (lignes 891-907) : double boucle `for` séquentielle, chaque `stop()` borné `.timeout(300ms)`, aucune borne globale sur l'ensemble. Call site : `session_controller.dart:1197-1211`, le handler public du bouton pause, `await`-e ce pool **avant** `notifyListeners()` — donc bloquant pour de vrai, pas seulement en théorie (le rapport l'avait laissé en [déduit] sans remonter jusqu'au call site).

**Contraste trouvé en chemin** : `session_controller_break.dart:66` utilise `unawaited(_beep.pause())` pour un autre chemin (pause scénarisée) — le code est donc conscient du risque et l'a mitigé ailleurs, mais pas sur le bouton pause principal.

**Écart avec la prédiction** : aucun ; la confirmation va plus loin que le rapport sur le call site.

**Ce qui n'a pas pu être établi** : observation en situation réelle sur appareil engorgé — aucune compilation Android autorisée. Le chiffre ~18 s reste une borne arithmétique (60 × 300 ms), jamais mesurée en conditions réelles.

**Verdict : TOUJOURS LÀ.**

---

## B4 — Icône notifications surprise gatée par la leçon

**Prédiction avant mesure** : la garde d'affichage doit exister et lire un unlock de milestone spécifique ; la leçon qui la débloque doit avoir un prérequis atteignable tôt dans la progression.

**Sonde [mesuré, lecture directe]** : `mode_selection_screen.dart:307` — `if (!milestoneService.hasUnlock(UnlockKey.surpriseNotifs)) return const SizedBox.shrink();`, sous un `ListenableBuilder` qui écoute le service pour un rebuild immédiat. `assets/career/milestones.json` — la milestone `intro_surprise_notifs` (`unlocks: ["surprise_notifs"]`) ne `requires` que `["beg_libre"]`.

**Écart avec la prédiction** : aucun — confirmé mot pour mot.

**Ce qui n'a pas pu être établi** : le comportement de « reprise au démarrage » si la leçon est interrompue avant complétion, non creusé — priorité basse assumée (issue #76, `wontfix`, déjà tranché par Manu).

**Verdict : TOUJOURS LÀ.**

---

## B5 — Blocage progression carrière, séance figée en fin (#317)

**Prédiction avant mesure** : si le rapport a raison, deux bornes précises doivent exister (5 s report parlé, 2 s arrêt son fin de séance) couvrant exactement le chemin de fin de séance.

**Sonde [mesuré, grep + git log]** : `.timeout(` dans `lib/services/tts_service.dart`, `lib/career/services/career_progress_service.dart`, `lib/controllers/session_controller*.dart`.
- Borne 2 s **confirmée** : `session_controller.dart:1816`, dans `_finish()` — `await _beep.stop().timeout(const Duration(seconds: 2), onTimeout: () {});`. Commentaire quasi littéralement identique au symptôme #317 (« la session ne passait jamais en `finished`, écran de fin absent »). Commit `6ebdb84` (2026-08-06), message : « fix(audio): borne seek/stop pour ne plus bloquer la fin de séance ».
- Borne 5 s « report d'un pas parlé » : **introuvable**. `ttsSpeakTimeout` vaut 20 s, pas 5 ; les deux seuls `5s` du dépôt sont dans `beep_engine.dart` (init du moteur, pas la parole) — grep exhaustif sur `seconds: 5)`.

**Écart avec la prédiction** : la moitié seulement de la preuve annoncée par le rapport se confirme. L'autre moitié ne se retrouve pas — soit une confusion dans le rapport original, soit un détail qui a échappé au budget de cette relecture.

**Renfort trouvé en chemin [mesuré]** : la suite complète (relancée pour la non-régression de cette tâche) contient `test/session_freeze_tts_speaking_test.dart`, quatre tests dédiés à « un moteur qui ne rend jamais la main sur `speak()` » — ils vérifient que ce cas ne fige plus ni le flow FAIL ni l'écran de fin. Le bornage y est `session_controller.dart:1195` : `_tts.speak(text).timeout(ttsSpeakTimeout, onTimeout: () {})`, avec `ttsSpeakTimeout` = **20 s**, pas 5 s — un garde-fou distinct de celui du `beep.stop()`, réel, mais qui ne correspond pas non plus au chiffre du rapport.

**Ce qui n'a pas pu être établi** : la cause racine du silence du moteur vocal signalée par le rapporteur (le rapport l'admet déjà) ; donc aucune garantie que TOUTE cause de blocage en fin de séance soit couverte — seulement les deux gardes-fous datés identifiés ici (2 s sur l'arrêt du son, 20 s sur la parole).

**Verdict : CORRIGÉ**, pour le mécanisme précis identifié (audio et TTS qui ne rendent jamais la main sont désormais bornés sur le chemin de fin de séance).

---

## C2 — Défi annoncé dans les 13 s après une pause scénarisée

**Prédiction avant mesure** : si le test déjà présent sur `develop` (`scripted_breaks_challenges_test.dart`, 0 collision sur son propre balayage à 60 graines/format) est représentatif, une fenêtre élargie à 500 graines sur le couple précis accusé par le rapport (format longue + 4 défis) devrait, en théorie, rester à 0 aussi.

**Sonde [mesuré]** : (1) exécution du test existant → 1920 séances générées, **0 collision**, 2/2 tests passent. (2) Sonde indépendante ciblée, 500 graines, format longue + pool de 4 défis, même fenêtre de 13 s → **0/500**.

**Écart avec le rapport** : le rapport affirme avoir retrouvé « à l'identique » les 4 collisions sur 500 graines d'un rapport d'intégration antérieur (11/08), sur la même révision `25657d5`. Ma sonde ciblée sur ce couple précis n'en trouve aucune. Le mécanisme de correction est visible dans le code — `career_session_generator.dart:875-991` calcule `challengeTriggerTimes`, et le docstring du test existant explicite : « le planificateur de pauses connaît désormais les créneaux de défi et cède le passage ». **Cet écart entre mon chiffre et celui du rapport n'est pas expliqué** : je n'ai pas retrouvé la ligne exacte du scheduler qui consulte `challengeTriggerTimes` (budget), donc je ne peux pas dire si le rapport utilisait un profil/une graine différente ou si son « à l'identique » était une erreur de recopie de l'ancien rapport du 11/08 sans réexécution.

**Verdict : CORRIGÉ**, sur la base de ma mesure — à confirmer par Manu vu l'écart avec le chiffre du rapport lui-même.

---

## C3 — Séance sans défi dépassant le plafond qu'un défi aurait eu

**Prédiction avant mesure** : `RhythmChainTracker.effectiveCapSeconds` est piloté par `motion_streak.comfort` du **profil** ; `maxChallengeDurationSeconds` est piloté par le **format** de la séance. Les deux bornes n'ont structurellement aucune raison de coïncider — un profil entraîné doit donc pouvoir dépasser passivement le plafond qu'un défi du petit format aurait eu.

**Sonde [mesuré]** : format bâclée (plafond défi = 180 s), sans le moindre défi, profil `rhythmMotionStreak` comfort=400, 300 graines, longueur de chaîne = steps `rhythm` OU `lick` consécutifs (le vrai critère `isMotion`, `capability_tracker.dart:420` — une première tentative avec `rhythm` seul sous-comptait et donnait 0/300 à tort).

**Résultat** : chaîne max = **187 s**, plafond = 180 s, **1/300** séances au-delà.

**Écart avec le rapport** : le phénomène est réel mais **beaucoup plus rare** dans ma mesure (1/300) que ne le laisse penser le rapport, qui ne donne pas de fréquence mais un cas unique par format. Je n'ai pas reproduit les chiffres exacts (183 s / 193 s) ni compris d'où vient « 193 » pour le format court — la formule `maxChallengeDurationSeconds` donne 180 pour bâclée **et** courte (calcul identique à `totalEvents=2`), pas 193. Un comfort plus représentatif d'un vrai profil aurait probablement donné un dépassement plus systématique (le code cite lui-même des cas réels à comfort 353, voire 3000).

**Ce qui n'a pas pu être établi** : la définition exacte de « plafond » et la méthodologie de la passe 4 d'origine ; un comfort plus élevé, plus proche d'un profil de joueuse expérimentée.

**Verdict : TOUJOURS LÀ**, mais faiblement reproduit — ce n'est pas la règle, c'est un cas rare dans le paramétrage testé ici.

---

## C4 — Pas de respiration du tutoriel sans durée déclarée

**Prédiction avant mesure** : si `fix/tutorial-breath-duration` n'est pas fusionnée, le step `breath` à t=210 des 4 fichiers de session tutoriel devrait toujours manquer le champ `duration` sur `develop`.

**Sonde [mesuré, lecture directe]** : contenu actuel de `assets/sessions/session_tutorial.json`, `_de.json`, `_en.json`, `_es.json` au step `time: 210` — les 4 portent `"mode": "breath"` sans `"duration"`.

**Écart avec la prédiction** : aucun.

**Trouvaille annexe [mesuré]** : la branche `fix/tutorial-breath-duration` elle-même (279 commits de retard, 1 en avance) ne touche que 3 fichiers sur 4 — FR, DE, EN — et **oublie l'espagnol**. Même fusionnée telle quelle, elle laisserait le défaut ouvert pour `es`.

**Verdict : TOUJOURS LÀ**, dans les 4 langues.

---

## C5 — Countdown optionnel sur les tenues + fondu entre modes

**Prédiction avant mesure** : si `feat/screen-polish` n'est pas fusionnée (755 commits de retard), le champ `showCountdown` ne devrait exister nulle part dans `lib/models/session_step.dart` sur `develop`.

**Sonde [mesuré]** : `grep -n "showCountdown" lib/models/session_step.dart` → aucune occurrence sur `develop`. Confirmé présent uniquement sur `feat/screen-polish` (diff : champ + parsing JSON + overlay UI dédié `_HoldCountdownOverlay`, scope hold-throat/full + breath uniquement).

**Note pour Manu** : la mémoire projet `feedback_hold_countdown_scope.md` décrit ce même scope (« throat/full + breath uniquement, jamais tip/head/mid ni rythmés ») sans préciser qu'il s'agit d'une décision de conception prise sur une branche **jamais fusionnée** — à lire comme une règle de design, pas comme un état livré.

**Écart avec la prédiction** : aucun sur le countdown. Sur le fondu entre modes, je n'ai pas relu `movement_animation.dart` ligne à ligne (grep « fade » y trouve des mécanismes préexistants, mais pour le fade **interne** aux beats d'un même mode — pas un fondu **entre** modes) ; conclusion par cohérence avec le reste de la branche non fusionnée, pas par lecture exhaustive.

**Verdict : TOUJOURS LÀ** — countdown [mesuré], fondu entre modes [déduit].

---

## D — Non traité

Le plafond de budget de la tâche est arrivé avant la section D du rapport (constats classés « corrigé » ou « obsolète » par le rapport lui-même, priorité basse par consigne explicite). Aucun de ces constats n'a été rejoué ; aucune sonde des sections A/B/C n'est tombée dessus en chemin.

---

## Ce que je n'ai pas pu établir (au global)

- **Aucune donnée d'usage réel** pour aucun constat : toutes les proportions ci-dessus portent sur des séances générées en boucle, jamais sur des séances effectivement jouées.
- **Aucune vérification sur device Android** (bips manquants, latence pause perçue, défi « pousse ta limite ») — hors périmètre par consigne, pas une esquive.
- **L'écart C2** entre le rapport (4/500, « retrouvé à l'identique ») et ma mesure (0/500, 0/1920) reste sans explication.
- **Le mécanisme exact** qui rend le rythme surchargeable en mode Encore malgré un plafond de tirage non-boosté (trouvaille A) n'a pas été identifié ligne à ligne — seulement mesuré comme effet.
- Rien trouvé hors du périmètre de ce tri qui aurait mérité une fiche SAS.

## Vérification de non-régression

[mesuré] `flutter analyze` → *No issues found!* · `dart format --set-exit-if-changed lib/ test/` → propre (0 fichier à reformater après correction des lints introduits par les sondes) · `flutter test` (suite complète) → **986 tests, tous verts** (978 avant cette tâche + 8 apportés par les deux fichiers de sonde commités).
