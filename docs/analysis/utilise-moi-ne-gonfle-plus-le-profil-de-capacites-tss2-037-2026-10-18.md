---
type: analyse
sujet: utilise-moi-ne-gonfle-plus-le-profil-de-capacites-tss2-037
ecrit_le: 2026-10-18T11:32:14+02:00
auteur: session tss2-confort-finition · claude-sonnet-5-5
revision: e61ad07
branche: feat/utilise-moi-dynamique
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/capability_service.dart
  - rhythm_coach/lib/services/capability_tracker.dart
  - rhythm_coach/lib/services/diagnostic_export_service.dart
  - rhythm_coach/lib/services/diagnostic_import_service.dart
provenance:
  mesure: 19
  deduit: 1
  document: 4
  sans_marqueur: 1
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1592
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:441
  - rhythm_coach/lib/services/capability_service.dart:554
  - rhythm_coach/lib/services/capability_tracker.dart:105
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Ce dont il s'agit

tss2-037 : « Utilise-moi » (escalade 160→300 BPM) gonflait le profil de capacités. Branche `feat/utilise-moi-dynamique` du dépôt BeatBitch, worktree `~/perso/git/tss2-useme`, base `d774101`, tête `e61ad07`. **Rien n'a été poussé, fusionné ni installé.** [document]

Décision de Manu (18/10) : **aucune réparation des profils existants**. Un `best` déjà gonflé reste gonflé ; le test T8 se limite à prouver qu'un tel profil se lit sans erreur et que le nouvel axe s'amorce. [document]

## Cause

Le tracker comptait les steps « Utilise-moi » comme des steps normaux : `best` des axes BPM à 280-300, streaks de 318 à 657 s écrits dans `best`, et plafonds de session figés par le FAIL qui termine le mode (motion 95→5…50, apnée 18→1…6, hold gorge 22→6 selon l'instant du FAIL balayé). Le même effondrement existe sur une séance normale suivie d'un FAIL (motion 95→6…30) : il est générique, fiche sas `tss2-038` déjà écrite. [mesuré, session précédente, non rejoué ici]

## Correctif

- Le tracker reçoit `useMe` aux sites d'application de step. Records et plafonds d'un step « Utilise-moi » vont dans un tampon `useMeReached` ; aucun plafond n'est figé depuis un step « Utilise-moi » ; les streaks vivants sont clos à l'entrée et à la sortie du mode. [mesuré]
- Axe informatif `useMe.held_streak` (4 langues), amorcé une fois depuis `stats.max_use_me_sec` ; `_endUseMe` passe avant `finalizeReport`. L'export et l'import diagnostic portent le drapeau d'amorçage et `stats.max_use_me_sec` ; « Tout remettre à zéro » efface la tenue max. [mesuré]
- `best` n'est jamais écrit par « Utilise-moi » ; seul le `comfort` des quatre axes BPM peut monter (règle ci-dessous). [mesuré]

## Règle du gain décidée par Manu

Décision du 18/10. Le gain de `comfort` est **proportionnel à la durée tenue en « Utilise-moi », +5 % pour 5 minutes, plafonné par séance** : `comfort × (1 + 0,05 × min(1, secondes / 300))` (`kUseMeComfortGainMax`, `kUseMeFullGainSeconds`). Exemples vus par les tests : 2 × 2 min → +4 % (T3), 2 min 30 → +2,5 % (T12), 8 min → +5 % (T13), 3 s puis FAIL → +0,05 % (T11). [document]

- Les secondes sont les ticks `onTickSecond(useMeActive: _useMeActive)` cumulés sur la séance (`report.useMeSeconds`) : les épisodes s'additionnent. Le FAIL baisse `_useMeActive` avant `_restorePreviousLoop`, donc la boucle rejouée ne compte pas ; pause et défi ne produisent aucun tick. [mesuré]
- Les gates sont inchangées : axes BPM seulement, `useMeReached ≥ comfort × marge`, résultat ≤ `best_normal × 1,15`, rien si un plafond de session existe ni en quickie. [mesuré]
- Le temps est un total de séance appliqué à chaque axe BPM éligible, pas une durée par axe. `playedElapsed` n'a pas été retenu : le chrono continue pendant un défi et le compterait. **À relire par Manu.** [déduit]

## Provenance portée par le step

Le régime « Utilise-moi » n'est plus un état du mode relu à l'application : `SessionStep.useMe` est sérialisé, copié par `rebased`, posé par `buildUpgradedSession(useMe:)` ← `requestUpgrade(useMe: true)` (seul producteur). Le drapeau `_lastConfigStepUseMe` est supprimé ; un seul chemin mène à `onStepApplied` : `_trackConfigStep(step)` avec `useMe: step.useMe`. Dans le tracker, tout dérive de `_config.useMe`. [mesuré]

Conséquence : un step d'escalade appliqué après le FAIL (hook `onUseMeEnded` rendant `null`, moins de 30 s restantes) ou rejoué par `_restorePreviousLoop` reste compté « Utilise-moi » (T10, T6c). `_crossingsAccum` et `recordUseMeHeld` restent hors provenance. [mesuré]

## Défauts du deuxième tour

Relecture adverse `670824d`. [mesuré]
| Défaut | Sort |
|---|---|
| D1 grave : steps d'escalade après FAIL écrivant le profil normal (`Actual 290.0` contre 105) | corrigé par la provenance portée par le step (`b9e195c`), T10 |
| D2 moyen : un cran même si le FAIL suit 3 s | résolu par la règle du gain (`e61ad07`) : T11 `Actual 105` avant, `100,05` après |
| D3 faible : « Tout remettre à zéro » réamorçait l'axe (400) | corrigé (`95c2ac6`), fiche sas `tss2-040` ; T9 |
| D4 faible : les franchissements « Utilise-moi » entrent dans `gorge.crossings_lifetime` | **inchangé**, choix de l'orchestrateur, à trancher par Manu |
| D5 faible : export et import diagnostic ignoraient l'amorçage | corrigé (`00bc01b`), aller-retour testé |
[mesuré]

M7 (clôture des streaks au changement de régime retirée) survivait à la suite : T11 « changement de régime », dans les deux sens, la garde désormais (`8d899b5`). [mesuré]

## Mutations

Restauration par copie, `cmp`, puis arbre git propre. [mesuré]
| Mutation | Résultat | Assertion qui tombe |
|---|---|---|
| M1a retirer `useMe:` du site `session_controller` | rouge | T6b, T5 : best 280 contre 105 |
| M1b `_restorePreviousLoop` repasse `_useMeActive` | rouge | T6c |
| M1c retirer `useMe:` du site `challenge` | **survit** | site inatteignable pendant le mode (bouton masqué, session sans défis) |
| M2 cran 5 %→35 % | rouge | T2 et T3 : 120,75 contre 105 |
| M3 plafond `1,15 × best` retiré | rouge | T2b |
| M4 `_endUseMe` après `finalizeReport` | rouge | T5 : axe absent |
| M5 plafonds posés depuis un step « Utilise-moi » | rouge | T4, T6b, T6c |
| M6 plafond par séance (`clamp(0,1)` retiré) | rouge | T13 : `Expected 1,05 Actual 1,08` |
| N1 somme → max sur les épisodes | rouge | T3 : `Expected 104 Actual 102` |
| N2 boucle rejouée comptée (`_endUseMe` ne baisse plus le drapeau) | rouge | T6c : `Actual 100,183` hors [100 ; 100,1] |
| N3 tick sur horloge murale (la pause compte) | rouge | T6d : `Actual 100,2` hors [100 ; 100,17] |
| N4 `useMeActive:` retiré de `_accrueHoldSecond` | **survit** | aucune, ni sur les 16 fichiers `capability_*`/`use_me_*` |
[mesuré]

N4 : le contrôleur ne transmet plus le drapeau, `useMeSeconds` reste à 0, le gain est nul et la suite reste verte. T6c et T6d n'ont que des bornes hautes ; aucun test de contrôleur n'exige un gain strictement supérieur à `comfort`. Le câblage contrôleur→tracker du gain n'est donc gardé que côté tracker (T3, T11-T13 pilotent le tracker directement). **Aucun test ajouté, rien corrigé** (consigne de clôture). N3 modélise « la pause compte » par un compte sur horloge murale, faute de chemin où la pause ajoute des ticks. [mesuré]

## Suite complète

`timeout 900 flutter test` redirigé vers fichier, à `e61ad07` : **1501 tests passés, 0 échec**, exit 0. `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed .` : 0 fichier changé. [mesuré]

## Ce que je n'ai pas pu établir

- **N4 survit** : voir ci-dessus. Un test de contrôleur exigeant un gain > 0 après une tenue sans FAIL le garderait. [mesuré]
- **M1c survit** : le site `session_controller_challenge.dart` ne compte que si un défi démarre pendant « Utilise-moi » ; je n'ai pas établi que c'est possible. [mesuré]
- **Défi et arrière-plan pendant le mode** : aucun test direct (pause seule, par borne). [non vérifié]
- **Comportement préexistant** : après un FAIL en « Utilise-moi » avec moins de 30 s restantes, la boucle 280 BPM est rejouée jusqu'à la fin. Elle ne touche plus le profil ni le gain, mais l'utilisatrice l'entend. Non modifié. [mesuré]
- T5b (l'axe `useMe.held_streak` n'influence pas le générateur) est un garde jamais vu rouge : aucune mutation ne le cible. [mesuré]
- Les tests T5, T6 et T11-T13 du câblage tournent en temps réel ; verts à chaque lancement, non rejoués en boucle. [mesuré]
- Ni l'affichage de l'axe dans `ProfileScreen` ni l'export diagnostic n'ont été vus sur appareil. Aucune compilation Android, aucune installation (consigne de la tâche). [document]
