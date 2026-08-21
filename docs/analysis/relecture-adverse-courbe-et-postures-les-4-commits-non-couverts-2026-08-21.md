---
type: analyse
sujet: relecture-adverse-courbe-et-postures-les-4-commits-non-couverts
ecrit_le: 2026-08-21T20:01:20+02:00
auteur: session tss2-relecture-courbe-fin · claude-sonnet-5
revision: 4f92c0c
branche: fix/courbe-continuite-visuelle
porte_sur:
  - /home/emmanuel/.claude/orchestration/sas/tss2/awaitready-perdu-aux-rebases-de-timeline.md
  - rhythm_coach/lib/career/models/level_milestone.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/controllers/posture_gate.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_challenge.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/movement_animation_step_serial_test.dart
  - rhythm_coach/test/movement_animation_transition_widget_test.dart
  - rhythm_coach/test/posture_await_ready_rebase_test.dart
provenance:
  mesure: 12
  deduit: 8
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - /home/emmanuel/.claude/orchestration/sas/tss2/awaitready-perdu-aux-rebases-de-timeline.md
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:1629-1693
  - rhythm_coach/lib/controllers/posture_gate.dart
  - rhythm_coach/lib/controllers/session_controller.dart:1341-1382
  - rhythm_coach/lib/controllers/session_controller.dart:1513-1560
  - rhythm_coach/lib/controllers/session_controller.dart:2086-2200
  - rhythm_coach/lib/controllers/session_controller.dart:925-936
  - rhythm_coach/lib/controllers/session_controller_challenge.dart:974-1006
  - rhythm_coach/lib/models/session_step.dart:36-234
  - rhythm_coach/lib/screens/session_screen.dart:1118-1153
  - rhythm_coach/lib/services/beep_engine.dart:360-370
  - rhythm_coach/lib/services/beep_engine.dart:880-891
  - rhythm_coach/lib/widgets/movement_animation.dart:190-237
---

## Périmètre effectivement relu

**[mesuré]** Diff rejoué : `git diff 0b618a5..4f92c0c -- ':!docs'` — 9 fichiers, 284 insertions,
48 suppressions, conforme au tableau de la consigne. Les deux commits de documentation intercalés
(`921685f`, `aa36394`) ne touchent aucun fichier de ce diff — hors périmètre confirmé.

**[mesuré]** Rejoué moi-même depuis `rhythm_coach/` : `flutter pub get` (OK, 65 paquets ont une
version plus récente disponible, sans rapport), `timeout 300 flutter analyze` → *No issues found!*
(3.7 s), `timeout 900 flutter test` (sortie redirigée vers fichier, jamais pipée) → **1056 tests,
`All tests passed!`, exit code 0**. Rejoué une seconde fois après restauration des trois mutations
ci-dessous pour confirmer que l'arbre de travail était revenu à l'identique (`diff` fichier par
fichier + `git status --short` vide) : `flutter analyze` de nouveau *No issues found!*.

## Réserve 1 — `isTimelineFrozen` : vrai pour les trois conditions qu'il nomme, faux comme garantie générale

**[mesuré]** `_onTick` (ligne 1380) appelle littéralement `isTimelineFrozen` — ce n'est plus une
expression dupliquée mais le même appel de méthode des deux côtés (`session_controller.dart:935-936`
et `:1380`). Sur les trois conditions que le getter nomme (`isChallengeActive`,
`_inPostChallengeBreath`, `awaitingPostureReady`), aucune divergence n'est possible par construction :
il n'y a qu'un seul endroit où l'expression est écrite.

**[déduit]** Mais le commentaire du getter va plus loin (« c'est la même expression qui gèle et qui
répond ici, pour que les deux ne puissent pas diverger ») — une garantie générale de non-divergence
entre « l'horloge est gelée » et « le getter le dit ». Cette garantie est fausse : `grep
"_timelineOffset -= _tickInterval"` sur `session_controller.dart` trouve **deux** sites, pas un.
Le second, dans `_checkSteps` (ligne 1558), décrémente `_timelineOffset` pour différer un step dont
le texte chevauche un TTS en cours (« anti-coupure des phrases random »), jusqu'à
`_maxTtsDeferTicks = 25 × _tickInterval (200 ms) = 5 s`. Ce site est **préexistant** au diff relu —
`git show 0b618a5:...` le montre déjà présent en ligne 1549 avant les quatre commits — donc ni
introduit ni corrigé par `22a6cd8`. Pendant cette fenêtre de différé, l'horloge de séance est bel et
bien gelée (le stopwatch réel avance, `_timelineOffset` compense) sans qu'aucune des trois conditions
de `isTimelineFrozen` ne soit vraie : c'est le chemin demandé par la consigne, « l'horloge gelée sans
que le getter le dise ».

**[déduit]** `posture_gate.dart` (fichier non touché par ce diff) nomme explicitement ce second site
dans sa propre documentation — « un gel ne fait que le décrémenter (un tick par battement, **comme le
report TTS**) » (ligne 49) — donc l'auteur du mécanisme de gel de posture avait connaissance de ce
chemin analogue avant même `22a6cd8`. Le comparateur `stillHolds` (`timelineOffset >
this.timelineOffset`) n'y est pas sensible : un décrément, quelle qu'en soit la source, ne fait jamais
tomber le gel de posture. Ce n'est donc pas une régression du gel de posture lui-même — seulement du
périmètre que `isTimelineFrozen` prétend couvrir.

**[déduit]** Impact sur `session_screen.dart:1128` (la seule consommatrice de `isTimelineFrozen`) :
je n'ai **pas** pu établir de scénario où le différé TTS ferait afficher un contenu faux. Contrairement
au défi (qui remplace `session.steps` par des segments produits en direct, hors de la liste), le
différé TTS ne substitue rien — les mêmes steps restent en attente, et la compensation
`_timelineOffset` garde leur distance en temps-de-séance exacte : à la reprise, le prochain step
arrive exactement à l'instant qu'affichait `upcomingSteps` pendant le gel. Je n'ai construit aucun
instant où l'annonce serait objectivement fausse pendant ce différé — seulement constaté que
l'affirmation « ne peuvent pas diverger » du commentaire est inexacte au sens strict.

## Réserve 2 — `_pushMilestoneSequence` : confirmé, `awaitReady` recopié, `chainAction`/`background` perdus

**[mesuré]** `career_session_generator.dart:1653-1663` construit chaque `SessionStep` de la séquence
milestone champ à champ : `time, text, mode, bpm, from, to, duration, swallowMode, awaitReady` —
`chainAction` et `background` ne figurent pas dans l'appel. `LevelMilestone.sequence` est bien typé
`List<SessionStep>` (`level_milestone.dart:47`), donc un step de séquence *pourrait* porter ces deux
champs ; s'il en portait, ils seraient perdus au passage dans `ctx.steps.add(...)`.

**[mesuré]** `grep -c "chainAction\|background" assets/career/milestones.json` → 0. Aucune milestone
actuelle n'exploite ce chemin — le défaut est réel mais dormant dans le contenu livré aujourd'hui.

**[document]** Ce constat recoupe exactement la fiche déjà présente dans le sas
(`~/.claude/orchestration/sas/tss2/awaitready-perdu-aux-rebases-de-timeline.md`, verdict CONFIRMÉ
2026-08-21 contre `4f92c0c`), qui note « recopie bien `awaitReady` mais laisse tomber `chainAction`
et `background` » et précise que ce 4ᵉ site n'est pas traité par ce commit. Conforme à la consigne :
non corrigé, pas de nouvelle fiche déposée (celle-ci existe déjà et porte le bon verdict).

## Réserve 3 — câblage `stepSerial` : le pur est testé, le câblage moteur → écran ne l'est pas

**[mesuré]** `grep -rln "stepSerial" test/ lib/` : le symbole n'apparaît en test que dans
`movement_animation_step_serial_test.dart`, qui construit `MovementAnimation` directement et lui
passe `stepSerial` comme entier littéral — aucun chemin de ce test ne passe par `BeepEngine` ni par
`session_screen.dart`.

Table mutation → sonde (fichiers restaurés après chaque essai, `diff` + `git status --short` vérifiés
propres) :

| Sonde | Mutation appliquée | Résultat |
|---|---|---|
| `movement_animation_step_serial_test.dart` | `movement_animation.dart:213` : `stepReapplied` figé à `false` | **[mesuré] ROUGE** — `Expected: <0.5>, Actual: ...` sur l'assertion de bridge au gap |
| `movement_animation_transition_widget_test.dart` | même mutation | **[mesuré] VERTE** — sans rapport, ce test ne varie jamais `stepSerial` |
| Suite complète (1056 tests, incl. les deux tests ci-dessus) | `beep_engine.dart:362` : `_stepSerial++` commenté (le compteur reste bloqué à 0 pour toute la session) | **[mesuré] VERTE partout** — `All tests passed!`, exit 0 |

**[déduit]** La première ligne établit que la logique interne du widget (comparer
`oldWidget.stepSerial` à `widget.stepSerial` pour déclencher le pont vers `to`) est réellement
exercée — pas un test qui passerait quoi qu'il arrive. La troisième ligne établit l'inverse pour le
câblage amont : si le compteur du moteur ne bougeait plus jamais (bug total de `BeepEngine`),
**aucun** des 1056 tests ne le remarquerait — ni un test dédié à `BeepEngine.stepSerial`, ni un test
de `session_screen.dart` qui vérifierait `stepSerial: widget.beep.stepSerial` (ligne 1128).

**[déduit]** Par lecture, le câblage semble correct : `_stepSerial++` s'exécute pour tout step
`!isTextOnly` appliqué (y compris les réapplications à configuration identique, cas visé par
`b2ec4fe`), et `session_screen.dart:1128` relit `widget.beep.stepSerial` à chaque `build()` — donc à
chaque `notifyListeners()` qui suit un `applyStep`. Je n'ai pas trouvé de chemin où `applyStep`
s'exécuterait sans qu'un `notifyListeners()` ultérieur ne rafraîchisse l'écran avant le prochain step.
Mais c'est une lecture, pas une mesure : le grep ci-dessus confirme qu'aucune sonde ne peut le
contredire aujourd'hui si ce raisonnement s'avérait faux.

## Lecture adverse du reste du diff

**[mesuré]** Les trois sites de rebase (`buildUpgradedSession`, `buildPostChallengeRegenSession`,
`session_controller_challenge.dart:1004` dans `_excisChallengeFromSession`) passent tous par
`SessionStep.rebased`. `rebased()` recopie explicitement les 11 champs du constructeur — vérifié par
mutation propre : `awaitReady` forcé à `false` dans `rebased()` fait tomber rouge les 3 tests de
`posture_await_ready_rebase_test.dart` (« la posture doit survivre au rebase / à la régénération »,
`Expected: length 1, Actual: []`), fichier restauré ensuite. Je rejoue ici moi-même la mesure déjà
revendiquée par la fiche du sas plutôt que de la reprendre telle quelle.

**[mesuré]** `toJson()` (`session_step.dart:207-220`) sérialise les 11 mêmes champs (y compris
`awaitReady` en ligne 219, conditionnel à `true`) — le test « rebased ne perd aucun champ » (comparant
`toJson()` avant/après moins `time`) est donc un garde-fou réel pour tout champ futur : un champ ajouté
au constructeur sans être ajouté à `toJson()` échapperait à ce test, mais un champ ajouté aux deux
et oublié dans `rebased()` serait attrapé.

**[déduit]** `stepReapplied` (nouvelle condition dans `didUpdateWidget`) est un simple `||` ajouté aux
trois conditions existantes (`modeChanged || tempoChanged || positionChanged`) — il ne peut pas
supprimer de comportement déjà déclenché par les trois autres, seulement en ajouter. Aucune régression
trouvée sur ce point par lecture des quatre branches du booléen.

**[déduit]** `session_screen.dart:1128` — le remplacement de `ctrl.isChallengeActive` par
`ctrl.isTimelineFrozen` **élargit** la fenêtre où `upcomingSteps` est vidée (défi seul → défi + breath
post-défi + attente posture). Ça ne peut pas faire réapparaître une annonce qui était déjà supprimée
avant ; ça peut en supprimer de nouvelles, pendant l'attente de posture et le breath post-défi — c'est
exactement l'intention du commit et cohérent avec le comportement de `_onTick`, qui gèle l'horloge
sur les trois mêmes conditions.

## Ce que je n'ai pas pu établir

- **Impact réel du différé TTS sur `isTimelineFrozen`** (réserve 1) : j'ai établi que le chemin de
  divergence existe et qu'il est antérieur à ce diff, mais pas qu'il produit un affichage
  objectivement faux — la compensation d'horloge semble le neutraliser en pratique, sans que j'aie pu
  le vérifier à l'exécution (aucun test ne monte `SessionScreen` avec un TTS mocké en cours de
  différé pendant que `MovementAnimation` est au premier plan).
- **Si un step de séquence milestone future utilisera un jour `chainAction`/`background`** (réserve
  2) : le défaut est confirmé par lecture, dormant dans le contenu actuel — je n'ai pas cherché du
  côté du générateur procédural si un chemin construit dynamiquement un `mStep` avec ces champs
  renseignés avant de le pousser dans `milestone.sequence`.
- **Le câblage `stepSerial` en conditions réelles** (réserve 3) : établi qu'aucun test ne le couvre,
  pas qu'il est cassé — je n'ai pas monté `SessionScreen` complet avec un `BeepEngine` réel pour
  observer le compteur traverser jusqu'au widget à l'exécution.
- **[déduit]** **Les 25 autres commits de la branche** (`develop..0b618a5`) : hors périmètre de cette
  relecture, non rejoués ici — la relecture précédente
  (`relecture-adverse-courbe-config-identique-2026-08-21.md`) les couvre.

## Verdict

**Publiable avec réserves.**

`flutter analyze` et `flutter test` sont verts sur `HEAD` (`4f92c0c`), mesurés par moi-même. Les trois
sites de rebase perdant `awaitReady` (défaut réel, préexistant, confirmé par une session antérieure)
sont effectivement corrigés et gardés par une sonde qui tombe rouge à la bonne raison sous mutation.
La détection du gap de transition sur step réappliqué (`b2ec4fe`) est elle aussi gardée par une sonde
qui tombe rouge à la bonne raison.

Trois réserves, aucune ne bloque à mon sens la publication :
1. Le commentaire du getter `isTimelineFrozen` affirme une garantie de non-divergence qui est fausse
   au sens strict (un second site de gel d'horloge existe, préexistant, hors de son périmètre) — sans
   impact démontré sur l'affichage, mais le commentaire devrait être corrigé pour ne pas sur-promettre.
2. `_pushMilestoneSequence` perd `chainAction`/`background` — confirmé, dormant, déjà tracé dans le
   sas, à ne pas corriger ici par consigne explicite.
3. **[mesuré]** Le câblage `BeepEngine.stepSerial → session_screen.dart → MovementAnimation` n'est
   vérifié par aucune sonde à l'exécution — seule la fonction pure du widget l'est. Une mutation qui
   bloque le compteur du moteur à 0 laisse les 1056 tests verts.
