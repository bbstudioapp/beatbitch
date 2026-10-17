# Relecture adverse — piste en forme de verge intégrée (`feat/courbe-piste-integree` @ `9bd4d6e`, 2026-10-17)

Relecteur : Fable 5.1. Relu : `dc36047` (piste du 14/10, jamais relue) tel qu'intégré par la fusion
`6103085` au-dessus de `fix/corrections-octobre` @ `cb080c6`, puis `0220ea3`, `145b5b0`, `f1043e7`.
Compte rendu de l'intégrateur (`piste-integration-2026-10-17.md`) vérifié point par point.
Consigne : réfuter, pas valider. Rien n'a été vu sur le téléphone.

## Verdict : publiable avec réserves

Aucun défaut bloquant. Le calage, les 6 places, le repli sans image et le chemin de la CI tiennent
sous mutation et à toutes les tailles essayées. Reste un flash d'une image au montage (à voir sur le
téléphone) et trois trous dans les tests.

## Ce que la joueuse vit

Sous le curseur, l'image d'une verge (opacité 0,85) : bout du gland sur la ligne Bout, jonction
tige/bourses sur la ligne Tout, bourses sous la dernière ligne. La place du niveau balls est
toujours réservée : à 5 lignes affichées, les niveaux sont aux mêmes ordonnées qu'à 6, et un cran
vaut 20 % de moins qu'avant la piste. Sans l'image (build local, CI), la silhouette dessinée d'avant.

## Ce qui a été vérifié

| Vérification | Résultat |
|---|---|
| Fusion : lignes `+` de `c57bdcd..dc36047` toutes présentes dans `cb080c6..6103085` (diff des deux diffs) | aucun hunk de la piste perdu |
| Workflows ×4 : `assets/courbe` dans le `mkdir`, synchro `courbe/v1/` ; `.gitkeep` suivi ; `pubspec` ; `.gitignore` | cohérents ; R2 `courbe/v1/` contient les 3 variantes (16 436 / 53 589 / 111 070 o) |
| Six places : lignes, libellés, curseur, trajectoire (`maxIdx`), langue (curseur + courbe) | tous sur `_kLevelSlots` ; `rowCount` ne sert plus qu'au nombre de lignes/libellés, à `_tongue()` et à `_sameGeometry` |
| Banc jetable géométrie : 6 tailles (320×130 → 800×160, 400×100, 400×250) × 5/6 lignes × tenue bout/mid/fond, 36 cas | lignes = libellés = curseur à 0,0 px ; gland sur Bout et jonction sur Tout à 0,0 px ; 5 lignes aux ordonnées des 6 ; aucune exception |
| Débordement de l'image (`Clip.none`) | bas de l'image à 157,2/160 et 124,7/130 ; déborde de 4,9 px seulement à 250 px (seuil ≈ 193 px). L'écran de séance ne donne que 130 ou 160 (`animHeight`) : sans effet en pratique |
| Chemin CI : image retirée d'`assets/courbe/` **et** cache `build/unit_test_assets` vidé | `load` nu (mutation) → `movement_piste_image_test` rouge (« Unable to load asset ») et les 14 cas d'alignement rouges au build ; code HEAD → 3 fichiers verts ; suite complète sans image : voir ci-dessous |
| Source SDK : `PlatformAssetBundle.load` lève de façon synchrone quand `send` rend `null` ; `flutter_test` (`mockFlutterAssets`) rend `null` pour un fichier absent | diagnostic de l'intégrateur exact ; sur appareil le messager rend toujours un Future, l'erreur passe par `onError` |
| `movement_animation_hold_moves_test` adapté (gorge 0,5 → 0,2, cran 0,5 → 0,4) | seuils en crans identiques à l'ancien test (0,3 / 0,1 / 0,5 / 0,06 cran) ; tolérances absolues gardées (0,05 ; 0,15 ; −0,85) valent 0,125 / 0,375 / 0,375 cran au lieu de 0,1 / 0,3 / 0,3 ; `microAmplitude` 0,4 → 0,8 et → 0,15 : rouges les deux fois. Pas affaibli |
| `f1043e7` | code identique hors commentaires, 0 retour chariot |
| Déterminisme : alignement, image, hold_moves × 3 relances ; `flutter analyze` ; `dart format --set-exit-if-changed` | 3 × 3 verts ; 0 ; 0 |
| Image 1x (58 × 201) lue pixel par pixel | première ligne pleine y = 1, `_assetTipY = 3` : le bout dessiné dépasse la ligne Bout de 2 px image (1,4 px à 160) ; les bourses s'élargissent à partir de y ≈ 149-154, `_assetFullY = 149` cohérent ; variantes 117 × 402 et 175 × 603 (1 px de trop en largeur : `BoxFit.fill` les serre de 0,6-0,9 %, invisible) |

Suite complète **sans image** sur HEAD (chemin CI, cache vidé) : 1392 verts en 2 min 13 s.

## Mutations (restaurées par copie, `cmp` vérifié)

| # | Mutation | Attendu | Obtenu |
|---|---|---|---|
| M01 | `_verticalInset = 5.0` | rouge | rouge (2 cas trajectoire) |
| M02 | `maxIdx = _kLevelSlots` | rouge | rouge (2) |
| M03 | `levelY` sans `_kLevelBox / 2` | rouge | rouge (image) |
| M04 | `_opacity = 1.0` | rouge | **vert** — trou |
| M05 | image sans `- width / 2` (centrage X) | rouge | **vert** — trou |
| M06 | lignes sur `widget.rowCount` | rouge | rouge (5 cas à 5 lignes) |
| M07 | curseur sur `widget.rowCount` | rouge | rouge (4 alignement + 2 hold_moves) |
| M08 | `microAmplitude` 0,8 / 0,15 | rouge | rouge / rouge |
| M09 | boîte des libellés + 10 px | rouge | rouge (11) |
| M10 | boîte de la langue + 10 px | rouge | rouge (lick balls) |
| M11 | `load` nu, sans image | rouge | rouge (1 + 14) |
| M12 | `_assetFullY = 140` | rouge | rouge (image) |
| M13 | `_kLevelSlots = 5` (retour à l'ancien) | rouge | rouge sur lick balls et hold_moves (3) ; **vert** sur les 11 « tenue » et sur le test image |
| M14 | `_kLevelBox = 20` | rouge | **vert** — trou |

## Réserves

1. **À trancher par Manu — flash au montage.** `_Shaft` lit `_available` dans un `FutureBuilder` sans
   `initialData`. Avec un messager asynchrone comme sur appareil (banc jetable : gestionnaire
   `flutter/assets` rendant un vrai `Future`), le **premier frame après chaque montage montre la
   silhouette dessinée, le second l'image** — au montage initial comme à chaque remontage (retour
   d'un break, bascule timer/animation). Au démarrage de séance s'ajoutent la latence du canal et le
   décodage : silhouette, puis rien, puis image. Sous `flutter_test` avec l'image, le messager rend une
   `SynchronousFuture` et l'image est là dès le premier frame : **aucun test ne peut voir ce flash.**
   Perceptible ou non à 60 i/s, seul le téléphone le dira.
2. **Mineure — trois trous.** Opacité 0,85 (règle de Manu) non gardée (M04) ; position horizontale de
   l'image non gardée (M05 : image décalée de 21 px, tout vert) ; `_kLevelBox` plus petit que le
   curseur non gardé (M14 : orbe écrasé en 28 × 20, tout vert).
3. **Mineure — la règle « 6 places » tient par ricochet.** Seuls le test lick balls (langue) et les
   constantes 0,2 / 0,6 codées en dur dans hold_moves, step_serial et transition tombent à 5 places
   (M13). Les 11 cas « tenue » et le test image restent verts : ils vérifient la cohérence entre
   éléments, pas le nombre de places.
4. **Mineure, préexistante — 1,4 px.** Le curseur est à 0,45 · W + 0,05 · sa largeur (181,4 px à
   400), l'image et la trajectoire à 0,45 · W (180,0) : convention `Align` d'avant la piste.
5. **Mineure — test conditionnel.** `movement_piste_image_test` suit l'état du poste : en CI il ne
   vérifie jamais le calage, en local jamais le repli. Il faut jouer les deux états à la main.
6. **Information.** Sans l'image, la silhouette de repli couvre 96 % de la hauteur, centrée : calée
   sur aucun niveau, comme avant la piste ; à 5 lignes elle descend d'une place sous Tout.

## Ce que je n'ai pas pu établir

- Le rendu réel : rien vu sur le téléphone, ni le flash (1), ni l'effet d'un cran 20 % plus petit.
- Le « 10 rouges sur 11 sur `cb080c6` » de l'intégrateur : non rejoué.
- La suite complète **avec** image sur HEAD : chiffre de l'intégrateur (1392) non rejoué, une seule
  suite à la fois ; la suite sans image (chemin CI, jamais jouée sur le HEAD final) a été préférée.
