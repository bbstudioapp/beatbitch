# Relecture adverse — finition de la piste (`feat/courbe-piste-integree`, `df4907b..4c172b6`, 2026-10-17)

Relecteur : Fable 5.1. Relu : les cinq commits au-dessus de `360e753`, écrits par claude-sonnet-5-5,
et le compte rendu `piste-finition-2026-10-17.resultat.md` point par point. Consigne : réfuter, pas
valider. Rien n'a été vu sur le téléphone. Aucun fichier de code ni de test modifié ; mutations
restaurées par copie (`cmp`), bancs jetables supprimés, arbre propre à la fin.

## Verdict par commit

| Commit | Verdict | Pourquoi |
|---|---|---|
| `df4907b` sonde par bundle | **publiable** | en production `DefaultAssetBundle.of` rend `rootBundle` (ni `WidgetsApp` ni `MaterialApp` n'en posent un, grep du SDK ; aucun dans `lib/`) : une sonde par processus, créée au premier `build`, exactement comme l'ancien `static final`. Le test dépend bien du bundle du contexte (mutation MF rouge ×3). |
| `e753953` plus de silhouette avant l'image | **publiable avec réserves** (mineures, ci-dessous) | rouge sous cinq mutations, chacune pour la bonne raison ; la silhouette finit toujours par s'afficher sans image, après remontages, sonde en cours ou changement de bundle (banc jetable) ; le trou visuel n'est pas plus long qu'avant |
| `4473f2e` six places sur les cas de tenue | **publiable** | `_kLevelSlots = 5` : 9 des 11 cas rouges (les deux `tip` restent verts, à 14 px quel que soit le nombre de places) ; `_kLevelBox = 20` : les 11 cas rouges aussi, trou M14 de la relecture précédente refermé deux fois |
| `a798099` variantes servies par le faux bundle | **publiable** | suite complète verte dans les deux états du poste (manifeste avec variantes, manifeste neuf sans image) ; le « rouge avant » de l'auteur non rejoué |
| `4c172b6` commentaires | **publiable** | fichier identique hors lignes de commentaire (4 suppressions, 0 ajout) |

## Ce qui a été vérifié

| Vérification | Résultat |
|---|---|
| Ligne de base, `movement_piste_image_test` + `movement_ladder_alignement_niveaux_test` | 22 verts |
| Ordre aléatoire (`--test-randomize-ordering-seed=random`) ×3 | 22 verts ×3 |
| `flutter analyze` ; `dart format --set-exit-if-changed` | 0 avis hors banc jetable ; 0 |
| Suite complète **avec** image (cache `unit_test_assets` garni, 3 variantes) | 1399 verts |
| Suite complète **sans** image (PNG retirés d'`assets/courbe/` **et** cache vidé) | 1399 verts (+ 1 banc jetable) |
| Banc de la piste, image retirée mais cache périmé gardé | 8 verts |
| Assets restaurés (`diff -r`), cache régénéré avec image, `git status` | propre |
| `_Shaft` dans son `Stack` (alignement centre, enfants non positionnés) | `SizedBox.shrink`, `_image()` (Positioned seuls) et `_ShaftBackdrop` (`Align`) donnent la même taille au `Stack` : les 11 cas d'alignement mesurent les mêmes ordonnées dans l'état image et dans l'état silhouette |

### Mutations (toutes sur `4c172b6`, restaurées par copie, `cmp` OK)

| # | Mutation | Attendu | Obtenu |
|---|---|---|---|
| MA | `initialData` retiré | rouge | rouge ×3, « premier frame du remontage » : `exactly one matching candidate / Found 0` (présente, absente sync, absente async) |
| MB | `null => _ShaftBackdrop()` | rouge | rouge, « premier frame, réponse attendue » : `no matching candidates / Found 1` |
| MC | `known = true` → `true` | rouge | rouge, remontage image : `Found 0` |
| MD | `known = false` → `false` | rouge | rouge ×2, remontage absente |
| ME | `Future.sync` retiré | rouge | rouge, absente sync : `Expected: null / Actual: FlutterError:<Unable to load asset…>` |
| MF | sonde sur `rootBundle` au lieu du bundle du contexte | rouge | rouge ×3 (image présente sur le poste : les deux « absente » et le premier frame) |
| MG | `_kLevelSlots = 5` | rouge | rouge ×11 : 9 tenue + lick balls + calage image, `40,4 attendu / 47,0` |
| MH | `_kLevelBox = 20` | rouge | rouge ×14 : 11 tenue + `_OrbShape` + `_RingShape` (`Size(28.0, 20.0)`) + calage |
| MI | témoin, alpha 0,06 → 0,07 de la silhouette | vert | vert (22) |

### Banc jetable (supprimé) — silhouette et changement de bundle

| Scénario | Frames observés |
|---|---|
| S1 présente (image affichée) → bundle absente sync, même arbre | `IMAGE` (périmé, un frame) puis `SILHOUETTE` ; une erreur « Unable to load asset » rapportée par le service d'images sur le frame périmé, attrapée par le test suivant |
| S2 inconnue (sonde en cours) → bundle absente async | `RIEN` puis `SILHOUETTE` |
| S3 absente sync (silhouette) → bundle présente, réponse tenue | `SILHOUETTE` périmée pendant l'attente, puis `IMAGE` |
| S4 cinq remontages, bundle absente async | `SILHOUETTE` au premier frame ×5 |
| S5 remontage pendant la sonde, puis réponse | `RIEN` puis `IMAGE`, aucune exception |
| S6 remontage pendant la sonde absente async | `SILHOUETTE` puis `SILHOUETTE` |
| S7 `rootBundle` nu sous flutter_test, image dans le cache | `IMAGE` dès le premier frame et au remontage (`SynchronousFuture`) |
| S7 `rootBundle` nu sous flutter_test, sans image | `RIEN` au premier frame, `SILHOUETTE` au second |

### Trou visuel au premier affichage

Avant le correctif : silhouette pendant l'aller-retour du canal `flutter/assets`, puis rien pendant le
décodage, puis l'image. Après : rien pendant l'aller-retour, rien pendant le décodage, puis l'image.
L'`Image.asset` n'est monté qu'après la réponse de la sonde dans les deux versions : la durée jusqu'à
l'image est la même, seule la silhouette a disparu de la première phase. Pas plus long. Non chronométré
sur appareil.

## Réserves

1. **Mineure — sonde sans borne.** `probe.available` n'a pas de `timeout`. Si `rootBundle.load` ne
   répondait jamais, l'emplacement resterait vide là où l'ancien code montrait la silhouette. Canal
   `flutter/assets`, réponse du moteur : improbable, mais le mode de panne a changé (visible → vide).
2. **Information — changement de bundle à chaud.** `FutureBuilder.didUpdateWidget` garde l'ancienne
   donnée (`inState(none)`), l'`initialData` neuf n'est pas relu : un frame périmé (S1, S3) et, de
   présente vers absente, une erreur d'image rapportée. Inatteignable en production : aucun
   `DefaultAssetBundle` dans l'app ni dans le SDK (`WidgetsApp`, `MaterialApp`). Signalé parce que le
   prompt le demandait, pas une réserve sur le commit.
3. **Information — « levée synchrone » ne veut pas dire silhouette synchrone.** Sans image, `Future.sync`
   capture la levée mais `onError` court dans un microtask : `known` est `null` au premier frame et la
   silhouette arrive au second (S7 sans image). Sous flutter_test sans image, tous les tests qui passent
   par `rootBundle` voient donc un premier frame vide. Aucun ne s'en plaint (suite verte). Le
   commentaire « `load` lève avant de rendre un Future » reste exact.
4. **Reportées, non traitées** (relecture précédente) : 1,4 px entre curseur et colonne de l'image
   (réserve 4, l'auteur l'a notée sans la corriger) ; silhouette de repli calée sur aucun niveau (6).

## Ce que je n'ai pas pu établir

- Le rendu réel sur le téléphone : ni l'absence de silhouette, ni la durée du « rien » avant décodage.
- « L'image dès le premier frame au remontage » : le test et le banc voient le **widget** `Image`,
  pas les pixels. Si l'`ImageCache` a évincé l'image décodée, le premier frame du remontage est vide
  (pas une silhouette). Non reproduit.
- Le « premier essai sans image rouge, 6 cas » de l'auteur avant `a798099` : non rejoué sur `4473f2e`.
- Les rouges « avant correctif sur `df4907b` » du compte rendu : non rejoués ; les mutations MA–MD sur
  `4c172b6` couvrent le même terrain.
