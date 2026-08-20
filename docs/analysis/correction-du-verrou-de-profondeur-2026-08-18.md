---
type: analyse
sujet: correction-du-verrou-de-profondeur
ecrit_le: 2026-08-18T18:56:55+02:00
auteur: session tss2-fix-profondeur · claude-opus-5
revision: e11271bc
branche: develop
porte_sur:
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/career_level_gates.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/capability_clamps.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/position_pickers.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/capability_service.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/test/capability_depth_comfort_vs_best_test.dart
provenance:
  mesure: 23
  deduit: 3
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre: ⚠️ NON RENSEIGNÉ
---

> ⚠️ **L'en-tête ci-dessus décrit le dépôt AutoPump, pas celui-ci.** Ce document a été écrit le
> 2026-08-18 par une session tss2 avec `castor doc:ecrire`, un outil qui ne vivait alors que dans le
> dépôt AutoPump : la session a dû s'y placer pour l'exécuter, et l'outil y a lu la révision, la
> branche et le dossier de destination. Les champs `revision`, `branche` et les chemins `porte_sur`
> en `_bmad-output/` renvoient donc à AutoPump et **ne décrivent pas l'arbre analysé ici** — la vraie
> révision jugée est écrite dans le corps du document. Rapatrié le 2026-08-19, sujet AutoPump #358 ;
> l'outil a été sorti de ce dépôt le même jour, un document écrit depuis tss2 reste désormais chez
> tss2 avec sa vraie révision.

Le verrou de profondeur se corrige sur `fix/depth-comfort-probe-2` (dépôt `tss2-w2`, branchée sur
`origin/develop` = `25657d5`, tête `2e62312`, **non poussée**). Quatre commits : reprise de la sonde,
correctif, sonde retournée, format. [document] L'en-tête ci-dessus est fabriqué depuis le dépôt
`auto-pump` — sa `revision` et sa `branche` sont celles d'`auto-pump`, pas celles jugées ici ; les
révisions qui comptent sont celles de ce paragraphe.

## Le rouge que j'ai vu — et l'écart avec la consigne

[mesuré] La sonde `test/capability_depth_comfort_vs_best_test.dart`, reprise telle quelle de
`test/sondes-adversariales-constats` (`13a3b0e`) et exécutée sur `origin/develop`, **passe au vert
6/6**. Ce n'est pas un test rouge à faire virer : c'est un test de *caractérisation* qui fige le
comportement actuel, défaut compris — son premier cas attend littéralement `expect(rhythm, 0)`.

[mesuré] Les chiffres annoncés, eux, sont retrouvés exactement. Profil `comfort=mid` / `best=throat`,
niveau 14, séance de 1500 s, 300 graines, milestones `holdMid` + `throatHold` + `throatPulse` :

| scénario — tout [mesuré] | séances avec un rythme `to >= throat` | idem en tenue |
| --- | --- | --- |
| normal, `successRate` 0.50 | **0/300** | 300/300 |
| normal, `successRate` 0.80 | 300/300 | 300/300 |
| normal, 14 axes à égalité 0.70 | 16/300 (5,3 %) | 300/300 |
| Encore, 0.50 | **300/300** | 300/300 |
| Encore, 0.80 | 300/300 | 300/300 |
| Utilise-moi, 0.50 | **300/300** | 300/300 |

[mesuré] En proportion de steps, et non plus de séances : sur `origin/develop`, séance normale à
`successRate` 0.50, **0 step rythmé sur 22 078** vise `throat` ou plus profond. La tranche n'est pas
rare, elle est absente.

Donc : chiffres retrouvés, statut du test différent de ce que la consigne prédisait. J'ai continué,
et je livre la sonde retournée avec sa preuve de discrimination (plus bas) plutôt qu'un rouge que
personne n'avait écrit.

## Ce que j'ai changé, et pourquoi

[mesuré] La cause n'est pas là où la sonde la cherchait. Son commentaire affirme que le plafond de
*tirage* (`maxDepthIndexForProfile`) « empêche `capabilityCapFor` de jamais servir à quoi que ce soit
pour rhythm ». C'est faux : mesuré, `maxDepthIndexForProfile` vaut bien `2` (mid) sur ce profil, et
pourtant des dizaines de steps `rhythm head→throat` sortent par séance dès que `successRate` passe
0,65. Le chemin dominant ne construit pas sa profondeur via `sampleFromTo` (le seul plafonné par
`maxDepthIndex`) : il produit un `to` plus profond que le tirage, puis le fait **rabattre en aval**
par `clampToCapability`, qui lit `capabilityCapFor(rhythmDepthMax)`. Le verrou réel est donc le
clamp, pas le tirage.

[mesuré] Sur `origin/develop`, ce clamp n'accorde le cran supplémentaire que si **deux** conditions
tombent ensemble : la profondeur gagne la loterie d'axe surchargé (mesuré à 16/300 ≈ 5,3 % quand les
14 axes sont à égalité, cohérent avec 1/14) **et** `successRate >= kDepthCranGate` (0,65). Sinon le
`to` est rabattu au `comfort`, donc `reached` ne dépasse jamais le `comfort`, donc le régulateur ne
voit jamais l'overshoot qui seul ferait remonter le `comfort` — le circuit est bien fermé sur
lui-même.

[document] Le correctif de référence `411feba` (`origin/feat/depth-comfort-probe`) vise exactement
ça. [mesuré] Ses deux fonctions cibles sont **identiques** à ce qu'elles étaient à son merge-base
(`39cbcaa`) : `git diff 39cbcaa..origin/develop` est vide sur `career_level_gates.dart` et
`capability_clamps.dart`. Les 101 commits intercalés (défis en streaming, pauses scénarisées,
postures) n'ont touché ni l'une ni l'autre, ni les deux sites d'appel de `maxDepthIndexForProfile`.
Son raisonnement tient donc tel quel, et je l'ai réappliqué à la main plutôt que par rebase.

[document] Deux écarts assumés par rapport à `411feba` :

- `capabilityCapFor` : j'ai ajouté un garde-fou `max(comfort, …)`. Sans lui, un profil où
  `best < comfort` verrait la « sonde » **rabaisser** le cap sous le confort — l'inverse exact de ce
  qu'on corrige. [déduit] `best` est monotone croissant en mémoire pour un axe `maximize`, mais il est
  persisté dans une clé séparée du `comfort` et rechargeable par un import : l'incohérence n'est pas
  un scénario impossible. [mesuré] Avec le garde-fou, `comfort=throat` / `best=mid` produit
  exactement la même séance qu'avant le correctif.
- `maxDepthIndexForProfile` : formulé `best.round() > rounded ? rounded + 1 : rounded` — équivalent au
  `min` d'origine sur des entiers, et non abaissant par construction.

[mesuré] Le `min(comfort + 1, best)` du clamp est conservé tel quel, lui, parce que le `comfort` y est
un double que le decay rend fractionnaire : avec `comfort=2.7` / `best=throat`, `min` donne throat
là où un `+1` nu donnerait `3.7`, que le consommateur arrondirait à **full**. Vérifié : ce profil
produit 59,7 % de steps throat, identiques au cas `comfort=mid`, et aucun step full.

### La question du gate, mesurée et non tranchée

La relecture adverse relevait que le correctif est plus généreux que son intitulé : le gate
`successRate >= kDepthCranGate` ne protège plus que le **dépassement du best**, plus la sonde vers
lui. C'est exact, c'est délibéré, et voici ce que ça vaut en chiffres.

[mesuré] Part des steps rythmés visant `throat` ou plus, 300 graines par ligne :

| profil (`comfort`/`best`), séance normale — tout [mesuré] | avant | après |
| --- | --- | --- |
| mid / throat, sr 0.50 | 0,0 % (0/22 078) | **59,7 %** (12 765/21 397) |
| mid / throat, sr 0.70 et 0.80 | 54,6 % | 59,7 % |
| **head / throat**, sr 0.50 **et** 0.80 | 0,0 % | **0,0 %** |
| mid / mid (axe consolidé), sr 0.50 | 0,0 % | 0,0 % |
| mid / mid, sr 0.80 | 54,6 % | 54,6 % |
| throat / throat, sr 0.50 | 59,7 % | 59,7 % |
| throat / mid (profil incohérent) | 59,7 % | 59,7 % |
| Encore mid / throat, sr 0.50 | 55,0 % | 61,5 % |
| Utilise-moi mid / throat, sr 0.50 | 100 % | 100 % |

Deux lectures s'imposent, et elles tirent en sens contraire :

- **[mesuré] Le correctif ne rend qu'un cran.** Une chute de deux crans (`comfort=head`, `best=throat`) reste
  à 0 % de throat, même à `successRate` 0,80 : la sonde plafonne à mid. La remontée est graduelle,
  une séance après l'autre. C'est ce qui distingue ce correctif d'un simple « on repart du best ».
- **[mesuré] Sur une chute d'un cran, il efface complètement la rétrogradation.** Le profil
  `comfort=mid` / `best=throat` produit après correctif *exactement les mêmes chiffres* que le profil
  `comfort=throat` / `best=throat` avant : 12 765/21 397 en rythme, 9 122/9 402 en tenue. Or la chute
  d'un cran est précisément ce que le régulateur applique sur un tap-out imputé. **Conséquence : pour
  la profondeur rythmée, un tap-out isolé n'a plus d'effet visible sur la séance suivante.** Il reste
  inscrit dans le profil (le `comfort` reste à mid tant qu'aucun overshoot n'est enregistré), mais il
  ne se voit plus dans ce qui est proposé.

C'est un arbitrage de design, pas une erreur de code : décider si la punition d'un tap-out doit rester
visible au moins une séance est une décision de Manu, pas la mienne. Je la signale sans la trancher.
Le correctif tel que livré fait le choix de la remontée immédiate d'un cran dans le territoire déjà
prouvé.

## Le vert, et la preuve que la sonde discrimine

[mesuré] La sonde retournée compte 11 tests. Sur la branche : **11/11 verts**. Rejouée telle quelle
sur un worktree détaché sur `origin/develop` : **2 rouges**, 9 verts.

Les deux rouges sont exactement les deux cas que le correctif adresse :

- [mesuré] `comfort=mid/best=throat, sr sous le seuil — throat revient` : attendu 300, obtenu **0** ;
- `maxDepthIndexForProfile suit la même règle` : attendu `3` (throat), obtenu **2** (mid).

[mesuré] Les 9 verts des deux côtés sont les non-régressions — escalade, no-op, chute de deux crans, tenues.
Qu'ils passent avant comme après est le résultat voulu : ils bornent le correctif, ils ne le prouvent
pas.

[mesuré] Suite complète : **978 tests verts sur `origin/develop`** (worktree détaché, aucun de mes
fichiers), **989 verts sur la branche** — les 11 de la sonde, aucun autre mouvement. `flutter analyze`
→ « No issues found! ». `dart format --set-exit-if-changed lib/ test/` → sortie 0.

## L'effet mesuré sur les tenues

[document] `position_pickers.dart` documente que `pickHoldPosition` n'est **pas** capé par
`maxDepthIndex` : la profondeur d'une tenue est gatée par les milestones `fullHold` / `throatHold` /
`holdMid`, et bornée en aval sur `hold.*.streak`, pas sur `rhythm.depth_max`. [déduit] Aucune des deux
fonctions modifiées n'est lue par ce chemin.

[mesuré] Les compteurs bruts de tenue **ne sont pas comparables step à step** entre les deux côtés :
déplacer un step rythmé décale toute la séquence pseudo-aléatoire en aval, si bien que les totaux
bougent (9 384 tenues avant, 9 402 après) sans qu'aucune règle de tenue n'ait changé. J'ai donc
retenu deux invariants insensibles à cette dérive :

- **[mesuré] `full` ne s'ouvre jamais.** Sans `fullHold` acquise, l'histogramme des tenues vaut
  `{throat, mid}` avant comme après, dans tous les scénarios normaux et Encore. Le seul cas où `full`
  apparaît est « Utilise-moi », à l'identique des deux côtés : `{throat: 9 811, full: 434}`.
- **[mesuré] La tranche throat en tenue ne bouge pas de régime** : 96,6 % à 97,4 % des tenues visent throat,
  avant comme après, y compris dans le scénario où le rythme passe de 0 % à 59,7 %.

[mesuré] Preuve la plus nette : dans le cas no-op (`comfort=mid` / `best=mid`), les tenues sont
**strictement identiques** des deux côtés, totaux compris — `{throat: 9 069, mid: 315}` sur 9 384.
Quand la sonde ne s'applique pas, rien ne bouge, tenues comprises. Et dans le cas `comfort=mid` /
`best=throat`, les chiffres de tenue après correctif (`{throat: 9 122, mid: 280}`) sont *exactement*
ceux que produisait avant le profil `comfort=throat` / `best=throat` : les tenues suivent l'état du
profil tel que le générateur le voit, pas le correctif.

## Ce que je n'ai pas pu établir

- **Le ressenti d'une séance.** Passer de 0 % à 59,7 % de steps rythmés visant throat est un chiffre,
  pas un vécu. Que ce soit « la gorge revient enfin » ou « c'est devenu trop profond trop souvent »
  ne se juge pas en test, et je n'ai rien pu en établir. Rien de ce que j'ai lancé n'a d'effet sonore.
- **Le comportement sur plusieurs séances enchaînées.** Toutes mes mesures portent sur des profils
  *figés* injectés au générateur. Je n'ai pas simulé la boucle complète séance → régulateur → séance
  suivante, donc je n'ai **pas** prouvé le point qui motive le correctif : que le `comfort` remonte
  effectivement vers le `best`. J'ai établi que la condition nécessaire est levée (l'overshoot
  redevient possible), pas que la remontée se produit ni en combien de séances.
- **Les profils réels des joueuses.** Mes six profils sont construits à la main. Je ne sais pas quelle
  proportion de profils réels porte `comfort < best` sur cet axe, ni de combien de crans — donc pas
  combien de joueuses ce correctif touche réellement.
- **Le mode Custom et le mode Music.** Non mesurés. Custom fournit son propre `maxDepthIndex` (le
  correctif est court-circuité), mais je ne l'ai pas vérifié à l'exécution.
- **La cohérence avec la sonde d'origine sur un point.** Sa version d'origine annonçait, pour
  `Encore`, un désaccord possible avec le rapport de tri. [mesuré] Il n'y en a pas : Encore et
  Utilise-moi sortent tous deux 300/300 sur `origin/develop`. Le doute que son commentaire soulevait
  est levé, mais je n'ai pas cherché d'où venait la divergence annoncée.

## Hors périmètre, signalé et non fait

Les profils déjà faussés sur les téléphones ne sont pas touchés — c'est explicitement hors tâche.
[déduit] Corriger le calcul ne répare rien chez une joueuse dont le `comfort` est déjà descendu :
son profil persisté garde la valeur basse, et le correctif la lui fera remonter d'un cran par séance
au lieu de la débloquer d'un coup. Si une réconciliation au chargement est souhaitée, elle reste à
décider et à écrire — je ne l'ai pas implémentée.

[mesuré] Un point relevé en passant, hors de mon périmètre et non corrigé : le commentaire de la sonde
d'origine qui attribue le verrou au plafond de tirage est faux (mesuré plus haut). Il disparaît avec
la réécriture de la sonde, mais l'affirmation équivalente ne se trouve nulle part ailleurs dans le
code — rien d'autre à corriger de ce chef.
