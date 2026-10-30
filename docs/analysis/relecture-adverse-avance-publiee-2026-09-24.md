---
type: analyse
sujet: relecture-adverse-avance-publiee
ecrit_le: 2026-09-24T15:27:42+02:00
auteur: session tss2-relecture-publiee · claude-opus-5-5
revision: de5ddeb
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/lib/career/services/debug_settings_service.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/profile_screen.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/music_clock.dart
  - rhythm_coach/lib/services/music_engine.dart
  - rhythm_coach/lib/widgets/music_beep_advance_section.dart
  - rhythm_coach/test/session_music_controller_test.dart
  - rhythm_coach/test/session_music_screen_wiring_test.dart
provenance:
  mesure: 16
  deduit: 15
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1177
  - rhythm_coach/lib/controllers/session_controller.dart:1460
  - rhythm_coach/lib/controllers/session_controller.dart:945
  - rhythm_coach/lib/screens/profile_screen.dart:222
  - rhythm_coach/lib/screens/session_screen.dart:1255
  - rhythm_coach/lib/services/music_clock.dart:58
  - rhythm_coach/lib/services/music_engine.dart:110
---

## Verdict : publiable avec réserves

[mesuré] Relu : `git diff 33d3f21..de5ddeb` (code `a1d1703`, rapport `de5ddeb`). Je n'ai rien corrigé. `flutter analyze` : « No issues found! » ; `dart format --set-exit-if-changed .` : 0 fichier changé ; suite complète 1195/1195 verte.

[déduit] L'avance de 150 ms s'applique bien hors debug, une valeur mémorisée est respectée, les séances ordinaires ne bougent pas, et la fin de séance reste propre pour la joueuse quel que soit l'ordre des événements. Aucune réserve bloquante.

| Réserve [déduit] | Poids |
|---|---|
| R1 — à 150 ms, « Fin » et « Souffle » ne jugent plus `tss2-014` ; jouer ces essais à 0 ms, pas à 100 | gênante (protocole d'essai, pas la joueuse) |
| R2 — la garde « hors debug » ne voit que `kDebugMode` : un `kReleaseMode` passe | non gênante |
| R3 — la section du Profil peut disparaître sans qu'un test tombe | non gênante |
| R4 — le réglage s'affiche même quand le morceau n'est pas livré | non gênante |
| R5 — une clé `debug.*` et des libellés `sessionDebug*` portent désormais un réglage joueuse | non gênante |

## 1. Release

[mesuré] Le chemin de l'avance, soit six fichiers (`session_controller.dart`, `beep_engine.dart`, `music_engine.dart`, `music_clock.dart`, `debug_settings_service.dart`, `music_beep_advance_section.dart`), ne contient aucun `assert`, `kReleaseMode`, `kProfileMode` ni `bool.fromEnvironment`. Les `kDebugMode` restants ne gardent que des `debugPrint`, le défaut d'un autre réglage (`showTrajectoryDots`), ou le contrôle − / + de l'écran de séance (`session_screen.dart:1255`). La section du Profil est montée sans condition (`profile_screen.dart:222`). La lecture au `start` (`session_controller.dart:1177`) n'est pas conditionnée.

[mesuré] Mutation à moi, M5 : `if (!kReleaseMode)` devant la lecture de la préférence au `start`. Résultat : 35/35 verts sur les trois fichiers de test concernés. Le test qui lit les sources ne cherche que `kDebugMode`. En release, M5 garderait le défaut 150 (valeur initiale du champ) mais ignorerait sans bruit le réglage du Profil. **R2, non gênante** : le code d'aujourd'hui est propre, mais la garde est plus étroite que son nom.

[déduit] Non établi : rien n'a été exécuté en release. La preuve reste une lecture du code, élargie aux quatre formes de conditionnement ci-dessus.

## 2. Défaut et valeur mémorisée

[mesuré] Mutations annoncées, rejouées et vérifiées posées (motif unique, diff d'une ligne), rouges sur la bonne assertion :
- M1, `?? defaultMusicBeepAdvanceMs` → `?? 0` : `Expected: '150 ms' Actual: '0 ms'`, `Expected: <150> Actual: <0>`, `Duration:<0:00:00.150000>` / `<0:00:00.000000>` (5 rouges).
- M2, écriture retirée du widget : `Actual: <null>`.
- M3, défaut à 160 : `Expected: <150> Actual: <160>` (5 rouges).
- M4, garde `if (_music == null) return;` du setter retirée : `Expected: Duration:<0:00:00.000000> Actual: Duration:<0:00:00.300000>`.

[mesuré] Mutation à moi, M7 : `_beep.musicBeepAdvance = …` retiré du `start`. Deux rouges : 120 ms attendus, 0 obtenu, puis 150 ms attendus, 0 obtenu. La transmission aux bips est bien gardée.

[mesuré] La clé `debug.music_beep_advance_ms` n'a que deux écrivains : `SessionController.setMusicBeepAdvanceMs`, appelé seulement par le contrôle de séance sous `kDebugMode`, et la section du Profil. L'export/import de diagnostic ne la porte pas. Aucun code ne purge les clés `debug.*`. `android:allowBackup="false"`. Le commit qui a introduit la clé (`6622758`) n'est contenu dans aucun tag ni aucune branche distante.

[déduit] Un 0 hérité du réglage debug est donc inatteignable chez une joueuse de l'app publiée. Il ne peut exister que sur un appareil de développement qui a porté un build debug, comme le S21 de Manu. Un APK release, signé autrement, ne s'installe pas par-dessus sans désinstaller. Conséquence pratique : le S21 peut avoir gardé la dernière valeur réglée en debug plutôt que le défaut. Le Profil affiche cette valeur, il faut la lire avant les essais.

## 3. Séances non musicales

[mesuré] Le seul changement du contrôleur est la valeur initiale du champ. Or ce champ n'est lu que si `_music != null` : `elapsed`, le getter et le setter court-circuitent avant. M4 rougit le test de la séance ordinaire sur la bonne assertion.

[déduit] Le test compare un `_Beep` neuf à `Duration.zero`, une assertion faible en soi. C'est l'assertion sur `elapsed` (< 150 ms) et celle du setter qui portent la preuve. Dans l'app, `musicBeepAdvance` n'est lu que par la boucle de grille, qui exige un morceau attaché. Une valeur restée sur un moteur partagé n'a donc aucun effet sur une séance ordinaire.

## 4. Fin de séance

[mesuré] Le calcul se confirme. La séance finit quand `(position + avance).inSeconds ≥ 179`, soit position ≥ 178,850 s à 150 ms. Le morceau fait 7452 trames × 1152 / 48 kHz = 178,848 s (`ffprobe -count_frames`, décodage complet 8 584 704 échantillons). La marge théorique est bien de 2 ms.

[mesuré] Ce 178,848 s compte toutes les trames, remplissage de l'encodeur compris : le fichier n'a pas d'en-tête Xing/Info. La durée que rend le décodeur du téléphone n'est pas mesurée.

[déduit] Une marge de 2 ms est plus petite que chacune des incertitudes réelles : délai du décodeur, latence du canal de plateforme, rapports de position espacés, tick de 200 ms. L'ordre entre « tick qui termine » et « événement de fin » est donc indéterminé sur l'appareil, pas « l'événement d'abord ».

[mesuré] Sonde jetable (retirée), séance de 100 s, dernier rapport à 99,7 s, ticks tous les 5 ms :

| Retard de l'événement de fin [mesuré] | Séance finie avant l'événement | État final |
|---|---|---|
| 0 ms | non | finished |
| 1 ms | non | finished |
| 7 ms | oui, à +150 ms murales, lecteur arrêté (2 `stop`) | finished |
| 50 ms | oui, idem | finished |

[déduit] Conséquence pour la joueuse : aucune, dans aucun ordre.
- L'événement de fin ne termine jamais la séance : il ré-ancre l'horloge (`MusicClock.end`), qui continue de courir. La séance se termine toujours sur un tick de l'horloge.
- Si le tick passe avant l'événement, le morceau est déjà fini, ou il perd quelques ms d'un fondu mesuré à −46 dB par la relecture précédente.
- L'avance n'ouvre aucun chemin « pas de fin du tout ». Elle réduit même l'exposition au rapport de position à 0 de fin de lecture : la séance peut finir avant qu'il arrive.

[déduit] **R1, gênante pour le protocole d'essai.** Si le câblage de fin (`tss2-014`) était cassé, la séance finirait quand même dès qu'un tick tombe entre fin + 2 ms et le rapport à 0 du plugin. « Fin » répondrait alors « oui » à tort, et « Souffle » de même, puisqu'il finit sur la même horloge. Le rapport relu propose de jouer ces essais « par exemple à 100 ms ». Cela laisse 52 ms, sans preuve que le rapport à 0 arrive plus tôt. Il faut les jouer à **0 ms**, réglables dans le Profil : c'est le régime de 152 ms que la relecture précédente a jugé discriminant. Ensuite, revenir à la valeur voulue.

[déduit] Non établi : le retard réel de l'événement de fin et du rapport à 0 sur le S21, et la durée rendue par son décodeur.

## 5. Écran d'options

[document] La section se trouve entre « Voix » et « Affichage de session », parmi les réglages joueuse. C'est un placement cohérent.

[mesuré] Le texte définitif tient dans 320 px de large avec une police doublée, en fr/en/de/es, sans exception de mise en page (test de la section). Les infobulles réutilisent les clés `sessionDebug*`, dont les textes ne contiennent pas « DEBUG ».

[déduit] Côté lisibilité, « 150 ms » reste un peu technique mais l'aide dit dans quel sens régler. « Si les bips arrivent après la musique » serait plus net avec « après le temps », sans que ce soit gênant.

[mesuré] **R3, non gênante.** Mutation à moi, M6 : les quatre lignes de la section retirées de `profile_screen.dart`, suite complète 1195/1195 verte. Le placement n'est gardé par rien. Un refactor du Profil pourrait faire disparaître le seul réglage joueuse sans bruit : ce n'est gênant que le jour où le Profil bouge.

[mesuré] **R4, non gênante.** `SessionLoader` masque la séance musicale quand le morceau n'est pas embarqué. Or les workflows de release et web construisent sans musique si les secrets R2 manquent. La section du Profil, elle, s'affiche sans condition : ce serait un réglage orphelin dans ce cas.

[déduit] **R5, non gênante.** La préférence joueuse vit sous `debug.music_beep_advance_ms` et ses infobulles sous `sessionDebug*`. Aucun code ne purge les clés `debug.*` aujourd'hui, mais une future purge des réglages debug effacerait un réglage joueuse.

## 6. Tests adaptés

[mesuré] « stop pendant la queue » : la position passe de 99,8 à 99,6 s. Mutation témoin M8, `await _releaseMusic();` retiré de `stop()` : le test rougit sur `Expected: a value greater than <1> Actual: <1>`. Il garde donc toujours la libération du morceau. Le scénario modélise désormais une queue de 400 ms, alors que le téléphone n'en a plus que 2 ms au défaut. Le comportement gardé (arrêt, jamais `finished`, morceau libéré) est le même. Rien n'est masqué.

[mesuré] Câblage écran : « 0 ms » devient « 150 ms », « 10 ms » devient « 160 ms ». Le test repart de préférences vides et garde toujours l'affichage de la valeur du contrôleur et l'incrément d'un pas. M1 et M3 le rougissent (`Found 0 widgets with text "150 ms"`).

## Ce que je n'ai pas pu établir

- [déduit] L'exécution en release : aucune compilation, preuve par lecture élargie à `assert`, `kReleaseMode`, `kProfileMode` et `fromEnvironment`.
- [déduit] Sur le S21 : l'ordre réel entre fin audible, rapport à 0 et événement de fin, la durée rendue par le décodeur et la valeur actuellement mémorisée.
- [déduit] Que 150 ms convienne à d'autres téléphones.
- [déduit] Le parcours complet « Profil → séance suivante » dans un seul test : la preuve repose sur la clé commune et deux tests.
