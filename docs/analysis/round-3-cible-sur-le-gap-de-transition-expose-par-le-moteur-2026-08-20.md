---
type: analyse
sujet: round-3-cible-sur-le-gap-de-transition-expose-par-le-moteur
ecrit_le: 2026-08-20T18:57:33+02:00
auteur: session tss2-animations-round3 · claude-opus-5
revision: e1d38e9
branche: feat/movement-trajectory-continuity
porte_sur:
  - docs/analysis/gap-de-transition-du-moteur-expose-dans-la-trajectoire-2026-08-20.md
  - rhythm_coach/assets/career/milestones.json
  - rhythm_coach/lib/career/screens/career_screen.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/beep_engine_transition_gap_test.dart
  - rhythm_coach/test/movement_trajectory_continuity_test.dart
provenance:
  mesure: 15
  deduit: 9
  document: 3
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/screens/career_screen.dart:778
  - rhythm_coach/lib/controllers/session_controller.dart:2083
  - rhythm_coach/lib/controllers/session_controller.dart:960
  - rhythm_coach/lib/screens/session_screen.dart:1122
  - rhythm_coach/lib/services/beep_engine.dart:153
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart:66
---

Round 3 sur `feat/movement-trajectory-continuity`, passe ciblée sur le seul diff du round 2
(`5ee149f` le code, `e1d38e9` le rapport). Le reste de la branche n'a pas été relu. Consigne :
réfuter, pas valider.

## 1 — Le comportement audio est-il rigoureusement inchangé ?

[mesuré] Sonde de caractérisation écrite contre le vrai `BeepEngine` (canaux `audioplayers` mockés
en no-op), qui mesure le délai réel rendu par `applyStep` sur la matrice complète : 9 modes de
départ × 9 modes d'arrivée × `to ∈ {null, throat}`, soit 162 cas. Jouée telle quelle sur `HEAD`,
puis sur le `beep_engine.dart` de `f8da372` remis en place à l'identique. Les deux relevés sont
octet pour octet identiques : 18 cas à 300 ms, 40 à 600 ms, 104 à 1500 ms. Le refactor
(`_needsBigGap` statique, extraction de `transitionGap`) ne déplace aucun délai, y compris sur les
cas que le round 2 n'avait pas couverts — `beg` avec et sans `to`, chacun des 9 modes en arrivée,
et le retour sur le même mode avec un `to` différent.

[déduit] La ventilation attendue depuis les règles se recoupe avec le relevé : 9 modes × 2 valeurs
de `to` en même-mode = 18 ; `rhythm`/`hold` en arrivée depuis 8 autres modes × 2 = 32, plus `beg`
avec `to` depuis 8 modes = 8, soit 40 ; les 6 modes à grand geste × 8 × 2 = 96, plus `beg` sans
`to` depuis 8 modes = 8, soit 104.

[déduit] Le cas `previous: null` n'est atteignable par aucun chemin : `_mode` est un champ non
nullable initialisé à `SessionMode.rhythm` (`beep_engine.dart:153`), et le seul autre appelant de
`transitionGap` est `resolveUpcomingMovementSteps`, qui amorce sa chaîne sur `currentMode`. Le
5ᵉ test de `beep_engine_transition_gap_test.dart` verrouille donc une branche morte — sans
conséquence, mais ce n'est pas une couverture.

[mesuré] Les deux entrées que le résolveur d'affichage fournit à `transitionGap` sont bien celles
du moteur : `ctrl.currentMode` est un passe-plat vers `_beep.currentMode`
(`session_controller.dart:960`), et les cinq appelants d'`applyStep` passent tous
`session.defaultMode` comme mode par défaut, exactement ce que reçoit
`resolveUpcomingMovementSteps` (`session_screen.dart:1122`). Le `to` transmis n'est pas la valeur
héritée mais `step.to` brut (`movement_trajectory_forecast.dart:66`), donc la même que celle que
lit `applyStep` — c'était le point où une divergence sur `beg` aurait été silencieuse.

## 2 — Le risque que le round 2 déclare et n'a pas fermé

Le round 2 borne le risque sur les milestones et s'arrête à une borne partielle, par recherche de
texte, côté générateur de carrière. Je l'ai fermé par la mesure.

[mesuré] Sonde qui génère des séances réelles avec `CareerSessionGenerator` — 8 graines × 5 niveaux
× 4 variantes (`plain`/`intense`/`quickie`/`useMe`) × 4 paliers de durée sans milestone, puis les
37 milestones du catalogue réel chargé par `MilestoneLoader`, en `bodies` et en `finalMilestone` —
soit 1232 séances effectivement produites (640 sans milestone, 480 avec une milestone de corps,
112 avec une milestone finale) et 169 340 paires de steps de bip consécutifs. L'écart minimal
mesuré est de 2000 ms, aucune paire ne descend sous ce seuil, et le nombre de points dont
l'instant de reprise recule est de zéro. Les durées calculées dynamiquement que le round 2
n'arrivait pas à borner sont donc couvertes, non par lecture mais par production.

[mesuré] Le chiffre du round 2 sur les milestones est reproduit indépendamment, en repartant du
JSON et en dépliant `chainAction` selon la règle du loader : 37 milestones, 165 paires, écart
minimal 2000 ms, aucune paire sous 2000 ms.

[déduit] Restent deux chemins qui fabriquent une liste de steps à l'exécution, hors générateur.
`buildPostChallengeRegenSession` décale toute la suite d'un offset uniforme, ce qui conserve les
écarts. `buildUpgradedSession` fabrique une jonction : un `beg` insistant à `start`, puis la suite
à `start + begDuration`. Les quatre valeurs de `begDuration` du code sont 12, 6, 5 et
`(begWordCount * 0.6).ceil() + 1`, dont le plancher théorique est 1 s pour une phrase vide. Même à
ce plancher, l'instant de reprise du step suivant est à 1000 + 600 = 1600 ms contre 1500 ms pour
le `beg` : la marge tient, mais elle tombe à 100 ms.

## 3 — Les tests discriminent-ils ?

Trois mutations posées sur l'arbre, chacune suivie d'un relevé du **statut** du run, pas seulement
de ses chiffres.

[mesuré] Mutation 1, `resumeAt = boundary` — c'est-à-dire le code d'avant le round 2 remis en
place : `movement_trajectory_continuity_test.dart` sort en `+9 -2`, exit 1, avec `Actual: <800.0>`
contre `a value greater than <1300>` et `a value greater than <2200>`. Les deux tests annoncés
comme rouges avant le correctif le sont bien, et pour la bonne raison.

[mesuré] Mutation 2, `transitionGap: Duration.zero` dans le résolveur : `+10 -1`, exit 1,
`Expected: 0:00:00.300000 / Actual: 0:00:00.000000`.

[mesuré] Mutation 3, suppression de la règle même-mode dans `BeepEngine.transitionGap` : `+14 -2`,
exit 1 — la règle est tenue à la fois par le test de fonction pure et par celui du résolveur.

## Ce que le round 2 affirme et que la mesure contredit

[document] Le rapport du round 2 écrit, à propos de deux frontières plus rapprochées que le gap du
second step : « `addPoint` ignore silencieusement un point dont l'instant est déjà passé
(`dtMs < 0 → return true` sans rien ajouter) — pas de crash, au pire un segment de courbe sauté ».

[mesuré] Sonde qui pose deux frontières à la même seconde avec des gaps décroissants (1500 puis
600) sur `computeFutureBeatsForTest`. La suite d'instants produite est `[0, 2300, 1400, 2400,
3400]` ms, avec deux points à `tip` : la courbe part à 2300, recule à 1400, puis repart. Ce n'est
pas un segment sauté, c'est un aller-retour dans la courbe. Le garde-fou cité ne couvre que les
points antérieurs à `now` ; un point qui recule tout en restant dans le futur est ajouté tel quel.

La conséquence pratique est nulle aujourd'hui — la condition d'entrée est mesurée comme jamais
atteinte au point 2 ci-dessus. Mais la phrase du round 2 rassure sur un mécanisme qui ne joue pas,
et c'est elle qu'un relecteur pressé recopierait.

## Étiquetage du rapport du round 2

[déduit] Trois paragraphes du round 2 portent `[mesuré]` alors qu'ils décrivent le diff plutôt
qu'une exécution : celui qui annonce que `_needsBigGap` ne lisait aucun état d'instance, celui qui
décrit le champ `transitionGap` et son défaut, celui qui décrit `resumeAt` dans
`_computeFutureBeats`. Sous la convention en vigueur — `[mesuré]` = exécuté, `[déduit]` = lu — ces
trois-là sont des lectures, et l'en-tête `mesure: 10` s'en trouve gonflé d'autant.

[mesuré] Le reste de l'en-tête est exact : les compteurs `[mesuré]` 10, `[déduit]` 4, `[document]`
2 correspondent au corps, aucune phrase ne porte deux marqueurs, et les références de ligne citées
tombent toutes sur la bonne construction — à une près, `movement_animation.dart:617` désigné pour
`addPoint`, qui est déclaré ligne 618.

## Vérifications

[mesuré] Depuis `rhythm_coach/` : `flutter pub get` exit 0 ; `flutter analyze` → « No issues
found! » ; `timeout 1500 flutter test` redirigé vers un fichier (jamais pipé) → `1031 tests, All
tests passed!`, exit 0, ce qui confirme le chiffre annoncé ; `dart format --set-exit-if-changed
lib test` → 295 fichiers, 0 modifié, exit 0. L'arbre de travail est revenu propre après chaque
sonde et chaque mutation.

## Ce que je n'ai pas pu établir

- **Rien vu en mouvement**, comme les trois rapports précédents. [déduit] Aucune de mes mesures ne
  dit si le nouveau calage se voit mieux à l'œil sur un appareil réel.
- **Le scénario de plancher de `buildUpgradedSession`** (phrase de `beg` vide donnant
  `begDuration = 1`, suivie d'un premier step lui-même en `beg`) donnerait un recul de 200 ms.
  [déduit] Je n'ai pas réussi à le produire — il demande la conjonction d'une phrase vide et d'une
  séance régénérée qui ouvre sur un `beg` — et je ne l'ai donc ni observé ni exclu formellement.
- **La couverture des chemins d'injection à l'exécution** (`requestUpgrade`, régénération
  post-défi) repose sur la lecture du code qui construit les listes, pas sur des séances jouées.
  [déduit] Ma sonde d'écart minimal ne parcourt que des séances issues du générateur.
- **Le calage retenu pour le point `tip`** le place à l'instant où le moteur démarre le nouveau
  mode, donc à la fin du silence, et non pendant. [document] C'est la lecture que la consigne du
  round 2 donnait de la réserve du round 1 ; je ne la rouvre pas, je la signale parce qu'elle
  porte un sens et non un calcul.

## Verdict

**Publiable.** Deux rounds de même signature n'avaient pas produit de défaut fonctionnel ; celui-ci
non plus. [mesuré] Le comportement audio est inchangé sur les 162 cas atteignables, le risque que le
round 2 laissait ouvert est fermé par 169 340 paires relevées sur des séances réelles, et les trois
tests ajoutés virent rouges quand on leur retire ce qu'ils prétendent tenir.

Les deux réserves qui restent sont documentaires et **aucune n'est gênante** : la phrase du
round 2 sur `addPoint` décrit un garde-fou qui ne joue pas dans le cas qu'elle prétend couvrir, et
trois de ses paragraphes sont étiquetés `[mesuré]` là où ils décrivent du code lu. Elles ne
touchent pas le code livré ; ce rapport-ci les corrige pour le lecteur suivant.
