---
type: analyse
sujet: correctif-tss2-027-l-arriere-plan-suspend-le-decompte-et-met-start-en-pause
ecrit_le: 2026-10-17T18:42:53+02:00
auteur: session tss2-arriere-plan · claude-sonnet-5-5
revision: 71ce087
branche: fix/demarrage-arriere-plan
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
provenance:
  mesure: 3
  deduit: 4
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1090
  - rhythm_coach/lib/screens/session_screen.dart:290
---

## Constat

[document] tss2-027 : appli en arrière-plan pendant le décompte de mise en place ou les `await` de `start()`, `pause()` sortait (`_state != running`), le décompte allait à zéro et la séance tournait seule, jusqu'à l'écriture au profil (sonde de tri : `stats.sessions_completed: 1`, `stats.total_seconds: 4`).

## Règle appliquée

Décision de l'orchestrateur sous mandat (Manu a validé l'objectif « elle attend ton retour », pas le détail) : le son ne repart jamais seul au retour dans l'appli.
- Décompte : suspendu en arrière-plan (minuteur et voix coupés), repris **depuis 7** au retour.
- `start()` : si l'appli a quitté l'avant-plan en chemin, la séance arrive en `paused`, sans step posé, sans horloge ni ticker ; la joueuse reprend avec le bouton existant.

## Reproduction (rouge avant correctif)

[mesuré] Banc `test/session_arriere_plan_demarrage_test.dart`, vrai `SessionScreen` + vrai contrôleur, cycle de vie par `handleAppLifecycleStateChanged`, jamais de `resumed` dans les cas d'absence. Sur `249f413` : 6 rouges sur 7, le témoin vert.
- `Expected: SessionState.idle / Actual: SessionState.running — la séance a quitté idle alors que la joueuse est partie` (décompte).
- `Expected: SessionState.paused / Actual: SessionState.running — la séance n'arrive pas en pause` (start() en vol, et variante retour avant la fin).
- `… le retour dans l'appli a relancé la séance seul` (reprise).

## Correctif (`908b7cb`, tests `5ccbcb5`)

[document] `SessionController` : `onAppBackgrounded()` / `onAppForegrounded()` retiennent `_appInBackground` ; `_backgroundedDuringStart` est posé à l'entrée de `start()` et par tout passage en arrière-plan pendant qu'il tourne. Juste après le dernier `await`, avant `_stopwatch.start()`, une séance marquée finit en `paused` (musique mise en pause). `resume()` ne relance le moteur qu'une fois `_configApplied` : sans cela, une reprise avant le step 0 faisait battre la config par défaut du moteur (rythme 60 BPM fantôme).
`_SessionScreenContentState` s'abonne au contrôleur : à l'arrière-plan il coupe le minuteur du décompte et la voix, au retour il relance le décompte.
La garde est l'état d'arrière-plan, pas le nom d'une méthode. `pause()` n'est pas modifié.

## Mutations

[mesuré] Chaque garde retirée seule, restauration par copie (`cmp` identique) :
- minuteur du décompte non coupé → 2 rouges ; voix non coupée → 1 rouge ; décompte non relancé au retour → 1 rouge ; retour au premier plan non relayé → 1 rouge ;
- fin de `start()` sans pause → 4 rouges ; arrière-plan en vol non retenu → 3 rouges ; état d'entrée non lu → 1 rouge ;
- `resume()` sans `_configApplied` → 1 rouge ; plus de `pause()` à l'arrière-plan en séance `running` → le témoin rougit.

## Vérifications finales

[mesuré] `flutter analyze` : No issues found ; `dart format --set-exit-if-changed .` : 0 ; suite complète : 1416 tests verts.
Commit « commentaires seulement » `71ce087` (`session_controller.dart`, `session_screen.dart`) : le code hors commentaires est identique avant/après (comparé), balayage fait par un agent délégué, relu seulement par ce contrôle de forme.

## Reste ouvert

- [déduit] Le décompte repris **re-prononce** la phrase de mise en place : c'est un son qui repart seul au retour dans l'appli, conforme au « reprend depuis le début » du mandat mais à la lisière de la règle. À confirmer par Manu.
- [déduit] Écran monté appli déjà en arrière-plan (enchaînement automatique de séance) : l'état n'est alimenté que par les événements reçus, donc non couvert. Fiche `tss2-030`.
- [déduit] Séance à morceau : la musique démarre dans `start()` avant la mise en pause finale ; si l'arrière-plan survient avant `music.start`, elle sonne jusqu'à la fin de `start()` (au pire quelques centaines de ms). Le `music.pause()` du chemin « en pause » n'a pas de test.
- `inactive` (volet de notifications, boîte système) compte comme arrière-plan, comme pour la pause existante : le décompte redémarre, la séance arrive en pause.
- tss2-022 (pause pendant le trou de transition du moteur) : non traité, `pause()` inchangé.

## Ce que je n'ai pas pu établir

[déduit] Que les timers Dart tournent en arrière-plan sur le S21 (condition de la gravité, non mesurée) ; rien joué sur téléphone, aucun son entendu, aucune compilation Android ; l'affichage de l'écran « en pause » sans config posée n'a été vu que par le banc (le bouton de reprise y est trouvé).
