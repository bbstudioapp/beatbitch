---
type: analyse
sujet: relecture-adverse-des-etapes-1-et-2-du-chantier-aimant
ecrit_le: 2026-08-20T20:42:16+02:00
auteur: session tss2-aimant-relecture · claude-opus-5
revision: 09eba45
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/beep_engine_anchored_beat_degenerate_test.dart
  - rhythm_coach/test/beep_engine_anchored_beat_test.dart
  - rhythm_coach/test/movement_animation_beat_interval_test.dart
provenance:
  mesure: 27
  deduit: 14
  document: 3
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:917
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:459
  - rhythm_coach/lib/services/beep_engine.dart:594
  - rhythm_coach/lib/services/beep_engine.dart:712
  - rhythm_coach/lib/services/beep_engine.dart:891
  - rhythm_coach/lib/widgets/movement_animation.dart:162
  - rhythm_coach/lib/widgets/movement_animation.dart:225
  - rhythm_coach/lib/widgets/movement_animation.dart:262
  - rhythm_coach/lib/widgets/movement_animation.dart:543
---

## Ce que j'ai relu

**[mesuré]** Branche `feat/aimant-battement-inegal`, worktree `~/perso/git/tss2-aimant`, trois commits au-dessus
d'`origin/develop` (`7dc9746`). Étapes 1 et 2 du chantier aimant : l'intervalle du loop rythmé dépend
de la position ancrée, et le curseur consomme cet intervalle au lieu de recalculer `60000/bpm`.

Consigne de relecture : chercher à réfuter. Ce rapport dit d'abord ce qui ne tient pas.

## Les chiffres, d'abord

**[mesuré]** `origin/develop` (`7dc9746`) compte **1015 tests verts**, mesurés sur un worktree
jetable créé pour ça puis supprimé. **[document]** La consigne annonçait 1023 : c'est l'auteur qui a
raison, pas elle.

**[mesuré]** La tête de branche (`4073614`) compte **1020 tests verts** — 1015 + 4 (étape 1) + 1
(étape 2). `flutter analyze` rend **No issues found!**, `dart format --set-exit-if-changed lib test`
rend exit 0.

**[mesuré]** Après les deux correctifs que j'ai commités (plus bas), la suite complète compte
**1022 tests verts**, `flutter analyze` reste à **No issues found!** et `dart format` à exit 0.

**[mesuré]** Les deux nouveaux fichiers de test, recopiés tels quels sur `origin/develop`, échouent à
la compilation (`'BeatAnchor' isn't a type`, `simulateBeatsForTest isn't defined`) : rouges, mais
d'un rouge d'API absente, pas d'un rouge de comportement.

**[mesuré]** Le test de l'étape 2, lui, est rouge **de comportement** : `movement_animation.dart`
seul ramené à l'étape 1 (`git checkout da2df27 -- …`), le test échoue sur son assertion de position,
pas à la compilation. Vérifié dans les deux sens, deux fois.

**[mesuré]** Le diff touche **8 fichiers de test existants** portant **9 sous-classes** de
`BeepEngine` (la consigne en annonçait 6 ; `session_break_fail_gate_test.dart` en porte deux). Les
huit diffs sont strictement l'ajout des deux paramètres optionnels aux `override` — **aucune
assertion modifiée, aucune supprimée, aucun `reason` affaibli**. Relu ligne à ligne.

## L'invariant `2 T` : ce qui tient, ce qui ne tient pas

**[mesuré]** Sonde exhaustive sur le vrai `_intervalAfter`, via `simulateBeatsForTest` : BPM entiers
de 20 à 300 × ratios {2, 3, 4, 5, 7, 10, 100} × ancres {`from`, `to`} = **3 934 combinaisons**. Sur
toutes : `long + court == (120000/bpm).round()`, les deux cycles consécutifs sont égaux, aucun
intervalle n'est nul ou négatif. **La construction par soustraction fait ce que l'auteur en dit.**

**[mesuré]** Mais le cycle ancré n'est pas égal au cycle **régulier d'aujourd'hui** : `round(2T)`
diffère de `2 × round(T)` d'une milliseconde sur **1 834 des 3 934 combinaisons**. Sur 500 cycles
enchaînés à 90 BPM, le geste ancré dure **500 ms de moins** que le geste régulier (666 500 ms contre
667 000). Même écart à 37 et 199 BPM ; nul à 20, 77, 113, 150, 300.

**[déduit]** L'écart vaut 0,075 % du tempo — inaudible, et il va dans le bon sens (le cycle ancré est
plus proche du `2T` exact que le régulier). Aucun axe de capacité ne mesure la durée réelle d'un
battement : ils lisent le BPM nominal du step. Le profil ne bouge donc pas.

**[document]** La phrase du rapport de l'auteur — « l'invariant tient **exactement** quel que soit le
BPM » — reste donc à nuancer : il tient au sens `long + court = round(2T)`, pas au sens « le cycle
dure ce qu'il durait ». La nuance ne change rien à la livraison ; elle compte pour l'étape 3, où
l'ancrage deviendra le régime courant.

## Ce que j'ai cassé, et corrigé

**[mesuré]** Deux entrées cassent l'invariant net, et pas de 1 ms.

**[mesuré]** **Sans amplitude** (`to` absent, ou `to == from`), `_pickPosition` renvoie toujours `_from` : avec
`anchor = from`, *tous* les intervalles deviennent longs — 1500 ms au lieu de 1000 à 60 BPM, soit un
tempo effectif divisé par 1,5 ; avec `anchor = to`, tous deviennent courts (500 ms, tempo doublé). Le
cycle vaut alors 3000 ou 1000 au lieu de 2000. `applyStep` relève bien `from` quand `to == from` en
rhythm et lick, mais **jamais quand `to` est absent**, et jamais pour `hand`.

**[mesuré]** **Un `ratio` hors domaine** : `0` donne un intervalle nul un battement sur deux, `-3` un intervalle
de **−1000 ms**, `-1` lève `Unsupported operation: Infinity or NaN toInt` — depuis un callback de
`Timer`, donc non rattrapée.

**[déduit]** Aucun de ces deux cas n'est atteignable aujourd'hui : rien ne pose d'ancrage. Ils le
deviennent à l'étape 3, où `ratio` viendra d'un JSON de séance sauvegardée — donc d'une entrée
extérieure au code.

**[mesuré]** J'ai fermé les deux dans `_intervalAfter` (une condition), avec
`test/beep_engine_anchored_beat_degenerate_test.dart` qui vérifie le repli sur l'intervalle régulier.
Ce test est **rouge sur le code d'avant le correctif** — statut vérifié, valeurs relevées
(`[1500, …]` et `[2000, 0, …]` au lieu de `[1000, …]`).

## Le point qui compte : « rien ne change pour personne » est faux

C'est ma réserve gênante.

**[mesuré]** Sans le moindre ancrage (`anchor = none`, `ratio = 1`), le visuel de production ne se
comporte plus pareil dès qu'un step porte une **rampe BPM**. `BeepEngine.currentBpm` — donc
`MovementAnimation.bpm` — reste le BPM de **départ** du step pendant toute la rampe, tandis que
`nextInterval` porte le BPM **interpolé**. Widget monté à 120 BPM, loop émettant à 200 BPM :
la durée du glissement du curseur vaut **500 ms sur le code d'avant** et **300 ms après**. Mesuré en
lisant `AnimatedAlign.duration` sur les deux versions du seul `movement_animation.dart`.

**[déduit]** Ce n'est pas une régression : le curseur était en retard sur une rampe qui accélère, il
ne l'est plus. C'est un **correctif collatéral**, livré sous une promesse de neutralité, sans test qui
le verrouille et sans que Manu ait été averti qu'il verrait quelque chose bouger.

**[mesuré]** Son ampleur : sur 100 séances de carrière générées (4 niveaux × 25 graines, 20 minutes,
générateur réel), **27 steps sur 11 911** portent une rampe, tous en mode synchronisé, écart moyen
17,2 BPM et maximum 24 — soit **875 secondes sur 86 106** de temps rythmé, **1,0 %**. C'est une borne
basse : plusieurs constructeurs de défis (`rhythm_bpm_ceil_*`, `gorge_crossings_bpm_*`) posent aussi
des rampes, et ces steps-là sont insérés hors timeline.

**[mesuré]** Le même changement atteint la **courbe de prévision pointillée** : `_computeFutureBeats`
lit `beatDuration`, qui est désormais `_controller.duration`. Elle est déjà sur cette branche, donc
déjà sur `origin/develop` — le rapport de l'auteur la présente comme vivant sur
`feat/movement-trajectory-continuity`, ce qui n'est vrai que de son amélioration.

## « Aucun chemin de production ne peut produire un ancrage »

**[mesuré]** La conclusion tient, la preuve donnée pour l'établir est fausse. Le rapport parle de
« l'unique appelant de production (`session_controller.dart:1596`) ». Il y en a **six** :

- `session_controller.dart:1596` — lecture normale de la timeline ;
- `session_controller_fail_flow.dart:190` — breath après échec ;
- `session_controller_fail_flow.dart:295` — rejeu des steps après reprise ;
- `session_controller_fail_flow.dart:459` — `_restorePreviousLoop` ;
- `session_controller_challenge.dart:854` — breath d'après-défi ;
- `session_controller_challenge.dart:917` — steps du segment de défi.

**[mesuré]** Aucun des six ne passe `anchor` ni `ratio` — vérifié par balayage de `lib/` : les seules
occurrences hors `beep_engine.dart` sont le `anchor:` du mode Musique, sans rapport (`BeatPattern`).
**[mesuré]** Le mode Musique n'appelle ni `applyStep` ni le loop rythmé : il ne joue que des one-shots
(`playHoldOnce`, `playPositionOnce`), qui n'émettent aucun `BeatEvent`. Il n'est pas concerné.

Le fait tient donc : **en production, `_anchor` reste `none`.** Mais quiconque reprendra la preuve
telle qu'elle est écrite cherchera un seul appelant et en oubliera cinq.

## Le contrat audio → visuel

**[mesuré]** Plus aucun recalcul de `60000/bpm` ne survit sur le chemin des battements :
`_durationFor` ne sert plus qu'au montage, au changement de mode et au changement de tempo — soit les
instants où aucun `BeatEvent` n'est encore arrivé.

**[déduit]** Un `BeatEvent` sans durée est impossible : `nextInterval` est `required` et
`beep_engine.dart` est le seul endroit du dépôt qui construise un `BeatEvent`. Un faux moteur qui en
fabriquerait un ne compilerait pas sans fournir la durée.

**[déduit]** Deux fragilités restent, aucune atteignable établie :

1. **[déduit]** `_onBeatEvent` filtre sur `event.mode` et écrit `_controller.duration` — le même contrôleur qui
   pilote le pulse des modes statiques (`hold`, `beg`, `suckle`). Un `BeatEvent` rythmé reçu pendant
   que le widget affiche un `hold` remplacerait les 1800 ms du pulse par l'intervalle du rythme, et
   `didUpdateWidget` étant déjà passé, la durée fautive tiendrait tout le step. Je n'ai **pas** su
   construire de chemin de production qui y arrive : `_stopLoop()` est synchrone dans `applyStep` et
   la livraison du `beatStream` est un microtask, donc le dernier battement est livré avant la
   bascule. La garde manquante est `widget.mode`, pas `event.mode`.
2. Le commentaire de `_buildForMode` affirme que « les autres modes ne reçoivent jamais de
   `BeatEvent` ». C'est un absolu que rien dans le code ne garantit. Je ne l'ai pas réécrit : le
   reformuler masquerait le signal alors que la garde, elle, manque toujours.

## Un commentaire qui mentait, et pourquoi

**[mesuré]** `MovementAnimation._durationFor` borne le BPM à `[20, 300]`. Le test de l'étape 2
montait le widget à **600 BPM** et annonçait « avec l'ancien calcul, la transition aurait duré
100 ms ». Elle aurait duré **200 ms** : le clamp ramenait 600 à 300. Le test restait rouge sur le code
d'avant, mais pour une raison autre que celle écrite à côté.

**[mesuré]** Je l'ai ramené dans le domaine réel — 200 BPM, `T = 300 ms`, intervalles 150 / 450 ms.
Vert sur la tête de branche, rouge sur le code d'avant l'étape 2 : il discrimine toujours, et son
commentaire ne ment plus.

**[déduit]** `beep_engine_anchored_beat_test.dart` garde son `bpm = 600`, lui aussi hors des bornes
`kMinBpm`/`kMaxBpm`. Sans conséquence : `_intervalAfter` est linéaire en BPM et ne clampe rien. Je
n'y ai pas touché.

## Ce que le paramétrage coûtera à l'étape 3

**[déduit]** `anchor` et `ratio` en paramètres nommés d'`applyStep` permettront l'étape 3 sans être
refaits — mais ils la rendront plus chère et plus fragile qu'un champ porté par le step :

- le plan (§6, étape 3) fait entrer `anchor`/`ratio` dans `SessionStep.toJson`/`fromJson` ;
  l'information sera donc **déjà dans le `step`** que reçoit `applyStep`. Deux sources pour une même
  valeur, qui peuvent diverger ;
- il faudra recâbler les **six** appelants, dont trois sont des chemins de reprise
  (`_restorePreviousLoop`, rejeu après échec, retour de défi). Un oubli sur ceux-là ne casse rien de
  visible : le geste redevient simplement régulier après une reprise, sans erreur ;
- les **neuf** sous-classes de test devront être réécrites une seconde fois.

**[déduit]** La lecture depuis le `step` supprime les trois problèmes d'un coup. Si un appelant a un
jour besoin de surcharger, le paramètre nommé peut rester en dérogation explicite — mais il ne devrait
pas être le canal principal.

**[déduit]** `startRhythmDemo` et `startLickDemo` remettent `_mode`, `_from`, `_to`, `_bpm` et
`_alternateToggle`, mais **pas** `_anchor` ni `_ratio`. À l'étape 3, l'écran de démonstration des sons
jouerait avec l'ancrage du dernier step de séance. Deux lignes, à poser avec le câblage.

## La courbe de prévision, à l'étape 3

**[mesuré]** `_computeFutureBeats` extrapole les battements à venir en répétant **un seul**
intervalle : `nextTime = nextTime.add(beatDuration)` en boucle, avec `beatDuration` = l'intervalle du
dernier battement reçu.

**[déduit]** Sous ancrage, cet intervalle alterne. La courbe ne montrerait donc pas « des points
régulièrement espacés pour un battement qui ne l'est plus », comme l'écrit le rapport de l'auteur :
elle changerait **d'échelle à chaque battement** — toute la fenêtre future dessinée à 0,5 T après un
court, puis toute à 1,5 T après un long. C'est un défaut plus visible que celui annoncé, et il tombe
dans la même étape.

**[déduit]** Aujourd'hui, sans ancrage, la seule conséquence est celle de la rampe BPM décrite plus
haut : la courbe suit désormais le tempo interpolé au lieu du tempo de départ. Plus juste, non testé.

## Ce que je n'ai pas pu établir

- **[document]** **Rien n'a sonné.** Règle du projet : on ne fait pas sonner le contenu de l'app en développement. Le
  rendu du geste à l'oreille appartient à Manu.
- **[mesuré]** **Aucune séance complète n'a été jouée** avec `SessionController`, `BeepEngine` et
  `MovementAnimation` montés ensemble. Comme l'auteur, je n'ai piloté que des briques séparées. Le
  changement de comportement sous rampe est donc établi au niveau du widget, pas au niveau d'une
  séance réelle.
- **[déduit]** **Le chemin qui atteindrait la fragilité 1** du contrat audio→visuel (durée de battement écrasant le
  pulse d'un mode statique) n'a pas été trouvé — ni prouvé impossible. Je n'ai pas exploré la pause,
  la reprise, ni le démontage du widget pendant un break.
- **[mesuré]** **Le volume réel des rampes** est une borne basse : les rampes posées par les constructeurs de défis
  ne sont pas dans les steps de la timeline générée, donc pas dans mon compte de 27.
- **[déduit]** **La dérive de `lastTargetMs` sous rampe ET ancrage combinés** n'a pas été mesurée. `_intervalAfter`
  calcule le long au BPM du tick courant et le court au BPM du tick suivant : leur somme n'est plus
  `2T` dès que le BPM bouge entre les deux. `DateTime.now()` n'étant pas simulé par `flutter_test`, la
  mesurer demande de faire tourner la vraie boucle en temps réel. Sans ancrage en production, ça
  n'engage rien aujourd'hui ; à l'étape 3, c'est à mesurer.

## Verdict

**Publiable avec réserves.**

Ce qui est demandé est fait, le moteur produit ce qu'il doit, le visuel suit, la suite existante passe
sans qu'on ait touché à une seule assertion, et les preuves annoncées ont été rejouées et tiennent.

**Les deux réserves gênantes** :

1. **La promesse de neutralité est fausse.** Le visuel change en production sur les steps à rampe BPM
   — mesuré, chiffré, non annoncé, non testé. Ce n'est pas une régression, c'est un correctif ; mais
   il appartient à Manu de le voir et de le valider, pas à une relecture de le découvrir.
2. **La preuve « aucun chemin de production » désigne un appelant sur six.** La conclusion est juste,
   l'énoncé est faux, et c'est exactement l'énoncé que reprendra l'étape 3.

**Les réserves non gênantes** : l'invariant `2T` à nuancer d'une milliseconde ; le paramétrage à
reprendre en champ de step avant l'étape 3 ; `_computeFutureBeats` à traiter dans la même étape ;
`startRhythmDemo`/`startLickDemo` à réinitialiser.

Rien de tout cela ne demande de recaler les deux commits en place. Les deux réserves gênantes
demandent une phrase de Manu, pas un correctif.

## Ce que j'ai commité

**[mesuré]** Deux commits, sur la même branche, sans rien pousser :

- `4332d16` — `fix(beep): l'ancrage ne déforme plus le tempo sans amplitude ni à ratio ≤ 1` : la garde dans
  `_intervalAfter` et son test.
- `09eba45` — `test(movement): le test d'intervalle ancré tourne dans le domaine BPM réel` : **[mesuré]**
  200 BPM au lieu de 600, et le commentaire qui redevient vrai.
