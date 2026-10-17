---
type: analyse
sujet: seance-musicale-avance-publiee
ecrit_le: 2026-09-24T15:15:36+02:00
auteur: session tss2-avance-publiee · claude-sonnet-5
revision: a1d1703
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/lib/career/services/debug_settings_service.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/profile_screen.dart
  - rhythm_coach/lib/widgets/music_beep_advance_section.dart
provenance:
  mesure: 7
  deduit: 10
  document: 4
  sans_marqueur: 1
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/debug_settings_service.dart:199
  - rhythm_coach/lib/controllers/session_controller.dart:956
  - rhythm_coach/lib/widgets/music_beep_advance_section.dart:18
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Ce qui est livré

[document] Décision de Manu (24/09) : 150 ms d'avance par défaut en séance musicale, release comprise, et un réglage dans les options ; le palier des 40 premières secondes reste de côté.

[document] Défaut : `DebugSettingsService.defaultMusicBeepAdvanceMs = 150`, lu par `getMusicBeepAdvanceMs()` quand rien n'est mémorisé ; le champ du contrôleur démarre à la même constante. Une valeur mémorisée, 0 compris, reste respectée. Le chemin (lecture au `start`, contrôleur, grille) ne référence pas `kDebugMode` ; seul le contrôle − / + de l'écran de séance en dépend, inchangé.

## Où est le réglage

[document] **Écran Profil**, nouvelle section « Bips sur la musique » (`profile_screen.dart`, widget `MusicBeepAdvanceSection`), entre la voix et l'affichage de séance. Choix : l'écran SONS (`sound_demo_screen.dart`) ne porte que des démos et le debug, aucun réglage de bip ni de volume ; le Profil porte déjà les réglages joueuse (langue, voix, débit et hauteur, déroulé de séance). Volumes de séance : dans l'écran de séance, pas dans des options.

[document] Contrôle − / + au pas de 10 ms, plage 0–400 ms, comme le réglage debug ; même clé de préférence `debug.music_beep_advance_ms`, donc le contrôle en séance et le Profil se lisent l'un l'autre. Aide : « Séances avec musique. Si les bips arrivent après la musique, augmente l'avance. » (fr/en/de/es).

## Tests, vus rouges

[mesuré] Sans valeur mémorisée, 150 ms (`session_music_controller_test.dart`). Rouge avant le correctif, sur code pristine : `Expected: Duration:<0:00:00.150000>  Actual: Duration:<0:00:00.000000>`. Pour « hors `kDebugMode` » : `flutter test` tourne en debug, la constante ne se bascule pas ; le test lit les sources et exige qu'aucun `kDebugMode` ne tombe à ±4 lignes d'une ligne d'avance (contrôleur, `BeepEngine`, service), avec un garde-fou anti-vide.

[mesuré] Défaut ramené à 0 dans le service (mutation vérifiée posée, `grep` = 1), test du réglage : `Expected: '150 ms'  Actual: '0 ms'` puis `Expected: '160 ms'  Actual: '10 ms'`. Écriture de la valeur retirée du widget : `Expected: <160>  Actual: <null>`.

[mesuré] Défaut mis à 160 : `Expected: <150>  Actual: <160>` sur le test de fin de séance à 150 ms, en plus de celui du défaut.

[mesuré] Séance non musicale : garde `if (_music == null) return;` du setter retirée : `Expected: Duration:<0:00:00.000000>  Actual: Duration:<0:00:00.300000>`. Fichier restauré, retest vert.

[mesuré] Le réglage des options écrit la valeur (160, plafond 400, plancher 0) et `getMusicBeepAdvanceMs()` la relit ; la séance la reprend (test existant à 120 ms, sur la même clé). Test de mise en page : 320 px de large, police ×2, fr/en/de/es, sur le texte définitif, sans débordement.

[mesuré] `flutter analyze` : « No issues found! » ; `dart format --set-exit-if-changed .` : 0 fichier changé ; suite complète 1195/1195. Deux tests existants ont dû bouger, non parce qu'un défaut est apparu mais parce qu'ils supposaient le défaut à 0 : le câblage écran (« 0 ms » → « 150 ms », « 10 ms » → « 160 ms ») et le test « stop pendant la queue » (position 99,8 → 99,6 s : à 99,8 + 150 ms + 100 ms murales, la séance était déjà finie avant le `stop`).

## Fin de séance à 150 ms et au maximum

[mesuré] Morceau 99,848 s pour 100 s de séance (même queue de 152 ms que 178,848 s pour 179 s), faux lecteur. À 150 ms, position 99,848 s : séance `running` ; l'événement de fin du morceau arrive, l'horloge court seule, la séance se termine 10 ms murales plus tard, morceau libéré, bips détachés, pas de finale_chime. À 400 ms, position 99,6 s : séance `finished`, sans événement de fin, morceau arrêté par `_finish`.

[déduit] À 150 ms la séance se termine 2 ms de position après la fin du morceau (152 − 150). À 400 ms, elle coupe 248 ms de queue, un fondu à −46 dB d'après la relecture précédente : sans conséquence audible.

## Ce que ça change pour « Fin » et « Souffle »

[déduit] Avant : 0 ms, séance = morceau + 152 ms d'horloge seule, les deux essais jugeaient bien. Avec 150 ms par défaut la fenêtre de 152 ms se réduit à 2 ms : le seuil de 152 n'est pas franchi, donc la séance ne finit pas avant l'événement de fin dans le cas idéal, et « Fin » peut encore juger le câblage (`tss2-014`).

[déduit] Marge réelle de 2 ms : l'horloge extrapole entre deux rapports du lecteur (au plus 200 ms) et le tick est de 200 ms. Si l'événement de fin arrive plus de 2 ms après la fin réelle, un tick peut terminer la séance avant lui, et « Fin » répondrait « oui » à tort. Non mesuré sur l'appareil. Pour qu'« Fin » juge sans ambiguïté, jouer l'essai à une avance nettement sous 150 (par exemple 100), visible et réglable dans le Profil ou en séance debug.

[déduit] « Souffle » : un souffle qui déborde 179 s se termine sur l'horloge décalée, donc à position 178,85 s, soit 2 ms après la fin du morceau à 150 ms ; à 0 ms c'était 152 ms après. Même marge, même réserve. Au-dessus de 152 ms (réglage joueuse), les deux essais perdent leur discrimination, comme relevé.

## Ce que je n'ai pas pu établir (ce que les tests n'établissent pas)

- [déduit] Que 150 ms corresponde au retard entendu sur un autre téléphone : mesure de Manu sur son S21 seulement.
- [déduit] « Hors `kDebugMode` » est établi par lecture des sources, pas par une exécution en release ; aucune compilation release ici.
- [déduit] Le Profil n'est pas monté entier dans un test : la section l'est seule (écriture, mise en page) ; son placement dans `ProfileScreen` n'est gardé par aucun test.
- [déduit] Le lien « écriture des options → séance suivante » est prouvé par la clé commune et deux tests (écriture / lecture au `start`), pas par un seul parcours de bout en bout.
- [déduit] La marge de 2 ms en fin de séance, et la gigue de l'horloge à cet endroit, ne sont pas mesurées sur l'appareil.
- [déduit] Un joueur qui a mémorisé 0 en debug avant cette version garde 0 : la valeur mémorisée prime.
