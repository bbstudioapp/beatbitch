# Postures et pauses plus fréquentes — 2026-10-17

Branche `feat/postures-pauses-frequence`, partie de `fix/corrections-octobre` (`cb080c6`).
Décision appliquée : Manu, 17/10 (changement de position toutes les 6-10 min, pauses
selon l'endurance, pause passable, fusion pause + changement). Valeurs révisées le 26/10 (§2,
§4) : pauses toutes les 7 à 12 min, 1er changement entre 4 et 7 min, annonce au début de la
pause, temps de pause hors du temps d'effort, pauses gardées dans les suites refaites.

## 1. L'existant, relevé avant de coder

| Question | Réponse dans le code de départ |
|---|---|
| La pause a-t-elle un bouton « passer » ? | **Non.** `_BreakBanner` (`session_screen.dart`) n'affiche que « PAUSE », le décompte et la future posture. Aucune méthode du contrôleur ne termine une pause en avance. |
| Comment la posture est-elle validée ? | Par un **gel de posture** déjà en place : `_enterAwaitReady()` fige l'horloge (`PostureGate`, gel dérivé de la scène qui l'ordonne), l'écran montre « JE SUIS EN PLACE » (`_PostureReadyButton` → `confirmPostureReady`), et un `Timer` de sécurité reprend seul au bout de **90 s**. Armé par les steps `awaitReady` des milestones posture et par la sortie d'une pause qui change de pose. Pas de caméra dans ce chemin. |
| Un changement de position hors pause existait-il ? | Non : seulement à la sortie d'une pause (`_exitBreak`) et pendant une milestone `intro_posture_*`. |
| Fréquence des pauses | `_computeBreakCount` : 0 sous 28 min, 1 dès 28 min (vers 50 % de `genUntil`), 2 dès 45 min (34 % / 67 %), plancher 25 % de `genUntil`. La 2ᵉ pause était forcée en récup pure (`pureRecovery`). Durée 60-120 s, trou d'effort dans l'enveloppe. |
| Mesures d'endurance disponibles | (a) la **jauge `stamina`** 0..100 (`stamina_model.dart` à la génération, `stamina_engine.dart` en live) : état instantané de la séance, pas un trait de la joueuse ; (b) les **points de spécialisation « Endurance »** (`SessionConfig.pts(SpecializationBranch.endurance)`), déjà lus par le générateur comme « endurance » (durées `scaleDuration`, `durScore` +0,08/pt, holds finaux +3 s/pt ; « endurance maxée » = 5 pts dans la doc) ; (c) l'axe de capacité **`effortNoBreathStreak`** (« Effort sans pause » au profil) : mesuré, mais jamais lu par le générateur, nul pour un profil neuf, et borné par les sas breath que le générateur pose lui-même. |

**Ce qu'il manquait** : un changement de position hors pause, une fréquence de pauses liée à la
durée et à l'endurance, un moyen de passer la pause. Le gel de posture et son bouton existaient :
ils sont réutilisés tels quels, seul le délai de reprise automatique passe à 2 min.

## 2. Ce qui est fait

| Commit | Contenu |
|---|---|
| `676316f` | Générateur : pauses toutes les `lerp(10 min, 20 min, pts_endurance / 5)`, jamais avant 10 min ni en phase finish (le nombre découle de la durée) ; changement de position seul (`PostureChange`, `Session.postureChanges`) dès 10 min puis tous les 6-10 min (tirage), parmi les postures débloquées hors `free`, jamais la pose en cours (milestones posture comprises), jamais sur un défi dû ; un changement dû à moins de 2 min d'une pause est porté par la pause. Runtime : `_updatePostureChange` (annonce `pickPostureChange`, coupure du bip, gel de posture), `skipBreak` (saut de timeline à la fin de la pause puis reprise normale), délai de reprise auto 90 s → 2 min, report des changements à l'excision d'un défi. |
| `ac19034` | Bouton « PASSER LA PAUSE » dans la bannière de pause, 4 langues (`sessionBreakSkipButton`). |
| `f5dd575` | Garde runtime impossible retirée, balayage des défis élargi (la garde du générateur n'y était pas atteinte), report à l'excision testé, commentaires rendus faux corrigés (90 s, « sessions longues », « 2ᵉ pause en récup pure »). |
| `b4941ee` | Commentaires seulement : références de ticket, de spec et de phase de refacto des fichiers touchés. |
| `5178b02` | Valeurs du 26/10 : pauses toutes les `lerp(7 min, 12 min, pts_endurance / 5)`, 1er changement de position tiré entre 4 et 7 min, puis 6-10 min. Remplace les 10-20 min et le 1er changement à 10 min du `676316f`. |
| `af320f9` | La pause qui change de position l'annonce dès son entrée : pose posée, une seule phrase (pose, sinon entrée), attente de mise en place pendant la pause ; `_exitBreak` ne dit plus que la reprise ; `skipBreak` ré-arme l'attente si elle n'était pas validée. |
| `557f030` | Le temps de pause sort du temps d'effort : fenêtre réservée comme un défi (`reservedWindowSeconds`), la séance dure la durée choisie + les pauses. `inLastMinute` et la progression de stamina des jalons se lisent sur le temps d'effort. |
| `87792bc` | Les suites refaites (après un défi, étape retentée) rejouent les pauses et changements non joués (`PostureScript`, `generate(carry:)`) ; l'effort restant exclut `pauseSecondsAhead`. « Utilise-moi » (non-stop) ne les garde pas. |
| `8edab32` | Libellé de durée : « + le temps des défis et des pauses » / « + le temps des pauses » (4 langues) ; la séance bâclée n'a jamais de pause. |
| `762a227` | Test des getters `unplayedPostureScript` / `pauseSecondsAhead` du contrôleur. |

Vérifications : `flutter analyze` → No issues found! ; `dart format` appliqué ; suite complète verte à
`f5dd575` (1390 tests) ; `flutter build web` OK. À `b4941ee` (commentaires seulement), une suite
complète a fait tomber `challenge_timeline_forecast_test` — flake déjà au sas (`tss2-008`), 3/3 vert
seul. Une autre suite (à `676316f`) a fait tomber `movement_rembobinage_tenue_gorge_test`, vert seul
→ fiche `tss2-026`.

## 3. Preuves rouges

Avant le code (API vide pour compiler) : 10 rouges sur 16, chacun sur l'assertion visée (0 pause là
où il en faut 1-2, aucun changement de position, pose non appliquée, pause non passée, gel absent).

Mutations, restaurées par copie :

| Mutation | Tombe |
|---|---|
| M1 endurance non câblée (intervalle figé à 10 min) | 3 tests fréquence (2, 5, 9 pts) |
| M2 échelle d'endurance /50 | 3 tests fréquence |
| M3 changements non livrés dans `Session` | 3 tests changements |
| M4 une pause ne prend jamais la pose | fusion pause + changement |
| M5 pas de report vers la pause proche | fusion pause + changement |
| M6 pas de garde « défi dû » | « jamais pendant un défi » (après élargissement du balayage ; survivait avant) |
| M7 changement dès 0 min | cadence 6-10 min dès 10 min |
| M8 même pose permise | « jamais deux fois la même » |
| M9 intervalle 6-10 → 1-3 min | cadence + fusion |
| M10 plancher de pause 10 → 4 min | 5 tests |
| R1 `_updatePostureChange` non appelé dans `_onTick` | 2 tests runtime |
| R2 délai de reprise 90 s | reprise auto à 2 min (fakeAsync) |
| R3 `skipBreak` sans saut de timeline | passer la pause |
| R4 changement sans coupure du bip | annonce + attente |
| R5 changement sans gel | annonce + attente, reprise auto |
| R6 excision sans décalage des changements | `posture_gate_invariant_test` |
| U1 bouton « passer » inerte | test d'écran `SessionScreen` |
| R7 garde `_breakActive` dans `_updatePostureChange` | **survivait** → garde retirée (cas impossible : le générateur ne pose jamais un changement dans une pause) |

## 4. Choix faits faute de précision dans la décision — à trancher par Manu

1. **Mesure d'endurance** : points de spécialisation « Endurance » (0 pt → pause toutes les 7 min,
   ≥ 5 pts → 12 min, linéaire entre). C'est l'« endurance » que le générateur lit déjà partout.
   Alternative : l'axe mesuré « Effort sans pause » (`effortNoBreathStreak.comfort`) — plus fidèle à ce
   que la joueuse tient, mais vide pour un profil neuf, jamais lu par le générateur et sans bornes
   existantes. Le choix est isolé dans `_breakIntervalSeconds()`.
2. **Postures « débloquées »** = hors `free`. Sans posture débloquée : aucun changement, pauses sans
   pose ; avec une seule : au plus un changement par séance.
3. **Premier changement** tiré entre 4 et 7 min (frontière de bloc suivante), puis +6-10 min tirés.
4. **« Près d'une pause » = 2 min** avant le début ou après la fin de la pause.
5. **Changement porté par une pause** : annoncé à l'entrée de la pause, qui attend « JE SUIS EN PLACE »
   avant de courir ; le temps de mise en place n'est pas déduit de la pause (l'horloge est gelée).
6. **Délai de reprise auto à 2 min pour tous les gels de posture** (milestones posture et pauses
   compris, 90 s avant) : une seule constante.
7. **Pauses hors effort** : la séance dure la durée choisie + les pauses, comme avec les défis ;
   passer une pause raccourcit la séance du temps de pause restant, jamais l'effort.
8. **Suites refaites** : post-défi et étape retentée gardent pauses et changements non joués, recalés
   sur le temps déjà joué ; une pause qui ne tient plus avant la phase finish est abandonnée. Une
   pause en cours au moment de la régénération est coupée. « Utilise-moi » ne garde rien (décision
   de Manu, 26/10).
9. **Libellé de durée** : trois variantes selon les défis et les pauses actifs, car « défis et pauses »
   serait faux dès qu'une des deux fonctions est éteinte.

## 5. Ce qui reste ouvert

- Retry d'une étape qui enseigne une posture : la pose du jalon rejoué peut rendre un changement
  porté sans effet (même pose). Rare, bénin.
- Non protégés par un test : `inLastMinute` sur le temps d'effort (observable seulement par une
  récupération absente, tirage trop fin pour une assertion stable) ; le câblage des trois sites de
  `career_screen.dart` (`pauseSecondsAhead`, `carry`) et du libellé, que seul un banc d'écran
  prouverait.
- Les cibles de jalon (`tryInsertAt`) restent sur `ctx.time` : avec des pauses avant, un jalon tombe
  plus tôt dans l'effort de la somme des pauses déjà passées, comme déjà avec les défis. Aucun
  jalon perdu (`insertAllRemaining`).
- Fusion avec `fix/regen-garde-jalons` (`1a274c8`) : mêmes deux builders et même constructeur
  `Session(...)` que `87792bc`, conflit textuel additif à la fusion.
- Rien n'a été joué sur téléphone : ressenti de la cadence, du bouton, de l'annonce et de l'attente à juger.
- Nettoyage des commentaires partiel dans les trois gros fichiers touchés : restent des lignes-récit
  (phases, spec, refacto) dans `career_session_generator.dart`, `session_controller.dart`,
  `session_controller_challenge.dart`.
- La spec locale `~/vault/perso/bb/specs/scripted_breaks.md` décrit encore les seuils 28/45 min.
