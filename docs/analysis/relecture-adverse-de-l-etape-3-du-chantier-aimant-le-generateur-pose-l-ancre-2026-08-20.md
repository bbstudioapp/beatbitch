---
type: analyse
sujet: relecture-adverse-de-l-etape-3-du-chantier-aimant-le-generateur-pose-l-ancre
ecrit_le: 2026-08-20T22:15:12+02:00
auteur: session tss2-aimant-e3-relecture · claude-opus-5
revision: 0870e40
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/models/punishment.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart
  - rhythm_coach/test/session_step_anchor_compat_test.dart
  - rhythm_coach/test/session_step_anchor_replay_test.dart
provenance:
  mesure: 23
  deduit: 15
  document: 6
  sans_marqueur: 10
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/career_level_gates.dart:130
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1653
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2068
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:197
  - rhythm_coach/lib/controllers/session_controller.dart:2097
  - rhythm_coach/lib/controllers/session_controller.dart:2185
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:1009
  - rhythm_coach/lib/models/punishment.dart:26
  - rhythm_coach/lib/models/session_step.dart:156
  - rhythm_coach/lib/models/session_step.dart:186
  - rhythm_coach/lib/services/beep_engine.dart:587
  - rhythm_coach/lib/services/beep_engine.dart:993
  - rhythm_coach/lib/widgets/movement_animation.dart:375
  - rhythm_coach/lib/widgets/movement_animation.dart:566
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 10 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Verdict

**Publiable avec réserves.** Deux réserves sont gênantes : la courbe de prévision peint des
intervalles faux — jusqu'à négatifs — dès qu'une rampe BPM et un ancrage se croisent, et le périmètre
laissé hors du geste ancré est nettement plus large que ce que le rapport de l'auteur annonce. Deux
défauts trouvés étaient assez nets pour que je les corrige moi-même (l'ancre perdue aux rebases de
timeline, la preuve de compatibilité aveugle au défaut du constructeur) ; ils sont commités à part.
Rien n'est poussé, rien n'est fusionné.

**[déduit]** Waiver doc: les paragraphes qui portent un chiffre sans marqueur de provenance — ce sont des lignes de tableau et des puces, chacune placée sous une phrase d'introduction qui porte déjà son marqueur.

## Ce que j'ai exécuté

**[mesuré]** Sur la tête relue `252b4e8`, depuis `rhythm_coach/` : `flutter analyze` → « No issues
found! » ; `dart format --set-exit-if-changed lib test` → exit 0, 0 fichier changé ;
`timeout 1800 flutter test`, sortie redirigée vers fichier → **1033 tests passés, 0 échec**. Les trois
chiffres du rapport de l'auteur se vérifient.

**[mesuré]** Après mes deux commits de correction : analyze toujours propre, format toujours propre,
**1038 tests passés, 0 échec**.

## 1. La compatibilité sur pièces — la preuve ne couvrait qu'une moitié de la surface

C'est la contrainte que Manu a posée en premier, et c'est là que la sonde était la plus faible.

**[mesuré]** J'ai renversé les défauts du constructeur de `SessionStep`
(`anchor = BeatAnchor.from`, `ratio = 3`) et relancé la suite entière : **les 1033 tests restent
verts**, `test/session_step_anchor_compat_test.dart` compris. La sonde de compatibilité ne casse donc
pas quand on donne aux champs absents une valeur par défaut différente — c'est exactement le contrôle
que la consigne demandait.

**[déduit]** La raison est dans `SessionStep.fromJson`, qui n'emprunte jamais les défauts du
constructeur : il passe explicitement `anchor: BeatAnchor.fromString(...)` (repli `none` sur clé
absente) et `ratio: _asInt(json['ratio']) ?? 1`. La sonde épingle ces deux replis-là, pas le défaut.
Or tout le reste du code — builders de défis, `punishment_builder`, `milestone_loader`, contrôleurs —
construit un `SessionStep` sans nommer ces champs et dépend du défaut du constructeur, lui.

**[mesuré]** Trois autres écarts entre ce que le test annonce et ce qu'il parcourt :

- **Le volume réel n'est pas 253 steps mais 430.** Les 20 fichiers de `assets/sessions/` portent 430
  steps de premier niveau (dont 107 rythmés) ; `assets/career/milestones.json` en porte bien 202
  (dont 43 rythmés) sur ses 37 paliers.
- **Aucune assertion de couverture.** Le test se terminait sur `expect(total, greaterThan(0))` : il
  serait resté vert en ne relisant qu'un seul step.
- **Aucun step d'asset ne porte de `chainAction`.** Sur les 632 steps relus, zéro. La récursion que le
  rapport met en avant (« `chainAction` compris, récursivement ») ne rencontre aucune donnée réelle.

**[mesuré]** Une quatrième famille d'assets est relue par le même parseur et sortait du test :
`assets/punishments*.json`, 76 steps sur 4 fichiers de langue, dont 12 rythmés — parsés par
`Punishment.fromJson` via `SessionStep.fromJson`.

**[mesuré]** Corrigé dans `0870e40` : la sonde couvre désormais la famille des punitions, porte des
planchers de couverture (20 fichiers / 430 / 37 / 202 / 76), et vérifie le défaut du constructeur
lui-même. Rejouée avec les défauts renversés en `from`/`3` : **rouge**, sur l'assertion du défaut
(`Expected: BeatAnchor.none / Actual: BeatAnchor.from`).

**[déduit]** Ce qui reste vrai malgré tout : aucune clé `anchor` ni `ratio` n'existe dans aucun JSON
d'`assets/`, donc la compatibilité elle-même tient. C'est la *preuve* qui était partielle, pas le
fait.

## 2. L'ancre ne survivait à aucun rebase de timeline

**⭐ C'est le défaut le plus grave de l'étape, et il frappe l'argument central du rapport.**

**[document]** Le rapport justifie le champ de step contre le paramètre nommé par les trois chemins
qui rejouent un `SessionStep` déjà construit : « un paramètre nommé les aurait tous laissés régresser
vers `none` en silence ».

**[mesuré]** Le raisonnement porte sur les six appelants d'`applyStep`. Il ne porte pas sur les sites
qui **reconstruisent** un `SessionStep` champ à champ, et ceux-là laissaient `anchor`/`ratio`
derrière eux :

| site | rôle |
|---|---|
| `session_controller.dart:2097` (`buildUpgradedSession`) | Supplier, retry milestone |
| `session_controller.dart:2185` (`buildPostChallengeRegenSession`) | régénération après défi |
| `session_controller_challenge.dart:1009` (`_excisChallengeFromSession`) | excision de la fenêtre défi |
| `career_session_generator.dart:1653` (`_pushMilestoneSequence`) | recopie des steps de palier |

**[mesuré]** Sonde sur une séance de carrière réellement générée (niveau 25, seed 42) : **113 steps
ancrés sur 265**, puis **0** après `buildPostChallengeRegenSession` comme après
`buildUpgradedSession`. Toute la suite de la séance redevenait métronomique après un défi ou un
Supplier — soit, en pratique, la majorité du temps de jeu d'une séance qui en contient un.

**[déduit]** `_excisChallengeFromSession` est le même bloc de recopie, à l'indentation près ; je ne
l'ai pas piloté de bout en bout (méthode privée d'instance, il aurait fallu monter un contrôleur
complet). `_pushMilestoneSequence` recopie des steps de palier, qui ne portent aucune ancre
aujourd'hui : la perte y est sans effet visible.

**[mesuré]** Corrigé dans `e5f5f53`, les quatre sites. `test/session_step_anchor_replay_test.dart`
rejoue le générateur réel puis les deux helpers purs, et vérifie en plus l'aller-retour JSON
(`Session.toJson` → `Session.fromJson`, le chemin de `SavedSessionsRepository`). Rouge avant le
correctif sur l'assertion de comptage — 113 attendus, 0 obtenus ; vert après.

**[déduit]** La leçon du chantier vaut donc une deuxième fois : porter l'information sur le step
supprime la question à l'appel, pas à la recopie. Le motif « un flag par chemin » s'est reformé sur
les quatre chemins qui refabriquent le step.

## 3. Les trois chiffres — d'où ils sortent et ce qu'ils donnent

**[document]** L'auteur pose `ratio = 3` (le schéma de Manu), `rhythmAnchorHarderBpmThreshold = 100`
et `rhythmAnchorToFloorLevel = 10`, et justifie le seuil de BPM par « le milieu de la plage `[60,140]`
que `RhythmRules.build` tire ».

**[mesuré]** La plage `[60,140]` est bien celle du tirage
(`career_session_generator_rules_rhythm.dart:197`). Ce n'est pas la distribution sur laquelle le seuil
s'applique : la décision se prend au point de matérialisation, sur un `draft.bpm` déjà passé par la
dégradation et les clamps de capacité. Voici cette distribution-là, sur les steps rythmés réellement
générés (40 seeds par niveau) :

| niveau | n | min | p25 | p50 | p75 | p90 | max | ≥ 100 |
|---|---|---|---|---|---|---|---|---|
| 10 | 1811 | 40 | 47 | 57 | 82 | 126 | 166 | 19,6 % |
| 15 | 3510 | 38 | 47 | 57 | 80 | 120 | 186 | 18,9 % |
| 25 | 4475 | 38 | 47 | 56 | 79 | 120 | 200 | 17,0 % |

**[mesuré]** La distribution effective déborde largement `[60,140]` — de 38 à 200 — et sa médiane est
à 56. Le « milieu de la plage » invoqué tombe donc au **83ᵉ centile** de ce qu'il départage, pas au
milieu.

**[mesuré]** Elle est aussi **bimodale** : 2546 steps entre 40 et 59 bpm, un creux à 294 entre 80 et
99, puis un second mode de 387 steps entre 120 et 139 (niveau 25). Le seuil de 100 tombe dans le
creux, ce qui le rend peu sensible : le déplacer à 80 donnerait 23,6 % de steps ancrés sur `to`, à 120
il en donnerait 12,1 %. **La justification écrite est fausse, le chiffre choisi est défendable.**

**[mesuré]** Ce que le plancher de niveau donne en pratique, par niveau (25 seeds chacun) :

| niveau | steps rythmés | ancrés `to` | part |
|---|---|---|---|
| 1 · 5 · 9 | 314 · 740 · 1142 | 0 | **0 %** |
| 10 | 1135 | 232 | 20,4 % |
| 12 | 1569 | 283 | 18,0 % |
| 15 | 2185 | 427 | 19,5 % |
| 18 → 30 | 2807 | 489 | 17,4 % (plateau) |

**Deux conséquences à remonter à Manu, pas à trancher ici.**

**[mesuré]** **Le durcissement commence au niveau 1, pas au niveau 10.** Sous le plancher, 100 % des
steps rythmés générés portent `anchor = from, ratio = 3` — aucun n'a d'amplitude nulle, donc aucun ne
retombe sur l'intervalle régulier de `BeepEngine._intervalAfter`. Le geste de toute joueuse change dès
la première séance ; le plancher ne décide que du *côté* de l'aimant, jamais de sa présence.

**[déduit]** **La bascule sur `to` reste minoritaire à tous les niveaux.** La consigne de Manu, telle
que le rapport la cite — « de base les from, mais sur les niveaux plus élevés sur les to » — se lit
plus volontiers comme une bascule dominante au-delà d'un certain niveau que comme un plafond à 17 %
qui ne bouge plus de 18 à 30. Le plateau à 17,4 % au-delà du niveau 18 n'est décidé par personne : il
tombe de la distribution des BPM générés, pas d'une intention.

## 4. Rampe de BPM et ancrage combinés — chiffré

**[document]** L'auteur déclare l'effet « de second ordre, non chiffré, non testé » : sa correction de
la courbe de prévision déduit le cycle nominal `2T` de `widget.bpm`, qui reste le BPM de départ
pendant toute la rampe.

**[mesuré]** `BeepEngine.currentBpm` retourne `_bpm`, jamais la valeur interpolée — le widget reçoit
donc bien le BPM de départ. Sur 120 séances générées (niveaux 10 et 25), 22 steps rythmés portent une
rampe (`bpmEnd != bpm`), tous ancrés.

**[mesuré]** L'erreur de l'intervalle complémentaire extrapolé, mesurée en bout de rampe sur six
rampes réellement générées :

| rampe | ancre | intervalles réels | complément peint | complément vrai | erreur |
|---|---|---|---|---|---|
| 140 → 155 | `to` | 581 / 193 | 276 / 664 | 193 / 581 | +83 ms |
| 107 → 126 | `to` | 714 / 238 | 407 / 883 | 238 / 714 | +169 ms |
| 88 → 110 | `from` | 273 / 818 | 1091 / 546 | 818 / 273 | +273 ms |
| 110 → 86 | `to` | 1047 / 348 | 44 / 743 | 348 / 1047 | −304 ms |
| 81 → 58 | `from` | 517 / 1552 | 964 / **−71** | 1552 / 517 | −588 ms |
| 73 → 52 | `from` | 577 / 1731 | 1067 / **−87** | 1731 / 577 | −664 ms |

**[mesuré]** Ce n'est pas du second ordre : l'erreur va de 83 ms à 664 ms par battement extrapolé,
soit de 6 % à 38 % du cycle nominal, sur une fenêtre de trajectoire de 3000 ms.

**[déduit]** Le cas des deux dernières lignes est qualitativement différent : **le complément devient
négatif**. `complementaryBeatIntervalMs` vaut `2T₀ − intervalRéel` ; dès qu'une rampe ralentit de plus
d'un quart, l'intervalle long ancré (`0,75 × 2T`) dépasse `2T₀` et le résultat passe sous zéro. La
courbe de prévision recule alors dans le temps entre deux points, au lieu d'avancer.

**[mesuré]** Le widget n'en meurt pas : monté à 81 bpm et nourri de battements ancrés à 58, il rend
six battements sans exception et sans blocage. La somme d'une paire d'intervalles peints vaut
toujours `2T₀ > 0`, donc la boucle d'extrapolation progresse malgré les pas négatifs.

**[déduit]** Fréquence : 22 rampes sur 120 séances, dont 2 sous le seuil du quart (81 → 58, 73 → 52).
Le dessin qui recule concerne donc de l'ordre d'une séance sur soixante, pendant une trentaine de
secondes. Le dessin simplement faux concerne toutes les rampes ancrées.

**Je n'ai pas corrigé, et je le remonte.** Les deux correctifs possibles — borner le complément par
le bas, ou faire remonter le BPM interpolé jusqu'au widget — modifient la courbe sous rampe, c'est-à-
dire précisément le curseur que Manu a dit garder. Le choix lui revient.

## 5. L'invariant `2 T` sur séances générées

**[document]** L'auteur écrit que chaque step rythmé d'une séance de niveau 25 est rejoué via le vrai
`BeepEngine.simulateBeatsForTest` et que la somme de deux intervalles consécutifs vaut exactement
`round(2T)`.

**[mesuré]** C'est vrai, et c'est vérifié sur des séances réellement générées, ancre alternée
comprise. Le test filtre sur `bpm`/`from`/`to` non nuls ; aucun step rythmé généré n'a `from == to`,
donc aucun ne bénéficie du repli régulier de `_intervalAfter`. La preuve porte bien sur des steps
réellement ancrés.

**[déduit]** La limite : `simulateBeatsForTest` prend un BPM fixe, donc les steps à rampe sont rejoués
comme s'ils n'en avaient pas. L'invariant n'est pas prouvé sur le seul cas où il pourrait céder.

**[mesuré]** Je l'ai rejoué en pilotant `emitOneBeatForTest` avec le BPM interpolé battement par
battement, sur trois rampes réelles :

| rampe | durée | battements | écart max \|cycle − 2T\| |
|---|---|---|---|
| 88 → 110 | 31 s | 52 | 3 ms |
| 110 → 86 | 36 s | 60 | 3 ms |
| 81 → 58 | 36 s | 42 | 9 ms |

**[déduit]** L'invariant cède, mais de 3 à 9 ms sur un cycle de 1,3 à 2,0 s — moins de 0,5 %. Les neuf
axes du profil ne courent aucun risque. Le côté moteur de l'aimant tient.

## 6. La courbe de prévision sous ancrage

**[document]** L'auteur reconnaît n'avoir testé que la brique arithmétique, pas la suite de points
peinte, `_PositionLadder` et `_computeFutureBeats` étant privés au fichier.

**[déduit]** Je confirme la limite et je n'ai pas trouvé de moyen honnête de la lever sans toucher au
code de production : les points ne sortent nulle part, et le `CustomPainter` qui les consomme est
privé lui aussi. Ce qui resterait à faire, si Manu veut la preuve, tient en une ligne — exposer
`_computeFutureBeats` en `@visibleForTesting` — mais c'est un changement de surface publique que je ne
prends pas de mon propre chef.

**[mesuré]** Ce que j'ai pu établir sans y toucher : l'alternance des intervalles est correcte hors
rampe (`beatMs` puis complément, `wasLastInterval` bascule aux deux ajouts), et fausse sous rampe dans
les proportions du §4. La brique arithmétique est juste ; c'est son entrée qui ment.

## 7. Le périmètre laissé hors du geste ancré est plus large qu'annoncé

**[document]** Le rapport nomme deux exclusions : `punishment_builder.dart`, et « les 6 autres
méthodes de `RhythmRules` » — `buildMiniWaveSegment`, `buildRecovery`, `postFinalVariants`,
`buildPreFinisher`, `buildIntroStep`, `firstStepVariants` — qui « ne sont pas ancrées non plus ».

**[mesuré]** **Cette seconde exclusion est fausse.** Toutes ces méthodes produisent un `StepDraft` qui
passe par le même `_draftToStep`, lequel n'a pas d'autre critère que `draft.mode == rhythm`. Relevé
sur des séances générées : les trois steps d'une mini-vague sortent en
`anchor = to, ratio = 3` (bpm 100/120/135, tous au-dessus du seuil), et le premier step rythmé d'une
séance sort en `anchor = from, ratio = 3`. Les vignettes que le rapport dit épargnées sont ancrées
comme les autres.

**[déduit]** La conséquence est plutôt heureuse — la mini-vague est un moment intense, l'ancrer sur
`to` a du sens — mais elle n'a été ni voulue ni relue : le rapport la décrit à l'envers.

**[mesuré]** Le vrai périmètre non ancré, lui, est plus large que `punishment_builder` :

- **7 builders de défis rythmés** construisent leur `SessionStep` en direct
  (`rhythm_bpm_ceil_{full,shallow,throat}`, `rhythm_motion_streak`, `rhythm_depth_max`,
  `gorge_crossings_bpm_{full,throat}`) — tous à `anchor = none`.
- **12 steps rythmés** dans `assets/punishments*.json`, plus les compositions de
  `punishment_builder`.
- **43 steps rythmés** dans les séquences de paliers, et **107** dans `assets/sessions/` — non ancrés
  par la contrainte de compatibilité de Manu, donc légitimement.

**[déduit]** L'incohérence audible que ça produit n'est pas marginale et vise le mauvais endroit : les
défis `rhythm_bpm_ceil_*` sont, par construction, les moments de rythme les plus rapides d'une séance.
Le battement y redevient métronomique juste au moment où l'ancrage sur `to` serait le plus marqué —
puis il redevient inégal à la sortie du défi. Un palier ou un scénario JSON produit la même bascule.
`punishment_builder` n'est donc pas une exception isolée : c'est une famille.

**Je ne tranche pas** — étendre l'ancrage aux défis et aux punitions est une décision de conception,
et Manu n'a jamais dit s'il attend l'aimant là.

## 8. Erreurs de fait du rapport de l'auteur

**[déduit]** Trois énoncés du rapport `chantier-aimant-etape-3-…` ne résistent pas à la mesure :

1. « les 6 autres méthodes de `RhythmRules` … ne sont pas ancrées non plus » — elles le sont (§7).
2. « le milieu de la plage `[60,140]` » comme justification du seuil de 100 — la distribution
   effective va de 38 à 200, médiane 56 (§3).
3. La compatibilité présentée comme « réglée sur pièces » — la sonde ne couvrait ni le défaut du
   constructeur, ni la famille des punitions, ni aucun volume minimal (§1).

**[déduit]** Aucun de ces trois n'invalide une décision ; les deux premiers décrivent mal un code
correct, le troisième surestime une preuve. Ils comptent parce que le rapport est le document dont on
recopie les conclusions.

## Ce que je n'ai pas pu établir

- **Le rendu à l'oreille.** Rien n'a sonné, la consigne du projet l'interdit. Le ratio 3:1, le seuil de
  100 et le plancher de 10 restent jugés sur des chiffres, jamais sur le geste. C'est la question
  ouverte qui commande toutes les autres, et elle appartient à Manu sur son téléphone.
- **La suite de points réellement peinte** par le `CustomPainter` de la trajectoire (§6). J'ai prouvé
  l'entrée fausse, pas le dessin qui en sort.
- **`_excisChallengeFromSession` de bout en bout.** J'ai corrigé le site par lecture du bloc, sans le
  piloter par un contrôleur monté ; les deux helpers purs voisins, eux, sont couverts par un test
  rouge-puis-vert.
- **Aucune séance complète** (`SessionController` → `BeepEngine` → `MovementAnimation` montés
  ensemble) n'a fait tourner le chemin ancré. Comme aux étapes précédentes, mes preuves pilotent le
  générateur, le moteur et le widget séparément.
- **Le mode Custom** hérite du mécanisme par le partage de `CareerSessionGenerator.generate()` ; je
  n'ai pas mesuré quel niveau virtuel `CareerDifficultyResolver` lui attribue, donc pas de quel côté
  de l'aimant tombe une séance Custom.
- **Le plateau à 17,4 % au-delà du niveau 18** vient peut-être de mon paramètre
  `humiliationCareer = 20 × niveau`, pas du générateur. Je n'ai pas isolé la cause.

## Réserves, par gravité

**Gênantes :**

1. **La courbe de prévision sous rampe** (§4) — erreur de 83 à 664 ms par battement, complément
   négatif au-delà d'un quart de ralentissement. Introduit par `c1a459f`, non tenu par un test,
   correctif à trancher par Manu.
2. **Le périmètre non ancré** (§7) — 7 builders de défis rythmés, dont les trois plafonds de BPM, plus
   les punitions. Le battement redevient régulier aux moments les plus rapides de la séance.

**Non gênantes :**

3. Le durcissement démarre au niveau 1 pour toutes les joueuses (§3) — conforme à la consigne citée,
   mais l'ampleur mérite d'être dite avant publication.
4. La bascule sur `to` plafonne à 17 % du niveau 18 au niveau 30 (§3) — lecture possible de la
   consigne, sûrement pas la seule.
5. Trois énoncés faux dans le rapport de l'auteur (§8), sans conséquence sur le code.

**Corrigé pendant cette relecture :** l'ancre perdue aux quatre rebases de timeline (`e5f5f53`), la
preuve de compatibilité aveugle au défaut du constructeur et à la famille des punitions (`0870e40`).
