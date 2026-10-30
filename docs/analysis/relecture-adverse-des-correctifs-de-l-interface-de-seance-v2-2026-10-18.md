---
type: analyse
sujet: relecture-adverse-des-correctifs-de-l-interface-de-seance-v2
ecrit_le: 2026-10-18T12:51:39+02:00
auteur: session tss2-relecture2-interface · claude-opus-5-5
revision: b86a0b4
branche: feat/interface-seance-v2
porte_sur:
  - rhythm_coach/lib/career/screens/career_screen.dart
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart
  - rhythm_coach/lib/main.dart
  - rhythm_coach/lib/screens/camera_test_screen.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/platform_capabilities.dart
  - rhythm_coach/test/session_interface_v2_test.dart
  - rhythm_coach/test/session_music_controller_test.dart
  - rhythm_coach/test/session_punishment_breath_screen_test.dart
provenance:
  mesure: 16
  deduit: 9
  document: 0
  sans_marqueur: 3
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/screens/career_screen.dart:1109
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart:327
  - rhythm_coach/lib/main.dart:53
  - rhythm_coach/lib/screens/camera_test_screen.dart:181
  - rhythm_coach/lib/screens/session_screen.dart:1062
  - rhythm_coach/lib/screens/session_screen.dart:1097
  - rhythm_coach/lib/screens/session_screen.dart:1106
  - rhythm_coach/lib/screens/session_screen.dart:181
  - rhythm_coach/lib/screens/session_screen.dart:224
  - rhythm_coach/lib/screens/session_screen.dart:248
  - rhythm_coach/lib/screens/session_screen.dart:279
  - rhythm_coach/lib/screens/session_screen.dart:692
  - rhythm_coach/lib/services/platform_capabilities.dart:26
  - rhythm_coach/test/session_punishment_breath_screen_test.dart:576
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 3 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Verdict

**Publiable avec réserves.** [mesuré] Les cinq défauts du 1er tour sont fermés et chaque correctif est gardé : `flutter analyze` rend « No issues found! », `dart format --set-exit-if-changed .` rend 0, la suite complète passe seule (1486 verts) à `b86a0b4`. Les mutations M1-M8 du 1er tour et une à trois par correctif tombent toutes, sur la bonne assertion, sauf une (MD5b). Trois réserves neuves, toutes faibles : la ligne réservée à « UTILISE-MOI » fait sortir « JE PEUX PAS » de l'écran sur les écrans bas (paysage web), le panneau de réglages masque une bonne part de la courbe sur petit téléphone, et l'absence de ligne réservée hors carrière n'est gardée que par accident.

[déduit] Aucune ne touche un téléphone Android ou iOS natif en portrait, qui est le cas d'usage de Manu ; aucune ne casse une séance.

## Pistes

### D1 — panneau non modal

[mesuré] Banc jetable, fr et de, six tailles (320×568, 360×640, 390×850, 700×1000, 1280×800, 568×320), « UTILISE-MOI » absent puis présent : panneau ouvert, « JE PEUX PAS » ne bouge pas, est atteint au centre par le test de frappe et un tap déclenche le FAIL dans toutes les tailles en portrait et 1280×800. Seule exception : 568×320, où le bouton est déjà hors écran panneau fermé (voir R1). Le panneau occupe `y 60→192` quelle que soit la taille ; il ne recouvre ni la flèche de retour (`6→54`) ni la pastille du mode (`16→38`).

[mesuré] Il recouvre la courbe, opaque (`AppTheme.surface`) : 101 des 160 dp de la courbe à 320×568, 75 dp à 360×640, 18 dp à 390×850, 30 dp à 1280×800, rien à 700×1000 → réserve R2.

[mesuré] Retour système (`handlePopRoute`) panneau ouvert : le dialogue de sortie s'ouvre, le panneau reste ouvert derrière ; « Continuer » rend la séance, panneau toujours ouvert. Avec la feuille modale, le retour fermait la feuille. Le panneau reste aussi ouvert pendant le FAIL ; en pause il est sous le voile de pause et ne reçoit plus de tap, comme l'icône (inchangé). Seule l'icône le referme.

[déduit] Volumes : les rappels sont les mêmes qu'avant (`setState` + `widget.tts.setVolume`, `ctrl.setAmbienceVolume`), le test de l'auteur vérifie les appels ; la persistance sur disque n'a pas été relue.

### D2 — propriétaire statique du mode immersif

[mesuré] Mutations : `if (true)` à la place du test de propriétaire (`session_screen.dart:279`) rougit « séance enchaînée » (`edgeToEdge` au lieu d'`immersiveSticky`) ; retrait de `_immersiveOwner = this;` (`:224`) rougit trois tests (plein écran, flèche de retour, séance enchaînée) sur `edgeToEdge` attendu.

[mesuré] Cas hors ordre, banc : séance A, écran quelconque par-dessus, séance B par-dessus, `pop` de B (B propriétaire : `edgeToEdge` envoyé), retour à A, arrière-plan puis reprise (A repose l'immersif sans redevenir propriétaire), sortie de A → **dernier ordre `immersiveSticky` sur l'écran d'accueil**. Avant le correctif, chaque `dispose` rétablissait `edgeToEdge`. [déduit] Seul chemin du code qui empile deux séances : l'action « caméra inactive » d'une séance (`session_screen.dart:248`) ouvre `CameraTestScreen`, qui lance sa propre séance (`camera_test_screen.dart:181`). Caméra expérimentale : à savoir, pas une réserve.

[déduit] Erreur au montage : si `initState` lève avant la ligne 224, l'immersif n'est pas posé et le propriétaire précédent reste ; son propre `dispose` le remettra à `null`. Fuite entre tests : le propriétaire est écrasé à chaque montage et remis à `null` au `dispose` du propriétaire, et `flutter_test` démonte l'arbre à la fin de chaque test ; la suite complète passe. Web et desktop : mêmes appels `SystemChrome` qu'avant, aucun chemin neuf ; non mesuré.

### D3 — plus d'écran laissé dans la pile

[mesuré] Mutation MD3 (le bouton réglages ouvre aussi une feuille modale) : « enchaînement automatique avec les réglages ouverts » rougit sur « 2 `SessionScreen` trouvées ». Le cas de la feuille est fermé.

[mesuré] Reliquat, banc : dialogue de sortie ouvert quand une séance Custom non-stop se termine → l'enchaînement automatique remplace le **dialogue** ; après `pop` de la nouvelle séance, l'ancienne est toujours là et l'accueil n'est pas revenu. [déduit] Préexistant (`_confirmExit`, `_maybeAutoChain`, `pushReplacement` non modifiés par ces commits) : parti en fiche `tss2-041`, hors de cette relecture.

### D5 — « JE PEUX PAS » immobile, ligne réservée

[mesuré] Quatre langues × six tailles : avant et après l'apparition d'« UTILISE-MOI », le rectangle de « JE PEUX PAS », celui de la consigne et celui de la courbe sont identiques au pixel près. « JE PEUX PAS » mesure 53 dp de haut partout (52,1 dp en allemand à 320×568) ; « UTILISE-MOI » est dans l'écran, ne chevauche pas la consigne, aligné à droite sur le bord du FAIL.

[mesuré] Ligne réservée (écart consigne → FAIL) : 68 dp en carrière avec `begLibre`, 12 dp en carrière sans `begLibre` et en Custom (`isCareer: false`), à 320×568 et 390×850. [déduit] Elle n'apparaît que si `onRequestUpgrade` est fourni : seuls les deux lancements de `career_screen.dart` (lignes 549 et 1142) le font ; le routeur de surprise (`isCareer: true` sans `onRequestUpgrade`) et les séances musicales n'en ont pas.

[mesuré] Écrans bas, comparés à `580dead` dans un worktree jetable (position de « JE PEUX PAS », hauteur d'écran) :

| Taille | Carrière `580dead` | Carrière `b86a0b4` | Custom `b86a0b4` |
|---|---|---|---|
| 844×390 | 297→350 | 326→379 | 297→350 |
| 667×375 | 282→335 | **326→379** (rogné de 4 dp) | 282→335 |
| 568×320 | 270→323, tap OK | **326→379, tap hors écran** | 270→323, tap OK |

→ réserve R1.

## Réserves, par gravité

### R1 — Écran bas : la ligne réservée pousse « JE PEUX PAS » hors de l'écran (faible)

[mesuré] Tableau ci-dessus : à 375 dp de haut le bouton est rogné, à 320 dp son centre sort de l'écran et le tap ne l'atteint pas sans défiler ; au commit d'avant il était entier à 375 et tapable à 320. Le banc a une zone sûre nulle : une barre d'accueil iOS (environ 21 dp) aggraverait d'autant.

[déduit] Les téléphones natifs sont verrouillés en portrait (`main.dart:53`, `platform_capabilities.dart:26`) ; le web ne l'est pas, donc la PWA iPhone tenue en paysage et une petite fenêtre desktop sont concernées. Le contenu ne peut plus se tasser : le bouton reste à `y=326` quelle que soit la hauteur, la page défile.

### R2 — Panneau de réglages : la courbe masquée sur petit téléphone (faible, à juger)

[mesuré] Voir D1 : jusqu'à 63 % de la courbe sous le panneau opaque à 320×568, et le panneau reste ouvert jusqu'au prochain tap sur l'icône, à travers FAIL et défis. [déduit] Ni « JE PEUX PAS » ni la flèche ne sont gênés ; c'est la lisibilité de la courbe pendant qu'on règle le son. À juger par Manu au téléphone.

### R3 — « Pas de ligne réservée ailleurs » gardé par accident (faible, test)

[mesuré] Mutation MD5b, `useMeAvailable = true || …` (ligne réservée partout, Custom compris) : `session_interface_v2_test.dart` reste **vert (26)**. La suite complète rougit deux tests de `session_punishment_breath_screen_test.dart` (« le curseur affiché remonte pendant la respiration… »), qui repassent sur code intact. [déduit] Mauvaise raison : leur sonde `_cursorY` (`session_punishment_breath_screen_test.dart:576`) lit le dernier `Align` d'alignement horizontal non nul ; elle tombe sur l'`Align(topRight)` de la ligne réservée et rend `y=-1`. Aucun test n'affirme que la ligne est absente en Custom ou sans `begLibre`, et cette sonde serait aveugle sur un écran carrière avec `begLibre`.

## Mutations

[mesuré] Restaurées par copie après chacune, arbre propre contrôlé. Lancées sur `session_interface_v2_test.dart` (plus `session_music_controller_test.dart` pour M1) ; MD5b aussi sur la suite complète.

| Id | Cassure | Résultat |
|---|---|---|
| M1 | retrait de `_playedAtLastFail = playedElapsed;` dans `_triggerMusicalFail` | rouge, test musical « remet à zéro le compteur », attendu `false` |
| M2 | retrait de `_enterImmersive()` au `resumed` | rouge, « retour d'arrière-plan », obtenu `[]` |
| M3 | `bottomVeilOnly: true` | rouge, voile à l'intro et à la fin |
| M4 | voile et dégradé inversés | rouge, couleur 0,45 obtenue |
| M4b | dégradé retourné | rouge, `bottomCenter` obtenu |
| M5 | flèche → `pop` | rouge, aucun `AlertDialog` |
| M6 | `useMeUnlocked` → `true` | rouge, 13 tests, « UTILISE-MOI » trouvé |
| M7 | « UTILISE-MOI » pleine largeur | rouge, largeur 358 non inférieure |
| M8 | pastille opaque | rouge, 1,0 obtenu |
| MD1 | panneau ancré en bas | rouge, FAIL non déclenché panneau ouvert |
| MD2 | `dispose` rétablit toujours `edgeToEdge` | rouge, séance enchaînée |
| MD2b | propriétaire jamais posé | rouge, 3 tests sur `edgeToEdge` |
| MD3 | feuille modale réintroduite | rouge, 2 `SessionScreen`, et FAIL non déclenché |
| MD5 | ligne de hauteur 0 tant qu'« UTILISE-MOI » est masqué | rouge, 12 tests, la consigne bouge |
| MD5b | ligne réservée partout | **vert** sur le fichier ; rouge ailleurs pour la mauvaise raison (R3) |
| MD5c | « UTILISE-MOI » aligné à gauche | rouge, 13 tests, bord droit |

[mesuré] Suite complète : 1486 verts seule ; lancée en même temps qu'un banc, un rouge dans `challenge_timeline_forecast_test.dart` (vert trois fois seul), déjà en fiche `tss2-008`.

## Ce que je n'ai pas pu établir

- Rien sur l'appareil : lisibilité du panneau, du bouton compact, de la courbe à moitié masquée ; immersif et retour système Android en navigation à trois boutons.
- `_handleEncore` et `_handleCycle` ne sont pas déroulés : le banc reproduit leur `pushReplacement` avec le vrai `_maybeAutoChain`, comme celui de l'auteur.
- R1 mesuré avec une zone sûre nulle ; pas sur Safari iOS réel ni sur une fenêtre desktop.
- Erreur au montage, web et desktop pour D2 : lus, non mesurés.
- Persistance des volumes sur disque : non relue, seuls les rappels le sont.
- Le reliquat `tss2-041` n'est pas mesuré sur `develop`, ni avec le dialogue de nom de `_handleSave`.
