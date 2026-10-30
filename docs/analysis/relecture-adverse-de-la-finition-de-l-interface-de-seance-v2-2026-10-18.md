---
type: analyse
sujet: relecture-adverse-de-la-finition-de-l-interface-de-seance-v2
ecrit_le: 2026-10-18T13:52:51+02:00
auteur: session tss2-relecture-interface3 · claude-opus-5-5
revision: 277c09d
branche: feat/interface-seance-v2
porte_sur:
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_interface_v2_test.dart
provenance:
  mesure: 7
  deduit: 5
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/screens/session_screen.dart:1126
  - rhythm_coach/lib/screens/session_screen.dart:410
  - rhythm_coach/test/session_interface_v2_test.dart:250
---

# Relecture adverse de la finition de l'écran de séance v2 (R1, R3)

Périmètre : `66f16b9..f97e4c3`. Verdict : **publiable avec réserves** — une régression de comportement sur fenêtre étroite et basse, hors des tailles testées.

## D1 — Fenêtre étroite et basse : « JE PEUX PAS » réduit de moitié, sous la cible tactile, et il bouge quand « UTILISE-MOI » apparaît (moyenne)

[mesuré] Banc jetable (carrière, `begLibre`, `onRequestUpgrade`), rect de « JE PEUX PAS » avant puis après `debugAddPlayed(useMeUnlockAfter)`, même sonde au commit `66f16b9` et à `f97e4c3` :

| Taille, langue [mesuré] | Avant (`66f16b9`) | Après (`f97e4c3`) |
|---|---|---|
| 384×400 fr | 352×53, immobile | 176×46,7, bouge de 0,6 dp |
| 384×400 de | 352×53, immobile | 176×43,5, bouge de 2,2 dp |
| 412×420 de | 380×53, immobile | 204×45,6, bouge de 1,2 dp |
| 360×430 fr | 328×53, immobile | 152×44,4, bouge de 1,8 dp |
| 360×430 de | 328×53, immobile | 152×41,7, bouge de 3,1 dp |

[mesuré] Au commit d'avant, ces fenêtres tenaient le bouton entier en pleine largeur (bas à 379–390 dp) : le défaut R1 ne les touchait pas. Le texte du bouton tombe de 23 dp à 11,7 dp en allemand à 360 de large.

[déduit] Cause : sous `_compactHeight` (`session_screen.dart:410`), la ligne `Row` de `_buildActionRow` (`session_screen.dart:1126`) donne à « JE PEUX PAS » la largeur restante après les 168 dp réservés ; le `FittedBox` réduit le libellé, donc la hauteur du bouton, sous les 48 dp de `minHeight` d'« UTILISE-MOI ». La `Row` prend la hauteur du plus haut enfant et centre l'autre : quand « UTILISE-MOI » apparaît, la ligne grandit et « JE PEUX PAS » se recentre. Contraire à la décision de Manu du 18/10 (place et taille identiques) et cible tactile sous 48 dp.

[déduit] Qui est concerné : le seuil se lit sur la hauteur seule, toute largeur. Une petite fenêtre desktop ou web, et l'écran partagé Android (le manifeste ne pose pas `resizeableActivity="false"`, le verrou portrait n'empêche pas le multi-fenêtre). Les paysages de téléphone (568 dp de large et plus) ne sont pas touchés : le bouton y garde 23 dp de texte et ne bouge pas.

[déduit] Le test R1 (`session_interface_v2_test.dart:250`) ne couvre que des largeurs de 568 dp et plus en écran bas ; il reste vert.

## Points vérifiés sans défaut

[mesuré] Seuil de part et d'autre (hauteurs 380 à 500 dp, largeurs 568 et 844 dp, zone sûre nulle ou iPhone paysage gauche/droite 47 dp et bas 21 dp) : bouton entier dans la zone sûre, immobile, sans chevauchement. La zone sûre est retirée avant le `LayoutBuilder` (`SafeArea`), le seuil s'applique donc à la hauteur utile.

[mesuré] Place de 168 dp en paysage 568×320 et 844×390 : fr, de, es, en, aucun chevauchement, « JE PEUX PAS » immobile.

[mesuré] Test R3 : MD5b (`true || widget.isCareer`) rouge sur 390×850 (écart 0 au lieu de 56) et 568×320 (largeur 360, pas plus de 460) ; `if (compact)` sans `useMeAvailable` rouge sur 568×320. Il discrimine.

[mesuré] Les trois marges resserrées ensemble remises à leur valeur d'avant : R1 rouge à 568×320 (bas 323 au lieu de 320 au plus). La marge verticale seule remise : tout reste vert (garde collective seulement).

## Réserve faible

[déduit] Portrait non strictement inchangé : avec la barre de stamina affichée (réglage de débogage), les marges passent de 8 à 6 dp et de 10 à 6 dp (`showBar || compact`). Hors usage normal.

## Ce que je n'ai pas pu établir

[déduit] Rien sur appareil ni navigateur réel : police de test et non Roboto, donc l'échelle exacte du libellé diffère ; l'écran partagé Android sur le S21 n'a pas été essayé.
