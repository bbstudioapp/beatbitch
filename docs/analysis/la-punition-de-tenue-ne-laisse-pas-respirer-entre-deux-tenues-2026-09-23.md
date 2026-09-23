---
type: analyse
sujet: la-punition-de-tenue-ne-laisse-pas-respirer-entre-deux-tenues
ecrit_le: 2026-09-23T20:41:30+02:00
auteur: session tss2-punition · claude-sonnet-5
revision: 9db389f
branche: fix/punition-tenue-respiration
porte_sur:
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/assets/punishments.json
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/lib/career/services/generation/punishment_builder.dart
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/lib/screens/session_screen.dart
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/lib/services/beep_engine.dart
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/lib/widgets/movement_animation.dart
  - /home/emmanuel/perso/git/tss2-punition/rhythm_coach/test/session_punishment_breath_screen_test.dart
  - rhythm_coach/lib/career/services/generation/capability_clamps.dart
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/session_punishment_breath_screen_test.dart
provenance:
  mesure: 12
  deduit: 17
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/capability_clamps.dart:256
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart:161
  - rhythm_coach/lib/controllers/session_controller.dart:971
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:292
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:307
  - rhythm_coach/lib/screens/session_screen.dart:1118
  - rhythm_coach/lib/screens/session_screen.dart:876
  - rhythm_coach/lib/services/beep_engine.dart:417
  - rhythm_coach/lib/widgets/movement_animation.dart:438
  - rhythm_coach/test/session_punishment_breath_screen_test.dart:185
---

## En une phrase

La respiration entre deux tenues existe et le moteur la joue à l'heure, mais **l'écran ne la reçoit jamais** : pendant une punition, rien ne prévient `SessionScreen` que le moteur a changé de mode, donc le curseur reste figé sur la première tenue. Le correctif tient en un appel, `_notify()`, dans `_runPunishment`.

## Quelle punition Manu a pu vivre

- [déduit] La seule composition qui enchaîne deux tenues séparées par une respiration est `deep_hold_chain` (`punishment_builder.dart:161`) : tenue gorge, `breath` de 4 s sans texte, tenue `full`. Les autres compositions du générateur n'ont au plus qu'une tenue, en finale, après un rythme.
- [déduit] En carrière, `build()` retient la composition valide la plus exigeante (`valid.last` après tri sur `reqHumil`). Dès que l'humiliation cumulée atteint 20 et que les tenues gorge et `full` sont débloquées, **chaque FAIL donne `deep_hold_chain`**, sans tirage.
- [déduit] Hors carrière (Custom, scénarios), `triggerFail` retombe sur un tirage dans `punishments.json`. Sa `deep_hold_chain` compte trois tenues et deux respirations : tenue au temps 0, respiration au temps 12, tenue au temps 17, respiration au temps 31, tenue au temps 36. La fenêtre de respiration y dure donc 5 s entre deux steps, et « Respire. » est prononcé.
- [déduit] Rien ne consigne laquelle des deux Manu a jouée. Les deux routes sont donc testées, et elles échouent de la même façon. Sa phrase « aucune pause, le curseur reste en bas » colle aux deux.

## La cause

- [mesuré] Sonde jetable, non commitée, punition carrière non bornée (tenue 10 s, respiration 4 s, tenue 12 s), lecture toutes les 100 ms du mode reçu par `MovementAnimation` et de la position du curseur dessiné. Sur le code d'origine : à 9,9 s le moteur passe en `breath` mais l'écran garde `hold/throat`, y = 0,20 ; à 14,0 s le moteur passe en `hold/full`, l'écran garde `hold/throat`, y = 0,20 ; à 26,0 s le moteur est reparti en `rhythm/head`, l'écran est toujours sur `hold/throat`, y = 0,20. Le curseur ne bouge plus de toute la punition.
- [déduit] `_runPunishment` applique chaque step avec `_beep.applyStep` puis aligne l'ambiance, sans jamais appeler `_notify()` (`session_controller_fail_flow.dart:292` à `:305`). L'écran lit `ctrl.currentMode`, `currentFrom`, `currentTo` par `context.watch` (`session_screen.dart:876`, `:1118`), et `currentMode` relit `_beep.currentMode` (`session_controller.dart:971`) : il ne se redessine que sur notification.
- [déduit] Rien d'autre ne notifie pendant une punition : le ticker principal est annulé au FAIL, le contrôleur n'écoute aucun flux de beats, le service de voix n'est pas un notifieur. Les seuls `_notify()` du flow FAIL sont les changements de phase (`:166`, `:184`, `:209`, `:248`).
- [déduit] Seul le premier step s'affiche parce que `_failPhase = punishment; _notify()` précède `_runPunishment`, dont le premier `tick()` s'exécute de façon synchrone avant l'image suivante. Tous les steps suivants passent sous silence.

## Pistes réfutées

- [mesuré] Le clamp de capacité ne touche pas au `breath`. Le générateur, rejoué avec cinq profils (sans profil, profil vide, plafonds gorge 3 s et `full` 2 s, confort 3 s et 3 s, plafonds à 0), rend toujours `deep_hold_chain` avec la respiration intacte, sans texte : tenue, respiration de 4 s, tenue. Seules les durées des tenues varient (10/12 s non bornées, 2 à 3 s bornées).
- [mesuré] Le déroulé de `_runPunishment` est à l'heure : le moteur change de mode à 10,0 s et à 14,0 s, comme le plan. Ce n'est pas lui.
- [mesuré] `transitionGap` ne mange pas la fenêtre : une fois l'écran notifié, le curseur part à 10,0 s et atteint le haut à 10,8 s. [déduit] Ce délai retarde le démarrage du son (`beep_engine.dart:417`), pas l'état du moteur, posé avant l'attente.
- [mesuré] L'affichage du curseur pendant un `breath` est correct : une fois l'écran notifié, il monte à y = -1,00 (rangée `tip`). Ce n'est pas lui non plus.

## Le test rouge

- [mesuré] `test/session_punishment_breath_screen_test.dart`, commit `8b2d029`. Il monte `SessionScreen` avec un vrai `SessionController` et un vrai `BeepEngine` (échantillons non chargés, donc muet), déclenche un FAIL, puis lit à chaque image le mode que reçoit `MovementAnimation` et la position du curseur dessiné. Deux tests : route carrière (`deep_hold_chain` généré, confort de 3 s sur les deux tenues) et route `punishments.json` (le vrai `deep_hold_chain` chargé depuis l'asset français).
- [mesuré] Rouge sur le code d'origine, rejoué deux fois avec le même résultat, sur la bonne assertion (`:185`), pour les deux routes : `pendant la respiration le curseur doit être remonté en haut (y=-1). Moteur : {breath}, mode reçu par MovementAnimation : {hold}, y : {0.20}`. Les assertions qui précèdent passent : le moteur enchaîne bien tenue, respiration, tenue, et le curseur est bas pendant la première tenue. Seul l'écran est faux.
- [mesuré] Durée : de 15 à 17 s pour la route carrière, de 25 à 27 s pour la route JSON (temps réel, `Stopwatch` non simulé).

## Le correctif

- [mesuré] Commit `9db389f` : dans `_runPunishment.tick()`, `_notify()` après `_syncAmbienceToCurrentMode()` quand un step de configuration vient d'être appliqué (`session_controller_fail_flow.dart:307`). Un commentaire d'une ligne dit pourquoi.
- [mesuré] Les deux mêmes tests passent, sans changer une ligne. Vérification complète depuis `rhythm_coach/` : `flutter analyze` rend « No issues found! », `dart format --set-exit-if-changed .` ne change rien, `flutter test` rend 1103 tests passés, sortie 0. `challenge_timeline_forecast_test.dart` n'a pas échoué.
- [déduit] Le correctif couvre tout ce qui passe par `_runPunishment` : la punition après FAIL et la mini-punition inopinée. Il couvre aussi les transitions rythme vers tenue à l'intérieur d'une punition (`slow_torture`, `throat_relentless`), que la même cause laissait figées ; je ne les ai pas mesurées.

## Mesures pour trancher la durée de la respiration

- [mesuré] Sur la punition non bornée, une fois l'écran notifié : le curseur quitte y = 0,20 à 10,0 s, atteint y = -1,00 à 10,8 s, y reste jusqu'à 14,0 s, puis la tenue suivante le fait redescendre à y = 0,47 à 14,6 s et y = 0,60 à 14,8 s. Sur les 4 s de respiration : environ 0,8 s de remontée, environ 3,2 s en haut.
- [mesuré] Avec un profil de confort de 3 s, la chaîne dure 3 s, 4 s, 3 s : la respiration est plus longue que les tenues. Avec un profil non borné, elle dure 4 s entre des tenues de 10 s et de 12 s.
- Je ne tranche pas. Je n'ai aucune mesure qui dise que 4 s ne suffisent pas. [déduit] La remarque de Manu a été faite sur un écran qui ne montrait aucune respiration : son ressenti sur la durée n'a pas encore été calibré sur ce que l'écran montre vraiment. Allonger la respiration ou y ajouter une phrase du coach (aujourd'hui volontairement silencieuse) se décide après qu'il a vu la remontée.

## Ce que je n'ai pas pu établir

- [déduit] Rien de ce qui sort du haut-parleur : le moteur des tests n'a aucun échantillon, donc ni bip de tenue, ni son de respiration, ni délai audible du gap ; la voix passe par un canal simulé.
- [déduit] Le rendu sur téléphone (cadence d'images, transition réelle) : les tests lisent l'arbre de widgets, pas l'écran.
- [déduit] En production le moteur est déjà initialisé et `applyStep` pose son mode de façon synchrone ; celui des tests le pose une micro-tâche plus tard. Les deux passent avant l'image suivante, la différence n'est pas mesurée.
- [déduit] Laquelle des deux punitions Manu a réellement jouée (rien ne l'enregistre), et la durée réelle de ses tenues (elle dépend de son profil de capacités, 3 s dans le test).
- [déduit] Les punitions rythmées et la mini-punition inopinée n'ont pas été rejouées. Un constat annexe, la mini-punition qui ne peut jamais se déclencher, est à la fiche `tss2-010` du sas.

## Ce que Manu doit vérifier sur son téléphone

- [document] Installer l'APK construit par l'orchestrateur, jouer en carrière et appuyer sur FAIL. Le bandeau de phase affiche le nom de la punition. [déduit] La chaîne de tenues s'appelle `deep_hold_chain` en carrière et « Chaîne de Holds » hors carrière ; tout autre nom (par exemple `throat_relentless`) n'est pas la bonne punition, il faut refaire un FAIL plus tard.
- [déduit] Le repère est la couleur du curseur : jaune ambre pendant une tenue, vert pendant la respiration (`movement_animation.dart:438`, `:440`). Attendu : jaune en bas, puis vert tout en haut, puis jaune en bas.
- **Le mot à rapporter, un seul : « monte » si le curseur vert monte tout en haut pendant la respiration, « reste » s'il reste en bas.** Le jugement sur la durée de la respiration vient ensuite, séparément.
