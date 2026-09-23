---
type: analyse
sujet: seance-musicale-correctif-fin-du-morceau
ecrit_le: 2026-09-23T23:11:32+02:00
auteur: session tss2-musique-r1 · claude-sonnet-5
revision: f68db0e
branche: feat/seance-musicale
porte_sur:
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers-6.6.0/lib/src/audioplayer.dart
  - /home/emmanuel/perso/git/tss2-musique/rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - /home/emmanuel/perso/git/tss2-musique/rhythm_coach/lib/services/music_clock.dart
  - /home/emmanuel/perso/git/tss2-musique/rhythm_coach/lib/services/music_engine.dart
  - /home/emmanuel/perso/git/tss2-musique/rhythm_coach/test/music_clock_test.dart
  - /home/emmanuel/perso/git/tss2-musique/rhythm_coach/test/music_engine_test.dart
  - /home/emmanuel/perso/git/tss2-musique/rhythm_coach/test/session_music_controller_test.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/services/music_clock.dart
  - rhythm_coach/lib/services/music_engine.dart
provenance:
  mesure: 18
  deduit: 6
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - /home/emmanuel/.pub-cache/hosted/pub.dev/audioplayers-6.6.0/lib/src/audioplayer.dart:158
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:263
  - rhythm_coach/lib/services/music_clock.dart:58
  - rhythm_coach/lib/services/music_engine.dart:110
---

## Verdict

[mesuré] R1 est corrigé et R2 est gardé. Suite complète 1178/1178 (1167 avant, 11 tests ajoutés), `flutter analyze` « No issues found! », `dart format --set-exit-if-changed .` 0 fichier changé, à `f68db0e`. Chaque mutation a été vérifiée posée (motif unique, `git diff` non vide), jouée, puis restaurée par `git checkout` : l'arbre est propre. `duration_seconds` des JSON n'a pas bougé (aucun fichier d'`assets` dans le diff).

[mesuré] Le filet du correctif a deux trous : le câblage du vrai plugin (`AudioplayersMusicPort.completions`) et l'annulation de l'abonnement de fin ne sont gardés par aucun test. Fiche `tss2-014` au sas. Détail en fin de rapport.

## La cause, rejouée

[document] `audioplayers` 6.6.0 (`audioplayer.dart:158`) : sur l'événement de fin, l'état passe à `completed`, puis `stopAndUpdate()` relit la position par un appel de plateforme et la publie sur `onPositionChanged`. Les plugins natifs l'ont remise à 0 (relecture adverse, R1). `MusicClock.report` acceptait tout rapport en état `playing`.

[mesuré] Rejeu sur le contrôleur réel, avant correctif (`1f2f347`) : un faux lecteur rapporte 99,8 s, puis émet l'événement de fin et un rapport à 0, sur une horloge murale pilotée. 0,1 s de mur plus tard, `elapsed` vaut 0,1 s et la séance reste `running`. Même mécanisme que la sonde de la relecture, sur une séance de 100 s et un morceau de 99,85 s : l'écart de 0,15 s est celui du vrai contenu (179 s pour 178,85 s).

## Le test rouge

[mesuré] Faux lecteur (`_Port` de `session_music_controller_test.dart`) : `finish()` émet l'événement de fin puis un rapport à 0, `finish(zeroFirst: true)` l'ordre inverse. `build` reçoit une horloge murale pilotable. Sur le code d'avant, les 5 tests ajoutés pour R1 tombent, les autres restent verts.

```
fin du morceau : le lecteur retombe à 0, la séance court sur l'horloge murale… [E]
  Expected: a value greater than or equal to Duration:<0:01:39.000000>
    Actual: Duration:<0:00:00.100000>
```

[mesuré] Ce message tombe pour 4 tests : fin du morceau, rapport à 0 avant l'événement de fin, FAIL dont le souffle déborde la fin, stop dans la queue. Le cinquième (pause puis reprise dans la queue) tombe sur `Expected: <1>  Actual: <2>` : le lecteur est relancé. Le rouge est bien « `elapsed` retombé », pas une erreur de compilation ni de montage : le faux lecteur déclare `completions` sans `@override` tant que l'interface n'en a pas.

## Le correctif

[mesuré] Commit `5ea77cf` : `music_clock.dart` +18, `music_engine.dart` +13, le reste en tests.

- [mesuré] `MusicPlayerPort.completions` (`music_engine.dart:12`), câblé sur `onPlayerComplete` dans `AudioplayersMusicPort` (`:27`). Tout autre implémentant de l'interface doit le déclarer.
- `MusicEngine.start` s'abonne à la fin de lecture et retient `_peak`, la plus grande position rapportée (`:103` à `:110`). À la fin, il appelle `MusicClock.end(_peak)`. `_release` annule l'abonnement.
- `MusicClock.end` (`music_clock.dart:58`) ré-ancre sur le plus grand de la position extrapolée et de `_peak`, puis passe `_ended`. `report` ignore tout rapport ensuite (`:48`) ; `start()` remet `_ended` à faux. L'horloge court sur le mur au-delà de la fin ; `_onTick` termine la séance à `duration_seconds` par `_finish`, stats comprises, sans autre changement dans le contrôleur.

[déduit] Deux ajouts au-delà de la lettre du mandat, tous deux dans le chemin de la fin de lecture. `_peak` : l'ordre « fin puis 0 » se lit dans le code Dart du plugin (l'événement précède l'appel de plateforme qui publie le 0) mais l'ordre inverse n'est pas exclu côté natif ; le plancher rend le correctif indépendant de l'ordre. Garde de reprise : reprendre un lecteur terminé le relancerait depuis le début ; la queue est courte (0,15 s sur le contenu réel) mais une pause peut y tomber, un verrouillage d'écran par exemple ; `MusicEngine.resume` ne rappelle plus `play` après la fin.

## Ce que les mutations du correctif ont établi

[mesuré] Jouées sur les 3 fichiers de tests musique avant l'ajout du test R2 (39 tests), pas sur la suite complète.

| [mesuré] Mutation posée | Tests rougis |
|---|---|
| M1 : abonnement à la fin retiré (`_completion = null`) | 7 (2 moteur, 5 contrôleur), `Actual: 0:00:00.100000` |
| M2 : `if (_ended) return;` retiré de `report` | 7 (2 horloge, 1 moteur, 4 contrôleur) |
| M3 : plancher `_peak` retiré (`_anchor(current)`) | 2 (horloge et contrôleur, « rapport à 0 avant la fin »), `Expected: 0:02:58.800000  Actual: 0:00:00.000000` |
| M4 : garde de reprise retirée (`!_clock.isEnded`) | 2 (moteur et contrôleur), `Expected: <1>  Actual: <2>` |

[mesuré] Deux mutations restent vertes sur les 4 fichiers musique (42 tests) : M5, `unawaited(_completion?.cancel());` retiré de `_release` ; M6, `completions` du vrai port remplacé par `const Stream<void>.empty()`.

## R2 — le record Iron Lungs

[mesuré] Le faux `_Beep` suit désormais `currentMode`, `currentFrom`, `currentTo` et `currentBpm` par `resolveStepConfig` (`step_resolution.dart:31`), la fonction que le vrai `applyStep` appelle, avec les mêmes valeurs initiales (rhythm, head, nul, 60) et le même retour immédiat sur un step texte seul. Les 18 autres tests du fichier sont restés verts avec ce faux.

[mesuré] Test : tenue `full` de 10 à 30 s, position à 10,2 puis 11,2, 12,2, 13,2 (4 s créditées), FAIL, reprise après le souffle, secondes 22 à 29 créditées (8 s), step de 30 s qui vide le cumul. `maxHoldFullAtomic` doit valoir 8. Le test vérifie lui-même que le faux suit la tenue (`currentMode == hold`, `currentFrom == full`) avant le FAIL.

| [mesuré] Mutation dans `_triggerMusicalFail` | Résultat |
|---|---|
| les deux lignes retirées (`_currentHoldFullDuration = 0;` et `_disarmHoldVerifier();`) | rouge : `Expected: <8>  Actual: <12>` |
| `_currentHoldFullDuration = 0;` seule | rouge, même message |
| `_disarmHoldVerifier();` seule | **verte**, 19/19 |

## Ce que les tests établissent

[mesuré] Avec un lecteur qui fait ce que fait le code des plugins (fin de lecture, position 0), dans les deux ordres : la séance passe par `_finish` à sa durée, morceau libéré, bips détachés, `elapsed` jamais sous 99 s. Un FAIL dont le souffle déborde la fin ne l'empêche pas ; le souffle est coupé, `hadFailThisSession` reste vrai. Un stop dans la queue ramène à `idle`, libère le morceau, détache les bips, et la séance ne passe jamais en `finished` même quand le mur dépasse la durée. Une pause suivie d'une reprise dans la queue ne relance pas le lecteur.

[mesuré] Un FAIL musical pendant une tenue `full` ne fusionne pas la tenue d'avant le souffle avec celle d'après : le record enregistré est celle d'après seule.

## Ce que je n'ai pas pu établir

- [déduit] Que le S21 émette bien l'événement de fin : le faux lecteur reproduit le code des plugins lu, pas l'appareil. Le repère « Fin » du rapport de relecture tranche. Lequel des deux ordres (fin puis 0, ou 0 puis fin) se produit sur le téléphone reste inconnu ; le correctif tient dans les deux.
- [mesuré] Que le câblage du vrai plugin fonctionne : M6 est verte. Si `completions` était mal câblé, le correctif serait inerte sur le téléphone sans qu'un test tombe. Non traité ici, fiche `tss2-014`. M5 (annulation de l'abonnement) est verte aussi ; l'effet d'un abonnement laissé actif n'a pas été mesuré.
- [déduit] La géométrie réelle : les tests utilisent une séance de 100 s et un morceau de 99,85 s, pas les JSON (179 s, 178,85 s) ; le FAIL du test est à 92 s, pas à environ 171 s. Le mécanisme est le même, aucun test ne joue le contenu réel de bout en bout.
- [déduit] Ce que font les bips pendant la queue : la grille lit `music.position`, qui dépasse maintenant la fin du morceau. Aucun test ne le regarde.
- [mesuré] `_disarmHoldVerifier()` de `_triggerMusicalFail` n'est gardé par aucun test : aucun test n'injecte de `HoldVerifier` (caméra expérimentale, hors périmètre).
- [déduit] Le faux `_Beep` ne reproduit pas le relèvement aléatoire de `from` quand `from == to` en rhythm/lick, ni le gap de transition ni les boucles : sans effet sur une tenue, à savoir pour les prochains tests qui liraient `currentFrom` en rythme.
- [déduit] Le chiffre 8 de R2 dépend du pas de `at()` (un tick par seconde entière) et de la durée du souffle (16 temps de 0,49 s). Il n'a pas été rejoué avec un ticker à 200 ms.
- [mesuré] R3 à R8 ne sont pas traités, R6 revient à Manu. `challenge_timeline_forecast_test` est passé dans la suite complète cette fois (`tss2-008`).
