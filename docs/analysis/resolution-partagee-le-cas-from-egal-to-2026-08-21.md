# Étape 3 de la timeline unique — le cas `from == to` reste hors de la fonction pure

*Session du 2026-08-21, branche `fix/courbe-continuite-visuelle`. L'extraction demandée par
l'étape 3 est livrée (commits `ec27f8f` et `6dcdd2c`) ; ce document ne traite que le point laissé
ouvert : le relèvement aléatoire de `from` quand `from == to`. Aucune ligne n'a été écrite pour
ce point — c'est une décision de Manu.*

**Provenance** : **[mesuré]** = lu ou exécuté par cette session dans le dépôt à `6dcdd2c`.
**[déduit]** = raisonnement à partir de ce qui précède, non rejoué en séance.

## Ce qui est déjà unifié

**[mesuré]** `lib/services/step_resolution.dart` (`resolveStepConfig`) porte désormais la règle
« mode / bpm / from / to de ce step, sachant la configuration courante ». `BeepEngine.applyStep`
et `resolveUpcomingMovementSteps` l'appellent tous les deux au lieu de la réécrire chacun.
26 tests de caractérisation figent le comportement du moteur, écrits et verts **avant** l'extraction,
et rouges sur cinq mutations de la règle.

**[mesuré]** Un seul comportement change dans cette extraction : le résolveur d'affichage clampe
maintenant le BPM à `[20, 300]` comme le moteur le faisait déjà. Aucune source de contenu mesurée ne
sort de ces bornes (assets JSON scannés, mode Custom borné à 30-220 par
`CustomSessionConfig.minBpmLimit`/`maxBpmLimit`, défis clampés à `kMinBpm`/`kMaxBpm` avant
construction du step) — le clamp est donc un no-op sur le contenu d'aujourd'hui, et un alignement de
l'affichage sur le son si un contenu futur sortait des bornes.

## Le point ouvert

**[mesuré]** `beep_engine.dart:400-405` : en `rhythm` ou `lick`, si le `from` résolu est égal à `to`,
le moteur remplace `from` par une position tirée **au hasard** strictement plus aiguë
(`_pickShallowerThan`, ligne ~600, `Random` non seedé). L'affichage ne peut pas deviner ce tirage :
il n'a pas eu lieu quand la courbe annonce le step.

**[mesuré]** Conséquence sur la courbe : `movement_animation.dart:857` alterne par
`nextPos = (nextPos == segFrom) ? segTo : segFrom` — avec `segFrom == segTo`, la position ne bouge
jamais. La portion de courbe annonçant un tel step est **plate**, alors que le son alternera pour de
vrai une fois le step démarré.

### Combien de fois, et où

**[mesuré]** Génération procédurale : **0 occurrence** sur 600 séances générées (niveaux 1 à 15,
40 graines par niveau, humiliation 0 à 32), soit 59 827 steps de mouvement résolus. Le corps généré
d'une séance ne produit jamais ce cas. Ce chiffre recoupe celui de
`relecture-adverse-continuite-de-trajectoire-2026-08-20.md` (0 sur 1000 séances).

**[mesuré]** Contenu écrit à la main : 10 emplacements distincts, tous atteignables en jeu normal.

| Contenu | Step | Mode | `from == to` | Candidats du tirage |
|---|---|---|---|---|
| `milestones.json` — `intro_hold_mid` | t=38 | lick | head | 1 (`tip`) |
| `milestones.json` — `intro_biffle` | t=28 | lick | head | 1 (`tip`) |
| `milestones.json` — `intro_encore` | t=10 | lick | head | 1 (`tip`) |
| `milestones.json` — `intro_hold_full` | t=44 | lick | head | 1 (`tip`) |
| `milestones.json` — `intro_full_pulse` | t=40 | lick | head | 1 (`tip`) |
| `milestones.json` — `intro_surprise_notifs` | t=10 | lick | head | 1 (`tip`) |
| `punishments*.json` — `rapid_full` (4 langues) | t=0 | rhythm | full | 4 |
| `session_advanced_demo_orig.json` | t=0 | rhythm | head | 1 (`tip`) |
| `session_advanced_demo_ps1.json` | t=0 | rhythm | head | 1 (`tip`) |
| `session_advanced_demo_ps1.json` | t=210 | rhythm | throat | 3 |

**[mesuré]** Les séquences de milestone sont recopiées dans `session.steps`
(`career_session_generator.dart:1653`) : ces six steps passent donc bien par le résolveur
d'affichage et sont annoncés comme plateaux.

**[déduit]** Les steps à `t=0` ne sont presque jamais *annoncés* : le résolveur écarte
`step.time <= elapsedSeconds`, et à `t=0` le step est déjà le step courant, dont la position vient
de `currentFrom` — donc post-tirage, donc juste. Le défaut visible se réduit en pratique aux six
milestones `intro_*` (chacune jouée une fois en début de carrière) et au step t=210 de
`session_advanced_demo_ps1`.

## Les trois issues

### A — laisser le tirage dans le moteur et l'assumer

C'est l'état livré aujourd'hui : `resolveStepConfig` s'arrête avant le relèvement, `applyStep` le
fait juste après l'appel, l'affichage ne le fait pas.

- **Ce que la joueuse entend** : **rien de différent**. Le son n'est pas touché.
- **Ce qu'elle voit** : le plateau annoncé à tort sur les emplacements ci-dessus reste.
- **Coût** : zéro. Mais la promesse « une seule implémentation de la règle » comporte une exception,
  et une exception est ce qui a permis à cette divergence-ci d'exister.

*Variante à un cran, si Manu veut du visible sans toucher au son* : **ne rien annoncer plutôt
qu'annoncer faux** — le résolveur signale ces steps comme indécis et la courbe ne trace rien pour
eux, comme elle ne trace déjà rien quand l'horloge de séance est gelée (`d25b80b`). Ça ne remplace
pas une décision sur les trois issues, ça borne juste le mensonge en attendant.

### B — rendre le tirage déterministe des deux côtés

Dériver `from` d'une clé que l'affichage connaît aussi (index du step, `step.time`, mode, `to`)
plutôt que de `Random`.

- **Ce que la joueuse entend** : **ça change**. Le `from` joué cesse d'être tiré à chaque
  application : la même punition, le même step de démo sonneraient toujours pareil.
  **[mesuré]** L'effet est nul sur 8 des 10 emplacements (un seul candidat possible, `tip` ou
  équivalent — le tirage y est déjà déterministe de fait), et réel sur 2 : `rapid_full`
  (`full/full`, 4 candidats) et `session_advanced_demo_ps1` t=210 (`throat/throat`, 3 candidats).
- **Coût** : moyen. Mais **[mesuré]** la clé la plus naturelle, `step.time`, est mutable en cours de
  séance : `session_controller_challenge.dart` décale tous les `time` des steps futurs après un défi.
  Une clé qui bouge fait que l'annonce d'avant le défi ne correspond plus au tirage d'après — la
  détermination serait vraie entre deux régénérations seulement, pas dans l'absolu.
- **[déduit]** C'est la seule issue qui rend la courbe **exacte** sur ces steps, et la seule qui
  échange une variation audio contre cette exactitude.

### C — le moteur porte le résultat, l'affichage le lit

- **[mesuré]** Pour le step **courant**, c'est déjà le cas : l'affichage lit `currentFrom`, qui est
  post-tirage. Cette issue ne corrige donc rien du défaut, qui ne concerne que les steps **à venir**.
- Pour qu'un step à venir ait un résultat lisible, il faut que le moteur tire **avant** de
  l'appliquer, c'est-à-dire au moment où la timeline se construit. **[déduit]** Le tirage passe alors
  de « une fois par application » à « une fois par régénération de timeline » : sans mémoriser le
  résultat par step, un même step à venir serait re-tiré à chaque régénération et la courbe
  changerait d'annonce sans qu'aucun beat n'ait sonné — le symptôme même que l'étape 1 vient de
  supprimer.
- **Ce que la joueuse entend** : **rien de différent**, à condition que le tirage mémorisé soit bien
  celui que le moteur consomme ensuite. Si les deux se désynchronisent, elle entend un `from` que la
  courbe n'a pas annoncé — la divergence d'aujourd'hui, mais silencieuse.
- **Coût** : le plus élevé des trois. Il faut un cache de tirages tenu par le moteur, indexé par une
  identité de step stable à travers les recompositions de défi, et consulté par l'affichage. C'est
  de l'état partagé de plus, à l'opposé de la fonction pure que cette étape installe.

## Recommandation

**A**, pour maintenant. C'est la seule des trois qui garantit zéro changement audible sans ajouter
d'état partagé, et le défaut qu'elle laisse est borné : six milestones d'introduction jouées une
fois chacune, plus un step d'un scénario de démo. **[déduit]** B est le bon choix le jour où Manu
juge que l'exactitude de la courbe vaut la perte de variation sur `rapid_full` — c'est un arbitrage
de contenu, pas de code. C est à écarter : elle coûte le plus cher et son seul gain sur A est de
faire disparaître l'exception, au prix de réintroduire l'état partagé que ce chantier retire.

**[déduit]** Une quatrième voie existe et ne demande aucune décision de conception : corriger le
**contenu**. Un `lick head/head` n'a de sens que parce que le moteur relève `from` ; écrit
`lick tip→head`, il dit la même chose au son et n'a plus rien d'ambigu pour la courbe. Six des dix
emplacements sont des milestones qu'on peut réécrire à la main.
