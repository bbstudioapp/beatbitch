# Relecture adverse — `feat/tenues-vivantes` @ `cc7c64b` dans la fusion d'octobre (2026-10-17)

Relecteur : Fable 5.1. Branche partie de `feat/aimant-battement-inegal` @ `86f6fdc` (fusionnée avant
elle dans `chore/fusion-octobre`), 12 commits propres : 21 fichiers, +1867/−392. Relue telle qu'elle
est dans la fusion (HEAD `6ab1e82`). Consigne : réfuter, pas valider. Aucun appareil, aucun son.
Rien de modifié hors ce rapport ; sondes et mutations restaurées par copie, arbre propre vérifié.

## Ce que la joueuse vit

Pendant une tenue, trois mouvements possibles : un aller-retour éclair vers une position plus haute
(ou vers `full`), une rafale de micro-mouvements, ou un lick balls sur une tenue `full` (langue dessinée
en bleu entre `full` et `balls`). Chaque mouvement est annoncé à la voix, sonné par les bips et dessiné
par la courbe aux mêmes instants (`holdKeyframes`, source unique).

## Ce qui a été vérifié

| Vérification | Résultat |
|---|---|
| Les deux commits `docs(...)` de la branche (`cc7c64b`, `b70efa8`) | 0 ligne de code différente hors commentaires (comparaison après retrait des `//`) |
| Suite ciblée des 7 fichiers de test + `custom_anchor_wiring_test` (dans la suite de 126 tests des quatre travaux) | 126 verts, 19 s |
| Origine des instants : moteur `_startHoldMoves` après le `transitionGap` (`beep_engine.dart:314-337`) ; générateur `_withHoldMoveCues` ajoute le même gap (`career_session_generator.dart:2197`) ; widget `_movesOrigin = elapsed + _bridgeGap` | cohérents entre eux |
| Position tenue : moteur `_from` (résolution « cible dans `from` »), générateur `d.to ?? d.from` | cohérents |
| Fin des mouvements avant la fin de la tenue : A/R finissent à ≤ `dur − 1 s` du 1er bip, micro/lick `at + len ≤ dur − 1` ; gap d'entrée en tenue 300/600 ms | tenu par construction, et par le test « le dernier retour tombe avant la fin » |
| Pause : `pause()` fige `_holdElapsedMs`, `resume()` relance `_startHoldMoves` en sautant les instants passés (`beep_engine.dart:962-967`, `996`) | test « une pause décale les mouvements restants » vert |
| Fusion avec `feat/bips-coherents` : la langue joue `_lickAssetForPosition(balls)` = `lick_balls_beep` (`beep_engine.dart:803`), listé dans `_lickAssets` donc dans le pool | résolu, rien perdu |
| Phrases `hold.moves` / `hold.micro` / `hold.lick_balls` : 2 entrées × 4 langues ; « Tiens / Hold / Halt / Aguanta » uniquement dans ces pools de tenue | conforme à la règle |

## Mutations (restaurées par copie)

| Id | Ligne mutée | Suite | Résultat |
|---|---|---|---|
| M5 | `career_session_generator.dart:2197` — consigne micro/lick posée à `step.time + floor(at)` au lieu de `floor(gap + at)` | `career_hold_moves_test` (7) | **verte : non gardée** — l'assertion (`test:127-131`) accepte toute consigne entre `h.time` et `h.time + 1 + ceil(at)` |
| M10 | `movement_animation.dart:784` — `insideMove(nextTime)` retiré (points plats dessinés au milieu d'un mouvement) | `movement_animation_hold_moves_test` + `rembobinage` + `reprise_pause` (9) | **verte : non gardée** |
| M12 | `beep_engine.dart:774` — plus de saut des instants déjà passés à la reprise | `beep_engine_hold_moves_test` (4) | **verte : non gardée** — le test « une pause décale… » ne distingue pas « décalés » de « rejoués depuis le début » sur sa fenêtre |

Trois lignes du travail ne sont tenues par aucun test. Aucune des trois n'est un défaut ; ce sont trois
trous de filet.

## Ce que je n'ai pas pu établir

1. **Consigne micro/lick entendue après le début du mouvement.** La consigne est un step texte seul à
   `floor(gap + at)` avec `at ≥ 1,5 s`. Avec `fix/voix-sans-report` (fusionné), elle attend dans
   `_pendingSpeech` que la phrase de la tenue finisse. La phrase de tenue porte parfois en plus la
   consigne `hold.moves` (74 caractères en FR, `career_session_generator.dart:2148-2151`). Je n'ai pas
   mesuré la durée de parole des vraies phrases : **à juger sur le S21** (Manu a validé micro et lick,
   mais je ne sais pas si l'APK jugé contenait déjà la file de voix).
2. **Recopie des milestones.** `_pushMilestoneSequence` (`career_session_generator.dart:1657-1681`)
   recopie champ à champ sans `moves` : une tenue de `milestones.json` qui porterait `"moves"` les
   perdrait. Aucune n'en porte aujourd'hui. Même famille que les fiches « recopie partielle » du sas.
3. **Tenue balancée (ancre `to`).** `applyStep` n'arme les mouvements que hors `_startHoldSwingLoop`
   (`beep_engine.dart:329-338`, boucle balancée `:333`) ; le générateur ne pose de `moves` que si `anchor == none`
   (`:2143`). Un JSON qui combinerait `anchor: to` et `moves` serait muet sur ses mouvements, sans
   erreur. Non testé.
4. **Pause pendant le gap d'entrée en tenue.** Si `pause()` tombe pendant les 300/600 ms du gap,
   `applyStep` poursuit : bip de tenue et mouvements démarrent **pendant la pause**. Préexistant pour
   la boucle de rythme (develop) ; les mouvements de tenue en héritent. Sondé et déposé au sas
   (`tss2-022`), hors périmètre.
5. **Reprise : à-coup de 250 ms au plus.** Au premier frame après `resume()`, l'extrapolation d'horloge
   du widget (`extrapolatedElapsed`, plafond 250 ms) avance jusqu'au tick suivant : la seconde courbe
   (langue) peut sauter de ≤ 250 ms pendant ≤ 200 ms. Non mesuré, probablement invisible.
6. L'image des A/R, micro et lick sur le téléphone : validée par Manu les 04 et 06/10 ; je n'ai rien
   vu ni entendu.

## Verdict

**Publiable avec réserves.**

- Bloquante : aucune.
- À trancher par Manu : (1) la consigne micro/lick qui peut arriver après le début de la rafale ou du
  léchage, si l'APK jugé le 06/10 n'avait pas la file de voix.
- Mineures : trois lignes non gardées (M5, M10, M12) ; recopie des milestones sans `moves` (2) ;
  `anchor: to` + `moves` silencieux (3).
