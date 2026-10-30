---
type: analyse
sujet: seance-musicale-avance-des-bips
ecrit_le: 2026-09-24T12:42:38+02:00
auteur: session tss2-avance-bips · claude-sonnet-5
revision: 6622758
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/services/beep_engine.dart
provenance:
  mesure: 1
  deduit: 3
  document: 4
  sans_marqueur: 1
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:943
  - rhythm_coach/lib/services/beep_engine.dart:575
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Le calage actuel en cinq lignes

1. [document] `MusicEngine` (`music_engine.dart`) relaie la position rapportée par le lecteur `audioplayers` dans une `MusicClock` qui l'extrapole entre deux rapports ; `position` est cette horloge.
2. [document] `SessionController.start` appelle `_beep.attachMusic(track, () => music.position)` : le `BeepEngine` passe en boucle « grille » (`_startGridLoop`).
3. [document] La grille vise `music.beatTime(index)` et déclenche le bip quand la position lue atteint ce temps ; les bips d'un step sont donc dérivés du morceau, pas du BPM.
4. [document] L'écran lit `ctrl.elapsed` (= `music.position` en séance musicale) pour la courbe et le minuteur ; l'orbe suit `beatStream`, émis avec le bip.
5. [déduit] Le bip est déclenché à la position *rapportée* du décodeur, puis traverse sa propre latence de sortie ; le morceau a la sienne, distincte. Leur écart est constant par appareil/sortie : cohérent avec « retard fixe, pas de dérive » — une avance le corrige. Rien ne contredit la tâche.

## Ce qui est décalé, ce qui ne l'est pas

- Décalé de N ms (plus tôt) : le déclenchement des bips ; `SessionController.elapsed` (courbe, minuteur, frontières de steps, fin de séance) = position du morceau + N. Le curseur et les steps suivent donc les bips.
- Non décalé : le morceau (lecture, position rapportée, `MusicClock`), les temps de la grille (`beatTime`).
- Effet de bord [déduit] : la séance se termine jusqu'à N ms plus tôt sur la piste (≤ 400 ms) ; les derniers bips peuvent être coupés.
- Hors séance musicale : avance forcée à 0, rien ne change.

## Réglage

`BeepEngine.musicBeepAdvance` (0 par défaut), relu à chaque bip. Contrôle − / + (pas 10 ms, plage 0–400 ms) dans l'écran de séance, sous les volumes, `kDebugMode` et séance musicale seulement. Mémorisé dans `DebugSettingsService` (`debug.music_beep_advance_ms`), relu au démarrage de la séance.

## Le test rouge

[mesuré] Avance neutralisée (`lead() => position()` et `elapsed` sans N), tests relancés :
- `avance de 120 ms : chaque bip part 120 ms avant…` → `Expected: 0:00:16.814000 / Actual: 0:00:16.934000` (bip n°0 à 16,934 au lieu de 16,814) ;
- `l'avance se règle en cours de séance` → `Expected: 0:00:00.200000 / Actual: 0:00:00.000000` ;
- `avance des bips : lue des préférences…` → `Expected: 0:00:42.120000 / Actual: 0:00:42.000000`.
Le test « avance = 0 » reste vert sous mutation (attendu : c'est un témoin de non-régression ; les 28 tests de grille préexistants restent verts sur code inchangé). Mutation vérifiée posée (`grep -c` = 1), fichiers restaurés. Suite complète : 1183 tests verts, `flutter analyze` propre, format propre.
Le faux lecteur des tests de grille est une position fonction du temps mural, comme le rapport du vrai plugin ; celui du contrôleur est le `_Port` existant.

## Ce que je n'ai pas pu établir (ce que les tests n'établissent pas)

- [déduit] Que N ms corrige réellement le retard entendu : aucune mesure audio ici, la valeur est à trouver à l'oreille.
- Que la latence est bien *fixe* sur l'appareil (constat de Manu, non re-mesuré).
- Le comportement en fin de piste avec une avance élevée (bips coupés) n'est pas testé.
- L'absence du contrôle en build release n'est pas testée (les tests tournent en debug) ; elle repose sur `kDebugMode`.
- Le réglage au pas de 10 ms sur un vrai plugin : la position rapportée est interpolée (`MusicClock`), sa gigue éventuelle n'est pas mesurée.
