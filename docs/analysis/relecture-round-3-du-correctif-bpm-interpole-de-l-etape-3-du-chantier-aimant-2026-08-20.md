---
type: analyse
sujet: relecture-round-3-du-correctif-bpm-interpole-de-l-etape-3-du-chantier-aimant
ecrit_le: 2026-08-20T23:01:47+02:00
auteur: session tss2-aimant-e3-round3 · claude-opus-5
revision: ffce2ca
branche: feat/aimant-battement-inegal
porte_sur:
  - docs/analysis/chantier-aimant-round-2-reserves-1-et-2-de-la-relecture-2026-08-20.md
  - rhythm_coach/lib/career/models/custom_session_config.dart
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/models/session.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/surprise_router.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/movement_animation_future_beats_test.dart
provenance:
  mesure: 22
  deduit: 11
  document: 1
  sans_marqueur: 7
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/models/custom_session_config.dart:250
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart:188
  - rhythm_coach/lib/career/services/career_level_gates.dart:132
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2086
  - rhythm_coach/lib/controllers/session_controller.dart:790
  - rhythm_coach/lib/models/session.dart:226
  - rhythm_coach/lib/models/session_step.dart:152
  - rhythm_coach/lib/services/beep_engine.dart:386
  - rhythm_coach/lib/services/beep_engine.dart:556
  - rhythm_coach/lib/services/beep_engine.dart:591
  - rhythm_coach/lib/services/beep_engine.dart:699
  - rhythm_coach/lib/services/beep_engine.dart:995
  - rhythm_coach/lib/services/surprise_router.dart:140
  - rhythm_coach/lib/widgets/movement_animation.dart:106
  - rhythm_coach/lib/widgets/movement_animation.dart:281
  - rhythm_coach/lib/widgets/movement_animation.dart:387
  - rhythm_coach/lib/widgets/movement_animation.dart:584
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 7 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

**[déduit]** Waiver doc: les lignes des six tableaux (complément minimum, écart d'arrondi par bande,
mutations, recomptage des familles JSON, ancre par difficulté Custom, réserves) qui portent un chiffre
sans marqueur de provenance — chacune est placée sous une phrase d'introduction qui porte déjà le
sien, même convention que les deux rapports précédents de ce chantier.

## Verdict

**Publiable avec réserves.** **[mesuré]** Le diff du round 2 (`a9fa8a5` + `ebb1ca9`) ne déplace aucun
comportement hors des steps à rampe : `flutter analyze` propre, `dart format` propre, **1039 tests
verts** en 91 s. **[mesuré]** Aucun complément négatif ne subsiste sur tout le domaine jouable. **[mesuré]**
Les trois chiffres de l'erratum (125 / 43 / 12) sont exacts, recomptés indépendamment.

**[mesuré]** Une seule réserve gênante : **le correctif côté widget n'est tenu par aucun test** — en
lui rendant son code d'avant, les 1039 tests restent verts. **[déduit]** Trois réserves non gênantes :
un arrondi résiduel introduit par le correctif, le périmètre Custom et Surprise que le round 2 ne
chiffre pas, et un défaut préexistant croisé hors périmètre (fiché au sas, pas traité ici).

**[déduit]** Aucun défaut fonctionnel neuf dans le comportement livré. Deux rounds de même signature
sans défaut fonctionnel : la suite relève du polissage, sauf la réserve 1, qui n'est pas du polissage
mais une absence de filet — déjà déclarée par le round 2 lui-même.

## Piste 1 — ce qui bouge hors des steps à rampe

**[mesuré]** Rien. Le fil complet, remonté site par site :

- `_PositionLadder.bpm` n'alimente que `complementaryBeatIntervalMs` — aucun autre usage dans la
  classe.
- Hors rampe, `_currentInterpolatedBpm` retourne `_bpm.toDouble()` quand `_bpmEnd` ou
  `_loopDurationMs` est `null` ; `widget.bpm` vaut `ctrl.currentBpm` → `BeepEngine.currentBpm` → ce
  même `_bpm`, déjà clampé aux mêmes bornes. Le `.round()` du correctif redonne donc exactement la
  valeur d'avant.
- Modes non rythmés : `_PositionLadder` n'est pas construit (le `switch` ne l'instancie que pour
  rhythm / lick / hand).
- Biffle : `_notifyBeat` porte bien le nouveau champ, mais `_onBeatEvent` n'écrit `_lastBeatBpm` que
  dans la branche rhythm / lick / hand — la branche biffle ne touche que le contrôleur d'animation.
- `BeatEvent` n'a **qu'un** site de construction (`beep_engine.dart:699`) et deux consommateurs :
  `movement_animation` via `beatStream`, et `StaminaEngine.onBeat` via
  `session_controller.dart:790` — ce dernier ignore le nouveau champ.
- Reprise après échec : la punition passe par `generatePunishment` → `punishment_builder`, hors
  périmètre ancré ; `_restorePreviousLoop` réapplique le step d'origine via `applyStep`, donc avec
  son ancre et sa rampe réarmées depuis zéro.
- Défis : les trois écritures de `_bpm` hors `applyStep` sont les démos (`startRhythmDemo`,
  `startLickDemo`, `startBiffleDemo`), pas un chemin de défi.

**[mesuré]** Une précision sur le périmètre annoncé, qui joue en faveur du correctif : le message de
`a9fa8a5` dit « sous rampe ancrée », mais le défaut corrigé touchait **toute** rampe. Sur une rampe
80 → 160 sans ancrage, la courbe alternait 375 ms et 1125 ms alors que l'intervalle réel vaut 375 ms
partout ; après correctif, 375 et 375. Le corps du rapport round 2 annonce d'ailleurs le bon
périmètre (« aucun changement de comportement en dehors des steps à rampe ») — c'est le titre du
commit qui sous-vend.

**Ce que je n'ai pas pu établir** : que la boucle réelle rapporte le bon BPM en production. Tous les
tests du chantier passent par `emitOneBeatForTest(bpm)`, qui court-circuite `_currentInterpolatedBpm`
en injectant le BPM à la main. La chaîne `_startBeatLoop` → `_currentInterpolatedBpm` →
`_emitPositionBeat` n'est exercée par aucun test. **[déduit]** Limite héritée de l'étape 2, pas
introduite par le round 2 : `movement_animation_bpm_ramp_test` utilisait déjà la même sonde.

## Piste 2 — le complément peut-il encore être négatif

**[mesuré]** Non, sur tout le domaine jouable. Balayage exécuté contre le vrai code — `_intervalAfter`
appelé via `emitOneBeatForTest`, puis `complementaryBeatIntervalMs` nourri de `BeatEvent.bpm` — pour
`bpm` de 20,00 à 300,00 par pas de 0,05, ancres `from` / `to` / `none`, aux deux positions de
l'alternance :

| domaine du ratio | complément minimum | cas |
|---|---|---|
| production (`1` ou `3`) | **99 ms** | ancre `to`, ratio 3, 298,5 bpm |
| jusqu'à 40 (hors production) | **3 ms** | ancre `to`, ratio 40, 20,5 bpm |

**[mesuré]** Le ratio de production vaut toujours 3 (`CareerLevelGates.rhythmAnchorDefaultRatio`, seule
valeur écrite par les deux `_draftToStep`) ou 1 (défaut du constructeur et du parsing JSON) ; aucun
fichier d'`assets/` ne porte de clé `anchor` ou `ratio`. **[déduit]** Il faudrait un ratio supérieur à
39 pour repasser sous zéro — le rapport entre l'intervalle long et le cycle nominal devrait alors
dépasser l'erreur d'arrondi du BPM, ce que ratio 3 (0,75) laisse très loin.

**[mesuré]** Ce que le balayage a trouvé à la place : le correctif introduit un arrondi. `BeatEvent.bpm`
est un `double`, `_PositionLadder.bpm` reste un `int` — le `.round()` du call site perd la partie
fractionnaire du BPM interpolé. Écart entre le complément peint et le vrai intervalle suivant :

| bande de BPM | écart relatif maximal |
|---|---|
| 20 – 40 | 9,6 % |
| 40 – 180 | 4,9 % |
| 180 – 300 | 1,6 % |

**[mesuré]** Nul hors rampe, puisque le BPM interpolé y est déjà entier. **[déduit]** Réserve non
gênante : avant le correctif, l'écart dans ce même domaine atteignait 200 % (le cas 375 / 1125
ci-dessus). Le résidu se lèverait en typant `_PositionLadder.bpm` et le paramètre de
`complementaryBeatIntervalMs` en `num` — trois lignes, mais je ne l'ai pas fait : c'est une signature
`@visibleForTesting` partagée avec deux autres tests, et rien ne la couvre côté widget (cf. piste 3).

**[mesuré]** Cas de bord examiné et écarté : `didUpdateWidget` ne compare que `mode`, `bpm` et
`from`/`to`, donc deux steps consécutifs identiques sur ces trois axes ne remettent pas `_lastBeatBpm`
à `null` — le BPM de fin de rampe du step précédent survivrait au suivant. Mais `_startBeatLoop`
appelle `tick()` immédiatement, donc le premier `BeatEvent` du nouveau step recale le champ dès le
démarrage. **[déduit]** Fenêtre d'erreur de l'ordre d'un frame, non exploitable. Le fallback
`?? widget.bpm` est lui inatteignable pour un effet observable : `_lastBeatBpm` et `_lastBeatAt` sont
toujours écrits et remis à zéro ensemble, et `_computeFutureBeats` rend une liste vide dès que
`_lastBeatAt` est `null`.

## Piste 3 — le test du round 2 discrimine-t-il

**[mesuré]** À moitié. Trois mutations, suite complète ou fichier ciblé :

| mutation | résultat |
|---|---|
| **M1** — `bpm: widget.bpm` rendu à `_PositionLadder` (tout le changement widget annulé) | **1039 tests verts, aucun rouge** |
| **M2** — `_notifyBeat(…, _bpm.toDouble())` au lieu de `currentBpm` | rouge sur `expect(lastEvent.bpm, 50.0)`, `Actual: <60.0>` |
| **M3** — `_intervalAfter` renvoie toujours l'intervalle régulier | rouge sur `expect(paintedWithInterpolatedBpm, 600)`, `Actual: <1200>` |

**[mesuré]** M2 et M3 tombent sur la bonne assertion, avec le bon message d'échec, sans erreur de
compilation. M1 ne tombe nulle part : **le seul changement visible à l'écran n'est tenu par rien**.
C'est la cinquième occurrence de cette signature sur le chantier.

**[document]** Le rapport round 2 déclare cette limite en toutes lettres, marquée `[déduit]` : le fil
`_lastBeatBpm` → `_PositionLadder.bpm` → `complementaryBeatIntervalMs` est « vérifié par lecture du
code, pas par un test ». **[mesuré]** Mais le titre du test annonçait « le complément **peint** reste
positif » alors que le test appelle la brique pure et ne peint rien — et citait « cas 81→58 » quand il
joue 80→50. Corrigé ici, commit `ffce2ca`, libellé seul.

**[mesuré]** Renversement de défaut : ce test n'appuie aucune assertion sur un défaut de constructeur —
`anchor` et `ratio` sont passés explicitement à `configureBeatSourceForTest`, le BPM explicitement à
`emitOneBeatForTest`. M2 révèle au passage que `_bpm` conserve son défaut `60` (jamais écrit par la
sonde), mais aucune assertion n'en dépend en code sain.

**[mesuré]** Une assertion du test ne discrimine rien : sous M3, `expect(paintedWithMountBpm,
lessThan(0))` reste verte (−450 ms). Elle prouve que le défaut existait sous rampe descendante
suffisante, **pas** qu'il tenait à l'ancrage — ce qui recoupe exactement le constat de la piste 1 : le
défaut n'était pas propre aux steps ancrés.

## Piste 4 — l'erratum dit-il vrai

**[mesuré]** Oui, sur le fond comme sur les chiffres. Recomptage indépendant, en répliquant la règle de
résolution du contrôleur (`step.mode ?? session.defaultMode`) et en excluant `isTextOnly` selon sa
vraie définition (les quatre champs `from`, `to`, `bpm`, `mode` nuls) :

| source | résultat | annoncé par le round 2 |
|---|---|---|
| `assets/sessions/*.json` (20 fichiers) | 107 explicites + 18 hérités = **125** | 125 |
| `assets/career/milestones.json` | **43** | 43 |
| `assets/punishments*.json` (4 fichiers) | 3 × 4 = **12** | 12 |

**[mesuré]** Deux vérifications que le round 2 ne mentionne pas et qui auraient pu invalider le compte :
aucun `chainAction` rythmé non text-only dans `assets/sessions/` — le comptage à plat ne rate donc rien
de ce côté ; et `assets/sessions/` porte exactement 129 steps text-only résolus en rythme, ce qui
reconstitue le 254 du premier passage (125 + 129). **[mesuré]** Le repli de `Session.fromJson` est bien
`json['mode']` avec défaut `'rhythm'`, et aucun fichier d'`assets/` ne porte de clé `anchor` ou `ratio`.

**[déduit]** Sur le fond de la réserve 2 : l'erratum a raison contre le rapport d'étape 3. Le seul
critère des deux `_draftToStep` est `draft.mode == SessionMode.rhythm`, sans distinction de méthode
appelante — les six méthodes de `RhythmRules` sont donc bien ancrées.

## Piste 5 — ce que le mécanisme donne en Custom, et en Surprise

**[mesuré]** Custom appelle `CareerSessionGenerator().generate(level: cfg.resolveVirtualLevel(…))`
(`custom_mode_screen.dart:188`) : tous ses steps rythmés passent par le même `_draftToStep`, donc
tous sont ancrés au ratio 3. Le niveau virtuel décide de la variante :

| difficulté Custom | niveau de base | ancre |
|---|---|---|
| facile | 2 | `from` |
| normal | 6 | `from` |
| difficile | 11 | `to` dès que le BPM du step atteint 100 |
| extrême | 18 | `to` dès que le BPM du step atteint 100 |

**[mesuré]** En non-stop progressif, le niveau monte de 2 par cycle (capé à +12) : « normal » franchit
le seuil de 10 au cycle 2, « facile » au cycle 4. **[déduit]** Concrètement, un joueur qui règle Custom
sur « difficile » reçoit la variante `to` — celle que la carrière réserve au niveau 10 — sans l'avoir
demandée ni traversée.

**[mesuré]** Le **mode Surprise** est dans le même cas et n'est mentionné ni par le rapport d'étape 3
ni par celui du round 2 : `surprise_router.dart:140` appelle le même `generate` avec
`level: bundle.synthLevel`. L'écran de debug de scénarios également.

**[déduit]** Rien à trancher ici — c'est le prolongement direct de l'effet de bord assumé du partage de
`generate()`, et la décision appartient à Manu. Ce qui manque au dossier, c'est le chiffre : ni Custom
ni Surprise n'apparaissent dans le périmètre annoncé par le round 2.

## Réserves

| # | réserve | gênante |
|---|---|---|
| 1 | Le correctif côté widget n'est tenu par aucun test : M1 laisse 1039 tests verts. Ce qui est prouvé, c'est `BeatEvent.bpm` et la brique pure, pas le fil qui les relie à l'écran. | **oui** |
| 2 | Arrondi `double` → `int` au passage du BPM au widget : jusqu'à 9,6 % d'écart sous 40 bpm, 4,9 % entre 40 et 180. Nul hors rampe, et bien meilleur qu'avant le correctif. | non |
| 3 | Les modes Custom et Surprise héritent de l'ancrage, avec la variante `to` dès « difficile ». Ni chiffré ni testé par le round 2. Décision de Manu. | non |
| 4 | Les trois démos de bip ne remettent pas `_bpmEnd` / `_loopDurationMs` à `null` : une démo lancée après un step à rampe hérite de la rampe. Défaut préexistant (`5336d56`, 2026-05-06), hors périmètre — fiché au sas `2026-08-20-demos-heritent-rampe-bpm.md`, non traité ici. | non |

## Ce que je n'ai pas pu établir

- Que la boucle de production rapporte le BPM interpolé attendu : toutes les sondes injectent le BPM
  à la main, `_currentInterpolatedBpm` n'est exercé par aucun test.
- Qu'un complément négatif soit impossible **par construction** : je l'ai établi par balayage sur le
  domaine jouable et sur les ratios réellement écrits, pas par une preuve sur la formule.
- Que le défaut du sas soit atteignable : je n'ai pas vérifié si l'écran de démo partage l'instance
  de `BeepEngine` avec la session.
- L'effet visuel réel des 9,6 % d'écart d'arrondi sous 40 bpm : je n'ai mesuré que le chiffre, pas ce
  que la courbe donne à l'œil.
