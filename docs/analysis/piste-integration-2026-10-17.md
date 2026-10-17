# Intégration de la piste en forme de verge — 17/10/2026

Branche `feat/courbe-piste-integree`, partie de `fix/corrections-octobre` (`cb080c6`).
Piste fusionnée depuis `dc36047` (`feat/courbe-piste-penis`, 14/10) ; `2d52a16` non fusionné,
son nettoyage refait à la main.

## Résolution

| Endroit | Gardé du jour | Gardé de la piste |
|---|---|---|
| `release.yml` ×3, `web-deploy.yml` | `mkdir -p … assets/audio/music …` | `assets/courbe` ajouté à la même ligne, synchro R2 `courbe/v1/` |
| Ladder (lignes, libellés, curseur) | — | 6 places fixes (`_kLevelSlots`), boîtes `_kLevelBox` = 28 |
| Curseur langue (`_tongue()`) | comportement entier | alignement sur les 6 places + boîte de niveau (ajouté pendant la fusion) |
| Courbe de la langue | peintre dédié | paramètre `rowCount` retiré, mêmes ordonnées que la trajectoire |
| `_TrajectoryPainter._verticalInset` | — | `_kLevelBox / 2` (au lieu de 5 px) |
| Épingles de frontière, punition, rembobinage, reprise | inchangés (aucun conflit, tests verts) | — |

Usages restants de `rowCount` : nombre de lignes et de libellés affichés, `_tongue()` (pas de langue
sans la ligne balls), `_sameGeometry` et ses clés de test. Aucun ne dépend d'une géométrie à 5 rangées.

Tests du jour adaptés aux ordonnées des 6 places : `movement_animation_hold_moves_test.dart`
(gorge +0,5 → +0,2, cran 0,5 → 0,4, seuils exprimés en crans). La piste avait déjà fait de même pour
`step_serial` et `transition_widget`.

## Défaut trouvé dans la piste

Sans l'image, `_Shaft` jetait au build : sous `flutter_test`, `PlatformAssetBundle.load` lève de
façon synchrone quand le messager rend `null`, et `.then(onError:)` ne l'attrape pas. 29 tests du
widget tombaient — donc toute la CI, qui n'a pas l'image. Le 14/10 l'image était dans le worktree,
d'où le vert. Corrigé par `Future.sync` (`0220ea3`). Sur appareil l'erreur passe par le Future.

Piège local : `build/unit_test_assets` garde une image retirée de `assets/courbe/`. Pour jouer le
chemin « image absente », vider ce dossier.

## Tests et preuves rouges

| Test | Rouge obtenu par |
|---|---|
| `movement_ladder_alignement_niveaux_test` (piste, 11 cas) | version du jour sans la piste : 10 rouges sur 11 (mid à 5 rangées coïncide de lui-même) |
| idem, cas « pastilles sur les lignes » ×2 (neuf) | `_verticalInset = 5.0` → pastille du fond à 125 px contre ligne à 119,6 ; rouge aussi sur la version du jour |
| idem, cas « langue lick balls » (neuf) | boîte de niveau retirée autour de la langue → écart 3,6 px |
| `movement_piste_image_test` (neuf), image présente | `_assetTipY` 3 → 10 → gland à 8,7 px contre 14 |
| idem, image absente | `rootBundle.load` nu → exception ; repli remplacé par `SizedBox.shrink` → `_ShaftBackdrop` introuvable |

Suite complète : 1392 verts sans image (chemin CI) et 1392 verts avec image. `flutter analyze` :
No issues found. `dart format --set-exit-if-changed lib test` : 0.

## Non vérifié

Rien n'a été vu sur le téléphone. Le calage de l'image n'est mesuré qu'à 400 × 160 px.
