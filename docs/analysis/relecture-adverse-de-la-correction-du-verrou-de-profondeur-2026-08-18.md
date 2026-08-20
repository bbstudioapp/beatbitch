---
type: analyse
sujet: relecture-adverse-de-la-correction-du-verrou-de-profondeur
ecrit_le: 2026-08-18T20:39:00+02:00
auteur: session tss2-relecture-profondeur · claude-sonnet-5
revision: 9b6b6d17
branche: develop
porte_sur:
  - /home/emmanuel/perso/git/auto-pump/_bmad-output/implementation-artifacts/correction-du-verrou-de-profondeur-2026-08-18.md
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/career_level_gates.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/capability_clamps.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/humiliation_gates.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/position_pickers.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/capability_service.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/test/capability_depth_comfort_vs_best_test.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/test/career_max_depth_from_profile_test.dart
provenance:
  mesure: 21
  deduit: 9
  document: 5
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - /home/emmanuel/perso/git/auto-pump/_bmad-output/implementation-artifacts/correction-du-verrou-de-profondeur-2026-08-18.md:1
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/humiliation_gates.dart:195
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/position_pickers.dart:288
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_rhythm.dart:103
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/capability_service.dart:236
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/test/career_max_depth_from_profile_test.dart:8
---

> ⚠️ **L'en-tête ci-dessus décrit le dépôt AutoPump, pas celui-ci.** Ce document a été écrit le
> 2026-08-18 par une session tss2 avec `castor doc:ecrire`, un outil qui ne vivait alors que dans le
> dépôt AutoPump : la session a dû s'y placer pour l'exécuter, et l'outil y a lu la révision, la
> branche et le dossier de destination. Les champs `revision`, `branche` et les chemins `porte_sur`
> en `_bmad-output/` renvoient donc à AutoPump et **ne décrivent pas l'arbre analysé ici** — la vraie
> révision jugée est écrite dans le corps du document. Rapatrié le 2026-08-19, sujet AutoPump #358 ;
> l'outil a été sorti de ce dépôt le même jour, un document écrit depuis tss2 reste désormais chez
> tss2 avec sa vraie révision.

# Relecture adverse — correction du verrou de profondeur (comfort/best, `fix/depth-comfort-probe-2`)

**Verdict : publiable avec réserves.** Aucun défaut fonctionnel trouvé malgré une recherche adverse
étendue (preuve analytique + large balayage empirique sur grille fractionnaire, zéro contre-exemple,
suite de tests intégralement verte sur la branche — détails et chiffres exacts plus bas, chacun
étiqueté) — mais une affirmation d'équivalence du correctif est fausse à la frontière qu'il prétend
justement garder, et l'arbitrage de design qu'il remonte est exact seulement pour la mesure la plus
étroite possible.

**Consigne reçue : chercher à réfuter, pas à valider.** Ce document rend compte, piste par piste, de
ce que j'ai pu confirmer, infirmer, ou pas établir. Provenance systématique : **[mesuré]** (exécuté
par moi ou par un fork que j'ai lancé et dont j'ai lu le rapport dans cette session) · **[déduit]**
(raisonné depuis du code lu, non exécuté) · **[document]** (repris du rapport de l'auteur du fix, non
vérifié par moi).

Diff relu intégralement : `git diff 25657d5..HEAD` sur `rhythm_coach/lib/career/services/career_level_gates.dart`,
`rhythm_coach/lib/career/services/generation/capability_clamps.dart` et
`rhythm_coach/test/capability_depth_comfort_vs_best_test.dart` (3 fichiers, +322/−18). Comparé
ligne à ligne au correctif de référence non fusionné `411feba` (branche `feat/depth-comfort-probe`,
jamais mergée) : **[mesuré]**.

---

## Piste 1 — La cause est-elle le clamp, ou seulement le tirage ?

**[mesuré]** — la boucle principale d'échantillonnage rythme (`RhythmRules.build`,
`career_session_generator_rules_rhythm.dart:196-198`) tire `to` via `PositionPickers.sampleFromTo`,
dont le plafond est directement `config.maxDepthIndex.clamp(2,4)`
(`position_pickers.dart:288-291`). Pré-fix, avec `comfort=mid` (donc `maxDepthIndex=mid`), ce chemin
ne pouvait **structurellement pas** tirer `throat` : le plafond du tirage lui-même l'en empêchait.

**[mesuré]** — deux **autres** chemins tirent `to=throat` **directement depuis les milestones**, sans
jamais consulter `maxDepthIndex` au moment du tirage :
- `RhythmRules.buildRecovery` (`career_session_generator_rules_rhythm.dart:293-295`) : si
  `UnlockKey.throatPulse` est débloqué, `to=throat` inconditionnellement.
- `buildMiniWave` (`step_builders.dart:236-240`) : `hasThroat` = le même test d'unlock brut, pas
  `maxDepthIndex`.

Ces deux drafts, une fois émis, passent par `_clampToCapability` (`career_session_generator.dart:1440`
et via `HumiliationGates.enforceRequired`, `humiliation_gates.dart:207`) où
`RhythmRules.clampToCapability` (`career_session_generator_rules_rhythm.dart:116-121`) les rabat à
`comfort` pré-fix. **C'est bien là, et seulement là pour ces deux chemins, que le verrou opérait** —
confirmant le mécanisme que l'auteur attribue à « le chemin dominant ».

**Nuance à apporter** : « chemin dominant » est imprécis. La boucle principale (rôle
`mainLoopFallback`) ne déborde jamais — c'est `buildRecovery` (fréquent : choisi dès que l'endurance
projetée est basse, cf. `career_session_generator.dart:1398-1400`) et `buildMiniWave` (occasionnel,
gaté niveau/durée) qui débordent au tirage. Sans conséquence sur la nécessité du correctif : les deux
fichiers touchés restent chacun indispensables (`maxDepthIndexForProfile` pour que la boucle
principale tire elle-même plus profond ; `capabilityCapFor` pour que le clamp laisse passer ce que
`buildRecovery`/`buildMiniWave` proposent déjà) — **[déduit]**, vérifié en relisant les deux call sites
plutôt que supposé.

**Verdict : mécanisme confirmé, description imprécise sur un mot, sans conséquence.**

## Piste 2 — Les deux écarts assumés par rapport à `411feba`

**[mesuré]** — diff ligne à ligne contre `411feba` :

| | `411feba` (référence) | `fix/depth-comfort-probe-2` |
|---|---|---|
| `capability_clamps.dart` | `comfort = escalating ? comfort+1 : min(comfort+1, best)` | `comfort = escalating ? comfort+1 : max(comfort, min(comfort+1, best))` |
| `career_level_gates.dart` | `probe = min(comfort.round()+1, best.round())` | `probe = best.round() > rounded ? rounded+1 : rounded` |

**2a — Le garde-fou `max(comfort, …)` : le cas `best < comfort` est-il atteignable ?**

**[mesuré]** — j'ai retracé `CapabilityRegulator.regulate` (`capability_service.dart:236-402`) en
entier pour l'axe `rhythmDepthMax` (`isDepthCran`). Trois faits, tous vérifiés par lecture du code
réel (pas du commentaire) :
- Le seed initial pose `comfort = best` exactement (`capability_service.dart:279-286`).
- La branche ratchet ↑ pour `isDepthCran` calcule `comfort = min(comfort+1, reached)`
  (`capability_service.dart:346-352`), et `reached <= newBest` est garanti par le calcul de `newBest`
  juste au-dessus (`capability_service.dart:250-262`) — donc `comfort` reste `<= best` après un ratchet
  haut.
- La branche `hardNegative` (`capability_service.dart:314-317`) ne fait que baisser `comfort` (ou le
  laisser inchangé via le `.clamp(0, prev.comfort!)`), jamais le monter au-dessus de `best`.

Par récurrence sur ces trois branches (plus decay et soft-cap, qui ne font que rapprocher `comfort`
de `best*0.70` ou le baisser), **l'invariant `comfort <= best` se maintient pour cet axe à travers tout
`regulate()` et son orchestration `CapabilityService.commit()`** (`capability_service.dart:470-524`,
relu en entier — aucune écriture de `comfort`/`best` en dehors de `regulate()` dans ce chemin).

**Ce que je n'ai pas établi** : je n'ai pas audité le code d'import de profil (fonctionnalité de debug
existante d'après la mémoire du projet, hors du diff et hors du périmètre de cette relecture) qui
écrit `comfort`/`best` directement sans passer par `regulate()`. C'est la seule porte plausible que
j'identifie pour produire `best < comfort` — je ne l'ai pas vérifiée moi-même.

**Sur « le garde-fou masque-t-il un autre cas ? »** — **[déduit]** : non. Pré-fix, le cap était
toujours `comfort` (pas de logique `best` du tout). Sans le `max(comfort, …)`, un profil `best<comfort`
verrait son cap **baisser** en dessous de `comfort` (régression par rapport au comportement pré-fix
pour cet état). Le garde-fou restaure exactement le comportement pré-fix pour ce cas précis, sans
élargir ni rétrécir autre chose que j'aie trouvé.

**2b — La reformulation de `maxDepthIndexForProfile` : vraiment équivalente au `min` d'origine ?**

**[mesuré] — Non, elle ne l'est pas, à la frontière `best < comfort` précisément.** Preuve par le
propre test de l'auteur (`capability_depth_comfort_vs_best_test.dart:222-223`,
`expect(cap(3, 2), Position.throat.index)` — comfort=throat(3), best=mid(2)) :

- Nouvelle formule (celle du code) : `best.round()(2) > rounded(3)` → faux → `probe = rounded = 3` →
  `throat`. **Conforme au test.**
- `min` d'origine porté littéralement (`411feba`) : `probe = min(rounded+1, best.round()) =
  min(4, 2) = 2` → `mid`, borné à `[mid,full]` → reste `mid`. **Ne passerait PAS ce test** — le test
  attend `throat`, cette formule donnerait `mid`, une baisse sous le `comfort` de départ.

J'ai vérifié que les deux formules coïncident bien quand `best >= comfort` (les deux cas où le test
existant `career_max_depth_from_profile_test.dart` — jamais touché par ce diff, ses fixtures posent
toujours `best == comfort`, `capability_service.dart` n'entre pas en jeu — reste vert des deux côtés) :
`min(r+1, b) = r+1` quand `b > r`, `= r` quand `b == r`, dans les deux formulations. La divergence
n'existe que quand `best.round() < rounded`, c'est-à-dire exactement le cas « profil incohérent » que
l'autre fichier protège explicitement.

**Ce que ça veut dire concrètement** : la nouvelle formule de `career_level_gates.dart` porte le
**même garde-fou** que le `max(comfort, …)` explicite et longuement justifié de `capability_clamps.dart`
— mais ici, implicitement, sans commentaire qui le nomme, et avec un commentaire qui affirme
l'inverse (équivalence). Le comportement livré n'est pas en cause (il est cohérent, protecteur, et
passe le test) — c'est la **description du changement** qui est fausse sur ce point précis. Risque
concret : un futur refactor qui « simplifierait » cette ligne vers la forme `min` littérale, en se
fiant au commentaire d'équivalence, réintroduirait exactement la régression que l'autre fichier du
même correctif prend la peine d'empêcher.

**Verdict : pas de bug de comportement, mais une affirmation d'équivalence fausse et un garde-fou
dupliqué sous deux formes incohérentes entre les deux fichiers du même correctif — à corriger avant
fusion (commentaire, pas logique).**

## Piste 3 — `comfort` fractionnaire : un cran de trop, ou de moins ?

**[déduit], preuve analytique** — `RhythmRules.clampToCapability` consomme le cap double via
`.round()` (`career_session_generator_rules_rhythm.dart:118-119`). Pour la branche sonde (non
escalade), `résultat = max(comfort, min(comfort+1, best))`. Quand `best >= comfort` (cas normal),
`min(comfort+1, best) <= best`, et `round()` étant monotone non décroissante, `round(min(comfort+1,
best)) <= round(best)` **pour n'importe quelle valeur réelle** de `comfort`/`best` — la borne « jamais
au-delà du best arrondi » est donc garantie par construction, pas seulement par coïncidence sur les
valeurs testées.

**[mesuré]** — vérifié que `round(x)+1 == round(x+1)` pour tout `x >= 0` sous Dart (`(2.5).round()==3`,
`(3.5).round()==4`, ties round away-from-zero, jamais un problème car `comfort` est planché à 0 par
`_absoluteFloor`) : `dart run` sur 11 valeurs dont plusieurs `.5` exacts, aucune divergence. Ça ferme
le risque que `career_level_gates.dart` (qui arrondit *avant* le `+1`) et `capability_clamps.dart`
(qui arrondit *après*) produisent des crans différents pour le même profil fractionnaire.

**[mesuré] — confirmation empirique indépendante (fork dédié)** : balayage de 90 couples
(comfort, best) fractionnaires (comfort ∈ {1.5…2.99}, best ∈ {2.0…4.0}, `best >= comfort`),
50 graines chacun, 322 234 steps rythmés inspectés sur code fixé — **aucune violation de
`to.index > best.round()` trouvée**.

**Verdict : rien de fonctionnel trouvé sur ce point, recherche ciblée y compris aux bornes, preuve à
la fois analytique et empirique à grande échelle.**

## Piste 4 — Non-régression des tenues

**[mesuré]** — `PositionPickers.milestoneHoldCeilingIdx` (`position_pickers.dart:160-178`) et
`FinalPicker._holdCeilingIdx` (`final_picker.dart:88-96`, la tenue de la phase finale/climax) ne
consultent ni `capabilityCapFor(rhythmDepthMax)` ni `maxDepthIndexForProfile` — uniquement les
`UnlockKey` hold dédiés (`fullHold`/`throatHold`/`holdMid`). Seul repli vers `config.maxDepthIndex` :
`unlockedKeys.isEmpty` (mode hérité / démo, `position_pickers.dart:170-175` et
`final_picker.dart:94`) — un état que je n'ai pas trouvé atteignable pour un profil carrière portant
déjà une divergence `comfort`/`best` sur `rhythmDepthMax` (il faut avoir débloqué des milestones tôt
pour accumuler cette donnée), mais que je n'ai pas formellement exclu non plus.

**[mesuré]** — le groupe de test dédié « non-régression des tenues » (3 cas paramétrés : sonde
active, no-op, chute de deux crans) : **vert dans les trois cas, sur le code de la branche ET sur le
code pré-fix `25657d5`** (absent des 2 échecs listés dans « Suite de tests » ci-dessous) — confirme
empiriquement que ces trois scénarios ne discriminent pas le correctif, cohérent avec la lecture de
code (mécanisme disjoint).

**Verdict : confirmé par lecture de code sur toute la surface identifiée (corps de séance + final) ET
par l'exécution (3/3 verts des deux côtés du fix). Réserve : le cas `unlockedKeys.isEmpty` en
carrière réelle n'est pas formellement exclu par le code lu.**

## Piste 5 — Le cumul intense + sonde peut-il dépasser le `best` ?

**[déduit]** — piste ouverte que j'ai activement cherché à faire céder. `kIntenseDepthCranBonus`
(`capability_clamps.dart:221-227`) s'ajoute **après** le résultat de la sonde, pas après le `comfort`
brut. Pour un profil `comfort=mid/best=throat` en séance intense (Supplier/Encore) où l'axe n'est
*pas* l'axe surchargé de la séance : pré-fix, le cap valait `comfort_brut(mid) + intense(1) = throat`
(= `best`, jamais au-delà). Post-fix, le cap vaut `sonde(mid→throat, bornée par best) + intense(1) =
full` — **un cran au-delà du `best` prouvé**, ce qui n'arrivait pas avant dans ce même scénario.

**[mesuré]** — j'ai cherché si ce `to=full` calculé survit jusqu'à la séance. Il ne survit pas dans le
scénario testé : `HumiliationGates.enforceRequired` revérifie `isUnlocked` **après** le clamp capacité,
en boucle (`humiliation_gates.dart:204-228`) — si `to=full` sort du clamp mais que `UnlockKey.fullPulse`
n'est pas débloqué (le cas du fixture `_throatProvenUnlocks`, qui ne contient que `throatPulse`), le
draft est dégradé jusqu'à retomber sur une profondeur débloquée. Le filet milestone rattrape donc ce
scénario précis.

**Ce que je n'ai pas établi** : si `rhythm.depth_max.best` (profil de capacités) et
`UnlockKey.fullPulse` (milestone) peuvent désynchroniser en jeu réel — deux systèmes de tracking
distincts, dont je n'ai pas lu le code d'attribution des milestones (hors du diff). Si un tel désync
existe, ce cumul intense+sonde redeviendrait un chemin réel vers une profondeur non prouvée. Je le
signale comme piste non tranchée, pas comme défaut confirmé : dans le seul scénario que j'ai pu
tester (profil réaliste, milestones cohérentes avec le `best`), il ne se manifeste pas.

**Verdict : rien de confirmé — mécanisme plausible en théorie, neutralisé par un filet indépendant
dans le cas réaliste testé, désynchronisation profil/milestone non vérifiée.**

## Piste 6 — Le saut de pourcentage annoncé, et le rejeu du test

**[document]** — l'auteur annonce un passage de 0 % à 59,7 % de steps rythmés visant `throat` ou plus,
sur un profil `comfort=mid/best=throat`, séance normale, succès bas.

**[mesuré]** (fork dédié) — remesuré indépendamment, à un grain plus fin que le test existant (par
**step**, pas par session), sur 1000 graines et un profil équivalent (comfort=mid/best=throat,
`depthSuccessRate=0,50`, séance normale) :
- Code pré-fix (`25657d5`) : 0/73565 steps → **0,0 %**.
- Code du correctif (`2e62312`) : 42513/71367 steps → **59,57 %**.
Écart de 0,13 point avec le chiffre annoncé, cohérent avec une différence de méthodologie de mesure
(la mienne compte au step, l'origine du chiffre de l'auteur n'est pas documentée dans ce que j'ai
reçu) plutôt qu'un désaccord de fond.

**[mesuré]** (fork dédié) — la chute de deux crans (`comfort=head/best=throat`, `sr=0,80`, mêmes autres
paramètres) reste bloquée à **0,0 %** (0/73563 steps) sur le code du correctif : la remontée reste
bien graduelle, pas un rattrapage d'un coup. Confirme l'affirmation de l'auteur.

**[mesuré]** (fork dédié) — recherche d'un profil réaliste où le correctif proposerait une profondeur
non prouvée : balayage 90 combinaisons fractionnaires × jusqu'à 50 graines (piste 3) — aucun trouvé.

**Verdict : le saut annoncé est confirmé indépendamment, à la fois dans son ampleur et dans le fait
qu'il reste borné à un cran (pas un déverrouillage complet).**

## Piste 7 — L'arbitrage remonté : « un abandon isolé n'a plus d'effet visible »

**[document]** — l'auteur mesure qu'après correctif, `comfort=mid/best=throat` produit exactement les
mêmes statistiques que `comfort=throat/best=throat`, et en conclut que pour la profondeur rythmée, un
abandon isolé n'a plus d'effet visible sur la séance suivante.

**[mesuré]** (fork dédié) — vérifié au niveau le plus strict possible : sur 20 graines, comparaison
**champ par champ de chaque step** (mode/from/to/bpm/bpmEnd/duration, pas seulement les steps rhythm)
entre les deux profils — **sessions identiques bit à bit**, pas seulement statistiquement proches.
L'affirmation est donc exacte, et même plus forte que ce que sa formulation laissait entendre.

**[déduit] — mais cette égalité ne tient que parce que le `depthSuccessRate` est fixé à la même valeur
dans les deux profils comparés (0,50 dans le fixture de test, repris tel quel par ma remesure).** Dans
le régulateur réel (`CapabilityRegulator.regulate`, hors diff — non modifié par ce correctif), un
abandon imputé baisse **simultanément** `comfort` (`capability_service.dart:314-317`, −1 cran) et
`successRate` (`capability_service.dart:328`, EMA vers 0 avec poids plein). Un profil
`comfort=mid/best=throat` **produit par un vrai abandon** porterait donc un `successRate` plus bas
qu'un profil `comfort=throat/best=throat` jamais entamé — les deux profils comparés par le test/la
remesure ne sont donc pas ceux que produirait un abandon réel toutes choses égales par ailleurs.

**[mesuré]** — ce `successRate` plus bas a un effet réel, mais ailleurs que sur la profondeur atteinte :
il réduit le score de sélection de l'axe comme axe surchargé de la séance suivante
(`capability_clamps.dart:147-150`, le score inclut `+0,45 × sr`), donc réduit la probabilité que cet
axe déclenche la branche « escalade » qui seule fait grandir `best` au-delà de son maximum historique.
Effet indirect supplémentaire : la bande BPM consultée dépend de la profondeur `to` atteinte
(`CapabilityClamps.rhythmBpmCeilAxisFor`, `capability_clamps.dart:107-113`) — si l'abandon avait
empêché `to=throat` de ressortir (pré-fix), la bande BPM consultée aurait aussi différé ; post-fix, ce
n'est plus le cas puisque `to=throat` ressort à l'identique. Je n'ai trouvé aucun lien direct entre
`rhythmDepthMax` et la **durée** de séance (celle-ci vient du choix de format, pas du profil).

**Verdict : l'affirmation est exacte pour la mesure la plus étroite possible (la profondeur qui
ressort), et je n'ai rien trouvé qui l'élargisse sur le rythme ou la durée — mais elle est plus étroite
qu'une lecture rapide pourrait suggérer : un abandon réel laisse une trace mesurable ailleurs
(`successRate`, donc la vitesse à laquelle `best` lui-même peut regrandir), simplement pas sur ce que
ce correctif donne à voir la séance suivante. Un lecteur pressé du rapport source pourrait comprendre
« abandon sans conséquence » ; c'est plus précisément « sans conséquence sur la réapparition de la
profondeur déjà prouvée ».**

---

## Suite de tests — qualité du code livré

**[mesuré]** — sur la branche (`rhythm_coach/`, HEAD `2e62312`) :
- `dart format --set-exit-if-changed lib/ test/` → **exit 0**, « Formatted 289 files (0 changed) ».
- `flutter analyze` → **exit 0**, « No issues found! (ran in 3.1s) » — zéro erreur, zéro warning, zéro
  info.
- `flutter test` (suite complète) → **exit 0**, **989 passed, 0 failed** — « All tests passed! ».
  Correspond exactement au chiffre annoncé par l'auteur (989 sur la branche).

**[mesuré]** — rejeu du seul fichier de sonde (`capability_depth_comfort_vs_best_test.dart`, copié
tel quel depuis la branche) sur un worktree détaché à `25657d5` (= `origin/develop`, code pré-fix) :
**9 passed, 2 failed**, exit 1. Les deux échecs, nommés explicitement dans la sortie :
1. « sonde vers le best prouvé comfort=mid/best=throat, sr sous le seuil — throat revient »
2. « sonde vers le best prouvé maxDepthIndexForProfile suit la même règle »
Correspond exactement à l'annonce de l'auteur (« 11/11 verts sur la branche, 2 rouges rejoués sur
`origin/develop` ») — count ET noms.

**[déduit]** — je n'ai pas rejoué la suite *complète* (978 tests) sur `origin/develop` (seulement le
fichier de sonde isolé, ci-dessus) ; le chiffre « 978 sur develop » n'est donc pas [mesuré] par moi.
Il est cependant cohérent arithmétiquement : 989 (branche) − 11 (tests du nouveau fichier, tous
absents de develop) = 978, exactement le chiffre annoncé. Je le retiens comme probable mais pas
vérifié à la source.

**Est-ce que les 9 tests qui passent des deux côtés bornent réellement le correctif, ou passent-ils
par coïncidence ?** — **[déduit]**, vérifié un par un plutôt que supposé :
- « sr au-dessus du seuil — inchangé » et les deux tests du groupe « escalade — inchangée » (Encore,
  Utilise-moi) : ne sollicitent pas la logique `best` du tout (intense/`useMe` bypassent le clamp
  profondeur par un autre chemin, préexistant) — bornent le *non-changement* de ces chemins, pas le
  fix lui-même.
- « la sonde rend UN cran, pas le best : comfort=head reste borné à mid » et « best == comfort —
  no-op strict » : sur le code pré-fix, `maxDepthIndex = round(comfort).clamp(mid,full)` donne déjà
  `mid` dans les deux cas (le plancher pédagogique préexistant fait le travail, sans qu'aucune
  logique `best` intervienne) — passent trivialement des deux côtés pour la même raison structurelle,
  pas par coïncidence : ils **bornent la magnitude** du correctif (jamais plus d'un cran, jamais un
  no-op qui bouge) sans jamais exercer la branche qui a changé.
- « best < comfort (profil incohérent) — la sonde n'abaisse pas » : sur pré-fix, le cap vaut
  `comfort` (le code n'a jamais lu `best`) donc `best` y est simplement ignoré — passe trivialement
  côté ancien code parce que la régression que le garde-fou empêche n'existait pas encore *avant*
  d'introduire la logique `best`. Il **borne la non-régression**, il ne prouve pas le garde-fou lui-
  même (c'est le test unitaire `maxDepthIndexForProfile`, lui rouge sur l'ancien code, qui le prouve).
- Les 3 tests « non-régression des tenues » : exercent un mécanisme de gating entièrement disjoint
  (`milestoneHoldCeilingIdx`, jamais lu la logique `rhythmDepthMax`/`best`) — bornent l'absence
  d'effet de bord, sans jamais toucher le code modifié.

Verdict sur ce point : les 9 tests qui passent des deux côtés bornent effectivement des propriétés
réelles (magnitude, non-régression, étanchéité tenue/rythme) — aucun n'est un pass accidentel — mais
aucun n'exerce la ligne de code qui change de comportement. Seuls les 2 tests rouges pré-fix
discriminent vraiment le correctif ; c'est cohérent avec ce que le mécanisme prédit (cf. Piste 2b).

---

## Classification des constats

**Empêche la fusion : aucun.** Aucun défaut de comportement trouvé dans le mécanisme de sonde
lui-même, malgré une recherche adverse portant sur les bornes fractionnaires (preuve analytique +
large balayage empirique, détails piste 3), le cumul avec l'escalade intense, et l'atteignabilité de
l'état `best < comfort`.

**À corriger, ne bloque pas la fusion :**
1. **Le commentaire d'équivalence de `maxDepthIndexForProfile`** (`career_level_gates.dart`, piste 2b).
   Ce que la joueuse vivrait : rien directement — le comportement livré est correct. Le risque est pour
   la prochaine session qui touchera ce code : en croyant la reformulation « équivalente au `min`
   d'origine », un refactor la remplacerait par la forme littérale et réintroduirait la régression que
   `capability_clamps.dart` prend soin d'empêcher côté clamp. Preuve : le propre test de l'auteur,
   `cap(3,2)`, distingue les deux formules. Non bloquant.
2. **La portée de l'arbitrage « abandon sans effet visible »** (piste 7). Ce que la joueuse vivrait :
   rien de mesurable sur la profondeur de la séance suivante (confirmé identique bit à bit) — mais si
   le rapport ou une communication future généralise à « l'abandon n'a plus de conséquence », c'est
   inexact : le `successRate` de l'axe reste entamé, ce qui ralentit la capacité de l'axe à dépasser son
   record historique. Preuve : lecture de `CapabilityRegulator.regulate` (hors diff). Non bloquant —
   précision de formulation, pas de code.

**Piste ouverte, non tranchée (à garder à l'œil, pas à corriger en l'état) :**
- Le cumul intense + sonde qui peut en théorie viser un cran au-delà du `best` (piste 5) — neutralisé
  dans le scénario réaliste testé par le filet milestone, désynchronisation profil/milestone non
  vérifiée.
- **La chaîne séance → régulateur → séance suivante n'a jamais été simulée bout en bout, ni par
  l'auteur ni par cette relecture** (détail dans « Ce que je n'ai pas pu établir » ci-dessous). Le
  calcul rend la remontée du `comfort` vers le `best` possible ; personne n'a prouvé qu'elle se
  produit réellement, ni en combien de séances. C'est le point qui motive tout le correctif — il reste
  ouvert.

**Confort :**
- La description « chemin dominant » du mécanisme sous-jacent est imprécise (piste 1) — les chemins
  qui débordent réellement au tirage sont `buildRecovery` et `buildMiniWave`, pas la boucle
  d'échantillonnage principale. Sans conséquence sur la nécessité ou la correction du correctif.

## Ce que je n'ai pas pu établir

- **Si le code d'import de profil (debug) peut produire `best < comfort` en pratique** (piste 2a) — je
  n'ai pas lu ce code, hors périmètre du diff. C'est la seule porte que j'identifie vers l'état que le
  garde-fou `max(comfort, …)` protège ; je ne l'ai pas vérifiée à la source.
- **Si `rhythm.depth_max.best` (profil de capacités) et `UnlockKey.fullPulse`/`throatPulse` (milestones)
  peuvent désynchroniser** (piste 5) — deux systèmes de tracking distincts, code d'attribution des
  milestones non lu.
- **Le cas `unlockedKeys.isEmpty` pour un profil carrière portant une divergence `comfort`/`best`**
  (piste 4) — je juge cet état peu probable (il faut des milestones tôt pour accumuler la donnée qui
  produit la divergence) mais je ne l'ai pas formellement exclu.
- **La méthodologie exacte derrière le pourcentage annoncé par l'auteur** (piste 6, **[document]**) —
  je n'ai trouvé aucun document source, seulement le chiffre repris dans la consigne. **[mesuré]** ma
  remesure au grain step le corrobore (moins de 0,2 point d'écart) sans le reproduire à l'identique.
- **Ce qu'une joueuse ressent réellement** face à ce changement de rythme de progression — rien ici ne
  le mesure, ni le rapport source ni cette relecture.
- **La boucle complète séance → régulateur → séance suivante, sur plusieurs séances enchaînées.**
  **[document]** — j'ai trouvé et lu après coup le rapport original de l'auteur du correctif
  (`_bmad-output/implementation-artifacts/correction-du-verrou-de-profondeur-2026-08-18.md`, dépôt
  `auto-pump`) : il admet lui-même n'avoir jamais simulé cette boucle, seulement des profils figés
  injectés au générateur — donc n'avoir « pas prouvé le point qui motive le correctif : que le
  `comfort` remonte effectivement vers le `best` ». **[déduit]** Ni lui ni moi n'avons vérifié
  empiriquement que la remontée se produit réellement sur N séances. Le calcul l'ouvre (l'overshoot
  `reached(throat=3) >= comfort(mid=2)×1,02` est vrai dès la 1ʳᵉ séance où throat ressort) mais ne le
  garantit pas à lui seul : le ratchet ↑ pour un axe `depthCran` est **en plus** gaté par
  `successRate >= kDepthCranGate` (`capability_service.dart:348`), qui ne remonte que par EMA
  (`capability_service.dart:352`, poids 0,30) — donc potentiellement plusieurs séances réussies avant
  que `comfort` ne bouge effectivement, même une fois throat redevenu visible. Ni erreur ni preuve de
  défaut : une pacing non vérifiée par les deux relectures à ce jour.

## Verdict — ce correctif peut-il être fusionné en l'état ?

**Pour le code : oui.** Le mécanisme de sonde est correct au meilleur de ce que j'ai pu établir par
lecture exhaustive des deux chemins de gating (tirage et clamp), preuve analytique et balayage
empirique à grande échelle sur les bornes fractionnaires, et confirmation indépendante des chiffres
annoncés par l'auteur (saut de pourcentage, blocage à deux crans, non-régression des tenues sur la
surface que j'ai pu couvrir — chiffres exacts pistes 3, 4 et 6 ci-dessus).

**Avec réserves sur ce qui accompagne le code :** le commentaire d'équivalence de
`maxDepthIndexForProfile` (piste 2b) devrait être corrigé avant fusion — pas parce que le comportement
est faux, mais parce qu'il documente mal un garde-fou bien réel, avec un risque concret de régression
future si quelqu'un s'y fie. La formulation de l'arbitrage « abandon sans effet visible » (piste 7)
gagnerait à préciser sa portée avant d'être communiquée telle quelle.
