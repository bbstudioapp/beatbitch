---
type: analyse
sujet: utilise-moi-ne-gonfle-plus-le-profil-de-capacites-tss2-037
ecrit_le: 2026-10-18T11:32:14+02:00
auteur: session tss2-confort-finition · claude-sonnet-5-5
revision: c711d77
branche: feat/utilise-moi-dynamique
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/services/capability_service.dart
  - rhythm_coach/lib/services/capability_tracker.dart
provenance:
  mesure: 9
  deduit: 2
  document: 3
  sans_marqueur: 2
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1592
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:441
  - rhythm_coach/lib/services/capability_service.dart:554
  - rhythm_coach/lib/services/capability_tracker.dart:105
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 2 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Ce dont il s'agit

tss2-037 : « Utilise-moi » (escalade 160→300 BPM) gonflait le profil de capacités. Branche `feat/utilise-moi-dynamique` du dépôt BeatBitch, worktree `~/perso/git/tss2-useme`, base `d774101`. Cinq commits : `c8e4fbb` (correctif), `5e19d10` (mesures), `afffd76` (rejeu après FAIL), `765fc8e` et `c711d77` (tests). **Rien n'a été poussé, fusionné ni installé.** [document]

Décision de Manu (18/10) : **aucune réparation des profils existants**. Un `best` déjà gonflé reste gonflé ; le test T8 se limite à prouver qu'un tel profil se lit sans erreur et que le nouvel axe s'amorce. [document]

## Cause

Le tracker comptait les steps « Utilise-moi » comme des steps normaux : `best` des axes BPM à 280-300, streaks de 318 à 657 s écrits dans `best`, et plafonds de session figés par le FAIL qui termine le mode (motion 95→5…50, apnée 18→1…6, hold gorge 22→6 selon l'instant du FAIL balayé). Le même effondrement existe sur une séance normale suivie d'un FAIL (motion 95→6…30) : il est générique, fiche sas `tss2-038` déjà écrite. [mesuré, session précédente, non rejoué ici]

## Correctif

- Le tracker reçoit `useMe` aux trois sites d'application de step. Records et plafonds d'un step « Utilise-moi » vont dans un tampon `useMeReached` ; aucun plafond n'est figé depuis un step « Utilise-moi » ; les streaks vivants sont clos à l'entrée et à la sortie du mode. [mesuré]
- Le service accorde au plus un cran de +5 % du `comfort` sur les 4 axes BPM, plafonné à `best_normal × 1,15`, jamais si un plafond de session existe ni en quickie. `commit` n'est appelé qu'une fois par séance (`_finish`), donc un seul cran. [déduit]
- Axe informatif `useMe.held_streak` (4 langues), amorcé une fois depuis `stats.max_use_me_sec` ; `_endUseMe` passe avant `finalizeReport`. [mesuré]
- **Ajout de cette session** : `_restorePreviousLoop` rejouait le dernier step avec `_useMeActive`, déjà levé par le FAIL. Sans suite normale (hook `onUseMeEnded` qui rend `null`, soit moins de 30 s restantes), la boucle 280 BPM rejouée entrait dans le `best` normal. Le régime est maintenant gardé avec le step (`_lastConfigStepUseMe`). [mesuré]

## Preuves rouges (code d'avant, assertion lue)

- T1, T2, T2b, T3, T4 : rouges sur code intact (best 300 contre 105, comfort 124,65 contre 105, motion 15 contre 95). [mesuré, session précédente]
- T6c (nouveau) : rouge avant le correctif de rejeu, `Expected: <105> Actual: <280.0>` sur `best` de `rhythm.bpm_ceil.throat`. Vert après. [mesuré]
- T6a est un témoin de non-vacuité (un FAIL normal fige bien `rhythm.bpm_ceil.throat` à 120). T7 est le témoin de séance normale. [mesuré]

## Mutations (restauration par copie, `cmp` puis arbre git propre)

| Mutation | Résultat | Assertion qui tombe |
|---|---|---|
| M1a retirer `useMe:` du site `session_controller` | rouge | T6b : plafonds non vides (dont `rhythm.bpm_ceil.throat` 280), T5 : best 280 contre 105 |
| M1b `_restorePreviousLoop` repasse `_useMeActive` | rouge | T6c : best 280 contre 105 |
| M1c retirer `useMe:` du site `challenge` | **survit** (bancs T6, T1-T8, dynamique) | aucune : site non gardé |
| M2 cran 5 %→35 % | rouge | T2 et T3 : 120,75 contre 105 |
| M3 plafond `1,15 × best` retiré | rouge | T2b : 126,79 contre 120,75 |
| M4 `_endUseMe` après `finalizeReport` | rouge | T5 : axe absent (`null`) |
| M5 plafonds de nouveau posés depuis un step « Utilise-moi » | rouge | T4 : motion 15 contre 95 ; T6b ; T6c |
| M6 un cran par épisode | rouge | T3 : 110,25 contre 105 (T2, un seul épisode, reste vert) |

[mesuré]

M4 a d'abord **survécu** : T5 passait parce que l'amorçage depuis `stats.max_use_me_sec` (écrit par `_endUseMe` avant le commit) remplit l'axe même quand le rapport ne le porte pas. T5 neutralise désormais l'amorçage ; M4 est rouge depuis. [mesuré]

## Suite complète

`timeout 900 flutter test` redirigé vers fichier : **1485 tests passés, 0 échec**, exit 0 (3 min 27 s). `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed .` : exit 0. [mesuré]

## Ce que je n'ai pas pu établir

- **Site `session_controller_challenge.dart:~923`** : M1c survit. Il ne compte quelque chose que si un défi démarre pendant « Utilise-moi » ; je n'ai pas établi que c'est possible (le générateur reçoit-il des défis pour la suite « Utilise-moi » ?). Aucun test ne le garde. [non vérifié]
- **Écart au plan** : le cran vaut 5 % dans le code, 12 % dans le plan §2. Je ne l'ai pas changé. À trancher par Manu. [document]
- **Cran dès 3 s tenues** : un step BPM tenu 3 s à un niveau ≥ `comfort` suffit au cran, même si un FAIL suit (T4 n'exige que `comfort` ≥ avant). Conforme à la règle du plan, non confirmé par Manu. [déduit]
- **Comportement préexistant** : après un FAIL en « Utilise-moi » avec moins de 30 s restantes, la boucle 280 BPM est rejouée jusqu'à la fin. Elle ne touche plus le profil, mais l'utilisatrice l'entend. Non modifié. [mesuré]
- T5b (l'axe `useMe.held_streak` n'influence pas le générateur) est un garde jamais vu rouge : aucune mutation ne le cible.
- Les tests T5 et T6 tournent en temps réel (≈ 40 s) ; verts à chaque lancement isolé, non rejoués en boucle.
- Ni l'affichage de l'axe dans `ProfileScreen` ni l'export diagnostic n'ont été vus sur appareil. Aucune compilation Android, aucune installation.
