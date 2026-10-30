---
type: analyse
sujet: relecture-adverse-de-l-interface-de-seance-v2
ecrit_le: 2026-10-18T11:37:25+02:00
auteur: session tss2-relecture-interface · claude-opus-5-5
revision: 7be617d
branche: feat/interface-seance-v2
porte_sur:
  - rhythm_coach/lib/career/screens/career_screen.dart
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/mode_badge_row.dart
  - rhythm_coach/lib/widgets/session_background.dart
  - rhythm_coach/test/session_interface_v2_test.dart
provenance:
  mesure: 7
  deduit: 8
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/screens/career_screen.dart:1109
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart:327
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:206
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:64
  - rhythm_coach/lib/screens/session_screen.dart:275
  - rhythm_coach/lib/screens/session_screen.dart:305
  - rhythm_coach/lib/screens/session_screen.dart:555
  - rhythm_coach/lib/screens/session_screen.dart:681
  - rhythm_coach/lib/screens/session_screen.dart:775
  - rhythm_coach/lib/widgets/session_background.dart:113
---

## Verdict

**Publiable avec réserves.** [mesuré] Les règles demandées sont en place et la base est saine : `flutter analyze` rend « No issues found! », `dart format --set-exit-if-changed .` rend 0, la suite complète passe (1466 tests verts) au commit `7be617d`. Mais deux promesses du prompt validé par Manu sont réfutées par mesure : « JE PEUX PAS » n'est pas tapable quand le panneau de réglages est ouvert, et le plein écran est perdu dès la deuxième séance d'un enchaînement (encore carrière, cycle non-stop du mode Custom). Quatre comportements livrés ne sont gardés par aucun test.

[déduit] Aucun de ces défauts ne casse une séance ni ne touche aux données : ils dégradent l'accessibilité du bouton de sécurité et l'essai visuel. Aucun ne justifie de retirer l'APK d'essai du téléphone ; tous sont à corriger avant fusion.

## Défauts, classés par gravité

### D1 — Panneau de réglages ouvert : « JE PEUX PAS » hors de portée (moyen)

[mesuré] Banc jetable (écran 390×850, fr) : après un tap sur l'icône réglages, la feuille du bas couvre la zone `y 382→860` et le bouton FAIL est en `y 757→810`. Le test de frappe au centre du bouton ne l'atteint pas (`hit=false`), et un `tap` sur le bouton laisse `isFailing=false`. Il faut d'abord fermer la feuille (un tap sur la barrière, qui ne déclenche rien d'autre), puis taper « JE PEUX PAS ».

[déduit] Cause : `_openSettings` (`session_screen.dart:681`) ouvre un `showModalBottomSheet` modal, avec barrière, ancré en bas — exactement sur la ligne de boutons. Le prompt exigeait « JE PEUX PAS » TRÈS accessible, et la piste 1 de cette relecture cite nommément ce cas. La feuille ne se referme pas non plus quand la séance change d'état (fin, défi). Pistes de correction, à arbitrer : feuille non modale, ou panneau ancré en haut sous l'icône, ou bouton FAIL rendu au-dessus de la feuille.

### D2 — Séance enchaînée : mode immersif perdu (moyen)

[mesuré] Banc jetable : une `SessionScreen` poussée, puis remplacée par une autre via `pushReplacement` (le chemin de `_handleEncore`, `career_screen.dart:1109`, et de `_handleCycle`, `custom_mode_screen.dart:327`). Appels de mode système relevés après le remplacement, dans l'ordre : `immersiveSticky` puis `edgeToEdge`. Le dernier ordre envoyé est `edgeToEdge` alors que la nouvelle séance est à l'écran.

[déduit] Le nouvel écran pose l'immersif dans son `initState` ; l'ancien n'est libéré qu'à la fin de l'animation de transition et son `dispose` (`session_screen.dart:275`) rétablit `edgeToEdge` après coup. La deuxième séance d'un encore carrière et chaque cycle non-stop du mode Custom tournent donc avec barre d'état et barre de navigation, jusqu'au prochain retour de l'appli au premier plan (seul `resumed` réapplique l'immersif). Le prompt demandait le plein écran « pendant la séance » et la piste 2 cite la séance enchaînée.

### D3 — Panneau ouvert à la fin d'un cycle non-stop : l'ancien écran reste dans la pile (faible, déclencheur étroit)

[mesuré] Banc jetable : feuille de réglages ouverte, puis `pushReplacement` d'une nouvelle séance → deux `SessionScreen` montées, plus aucune feuille. Après `pop` de la nouvelle séance : il reste une `SessionScreen` et l'écran d'accueil n'est pas revenu.

[déduit] `pushReplacement` remplace la route du dessus, ici la feuille, pas l'écran de séance. En mode Custom non-stop, l'enchaînement est automatique (`_maybeAutoChain`, `session_screen.dart:555`) : si la feuille est restée ouverte jusqu'à la fin de la séance, l'ancien écran (contrôleur fini, audio détaché) reste sous le nouveau, et en sortant on retombe sur son écran de fin au lieu de l'écran Custom. Même cause que D1 (feuille modale qui survit à la séance) ; la corriger règle les deux.

### D4 — Quatre comportements livrés sans test qui les garde (faible)

[mesuré] Mutations jouées sur la suite complète, chacune restée **verte (1466 tests)** — sauf M4, dont le seul rouge (`movement_reprise_pause_test.dart:215`, courbe en retard de 202 ms, suite ralentie à 3 min 29) ne se reproduit pas : vert seul sous la même mutation, vert trois fois seul sur code intact, et `session_interface_v2_test.dart` reste vert sous M4. Ce test instable sous charge est parti en fiche `tss2-039` ; il ne garde pas le dégradé.
- M1 : retrait de `_playedAtLastFail = playedElapsed;` dans `_triggerMusicalFail` (`session_controller_fail_flow.dart:206`) — un FAIL en séance musicale ne remet plus le compteur des 2 min à zéro ;
- M2 : retrait de `_enterImmersive();` au `resumed` (`session_screen.dart:305`) — l'immersif n'est plus repris au retour d'arrière-plan ;
- M3 : `bottomVeilOnly: true` au lieu de `showRunning` (`session_screen.dart:775`) — intro, décompte et fin perdent leur voile uniforme, ce qui viole « rien ne change ailleurs » ;
- M4 : dégradé et voile uniforme inversés (`session_background.dart:113`) — le test « fond » ne lit que le drapeau, jamais ce qui est dessiné ;
- M8 : pastille du mode rendue opaque (`mode_badge_row.dart:46`).

[déduit] Le test « fond : dégradé bas seul en séance, voile uniforme ailleurs » promet dans son titre la moitié « ailleurs » qu'il ne vérifie pas (M3), et ne vérifie pas le rendu (M4) : c'est un test vert à tort sur ces deux points. M8 relève du jugement visuel et peut rester sans test.

### D5 — Cible FAIL réduite quand « UTILISE-MOI » apparaît (faible, à juger)

[mesuré] Hauteur du bouton FAIL seul : 53 dp dans toutes les tailles et langues mesurées. Avec « UTILISE-MOI » : 45,9 dp en allemand à 390×850, 45,7 dp en français à 320×568, 49,6 dp en français à 390×850. Le test de l'auteur exige `48 ≤ h ≤ 64` mais seulement en français à 390 de large ; en allemand à la même largeur, son propre critère tomberait. Le bord gauche du bouton passe de x=16 à x=166 (390 de large) à l'apparition, sans animation de largeur.

[déduit] Le `FittedBox` réduit l'étiquette quand la largeur baisse, et la hauteur suit. La position (UTILISE-MOI à gauche, FAIL à droite) est celle de la maquette ; mais le bouton FAIL glisse vers la droite pendant le jeu et « UTILISE-MOI » — l'action inverse — prend sa place sous un pouce posé à gauche. À montrer à Manu.

## Ce qui tient

[mesuré] « JE PEUX PAS » reste dans l'écran, atteint au centre par le test de frappe, et plus large que « UTILISE-MOI », dans les quatre langues et cinq tailles mesurées (320×568, 360×640, 390×850, 800×1280, 1280×800), seul ou accompagné ; aucune exception de rendu relevée. Mutations attendues rouges : M5 (flèche → `Navigator.pop` au lieu de `maybePop`) tombe sur « aucun `AlertDialog` » ; M6 (`useMeUnlocked` remplacé par `true`) tombe sur « `session-useme-button` trouvé » ; M7 (flex de « UTILISE-MOI » de 2 à 4) tombe sur la largeur relative. Les trois tombent sur la bonne assertion. Les mutations de l'auteur (règle des 2 min dans `triggerFail`, `bottomVeilOnly: false`, immersif au `dispose`, opacité du FAIL) n'ont pas été rejouées.

[déduit] Lu dans le diff :
- `PopScope` (`canPop`, `onPopInvokedWithResult`, `_confirmExit`) est inchangé ; la flèche appelle `maybePop`, qui passe par lui comme le retour système.
- Activation du bouton FAIL (`canTriggerFail`) inchangée ; pendant un défi il reste remplacé par les boutons du défi, comme avant.
- Horloge de la règle : `playedElapsed` (chronomètre de séance + décalage) — pauses exclues, défis inclus, flow de FAIL exclu (`_stopwatch.stop()` en `session_controller_fail_flow.dart:64`, reprise ligne 184). Une mini-punition (punition surprise) arrête aussi le chronomètre mais ne remet pas le compteur à zéro, choix signalé par l'auteur. Le compteur est posé avant `onMilestoneRetry`, donc un FAIL en fenêtre de palier le remet aussi à zéro.
- Règles existantes de « UTILISE-MOI » conservées (déblocage `begLibre`, carrière, `onRequestUpgrade`, masqué en défi, mêmes conditions d'activation) ; nouveauté : un FAIL après usage masque l'étiquette « UTILISÉE » pendant 2 min.
- `ModeBadgeRow` et le voile sont utilisés seulement par l'écran de séance ; intro et fin gardent leur `AppBar` (le chronomètre restant n'y apparaissait déjà pas) ; volumes : mêmes rappels (`tts.setVolume`, `setAmbienceVolume`), donc mêmes valeurs persistées.
- i18n : une seule clé neuve, `sessionSettingsTooltip`, présente dans les quatre ARB et les fichiers générés ; l'infobulle de la flèche vient de `MaterialLocalizations`. Aucune chaîne en dur ajoutée.

[déduit] Écarts mineurs au prompt, à arbitrer : la pause est la même vue que la séance en cours et prend donc la nouvelle disposition (le prompt la voulait inchangée) ; un écran poussé depuis l'écran de fin (`SpecializationScreen`) hérite du plein écran, aucun `edgeToEdge` n'étant envoyé avant lui ; `debugAddPlayed` est du code de test dans le contrôleur de production (`@visibleForTesting`).

## Ce que je n'ai pas pu établir

- Rien sur l'appareil : ni rendu réel, ni lisibilité de la consigne, de la courbe et de la pastille sur fond clair, ni comportement de l'immersif Android (retour système avec une navigation à trois boutons, qui demande désormais un glissement avant le bouton) — aucune compilation ni installation, par consigne.
- D2 et D3 sont mesurés sur un banc qui reproduit la mécanique de navigation (`push` puis `pushReplacement`), pas en déroulant `_handleEncore` ou `_handleCycle` eux-mêmes.
- Le recouvrement possible des flèche/réglages en surimpression avec la pastille, le chronomètre restant ou les barres de debug en haut d'écran : non mesuré.
- L'état de l'arbre avant le changement (`e55c8fd`) n'a pas été mesuré : je n'ai pas comparé la position du bouton FAIL avant/après.
- La règle des 2 min n'est vérifiée qu'en avançant le temps à la main (`debugAddPlayed`) : jamais en laissant le chronomètre tourner à travers une pause, un défi ou une punition.
