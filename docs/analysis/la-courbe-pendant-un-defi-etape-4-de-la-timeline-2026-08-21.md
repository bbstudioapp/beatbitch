# La courbe pendant un défi — étape 4 de la timeline

**21/08/2026** — branche `fix/courbe-continuite-visuelle`.

Symptôme visé, mot pour mot : « la courbe prédite reste collée en haut pendant un défi, le
curseur bouge normalement » (défaut #5 des notes du 21/08, jamais réinvestigué).

**Verdict : le défaut est reproduit, expliqué, et déjà corrigé en chemin** par `a02694e`
(« rien n'est annoncé pendant un défi »). Aucun changement de code de production dans cette
étape ; le livrable est le test qui verrouille les deux propriétés.

## Ce qui produisait le symptôme

Le step trigger d'un défi est un `breath` de 13 s, et il **reste dans `session.steps`
pendant tout le défi** — il n'en est excisé qu'à la clôture. Pendant ce temps l'horloge de
séance est gelée (`isTimelineFrozen`), donc ce `breath` reste figé **juste devant**
l'instant courant : à 3 s quand l'horloge est arrêtée à 2 s.

`MovementAnimation` trace `biffle`/`breath`/`freestyle` en ligne droite en haut
(`_ladderPositionsFor` → `tip`/`tip`, décision de Manu). Lue crûment, la timeline annonce
donc, à une seconde de là, une ligne droite au bout — pour tout le reste de la fenêtre de
trajectoire (3 s), le step de contenu suivant étant à 18 s. Pendant ce temps le moteur joue
les segments du défi, produits en direct par son builder, et le curseur les suit.

D'où : courbe collée en haut, curseur normal.

## La mesure

Un défi `holdThroatStreak` joué de bout en bout sur un vrai `SessionController`. En phase
`live`, le moteur tient `hold throat` (idx 3, tout en bas). Les deux lectures de la même
timeline, passées à `computeFutureBeatsForTest` :

| lecture | trajectoire (idx, du plus proche au plus lointain) |
|---|---|
| timeline lue crûment (avant `a02694e`) | `3.00 · 3.00 · **0.00** · **0.00** · **0.00**` |
| annonce vidée pendant le gel (aujourd'hui) | `3.00 · 3.00 · 3.00 · 3.00` |

La première remonte au bout à ≈0,9 s et n'en redescend plus. La seconde reste sur la gorge,
avec le curseur.

## Le recalage sur mutation de `session.steps`

C'est l'objet propre de l'étape 4 : vérifier que le mécanisme posé à l'étape 1 est câblé
pour ce cas. Il l'est, par deux chemins mesurés :

- `_excisChallengeFromSession` (`session_controller_challenge.dart`) reconstruit la
  `Session` ; la vue relit `ctrl.session.steps` à chaque `notifyListeners`, donc l'annonce
  suit la mutation **sans attendre le dégel** : mesuré à la clôture du défi, la suite
  annoncée passe de `3s:breath | 21s:rhythm | 51s:hold` à `3s:rhythm | 33s:hold`, les
  survivants ayant reculé des 18 s de la fenêtre excisée.
- Côté widget, `_sameUpcomingSteps` compare `startSecond` : ce décalage invalide la
  géométrie mémoïsée du ladder, qui se régénère.

Au dégel, le step qui suivait le défi est consommé immédiatement et l'annonce ne contient
plus que la suite — pas de trou, pas de saut.

## Le garde-fou et sa limite

`test/challenge_timeline_forecast_test.dart` joue un défi réel et mesure les deux lectures
côte à côte, puis le recalage à l'excision. Vérifié rouge par trois mutations, chacune sur
l'assertion attendue :

| mutation | assertion tombée |
|---|---|
| `isTimelineFrozen` sans `isChallengeActive` | « l'horloge est gelée dès l'armement » |
| excision sans `s.rebased(s.time - shift)` | « les survivants ont reculé de 18 s » |
| `breath` ne trace plus en haut | « et y reste — la courbe collée en haut » |

**Limite assumée** : le test verrouille le contrat du contrôleur et la mécanique de la
courbe, pas la ligne de `session_screen.dart` qui choisit entre les deux lectures. Si le
ternaire `ctrl.isTimelineFrozen ? const [] : …` disparaissait, le test resterait vert. Le
rendre testable demanderait d'extraire cette expression — une modification de production
hors du mandat de cette étape.

Un détail relevé au passage : `contains(tip)` ne décrit pas le symptôme. Le franchissement
de famille pose de lui-même un point au bout, même quand `breath` ne trace plus en haut.
Ce qui décrit « collée en haut », c'est que la courbe n'en **redescend plus**.
