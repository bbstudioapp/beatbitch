---
type: analyse
sujet: utilise-moi-ecrase-par-la-regeneration-post-defi
ecrit_le: 2026-10-18T20:56:24+02:00
auteur: session tss2-useme-regen · claude-opus-5-5
revision: 8478d56
branche: fix/useme-regen-post-defi
porte_sur:
  - rhythm_coach/lib/career/screens/career_screen.dart
  - rhythm_coach/lib/controllers/session_controller_career_hooks.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/test/use_me_post_challenge_regen_test.dart
provenance:
  mesure: 5
  deduit: 4
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/screens/career_screen.dart:847
  - rhythm_coach/lib/controllers/session_controller_career_hooks.dart:120
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:833
---

## Le défaut

[document] Fiche `tss2-042` du sas : quand « Utilise-moi » est pressé pendant le souffle qui suit un défi réussi, et que ce défi a élargi les déblocages, la régénération post-défi arrive après l'appui et remplace l'escalade par une suite normale. Le drapeau `_useMeActive` reste levé : la suite normale est comptée comme tenue « Utilise-moi » (record du Profil, axe `useMe.held_streak`).

## Reproduction

[mesuré] Test `rhythm_coach/test/use_me_post_challenge_regen_test.dart`, sur le vrai `SessionController` (carrière, suivi des capacités actif). Le défi est armé puis passé. Le vrai `_finalizeChallengeAcquittals` appelle `onPostChallengeRegen`, que le test tient en vol par un `Completer` ; « Utilise-moi » est pressé pendant ce temps, puis la régénération est libérée.

[mesuré] Sur le code d'avant le correctif (commit du test seul, `431a345`), le test tombe sur « la régénération post-défi ne remplace pas l'escalade » : plus aucun step « Utilise-moi » dans la séance. Sans cette première assertion, il tombe sur la sonde « le beg puis l'escalade ont joué » : un seul step joué sous le drapeau, le step normal de la régénération.

[mesuré] Le test vérifie aussi, jusqu'à la fin de la séance, que tout step joué pendant que le drapeau est levé est un step « Utilise-moi ». C'est la forme vérifiable de « le temps compté Utilise-moi n'inclut jamais une suite normale ». Un second test vérifie que, sans appui, la régénération s'installe toujours.

## Correctif

[déduit] `requestPostChallengeRegen` (`rhythm_coach/lib/controllers/session_controller_career_hooks.dart:120`) ne remplace plus la séance quand `_useMeActive` est levé. L'escalade gagne. La compétence débloquée arrive dans la suite normale demandée après le FAIL qui clôt « Utilise-moi » : `_handleUseMeEnded` relit `milestoneService.acquiredUnlockKeys()` (`rhythm_coach/lib/career/screens/career_screen.dart:847`). C'est déjà le comportement quand l'appui tombe juste après l'installation de la régénération : la fenêtre de course s'aligne sur le cas courant.

[déduit] Le drapeau est levé de façon synchrone, en tête de `requestUpgrade` (avant le premier `await`). Une régénération qui arrive pendant l'arrêt borné du TTS de l'appui voit donc déjà le drapeau.

[document] Option écartée : ignorer l'appui tant que la régénération est en vol. La joueuse perdrait un appui sans rien voir. Le choix est consigné dans le plan de la session, hors dépôt.

## Preuves

[mesuré] Mutation 1, garde retirée : rouge sur « la régénération post-défi ne remplace pas l'escalade ». Mutation 2, régénération toujours abandonnée : rouge sur le test « sans appui » (`contains <110>`, séance restée à la suite d'origine). Fichier restauré par copie, diff vérifié.

[mesuré] `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed .` : sortie 0. Suite complète, lancée sur `47d20db` (le commit suivant ne touche que des commentaires) : 1556 tests verts, 1 rouge, `movement_rembobinage_tenue_gorge_test` : l'instabilité sous charge déjà au sas (`tss2-026`). Relancé seul, il passe trois fois sur trois.

## Ce que je n'ai pas pu établir

[déduit] Le déclencheur réel n'est pas rejoué : le test force l'élargissement des déblocages par un écart entre `unlockedKeys` et `milestoneService`, comme le banc du tri. La durée réelle de la fenêtre sur appareil n'est pas mesurée. Rien n'a été joué sur téléphone.

[déduit] Non vérifié : une séance où la joueuse ne fait aucun FAIL après l'appui ne joue pas la compétence débloquée avant la fin. C'est le comportement du cas courant (appui après installation), lu dans le code, pas mesuré.
