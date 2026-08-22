---
type: analyse
sujet: relecture-adverse-de-la-reparation-du-saut-du-curseur-en-sortie-de-tenue
ecrit_le: 2026-08-22T22:27:21+02:00
auteur: session tss2-relecture-saut-tenue · claude-sonnet-5
revision: 35e8a3c
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/movement_trajectory_hold_exit_test.dart
provenance:
  mesure: 19
  deduit: 6
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/screens/session_screen.dart:1118
  - rhythm_coach/lib/screens/session_screen.dart:55
  - rhythm_coach/lib/widgets/movement_animation.dart:1105
  - rhythm_coach/lib/widgets/movement_animation.dart:303
  - rhythm_coach/lib/widgets/movement_animation.dart:310
  - rhythm_coach/lib/widgets/movement_animation.dart:629
  - rhythm_coach/lib/widgets/movement_animation.dart:688
  - rhythm_coach/lib/widgets/movement_animation.dart:727
  - rhythm_coach/lib/widgets/movement_animation.dart:780
  - rhythm_coach/lib/widgets/movement_animation.dart:884
---

## 1. Ce que j'ai rejoué

[mesuré] Périmètre confirmé par `git diff 6743744..HEAD --stat` : trois fichiers touchés —
`rhythm_coach/lib/widgets/movement_animation.dart` (37 lignes), `rhythm_coach/test/movement_trajectory_hold_exit_test.dart`
(95 lignes), et le rapport `docs/analysis/reparation-du-saut-du-curseur-en-sortie-de-tenue-2026-08-22.md`.
`beep_engine.dart` n'apparaît dans aucun des quatre commits du périmètre.

[mesuré] J'ai isolé la correction sans casser la compilation du test : `git checkout 6743744 --
movement_animation.dart` efface aussi le câblage `elapsed`/`upcomingSteps` de `anchorAfterScrollForTest`
qu'utilisent les deux sondes, ce qui empêcherait le fichier de test de compiler. J'ai donc retiré à la
main les quatre hunks de la correction (déclaration `pastAt`/`pastIdx`, la branche `else` de
`addBridgePoint`, la branche `dtMs < 0` de `addPoint`, le bloc de substitution de `beats[0]` en fin de
fonction) en gardant intact le reste du fichier, `git diff` à l'appui pour vérifier que le retrait
correspond exactement à l'inverse de `a41dc29` moins le câblage de test.

## 2. Les deux sondes sont rouges pour la bonne raison

[mesuré] Sur le code amputé de la correction, les deux sondes échouent avec des messages identiques,
au chiffre près, à ceux cités par le rapport de l'auteur :

```
un recalcul tombé après la frontière ne déplace pas le curseur en sortie de tenue [E]
  Expected: a numeric value within <0.05> of <3.75>
    Actual: <3.2432432432432434>

un recalcul tombé dans la dernière milliseconde du pont d'entrée laisse le curseur sur la cible du pont [E]
  Expected: a numeric value within <0.05> of <4.0>
    Actual: <2.693023981607519>
```

[déduit] La correspondance décimale exacte (`3.2432432432432434`, `2.693023981607519`) avec les valeurs
du rapport élimine l'hypothèse d'un rouge accidentel (mauvais paramètre de sonde, faute de frappe dans
l'assertion) : le même mécanisme, avec les mêmes entrées, produit la même sortie que celle décrite.

[mesuré] Restauration (`git checkout HEAD -- movement_animation.dart`) : les deux sondes passent au
vert sans modification du fichier de test.

## 3. Déterminisme des sondes, dans les deux sens

[mesuré] 20 lancements consécutifs de `movement_trajectory_hold_exit_test.dart` sur le code corrigé :
20/20 verts. 20 lancements consécutifs sur le code amputé de la correction : 20/20 rouges, avec
exactement les mêmes valeurs `Actual` (`3.2432432432432434` et `2.693023981607519`) sur les 20 essais
de chaque sonde, sans une seule bascule. La promesse de déterminisme du rapport est vérifiée dans les
deux sens, pas seulement au vert.

[déduit] Le second test ne dépend pas de la coïncidence d'un timing réel : il balaie 17 points
(`599900` à `599100` µs par pas de 50 µs) et retient le minimum, ce qui absorbe la gigue d'exécution
entre le `DateTime.now()` du test et celui, interne, de `_computeFutureBeats` (confirmé en lisant le
code — `now = DateTime.now()` est capturé à l'intérieur de la fonction, ligne 629, un instant différent
de celui du test). Le premier test n'a pas ce filet — il tolère 150 ms d'écart, marge large.

## 4. Chercher un cas où la nouvelle origine est pire que l'ancienne

[mesuré] Quatre scénarios construits à la main via `anchorAfterScrollForTest` (fichier de sonde jetable,
retiré après usage, non versionné) :

- [mesuré] plateau `hold` de 60 s avec deux frontières `upcomingSteps` toutes deux déjà périmées de
  plusieurs secondes → résultat non nul, valeur interpolée entre les deux positions attendues (3,27,
  entre throat et full), cohérent avec le mécanisme documenté ;
- [mesuré] pont en cascade (`hold` → `lick` → `hand`, deux traversées de famille toutes deux déjà
  passées) → résultat cohérent avec une interpolation depuis le point le plus récent réellement
  franchi (1,39, entre mid et head, tracé à la main confirme la valeur) ;
- [mesuré] reprise après une pause de 10 minutes sur le même scénario que la sonde 1 du rapport →
  **3,75**, la valeur exacte attendue par la sonde livrée ; l'âge de l'origine gelée (1,8 s dans la
  sonde livrée contre 10 min ici) ne change rien au résultat, ce qui confirme la généralité
  revendiquée au §8 du rapport ;
- [mesuré] tenue `throat` → rythme (le cas que les deux auteurs disent non traité) → **3,0** pile, la
  corde reste plate comme annoncé — aucun saut introduit ni corrigé ici, cohérent avec l'aveu du
  rapport.

[déduit] Aucun des quatre n'a produit une valeur aberrante (hors de l'intervalle des positions en jeu,
ou immobile côté silence). Je n'ai pas trouvé de cas où la nouvelle origine dégrade le curseur par
rapport à l'ancienne.

[mesuré] **Ce que je n'ai PAS pu établir** : je n'ai pas comparé ces quatre scénarios contre leur valeur
*avant* la correction (seul le premier a un équivalent direct dans la sonde livrée). Une régression
fine — un mauvais chiffre après la virgule sur un cas que je n'ai pas isolé du "avant" — resterait
invisible à cette méthode. Le nombre de scénarios couverts (4, à la main) est loin d'un balayage
exhaustif des combinaisons mode × famille × âge d'origine.

## 5. La condition « postérieur à l'origine courante »

[déduit] Lecture du code (`movement_animation.dart:884-896`) : la condition
`freshAt.isAfter(anchorOrigin)` bloque la substitution quand le dernier point passé trouvé est plus
vieux que l'origine déjà en place. Par construction du reste de la fonction, `pastAt`/`pastIdx` ne sont
écrasés que par des appels à `addPoint`/`addBridgePoint` dont l'argument `at` croît de façon monotone
au fil de la boucle — je n'ai pas trouvé de chemin où un appel plus tardif dans la boucle porte un `at`
antérieur à un appel précédent, ce qui garantit que "le dernier écrasé" est bien "le plus récent".

[mesuré] Scénario construit pour forcer le blocage : un vrai bip très frais (`lastBeatAt`, 50 ms) avec
une frontière `upcomingSteps` périmée de 3 000 ms — largement antérieure à l'origine réelle. Comparé
avant/après la correction, les deux codes rendent une valeur quasi identique (1,684 / 1,693) — un écart
de 0,0086. Pour distinguer un vrai no-op d'un artefact de mesure, j'ai relancé le même scénario 5 fois
de suite **sur le seul code corrigé** : la dispersion naturelle entre lancements va de 1,684 à 1,701
(0,017), plus large que l'écart avant/après observé. La différence avant/après tient donc à la gigue
d'horloge réelle du scénario (il n'utilise aucun balayage de fenêtre, contrairement aux sondes livrées),
pas à un effet du code : la garde bloque bien la substitution dans ce cas.

[mesuré] **Ce que je n'ai PAS pu établir** : je n'ai pas trouvé de cas où `freshAt` égale
`anchorOrigin` à l'identique (`isAfter` faux) tout en portant un `idx` différent — ce qui aurait été un
vrai défaut (correction bloquée par une égalité alors qu'elle aurait dû s'appliquer). J'ai identifié
un point d'égalité réel dans le code (le pont déjà résolu, `now >= last`, où `pastAt == anchorOrigin ==
last` et où les deux portent le même `idx = toIdx`) mais je ne l'ai pas testé empiriquement — l'analyse
statique du code aux lignes 688-710 et 751-754 me semble concluante mais n'a pas été rejouée par une
sonde.

## 6. Le moteur de bips

[mesuré] `git diff 6743744..HEAD --stat -- rhythm_coach/lib/services/beep_engine.dart` ne rend aucune
ligne — le fichier n'apparaît pas dans les quatre commits du périmètre. Confirmé indépendamment de
l'affirmation du rapport.

[mesuré] Le saut de deux rangées à ~1,2 s que le rapport écarte comme « artefact de ma sonde » : j'ai
tracé le mécanisme dans le code de production plutôt que de reprendre l'affirmation telle quelle.
`_isExternallyDriven => _beatSub != null` (ligne 303) ; `_onBeatEvent` (lignes 310-337) met à jour
`_flipped` et `_lastBeatAt` **dans le même `setState`** (lignes 327-330) — les deux ne peuvent pas
diverger tant qu'un `BeepEngine` est abonné. Le seul site de production qui instancie
`MovementAnimation` est `session_screen.dart:1118`, avec `beepEngine: widget.beep`, où `widget.beep`
est un champ `BeepEngine` **non nullable** (`session_screen.dart:55`) toujours construit avec l'écran —
`_beatSub` est donc systématiquement non nul en séance réelle. Le chemin où `_flipped` bascule sur le
statut interne de l'`AnimationController` (ligne 348-354, celui qui a produit le saut dans la sonde de
l'audit) n'est atteignable que quand aucun moteur n'est abonné — situation qui n'existe qu'en sonde de
test, jamais en séance. Je considère l'attribution du rapport confirmée, pas seulement recopiée.

## 7. Suite complète et analyse statique

[mesuré] `flutter analyze` : « No issues found! » (4,5 s).

[mesuré] `timeout 1200 flutter test` (sortie redirigée vers fichier, jamais de pipe vers `grep`/`head`) :
1099 tests, `All tests passed!`, aucune occurrence de `[E]` dans la sortie complète. Le chiffre
correspond exactement à celui du rapport.

## 8. La fiche du sas sur le second saut

[document] La fiche porte un verdict « rejoué et refermé » écrit par l'auteur de la correction
lui-même — exactement le cas que la méthode interdit (celui qui corrige ne tranche pas son propre
constat).

[mesuré] Je l'ai rejouée moi-même, indépendamment : c'est le second test de
`movement_trajectory_hold_exit_test.dart`, dont j'ai déjà obtenu, à la section 2 de ce rapport, la même
valeur rouge (`2.693023981607519`) sur le code d'avant et un vert sur le code corrigé, par ma propre
manipulation de retrait/restauration — pas par relecture du texte de la fiche. Le verdict de la fiche
tient sous un rejeu qui n'est pas celui de son auteur.

## 9. Ce que je n'ai PAS pu établir, au global

[déduit] Comme les deux auteurs précédents, je n'ai ni carte son ni téléphone : je n'ai rien vu ni
entendu, seulement mesuré des positions numériques dans des sondes et relu du code. Le lien entre la
valeur de curseur mesurée et ce que Manu voit à l'œil reste une déduction que je n'ai pas de moyen
d'établir davantage que mes deux prédécesseurs.

[déduit] Le cas d'une tenue à la gorge reste non traité — confirmé par mon propre scénario (§4,
dernier point : 3,0 pile, aucun artefact introduit ni corrigé) mais je n'ai pas cherché plus loin
l'origine d'un éventuel saut sur ce cas, hors périmètre de cette correction.

[mesuré] Je n'ai pas testé la fréquence réelle sur un appareil, ni posé de compteur dans `_recompute`
pour confirmer qu'un recalcul tombe effectivement dans la fenêtre incriminée en usage réel — sur ce
point je suis dans la même situation que les deux auteurs précédents, sans moyen de la dépasser depuis
une session shell.

## Verdict

**Publiable avec réserves.**

Réserves, aucune ne bloque :
- La couverture des scénarios adverses au §4 est artisanale (4 cas construits à la main, pas un
  balayage systématique) — une régression fine sur un cas non couvert resterait invisible à cette
  méthode.
- Le point d'égalité théorique `freshAt == anchorOrigin` avec des `idx` divergents (§5) n'a pas été
  rejoué par une sonde, seulement établi par lecture de code.
- Les deux réserves déjà connues (aucune observation audio/visuelle réelle, tenue gorge non traitée)
  restent ouvertes, comme documenté par les deux auteurs précédents.

Rien de ce que j'ai tenté n'a fait tomber les deux sondes pour une mauvaise raison, n'a cassé leur
déterminisme, n'a trouvé de cas où la nouvelle origine dégrade le curseur, ni n'a mis en défaut la
garde `isAfter` ou l'attribution du saut de deux rangées à un artefact de sonde.
