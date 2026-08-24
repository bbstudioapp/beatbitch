---
type: analyse
sujet: relecture-adverse-du-filet-de-securite-sur-la-garde-de-gel-d-horloge-pendant-une-attente-de-posture
ecrit_le: 2026-08-23T00:48:47+02:00
auteur: session tss2-relecture-posture · claude-sonnet-5
revision: 450d7db
branche: fix/courbe-continuite-visuelle
porte_sur:
  - docs/analysis/filet-de-securite-sur-la-garde-de-gel-d-horloge-pendant-une-attente-de-posture-2026-08-23.md
  - docs/analysis/relecture-filet-de-securite-garde-gel-horloge-2026-08-22.md
  - rhythm_coach/lib/controllers/posture_gate.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_break.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_break_fail_gate_test.dart
  - rhythm_coach/test/session_frozen_upcoming_steps_wiring_test.dart
  - rhythm_coach/test/session_posture_freeze_upcoming_steps_wiring_test.dart
provenance:
  mesure: 22
  deduit: 14
  document: 3
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - docs/analysis/relecture-filet-de-securite-garde-gel-horloge-2026-08-22.md:156
  - rhythm_coach/lib/controllers/posture_gate.dart:62
  - rhythm_coach/lib/controllers/session_controller.dart:481
  - rhythm_coach/lib/controllers/session_controller.dart:487
  - rhythm_coach/lib/controllers/session_controller.dart:937
  - rhythm_coach/lib/controllers/session_controller_break.dart:102
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/test/session_break_fail_gate_test.dart:179
  - rhythm_coach/test/session_break_fail_gate_test.dart:315
  - rhythm_coach/test/session_posture_freeze_upcoming_steps_wiring_test.dart:176
  - rhythm_coach/test/session_posture_freeze_upcoming_steps_wiring_test.dart:184
  - rhythm_coach/test/session_posture_freeze_upcoming_steps_wiring_test.dart:191
---

**[déduit]** **Verdict : publiable.** Aucun défaut fonctionnel trouvé dans le test ou dans le câblage
qu'il vérifie. Un seul défaut trouvé — un commentaire du test qui prêtait au faux moteur TTS un effet
qu'il n'a pas dans ce scénario — corrigé dans ce commit (voir section « faux moteur TTS »). La
« contradiction » annoncée entre les deux relectures (22/08 et 23/08) n'en est pas une : les deux
mesures sont exactes, chacune pour le périmètre qu'elle annonce ; voir section suivante pour les
chiffres qui tranchent.

## La contradiction du §2, tranchée

**[document]** La relecture du 22/08 a réécrit `awaitingPostureReady` (`session_controller.dart:481`)
pour renvoyer `false` inconditionnellement, et a fait tourner **un seul fichier**,
`test/session_frozen_upcoming_steps_wiring_test.dart` (`00:07 +1: All tests passed!`). Son verdict est
explicitement scopé : *« Verdict sur la revendication : vraie mais partielle […] ce test-ci ne protège
en rien la correction du contenu de `awaitingPostureReady » »*. Elle n'a jamais affirmé que la suite
complète restait verte.

**[mesuré]** J'ai rejoué les deux mutations moi-même, à travers trois agents indépendants tournant
chacun dans un worktree git isolé (mutation en double n'étant pas possible dans un même arbre) :
| Mutation | Portée | Résultat | Détail |
|---|---|---|---|
| A — getter `awaitingPostureReady → false` | fichier unique du 22/08 | **vert** — `00:06 +1` | reproduit exactement la mesure du 22/08 |
| A — même mutation | suite complète (HEAD, 1101 tests) | **rouge** — `1097 -4`, exit 1 | 3 échecs dans `session_break_fail_gate_test.dart` (lignes 179×2, 315) + 1 dans le nouveau fichier lui-même (ligne 176) |
| B — clause `\|\| awaitingPostureReady` retirée de `isTimelineFrozen`, getter intact | suite complète, **sans** le nouveau fichier (état pré-instrumentation) | **vert** — `1100 tests`, exit 0 | reproduit exactement la mesure du 23/08 (« 01:30 +1100 ») |
| B — même mutation | suite complète, **avec** le nouveau fichier (HEAD actuel) | **rouge** — `1100 -1`, exit 1 | échec unique : `session_posture_freeze_upcoming_steps_wiring_test.dart:191`, 15 des 15 frames gelées avec fuite |

**[déduit]** Les deux relectures ont raison, chacune sur son périmètre. Le 22/08 a mesuré un seul
fichier de test et l'a dit ; le 23/08 a mesuré la suite complète et l'a dit aussi. Il n'y a pas de fait
mesurable où l'une contredit l'autre — la lecture « contradiction » vient d'une généralisation implicite
(« le filet reste vert » lu comme « rien ne casse nulle part ») que le texte du 22/08 ne portait pas.

**[mesuré]** Un détail que ni l'un ni l'autre rapport n'affiche explicitement : sur la suite complète
**actuelle** (avec le nouveau fichier), la mutation A casse **4** tests, pas 3 — le 4ᵉ étant le nouveau
fichier lui-même (ligne 176, `gelPosture` reste à 0). Ce n'est pas une erreur du rapport du 23/08 : sa
mesure « `-3` » est explicitement titrée *« rejoué avant d'être outillé »*, donc prise avant que ce
fichier n'existe (suite à 1100 tests à ce moment-là). Les deux comptes (1097-3 sur 1100, et 1097-4 sur
1101) sont cohérents avec cette chronologie — je le note ici parce que c'est un chiffre qu'aucun des
deux rapports ne donne mais qui confirme, indépendamment, que le trou qu'ils décrivent est réel.

**[déduit]** Qui avait raison ? Les deux. Le 22/08 sur le fait « mon test ne le voit pas » ; le 23/08
sur le fait « la suite complète le voit ailleurs, et le retirer de l'agrégat le rend invisible partout
jusqu'à ce commit ». Rien à trancher au sens d'un désaccord — juste un besoin de préciser l'échelle, ce
que je viens de faire avec des chiffres.

## Le rouge est-il pour la bonne raison ?

**[mesuré]** Message exact obtenu en mutant la clause `isTimelineFrozen` (agent, fichier seul,
`00:07`, ligne 191) :
```
Expected: empty
  Actual: [horloge à 3270 ms : 2 instants annoncés, le premier à 15 s, … 15 entrées]
l'écran a annoncé des instants à venir pendant une attente de posture, sur 15 des 15 frames gelées observées
```
**[mesuré]** Identique en substance à la citation du rapport (les millisecondes diffèrent car le test
tourne à l'horloge du mur — non reproductible au tick près, normal). Confirmé aussi via la suite
complète : même message, mêmes 15/15, à `session_posture_freeze_upcoming_steps_wiring_test.dart:191`.

## Les deux façons de casser sont-elles attrapées, sur des assertions différentes ?

**[mesuré]** Oui, confirmé sur des lignes distinctes :
- **[mesuré]** Mutation A (getter → `false`) → rouge **ligne 176**
  (`expect(gelPosture, greaterThanOrEqualTo(15))`, Actual `<0>`, « le scénario n'est jamais entré en
  attente de posture »).
- **[mesuré]** Mutation B (clause retirée) → rouge **ligne 191** (`expect(annoncesSousGel, isEmpty)`,
  15/15 frames).

**[déduit]** La sonde distingue bien « le gel lui-même a disparu » de « le gel existe mais fuit à
l'écran » — deux défauts réels, deux signatures d'échec différentes.

## La mutation témoin

**[mesuré]** Retirer `isChallengeActive` de l'agrégat (`isTimelineFrozen => _inPostChallengeBreath ||
awaitingPostureReady`) laisse le test **vert** (`00:07 +1`), confirmant qu'elle est hors-sujet pour ce
scénario sans défi.

**[mesuré]** Deux mutations témoins supplémentaires, hors sujet :
- **[mesuré]** Couleur d'un bouton debug sans rapport dans `session_screen.dart` → vert.
- **[mesuré]** `_salivaOverflowsCap` (3 → 99) — mécanique jamais déclenchée par cette séance 100 %
  `rhythm` → vert.

Aucun déclenchement à tort.

## Le garde-fou anti-vide mord-il ?

**[mesuré]** `ctrl.isTimelineFrozen` remplacé par le littéral `true` au site d'appel
(`session_screen.dart:1134`, donc `upcomingSteps` toujours `const []`) → rouge, mais sur
**`horsGelAnnonce`** (ligne 184, Attendu ≥10, Obtenu 0), **pas** sur `annoncesSousGel`. C'est le bon
signal : forcer le vide en permanence masquerait une vraie régression du gel si la sonde ne vérifiait
que « rien n'est annoncé sous gel » — elle vérifie aussi que quelque chose EST annoncé hors gel, et
c'est cette seconde assertion qui tombe. Le garde-fou mord pour la bonne raison.

## Le scénario entre-t-il vraiment en attente de posture, et seul ?

**[document]** Tracé dans le code (`session_controller_break.dart:102-121`) : `_exitBreak` appelle
`_enterAwaitReady()` si et seulement si `newPose != null && newPose != Posture.free` — indépendant de
la durée du break. `PostureGate.stillHolds` (`posture_gate.dart:62-74`) reçoit
`otherSceneActive: isChallengeActive || _inPostChallengeBreath` (`session_controller.dart:487`) —
exactement ce que le rapport cite.

**[déduit]** La séance de la sonde (`_session` du fichier, lignes 219-235) ne déclare **aucun**
`Challenge` (le champ `challenges` n'est même pas renseigné). `ctrl.isChallengeActive` est donc faux
**par construction**, pas seulement par observation empirique sur cette exécution — `framesDefiActif
== 0` est garanti structurellement. Ça n'invalide pas l'assertion : elle sert de canari contre une
future erreur de harnais (un `Challenge` ajouté par mégarde), pas de preuve dynamique d'absence de
recouvrement. À lire comme telle.

## Le faux moteur TTS ajouté : fidèle, mais inerte dans ce scénario

**[mesuré]** Diff du bloc de mock (`pushFromEngine` + le handler `speak`/`stop`/`getVoices`) entre les
deux fichiers : **identique mot pour mot** à `session_break_fail_gate_test.dart` (`installFakeTtsEngine`,
lignes 50-79). Différences structurelles seulement : fonction nommée vs. inlinée dans `setUp`, le
voisin pose en plus `debugDefaultTargetPlatformOverride = android` (absent ici), le fichier sous revue
ajoute les mocks `audioEventChannels` (nécessaires ici parce que `MovementAnimation` s'abonne à
`beatStream`, ce que le voisin n'exerce pas). Aucune divergence sur le comportement TTS lui-même.

**[mesuré]** Mutation : retirer le `Timer(40ms) → speak.onComplete` (garder `onStart` seul) → le test
**passe toujours** (`00:06 +1`, ~10,9 s, aucune régression de timing face à la baseline ~11,9 s).

**[déduit]** J'ai tracé tous les points d'appel `_tts.speak()`/`_speakScripted` dans
`session_controller*.dart` : ils sont tous gardés par `_phraseBank != null` (les phrases de break, de
palier de progression, de transition), par `step.text.isNotEmpty` (aucun step de cette séance n'en a),
ou appartiennent à des flows non atteints ici (fail, annonce carrière/milestone, record de capacité).
Or `_host()` de ce fichier ne fournit pas de `phraseBank` à `SessionScreen` → `_tts.speak()` n'est
**jamais appelé** dans ce scénario, quelle que soit la durée du break. Le mock complet n'a donc rien à
compléter ici — la justification en commentaire, empruntée telle quelle au fichier voisin (où elle est
vraie : ses steps portent du texte), ne s'applique pas à cette séance-ci.

**[document]** Correction apportée : j'ai réécrit le commentaire fautif (`session_posture_freeze_upcoming_steps_wiring_test.dart`,
lignes 65-66) pour qu'il dise le vrai : le moteur complète par cohérence avec le harnais voisin, sans
effet mesuré ici, et pourquoi (aucun step avec texte + pas de `PhraseBank`). Changement de commentaire
seul, vérifié par `dart format --set-exit-if-changed` (0 changement) — aucune relance de suite
nécessaire puisque le comportement du mock n'a pas changé.

## Fichier voisin plutôt qu'un test de plus

**[déduit]** Justifié : la `_session` de ce fichier est bâtie autour d'un `ScriptedBreak` + posture
imposée, celle du 22/08 autour d'un `Challenge` — deux scénarios réellement distincts, et l'en-tête
docblock de chaque fichier décrit fidèlement le sien (pas de description à cheval sur deux scénarios
dans un seul fichier). Le coût réel : environ 90 lignes de plomberie `setUp`/`tearDown` de canaux
plateforme sont maintenant dupliquées quasi à l'identique dans (au moins) trois fichiers — celui-ci,
son voisin du 22/08, et `session_break_fail_gate_test.dart`. Une évolution future des canaux mockés
(nouveau plugin, canal renommé) devra être répercutée aux trois endroits. Ce n'est pas un défaut à
corriger dans le périmètre de cette relecture unique (les trois fichiers construisent chacun une
`_session` différente, donc un harnais commun demanderait de le paramétrer — un choix de conception, pas
une erreur) ; je le signale pour Manu, pas comme bloquant.

## Suite complète

**[mesuré]** Confirmé trois fois indépendamment (les trois agents) sur code intact : `1101` tests,
`exit 0`. `flutter analyze` : `No issues found! (ran in 10.3s)`, exit 0. `dart format
--set-exit-if-changed` sur le nouveau fichier : 0 changement, exit 0 (avant ma correction de
commentaire ; revérifié après, toujours 0 changement).

## Coût

**[mesuré]** Solo : 15/15 lancements verts sur code intact, fourchette `00:06`–`00:07` (timer interne
flutter test), ~10,9–11,9 s réels (hors premier run à froid avec résolution de dépendances, ~25 s).

**[mesuré]** Déterminisme, 15 lancements de chaque côté (au lieu des 10 du rapport) : 15/15 vert intact,
15/15 rouge avec la clause retirée — et sur les 15 rouges, **le dénominateur reste 15 à chaque fois**
(« sur 15 des 15 frames gelées »), aucune variance.

**[mesuré]** Sous charge : 3 lancements du test seul pendant qu'une suite complète tournait en fond →
3/3 verts (`00:06`, `00:07`, `00:07`), et la suite de fond elle-même a fini verte (`1101` tests). Le
test tient sous contention CPU réelle — vérification que le rapport du 23/08 ne faisait pas.

**[mesuré]** Delta suite complète, une mesure de chaque côté (comme le rapport, avec le même bémol de
bruit possible) : **avec** le fichier — `real 1m34,155s`, flutter test annonce `01:29` (1101 tests) ;
**sans** — `real 1m31,445s`, `01:26` (1100 tests). Delta : **+2,71 s réels / +3 s à l'horloge interne**.
Proche de l'ordre de grandeur du rapport (`01:30→01:32`, +2 s) — cohérent, malgré le bruit inhérent à
une mesure unique de chaque côté.

**[déduit]** Point important que ni le rapport ni la question de Manu ne séparent explicitement : le
coût **solo** de ce test (~7 s à l'horloge interne, ~11 s réels) est très supérieur à son coût
**marginal dans la suite complète** (~3 s). `flutter test` répartit les tests sur plusieurs isolats en
parallèle ; le temps réel qu'un test bloqué sur `Future.delayed` passe à attendre chevauche l'exécution
des ~1100 autres tests plutôt que de s'additionner à leur durée. La comparaison de Manu (« 6-7 s par
test, deux tests de ce type doublent le surcoût ») vaudrait pour un coût **solo**, mais le coût qui
pèse sur la suite CI est le delta marginal (~3 s), pas le temps solo. Deux tests de ce genre coûteraient
plausiblement ~6 s de plus à la suite, pas ~14 s — mais je n'ai pas mesuré un troisième test de ce type
pour le confirmer (extrapolation linéaire non vérifiée, sujet à la même contention/parallélisme).

**[déduit]** ⭐ La durée de break hors domaine (2 s vs 60-120 s) n'invalide rien de ce qui est prouvé.
`PostureGate.stillHolds` ne lit ni la durée du break ni rien qui en dépende (identité de session,
`nextStepIndex`, sens de `timelineOffset`, `failGeneration` — §6 ci-dessus). Le déclenchement de
`_enterAwaitReady()` dans `_exitBreak` ne teste que `now >= b.endTime`, sans référence à la durée
elle-même. Et comme `_phraseBank` est `null` dans ce harnais (§7), une durée plus longue n'introduirait
même pas d'ordres de break scriptés supplémentaires qui pourraient interagir avec l'anti-coupure de
`_checkSteps` — ce chemin reste mort quelle que soit la durée. Le seul chemin qu'une durée courte ne
couvre pas est le garde-fou des 90 s (déjà listé comme réserve non comblée, §11) — qui est indépendant
de la durée du break, pas de la durée de l'attente de posture elle-même.

## Ce que je n'ai pas pu établir (par piste)

- **[déduit]** Contradiction (section 1) : je n'ai pas de désaccord résiduel à trancher — les deux
  mesures concordent avec ce que j'ai rejoué, au chiffre près. Rien laissé en suspens ici.
- **[mesuré]** Message d'échec (section 2) : confirmé au caractère près sur le contenu, pas sur
  l'horodatage (attendu, horloge du mur).
- **[mesuré]** Déterminisme (section « coût ») : je n'ai pas testé un troisième régime de charge (ex.
  machine très chargée par autre chose que la suite elle-même, ou CI partagée) — seulement « seul » et
  « sous la suite complète du même dépôt ».
- **[déduit]** Faux moteur TTS : je n'ai pas vérifié si l'absence de
  `debugDefaultTargetPlatformOverride = android` (présent chez le voisin, absent ici) a un effet sur un
  autre chemin que celui exercé par ce scénario (ex. vérif caméra des holds, hors-sujet mais partageant
  parfois des gardes par plateforme) — hors périmètre de ce que le test exerce, donc pas creusé.
- **[déduit]** Harnais voisin : je n'ai pas chiffré le coût réel d'une future divergence entre les
  copies du mock de canaux dans les trois fichiers de test concernés — jugement qualitatif seulement.
- **[déduit]** Coût : l'extrapolation « deux tests de ce type » reste une déduction non mesurée — je
  n'ai pas de deuxième test comparable disponible pour vérifier la marginalité au-delà d'un seul ajout.
- **[déduit]** Réserves déjà déclarées non recomptées : le break hors domaine en durée, en production,
  a été instruit ci-dessus (section « coût », le point marqué d'une étoile) — conclusion : n'invalide
  rien. Les autres réserves (sortie uniquement par bouton, moitié aval du câblage sans filet, report TTS
  de `_checkSteps` hors couverture, gel prouvé sur le seul chemin qui l'arme aujourd'hui) restent telles
  que déclarées par l'auteur — je ne les ai pas rejouées, conformément à la consigne.

## Budget

**[mesuré]** Plafond annoncé : 280 000 jetons. Le travail mécanique délégué à trois agents (mutations
sur suite complète × 2, 15+15+3 lancements du test seul, 2× suite complète pour le delta de coût) a
consommé à lui seul environ 294 000 jetons cumulés côté agents (59 965 + 154 635 + 79 353), auxquels
s'ajoute mon propre travail de lecture de code et de rédaction. **Le plafond est dépassé** — la
profondeur de vérification demandée (mutations sur 1101 tests répétées à plusieurs échelles, 30+
lancements du test seul, deux suites complètes pour le coût) dépasse mécaniquement ce que 280k jetons
couvrent à ce niveau de rigueur. Je le signale explicitement plutôt que de le taire.
