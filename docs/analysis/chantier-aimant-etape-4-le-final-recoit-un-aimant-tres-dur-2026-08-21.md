---
type: analyse
sujet: chantier-aimant-etape-4-le-final-recoit-un-aimant-tres-dur
ecrit_le: 2026-08-21T00:25:55+02:00
auteur: session tss2-aimant-explosion · claude-sonnet-5
revision: 75df1ef
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/final_picker.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_hold.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/capability_tracker.dart
  - rhythm_coach/lib/services/hold_verifier.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/beep_engine_hold_swing_test.dart
  - rhythm_coach/test/capability_tracker_test.dart
  - rhythm_coach/test/career_hold_final_anchor_placement_test.dart
  - rhythm_coach/test/career_rhythm_anchor_placement_test.dart
  - rhythm_coach/test/session_controller_hold_verifier_swing_test.dart
  - rhythm_coach/test/session_step_anchor_replay_test.dart
provenance:
  mesure: 10
  deduit: 0
  document: 0
  sans_marqueur: 3
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/career_level_gates.dart:113
  - rhythm_coach/lib/career/services/career_level_gates.dart:132
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2080
  - rhythm_coach/lib/career/services/generation/final_picker.dart:214
  - rhythm_coach/lib/career/services/generation/final_picker.dart:238
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:457
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:500
  - rhythm_coach/lib/career/services/generation/rules/career_session_generator_rules_hold.dart:249
  - rhythm_coach/lib/controllers/session_controller.dart:1384
  - rhythm_coach/lib/controllers/session_controller.dart:1444
  - rhythm_coach/lib/controllers/session_controller.dart:1607
  - rhythm_coach/lib/models/session_step.dart:119
  - rhythm_coach/lib/models/session_step.dart:36
  - rhythm_coach/lib/services/beep_engine.dart:399
  - rhythm_coach/lib/services/beep_engine.dart:463
  - rhythm_coach/lib/services/beep_engine.dart:591
  - rhythm_coach/lib/services/capability_tracker.dart:166
  - rhythm_coach/lib/services/capability_tracker.dart:413
  - rhythm_coach/lib/services/hold_verifier.dart:114
  - rhythm_coach/lib/widgets/movement_animation.dart:176
  - rhythm_coach/lib/widgets/movement_animation.dart:293
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 3 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

Waiver doc: les listes à puces (« Ce que je n'ai pas pu établir », « Questions ouvertes, pour Manu »)
et l'énumération numérotée des trois mutations — chacune placée sous une phrase d'introduction qui
porte déjà son propre marqueur, même convention que les rapports précédents de ce chantier.

## Le vocabulaire, rappel

Le mot de Manu **« final »** = le moment de l'explosion, porté dans le code par le `finisherDraft`
(`finish_phase.dart:emitFinalStep`). C'est de lui seul qu'il s'agit ici — ni le finish (la montée,
déjà ancré), ni le post-final (l'après, non touché).

## Ce que j'ai fait

**[mesuré]** Le final n'est jamais un step `rhythm` : `RhythmRules` ne déclare aucun `finalVariants`
(seule référence à `SessionMode.rhythm` dans `career_session_generator_rules_rhythm.dart:319`, côté
`postFinalVariants`, pour bloquer un post-final rhythm si le final l'était). Le final est `hold`,
`lick`, `hand`, `biffle` ou `beg` selon la palette (`final_picker.dart:pickFinal`). Périmètre confirmé :
seul un final `hold` peut recevoir l'ancre de cette étape.

**[mesuré]** J'ai ajouté à `CareerLevelGates` (`career_level_gates.dart`) :
- `holdFinalAnchorRatio = 9` et `holdFinalAnchorBpm = 60` — repris tels quels de l'illustration donnée
  à Manu (« à 60 bpm, ~1,8 s sur l'ancre contre ~0,2 s sur l'autre » ⇒ `2×60000/60 × 9/10 = 1800`,
  `2000-1800 = 200`, arithmétique vérifiée).
- `holdFinalAnchorEligible({level, to})` : `level >= rhythmAnchorToFloorLevel && to != null &&
  to.index > 0`. Je n'ai pas inventé un nouveau plancher — je réutilise `rhythmAnchorToFloorLevel`
  (10, posé à l'étape 3), parce que c'est la même restriction que Manu a posée et jamais levée :
  « l'ancrage au fond » reste hors de portée des profils débutants. Le final n'est qu'une deuxième
  source qui la consulte.

**[mesuré]** `_draftToStep` (dupliqué dans `career_session_generator.dart:2080` et
`finish_phase.dart:386`, même construction qu'à l'étape 3-bis) gagne une branche `hold` : si le draft
est `hold`, que l'appelant passe `intense: true`, et que `holdFinalAnchorEligible` répond vrai, le
step matérialisé porte `anchor: BeatAnchor.to`, `ratio: 9`, et **`bpm: 60`** — un hold n'a normalement
jamais de bpm (`HoldRules.build`/`finalVariants`/`buildRecovery` posent tous `bpm: null` ; vérifié en
lisant les 9 sites de construction de `StepDraft` mode hold). `emitFinalStep` passe désormais
`intense: true` inconditionnellement à son `emitStep` — sans risque pour les autres modes finaux
(lick/hand/biffle/beg), le gate ne réagit qu'à `rhythm` et `hold`.

**[mesuré]** `BeepEngine` (`beep_engine.dart`) : le `case SessionMode.hold` de `applyStep` bascule sur
`_startHoldSwingLoop(_to!)` quand `_anchor == BeatAnchor.to` (au lieu du one-shot habituel). Ce loop :
joue le one-shot d'arrivée (identique à avant — un hold non ancré ne change pas de rendu), puis
enchaîne **4** allers-retours (position un cran au-dessus de l'ancre ↔ l'ancre), cadencés par la même
arithmétique long/court que `_intervalAfter` (le court se déduit du long par soustraction — invariant
`2T` préservé), puis **s'arrête de lui-même** : aucun Timer résiduel, le hold redevient silencieux et
immobile pour le reste de sa durée — c'est le mécanisme qui fait qu'« on reste sur le hold normal »,
pas un flag qu'on retire.

**Décision de conception, pas neutre — je l'assume et je l'explique.** Je n'ai PAS fait porter le
swing par `_from`/`_to` globaux du moteur (qui restent égaux à la position tenue, exactement comme un
hold classique, pendant tout le step y compris pendant les swings). J'ai dupliqué la petite
arithmétique de `_intervalAfter` plutôt que de la réutiliser, précisément pour ça : `currentFrom`
(l'état que lisent les ticks stats/capacités) ne dévie jamais vers la position haute du swing. Deux
conséquences directes :
- Le swing n'émet **aucun** `BeatEvent` (pas d'`onBeat`/`beatStream`) — je n'ai donc touché ni
  `_stats.recordBeat`, ni `_stamina.onBeat`, ni les compteurs de défis qui s'y accrochent
  (`session_controller.dart:_handleBeat`, `_onChallengeBeatIfCrossingsTracked`). Le visuel
  (`MovementAnimation`) ne bouge donc pas non plus pendant les swings — cf. question ouverte plus bas.
- Les axes `hold.throat.streak`/`hold.full.streak` ne sont **pas** alimentés par `_beep.currentFrom`
  mais par `CapabilityTracker.onStepApplied(mode, from, to, bpm, duration)` — appelé une fois par step
  avec les valeurs **du `SessionStep`**, jamais l'état interne du moteur (`session_controller.dart:1607`,
  `capability_tracker.dart:413` `_ConfigState.heldPos = (mode==hold||beg) ? (to??from) : null`). Le
  swing ne touche à aucun de ces champs : l'alimentation continue à l'identique, par construction, pas
  par un correctif spécial.

**Test écrit, comme demandé — pas seulement une intention.** `capability_tracker_test.dart` : un hold
`to: full`/`to: throat` **avec `bpm: 60`** (la nouveauté — un hold n'avait jamais porté de bpm avant
cette étape) crédite `holdFullStreak`/`holdThroatStreak` seconde par seconde, exactement comme avant.
Le risque réel que ce test couvre : un code qui, quelque part, distinguerait implicitement « c'est un
hold » via `bpm == null` — il n'y en avait pas (vérifié en lisant `_ConfigState`/`onTickSecond`
entiers), mais c'est désormais un test, pas une lecture de code qui peut se périmer.

**Badge « Bouche pleine » (`recordFinalMode`).** Intact sans rien faire de spécial : `finalMode` reste
`SessionMode.hold` (je ne change que `anchor`/`ratio`/`bpm` du `SessionStep`, jamais le mode), et
`recordFinalMode(finalMode)` (`session_controller.dart:1864`) ne regarde que le mode.

**`HoldVerifier` — traité explicitement, un choix assumé.** J'ai extrait la décision d'armement en une
fonction pure testable, `SessionController.shouldArmHoldVerifier(step, defaultMode)` : elle refuse
d'armer un hold dont `anchor == BeatAnchor.to` (seul un final ancré porte cette valeur pour un hold).
**Choix retenu : ne pas armer du tout ce step**, plutôt que d'armer avec une tolérance. Raison : la
caméra vérifie l'immobilité *du step entier* — il n'existe pas de sous-découpage « les 4 premiers
allers-retours, puis la portion statique ». Armer avec tolérance aurait fallu soit ignorer la dérive
pendant toute la durée du hold (donc ne rien vérifier non plus sur la portion statique qui suit), soit
recoder un découpage temporel que l'architecture actuelle n'a pas. **Limite assumée, pas cachée** : la
portion statique après les 4 swings n'est donc pas non plus vérifiée par la caméra sur ce step précis —
cf. question ouverte.

## Ce qui prouve que ça tient — mesuré, pas déclaré

**[mesuré]** `flutter analyze` (depuis `rhythm_coach/`) : **« No issues found! »**.
**[mesuré]** `dart format --set-exit-if-changed lib test` : **0 fichier changé**.
**[mesuré]** `flutter test` (jamais pipé — sortie dans un fichier, lue ensuite) : **1055 tests, tous
verts** (`+1055`, `All tests passed!`, exit 0). Base avant ce chantier (rapport étape 3-bis + 3 commits
depuis) : 1041. Delta = +14, qui se décompose exactement : 13 tests neufs dans 3 nouveaux fichiers +
1 nouveau test dans `capability_tracker_test.dart`, + 1 test ajouté après le round de mutation
ci-dessous (le compte matché avant/après, vérifié par moi-même, pas recopié).

**[mesuré]** Un test préexistant a cassé au premier passage et je l'ai corrigé, pas contourné :
`session_step_anchor_replay_test.dart` affirmait `expect(s.ratio, 3, ...)` pour **tout** step ancré
après un rebase — vrai tant que seul `rhythm` s'ancrait (ratio 3 fixe), faux dès qu'un final `hold`
s'ancre (ratio 9). Corrigé pour attendre le ratio spécifique au mode. C'est le signal que le
changement touche une vraie invariante préexistante, pas un artefact de mon ajout.

**[mesuré] Trois mutations, comme demandé, chacune restaurée après coup :**
1. Neutralisé le plancher de niveau dans `holdFinalAnchorEligible` (`to != null && to.index > 0`
   seul, sans le `level >=`) → rouge exactement sur les deux bonnes assertions : le test unitaire
   (`sous le plancher, même profond`, `Expected: false / Actual: true`) et le balayage générateur
   (`sawNotAnchored` resté faux — plus aucun final bas niveau n'échappait à l'ancre dans l'échantillon).
2. Mis `_holdFinalAnchorSwings` à `0` → rouge sur le test qui exerce la **valeur par défaut**
   (`Expected: <8> / Actual: <0>`) — j'ai dû l'ajouter en cours de route : mes tests initiaux
   passaient tous `swings:` explicitement, aucun n'exerçait la valeur réellement consommée par
   `_startHoldSwingLoop` en production. Corrigé avant de conclure, pas après.
3. Inversé `!=` en `==` dans `shouldArmHoldVerifier` → rouge sur les 3 assertions concernées
   (`Expected: true/false` inversés exactement là où attendu).

Aucune des trois mutations n'a laissé un test vert par accident, et aucune assertion finale n'est un
vague `greaterThan(0)`.

**[mesuré]** Compatibilité : `session_step_anchor_compat_test.dart` (20 assets JSON + 37 paliers) —
vert, et hors de portée de ce chantier par construction : il ne lit que les JSON statiques et le
défaut du constructeur, jamais le générateur.

## Ce que je n'ai pas pu établir

- **Le ressenti à l'oreille.** Rien n'a sonné pendant ce développement (consigne du projet) : ni le
  ratio 9, ni le bpm 60, ni le fait que 4 allers-retours (~8 s à 60 bpm) « sente » juste avant que la
  tenue se fige. Jugement qui appartient à Manu seul.
- **Le rendu visuel des swings.** Je n'ai délibérément pas fait passer le swing par `BeatEvent`/
  `MovementAnimation` (cf. décision de conception ci-dessus) : la joueuse entend les 4 allers-retours
  mais ne les voit pas bouger sur le curseur (qui reste sur `_StaticPosition`, pulsé à ~1,8 s comme
  n'importe quel hold). Si Manu veut le visuel synchronisé, c'est un chantier à part — brancher un
  `BeatEvent` sur le swing sans laisser fuiter la position haute vers `currentFrom`/les stats demande
  un canal séparé (un `BeatEvent` qui ne notifie que l'UI, pas les compteurs).
- **Le comportement pause/reprise en plein swing.** Mettre en pause pendant les allers-retours arrête
  le Timer (comme tout loop du moteur) ; à la reprise, `resume()` ne relance rien pour `hold` (comme
  aujourd'hui pour tout hold — commentaire existant « rien à reprendre »). Le swing interrompu ne
  reprend pas : le hold redevient simplement silencieux, comme s'il avait fini ses allers-retours plus
  tôt que prévu. Pas testé en pratique (pas de harnais de test qui pilote `pause()` sur ce chemin).

## Questions ouvertes, pour Manu

1. **La force exacte (ratio 9, bpm 60).** Reprise telle quelle de l'illustration qu'on t'a montrée —
   jamais validée à l'oreille par toi sur ce final précis. Ratio différent, bpm différent : à trancher
   en écoutant.
2. **La seconde position du swing.** J'ai choisi « un cran au-dessus de l'ancre » (`to.index - 1`) —
   la lecture la plus naturelle vu qu'une tenue n'a qu'une position aujourd'hui. Pas mesuré à l'oreille
   si un cran suffit à « se sentir » ou si ça casse la tenue au contraire.
3. **Le compte de swings.** Fixé à 4 (le haut de ta fourchette « 3 ou 4 »), en dur côté moteur de
   lecture — pas tiré au hasard entre les deux. Si tu veux de la variété (parfois 3, parfois 4), c'est
   un paramètre RNG à faire descendre depuis le générateur, pas encore fait.
4. **Les autres tenues longues.** Cette étape ne touche QUE le final. Ta dernière parole porte
   dessus, mais tu as aussi dit ailleurs « micro-mouvement sur les tenues longues seulement » — sans
   trancher, je n'ai pas généralisé. Question posée, pas décidée par moi.
5. **La portion statique du final après les swings n'est plus vérifiée par la caméra** (cf. limite
   assumée de `HoldVerifier` ci-dessus) — seulement sur ce step précis, seulement quand il est ancré.
   Acceptable, ou faut-il un mécanisme de réarmement à mi-step ?
