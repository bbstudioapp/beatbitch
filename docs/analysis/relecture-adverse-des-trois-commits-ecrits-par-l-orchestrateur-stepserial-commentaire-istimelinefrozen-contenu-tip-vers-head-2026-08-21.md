---
type: analyse
sujet: relecture-adverse-des-trois-commits-ecrits-par-l-orchestrateur-stepserial-commentaire-istimelinefrozen-contenu-tip-vers-head
ecrit_le: 2026-08-21T22:30:59+02:00
auteur: session tss2-relecture-mode-direct · claude-sonnet-5
revision: 52893b5
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/assets/career/milestones.json
  - rhythm_coach/assets/sessions/session_advanced_demo_orig.json
  - rhythm_coach/assets/sessions/session_advanced_demo_ps1.json
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/rhythmic_pattern_buffer.dart
  - rhythm_coach/lib/career/services/generation/stamina_model.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/step_resolution.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/beep_engine_step_serial_test.dart
  - rhythm_coach/test/content_from_equals_to_test.dart
provenance:
  mesure: 11
  deduit: 4
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1815
  - rhythm_coach/lib/career/services/generation/rhythmic_pattern_buffer.dart:75
  - rhythm_coach/lib/controllers/session_controller.dart:1382
  - rhythm_coach/lib/controllers/session_controller.dart:1560
  - rhythm_coach/lib/controllers/session_controller.dart:927
  - rhythm_coach/lib/controllers/session_controller.dart:937
  - rhythm_coach/lib/services/beep_engine.dart:362
  - rhythm_coach/lib/services/beep_engine.dart:598
  - rhythm_coach/lib/services/step_resolution.dart:31
---

*Relecture par `claude-sonnet-5` du travail de `claude-opus-5`. Consigne : chercher à réfuter, pas à
valider. Périmètre strict : trois commits, écrits par l'orchestrateur en mode direct et jamais
relus — `030170b` (sonde `stepSerial`), `d25b80b` (commentaire `isTimelineFrozen`), `52893b5`
(contenu `tip→head` + sonde `content_from_equals_to_test.dart`). Relus par SHA, pas par `HEAD` :
`HEAD` était exactement `52893b5` au début comme à la fin de cette relecture (`git rev-parse HEAD`
vérifié avant et après le run complet de la suite), donc aucune dérive de branche à signaler ici.

**[mesuré]** Une autre session travaille en parallèle sur cette branche et a laissé un fichier non
suivi, `rhythm_coach/test/zz_probe_challenge_curve_test.dart` (274 lignes, 1 test) — hors périmètre,
non touché, mais présent dans l'arbre de travail pendant mon run `flutter test` (cf. « Exécution »).

## Verdict

**Publiable avec réserves.** Aucune des trois affirmations centrales ne cède : la sonde `030170b`
prouve bien ce qu'elle prétend prouver, le son ne bouge pas dans `52893b5`, et le commentaire
réécrit dans `d25b80b` est vrai dans les deux sens. Les réserves portent sur la robustesse de la
sonde de contenu (`content_from_equals_to_test.dart`) et sur l'hygiène de la sonde `stepSerial` —
aucune des deux ne fait actuellement mentir un résultat, mais toutes deux peuvent laisser passer
une régression future sans le dire.

## 1. `030170b` — la sonde `stepSerial` prouve-t-elle quelque chose ?

**[mesuré]** `applyStep` est une fonction `async` ; `_stepSerial++` (ligne 364) est placé avant le
premier `await` de la fonction (`await init()`, ligne 365). En Dart, le corps d'une fonction `async`
s'exécute de façon synchrone jusqu'au premier point de suspension — donc `_stepSerial++` s'exécute
bien avant que l'appelant ne reprenne la main, `await`é ou non. J'ai rejoué la mutation annoncée par
l'auteur (`_stepSerial++` commenté) : `flutter test test/beep_engine_step_serial_test.dart` tombe
rouge exactement comme décrit — `Expected: <1> Actual: <0>` sur le premier test, à la ligne 32 du
fichier. Fichier restauré, `git status --short` vide après coup.

**[mesuré]** Le second test (« n'avance pas sur un step text-only ») est trivial et correct :
`applyStep` retourne avant `_stepSerial++` sur un step `isTextOnly`, aucune mutation nécessaire pour
s'en convaincre.

**[mesuré]** Sur la question « ça laisse des `Future`/timers pendants ? » : oui, mais sans
conséquence observée. Le premier test appelle `applyStep` deux fois sans `await` sur le même moteur
neuf ; les deux appels déclenchent chacun `init()` (`_initialized` est encore `false` au moment du
second appel — confirmé par les logs `[BeepEngine] échec chargement tip_beep #0` dupliqués), puis
chaque chaîne continue en tâche de fond après le `expect` : `await Future.delayed(300ms)` (gap de
transition même-mode), puis `_startBeatLoop` qui arme un `Timer` auto-replanifié (aucun `_stopLoop`
n'est jamais appelé sur ce moteur). Le test ne fait ni `dispose()` ni `stop()`. En pratique le
process du fichier de test se termine (`All tests passed!`, exit 0) avant que ce timer n'ait
l'occasion de refaire un tour significatif, et `_pools` est vide (tous les `AudioPlayer` ont échoué
au chargement via `MissingPluginException`) donc `_trigger` retourne immédiatement sans nouvel appel
de canal — rien n'a débordé sur un autre test dans ce run. C'est une ressource non nettoyée, pas une
pollution démontrée : je ne l'ai pas vue casser quoi que ce soit, mais le test aurait dû `stop()`/
`dispose()` le moteur.

## 2. `52893b5` — le son a-t-il bougé ?

**[déduit]** Non, sur les 8 sites. `Position` est `tip(0) < head(1) < mid(2) < throat(3) <
full(4) < balls(5)`. Avant le fix (`from: head, to: head`), `resolveStepConfig` renvoie
`from=head` (`step.from` explicite, mode rhythm/lick) ; `BeepEngine.applyStep` détecte ensuite
`_to == _from` et appelle `_pickShallowerThan(head)`, qui ne trouve qu'**un seul** candidat d'index
`< 1` : `tip`. Le tirage « au hasard » du commentaire de `_pickShallowerThan` est donc déterministe
dans ce cas précis — pas aléatoire, un seul candidat. Après le fix (`from: tip, to: head`),
`resolveStepConfig` renvoie directement `from=tip` et la garde `_to == _from` ne se déclenche même
plus (`tip != head`). État final du moteur identique dans les deux cas : `_from=tip, _to=head`.

**[mesuré]** J'ai vérifié pour les deux emplacements *laissés* `from == to` (non touchés par le
fix) qu'ils ont bien plusieurs candidats, donc un vrai tirage à préserver : `rapid_full`
(`punishments*.json#0`, `from/to: full`) → 4 candidats d'index `< 4` ; `session_advanced_demo_ps1.
json#210` (`from/to: throat`) → 3 candidats d'index `< 3`. Le classement « ces deux-là restent, les
8 autres se figent » n'est pas arbitraire.

**[déduit]** Sur « un endroit où `from` écrit explicitement change autre chose que le tirage » —
c'est la question que j'ai le plus cherché à casser :
- **Affichage/courbe** : `resolveStepConfig` est partagée entre le moteur (`BeepEngine.applyStep`)
  et l'affichage (`resolveUpcomingMovementSteps`), et son commentaire dit explicitement qu'elle ne
  couvre PAS le tirage `_pickShallowerThan` — c'est le cœur du bug que ce commit corrige : avant le
  fix, l'affichage voyait `from=head, to=head` (un plateau) alors que le moteur jouait `tip→head`
  (un mouvement). Le fix aligne les deux en écrivant `from=tip` en dur. C'est le changement
  *recherché*, pas un effet de bord.
- **Héritage vers le step suivant** : j'ai vérifié les 8 sites un par un (contexte JSON complet
  autour de chacun). Six sont le dernier step de config de leur séquence (rien n'hérite après). Les
  deux restants (`intro_encore` t=10, `intro_surprise_notifs` t=10) sont suivis de steps `beg`
  (sans `to`, donc sans effet sonore) puis d'un step rythmé qui fixe **son propre** `from` en dur
  (`head`). Aucun des 8 sites n'a de step suivant qui hérite silencieusement du `from` qu'on vient
  de changer — donc pas de divergence en cascade trouvée.
- **Progression de carrière** : les 6 sites de `milestones.json` passent par
  `_pushMilestoneSequence` (`career_session_generator.dart:1641`) quand la milestone est insérée en
  séance carrière générée. Cette fonction appelle `_trackPushedStep(mode, to, from: mStep.from, …)`
  avec la valeur JSON brute — donc `from=head` (avant) vs `from=tip` (après) atteint bien
  `RhythmicPatternBuffer.record(...)`. Mais son seul consommateur, `wouldBeFlat(...)`
  (`rhythmic_pattern_buffer.dart:75`), ne lit que `mode`/`to`/`bpm` — jamais `.from` (vérifié en
  lisant les 91 lignes du fichier et tous les appelants externes de `_patternBuffer` /
  `RhythmicPatternBuffer` dans `lib/career/services/generation/`). `from` y est donc stocké mais
  mort à l'usage. Même chose côté endurance simulée : `_stepToDraft(mStep)` alimente
  `StaminaModel.apply` via `positionDepth(from, to) = max(from.index, to.index) + 1` — `to=head`
  domine `max()` que `from` vaille `tip(0)` ou `head(1)`, donc le coût projeté est identique. Aucune
  divergence trouvée, mais c'est une lecture de code, pas une exécution : je ne l'ai pas confirmé
  par une sonde qui ferait tourner le générateur sur les deux contenus et comparerait la sortie.
- **Sérialisation** : `SessionStep.toJson()` réécrit `from`/`to` tels quels ; pas de perte ni de
  transformation trouvée.

## 3. `52893b5` — le balayage est-il exhaustif ?

**[mesuré]** `grep -l '"from"' assets -r` (tous les JSON du dépôt, pas seulement les fichiers cités
par le test) renvoie exactement la liste des fichiers déjà couverts par
`content_from_equals_to_test.dart` (`milestones.json`, les 4 `punishments*.json`, tous les
`assets/sessions/*.json`) — aucun fichier avec un champ `from` n'échappe au balayage de la sonde.
J'ai réimplémenté la même règle en Python, indépendamment, sur ces mêmes fichiers : **5 résultats**,
identiques à `_assumes`. Je n'ai pas trouvé de neuvième site.

**[mesuré]** Deux réserves sur la sonde elle-même, trouvées en essayant de la casser :
- **Collision de clé.** `_walk` identifie chaque occurrence par `path#(id ?? time)`. Deux milestones
  *différentes* dans `milestones.json` ont chacune un step à `time=10` (`intro_encore` et
  `intro_surprise_notifs`) — vérifié en restaurant temporairement le contenu d'avant le fix
  (`git checkout 52893b5^ -- …` puis restauration, `git status --short` vide après coup) : le test
  tombe bien rouge, mais son `Actual` ne liste que **5** entrées pour `milestones.json` (`#38, #28,
  #10, #44, #40`) alors que **6** sites réels y existaient avant le fix — les deux `#10` fusionnent
  en un seul élément de `Set`. Sans conséquence aujourd'hui (les deux sont corrigés, 0 site restant
  dans ce fichier), mais si une régression future introduisait un `from == to` sur un *nouveau* step
  à `time=10` dans ce même fichier alors qu'un autre site légitime y est déjà attendu, le `Set` ne le
  distinguerait pas — la sonde ne le verrait pas.
- **Filtre de mode incomplet.** `_walk` exclut un step seulement si `mode` est explicitement renseigné
  et différent de `rhythm`/`lick` ; un step sans `mode` (héritant du `defaultMode` de la session) est
  toujours inclus, sans vérifier ce que vaut réellement ce `defaultMode`. Les deux sites
  `session_advanced_demo_{orig,ps1}.json#0` sont dans ce cas — j'ai vérifié que leur `defaultMode`
  est bien `rhythm` (`"mode": "rhythm"` en tête de fichier), donc pas de faux résultat actuellement.
  Mais si un futur fichier de session avait un `defaultMode` de `hold`/`beg`/`suckle` (où `from` se
  résout depuis `to`, pas depuis `step.from`) et un step sans `mode` avec `from == to` écrit en dur,
  la sonde le compterait comme un site rhythm/lick alors qu'il n'en est pas un.

## 4. `52893b5` — la sonde neuve garde-t-elle l'acquis ?

**[mesuré]** Rejoué telle quelle : `git checkout 52893b5^ -- rhythm_coach/assets/career/
milestones.json rhythm_coach/assets/sessions/session_advanced_demo_orig.json rhythm_coach/assets/
sessions/session_advanced_demo_ps1.json`, puis `flutter test test/content_from_equals_to_test.dart`
→ rouge, `Actual` plus grand que `_assumes` de 7 éléments (les 6 occurrences milestones — 5 à cause
de la collision ci-dessus — plus les 2 sessions démo, moins celle déjà attendue à t=210). Restauré
ensuite (`git checkout HEAD -- …`), `git status --short` vide.

## 5. `d25b80b` — le commentaire est-il vrai maintenant ?

**[mesuré]** Les deux moitiés vérifiées séparément par grep exhaustif de `_timelineOffset` dans
`session_controller.dart` (seulement deux sites de décrément trouvés dans tout le fichier) :
- **Ce que le getter couvre** : `_onTick` (ligne 1382) fait `if (isTimelineFrozen) { _timelineOffset
  -= _tickInterval; }` — appelle bien le getter plutôt que de réécrire l'expression, exactement les
  trois conditions nommées (`isChallengeActive`, `_inPostChallengeBreath`, `awaitingPostureReady`).
  Et `isTimelineFrozen` est bien lu par l'affichage : `session_screen.dart:1128` vide
  `upcomingSteps` quand il est vrai — cohérent avec « les instants des steps à venir ne situent
  plus rien ».
- **Ce que le getter ne couvre pas** : `_checkSteps` (ligne 1560, dans la branche de report TTS
  `step.text.isNotEmpty && _tts.isSpeaking && _ttsDeferredTicks < _maxTtsDeferTicks`) fait aussi
  `_timelineOffset -= _tickInterval;`, sans passer par `isTimelineFrozen` et sans dépendre d'aucune
  des trois conditions du getter — c'est un chemin totalement indépendant. Le nouveau commentaire le
  dit explicitement (« Le report TTS de `_checkSteps` décrémente lui aussi `_timelineOffset` et
  n'est pas couvert ici »). Je n'ai trouvé aucun troisième site de décrément qui serait, lui,
  silencieusement omis du commentaire.

Je n'ai pas trouvé de sens inverse où le commentaire mentirait (aucune des trois conditions nommées
ne serait en fait absente du comportement réel de gel).

## Ce que je n'ai pas pu établir tel quel

**[déduit]** La divergence « progression de carrière » (point 2, `_trackPushedStep`/
`StaminaModel`) est établie par lecture de code, pas par une sonde qui ferait tourner
`CareerSessionGenerator.generate(...)` deux fois (contenu d'avant vs d'après) et comparerait les
séances produites. Vu que les deux fonctions concernées (`wouldBeFlat`, `positionDepth`) sont pures
et que j'ai lu leur totalité, je suis confiant sur la conclusion — mais ce n'est pas une mesure.

**[déduit]** Je n'ai pas quantifié l'impact réel du timer non nettoyé du point 1 sur une suite de
tests plus longue ou un run avec une concurrence différente (`flutter test` répartit les fichiers
sur des isolats séparés par défaut ; je n'ai pas testé un mode d'exécution qui partagerait
l'isolat). Absence de preuve de nuisance, pas preuve d'absence.

## Exécution

**[mesuré]** Depuis `rhythm_coach/`, contre `HEAD=52893b5` (vérifié identique avant et après) :
`flutter pub get` (OK), `timeout 300 flutter analyze` → *No issues found!* (4.2s), `timeout 900
flutter test` (sortie redirigée vers fichier, jamais pipée) → **1085 tests, `All tests passed!`,
exit 0** — pas 1084 comme annoncé par l'auteur. Écart expliqué : l'arbre de travail contenait le
fichier non suivi `test/zz_probe_challenge_curve_test.dart` laissé par la session concurrente
(1 test dedans, confirmé par grep) — `1084 + 1 = 1085`. Ce n'est pas un défaut des trois commits
relus, c'est une contamination de l'arbre de travail par un fichier hors périmètre. Dépôt propre
après la relecture (`git status --short` ne montre que ce fichier non suivi, non touché).

## Résumé

**[mesuré]** Les trois promesses centrales tiennent : `stepSerial` avance bien avant tout `await`
(mutation rejouée, rouge exact), le son ne bouge pas sur les 8 sites `tip→head` (déterministe, pas
aléatoire, aucune divergence trouvée en aval), et le commentaire de `isTimelineFrozen` est vrai dans
les deux sens. Les réserves sont mineures et non fonctionnelles : un timer de `BeepEngine` jamais
arrêté dans la sonde `030170b` (sans nuisance observée), et deux angles morts dans la sonde de
contenu `52893b5` (collision de clé `path#time`, filtre de mode qui ignore `defaultMode`) qui ne
faussent rien aujourd'hui mais pourraient laisser passer une régression future sans le signaler.
