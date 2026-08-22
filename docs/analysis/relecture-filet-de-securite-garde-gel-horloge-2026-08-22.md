---
type: analyse
sujet: relecture-filet-de-securite-garde-gel-horloge
ecrit_le: 2026-08-22T23:32:03+02:00
auteur: session tss2-relecture-filet · claude-sonnet-5
revision: f825160
branche: fix/courbe-continuite-visuelle
porte_sur:
  - docs/analysis/filet-de-securite-sur-la-garde-de-gel-d-horloge-apres-un-defi-2026-08-22.md
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/lib/widgets/movement_trajectory_forecast.dart
  - rhythm_coach/test/session_finished_duration_render_test.dart
  - rhythm_coach/test/session_frozen_upcoming_steps_wiring_test.dart
provenance:
  mesure: 18
  deduit: 6
  document: 1
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:481
  - rhythm_coach/lib/controllers/session_controller.dart:937
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/test/session_finished_duration_render_test.dart:1
  - rhythm_coach/test/session_frozen_upcoming_steps_wiring_test.dart:162
---

## Verdict

**[déduit]** **Publiable.** Le test tombe pour la bonne raison, sur la bonne ligne, rejoue la régression exacte
qu'il prétend garder, résiste à des mutations hors sujet, et son garde-fou de contrôle fonctionne. Une
réserve mérite d'être reformulée plutôt que reprise telle quelle (cf. § « Transitivité »), et une
question de fond — reste-t-il vrai que 6 s de temps réel par exécution valent le coup — reste à
trancher par Manu, pas par cette relecture.

## 1. Le rouge tombe-t-il pour la bonne raison ? [mesuré]

Garde retirée à la main (`session_screen.dart:1134`, ternaire supprimée en gardant l'appel à
`resolveUpcomingMovementSteps`), `flutter test test/session_frozen_upcoming_steps_wiring_test.dart`
tombe systématiquement sur `test.dart:162` (`expect(annoncesSousGel, isEmpty)`), jamais sur un
timeout, un `MissingPluginException`, ou un seuil de traversée. Message reproduit à l'identique de
celui du rapport :

```
l'écran a annoncé des instants à venir alors que l'horloge de séance était gelée, sur 30 des 30
frames gelées observées : horloge à 1896 ms (défi actif : true) : 3 instants annoncés, le premier à
2 s | ...
```

**[mesuré]** Les deux fenêtres du gel (`défi actif : true` et `défi actif : false`) apparaissent bien dans la liste
des 30 frames en échec — la garde retirée fait fuiter les annonces pendant le défi **et** après lui,
ce qui est le comportement attendu d'une garde totalement absente.

## 2. Le test tient-il la bonne ligne, la bonne relation ? [mesuré] + [déduit]

**[document]** La lecture du code confirme que `session_screen.dart:1134` appelle littéralement
`ctrl.isTimelineFrozen` — pas une copie de l'expression, pas un flag dérivé stocké ailleurs. Le test
lit la même expression au même instant (`ctrl.isTimelineFrozen` via `Provider.of`) que la propriété
`upcomingSteps` effectivement reçue par le `MovementAnimation` monté (`tester.widget<MovementAnimation>`),
les deux dans le même passage de la boucle, après un seul `tester.pump()` — donc sur la même frame
reconstruite. **[déduit]** Cette synchronisation est une garantie structurelle du framework de test
(un `pump()` reconstruit tout l'arbre de manière synchrone avant de rendre la main), pas quelque chose
qu'une mutation peut démontrer isolément.

**[mesuré]** Mutation témoin hors sujet : `bpm: ctrl.currentBpm` remplacé par `bpm: 999` dans l'appel à
`MovementAnimation` (aucun rapport avec `upcomingSteps`). Le test reste vert (`00:07 +1: All tests
passed!`) — il ne tombe pas pour n'importe quel changement du bloc `MovementAnimation`, seulement pour
celui qui touche la relation gel ↔ instants à venir.

**[mesuré]** Mutation témoin dans le résolveur : `resolveUpcomingMovementSteps` forcé à toujours
renvoyer `[]` (donc plus aucune annonce, gel ou pas). Le test tombe, mais **pas** sur la même
assertion : `test.dart:159` (`expect(horsGelAnnonce, greaterThanOrEqualTo(1))`), message « hors gel,
cette séance doit annoncer des instants à venir ; sans cela le vide observé sous gel ne prouverait
rien ». C'est la preuve directe que le test discrimine bien un vide voulu (la garde qui marche) d'un
vide qui ne prouverait rien (une séance rendue silencieuse par ailleurs) — cf. §6 pour le détail de ce
compteur de contrôle.

## 3. La régression exacte du 21/08 fait-elle tomber le test ? [mesuré]

**[mesuré]** Garde rétrécie de `ctrl.isTimelineFrozen` à `ctrl.isChallengeActive` (le défi seul, comme le défaut
signalé par Manu le 21/08). Le test tombe sur `test.dart:162`, mais cette fois sur **20 des 30**
frames gelées, et **uniquement** la fenêtre `défi actif : false` (la respiration de récupération après
le défi) :

```
horloge à 2058 ms (défi actif : false) : 1 instants annoncés, le premier à 8 s | ...
```

**[déduit]** Comportement exactement conforme à ce que rétrécir la garde devrait produire : pendant le défi lui-même
`isChallengeActive` reste vrai (rien ne change), mais après le défi il retombe à faux avant que
`isTimelineFrozen` ne le ferait — c'est cette fenêtre-là qui se met à fuiter, et c'est elle qui fuitait
dans le défaut du 21/08. Le filet protège bien contre cette régression précise.

## 4. Déterminisme [mesuré]

**[mesuré]**
- 15 exécutions consécutives sur code intact : 15/15 `All tests passed!`, 6-7 s chacune.
- 15 exécutions consécutives garde totalement retirée : 15/15 `Some tests failed.`, toujours sur
  `test.dart:162`.
- 5 exécutions du test ciblé lancées pendant qu'une suite complète (`flutter test`, ~1100 tests)
  tournait en tâche de fond sur la même machine : 5/5 `All tests passed!`. La suite complète elle-même
  a terminé sur `01:28 +1100: All tests passed!` malgré cette charge concurrente.

**[mesuré]** Aucune instabilité observée dans les deux sens, ni isolé ni sous charge — 35 exécutions au total pour
cette relecture (15 + 15 + 5), toutes cohérentes avec le comportement attendu.

## 5. Les faux canaux sont-ils fidèles à la plateforme, sans champ inventé ? [mesuré]

Diff ligne à ligne des blocs `setUp`/`tearDown` entre le nouveau fichier et
`session_finished_duration_render_test.dart` (le seul précédent du projet à monter `SessionScreen`) :
mêmes canaux (`flutter_tts`, les deux `audioplayers`, les deux `EventChannel` d'ambiance, les deux
méthodes pigeon `wakelock_plus`), mêmes handlers, même comportement (`getVoices` → `[]`, tout le reste
→ `1` ; méthodes audio → `null` ; wakelock → message pigeon `null` encodé). Les seules différences
sont les imports propres au nouveau test (`SessionController`, `MovementAnimation`, `provider` — tous
trois nécessaires à la lecture `Provider.of` et non des faux canaux), le docblock, et un commentaire
explicatif sur les `EventChannel` présent dans l'ancien fichier mais pas repris dans le nouveau (sans
conséquence fonctionnelle — le comportement mocké, lui, est identique). Les classes
`_SilentBeepEngine` / `_SilentAmbienceEngine` sont mot pour mot les mêmes dans les deux fichiers.
Aucun champ inventé constaté.

## 6. Le compteur de contrôle refuse-t-il une séance rendue muette ? [mesuré]

**[mesuré]** Cf. §2 — `resolveUpcomingMovementSteps` neutralisé pour toujours renvoyer `[]`. Le test tombe sur
`test.dart:159` (`horsGelAnnonce` reste à 0), après avoir consommé les 30 s de la boucle (la condition
de sortie anticipée `horsGelAnnonce >= 1` n'est jamais atteinte). Le garde-fou anti-vide-de-complaisance
fonctionne : un silence sous gel ne suffit pas à faire passer le test si la séance ne prouve pas par
ailleurs qu'elle sait annoncer quelque chose hors gel.

## 7. État de la suite complète [mesuré]

**[mesuré]**
- `flutter test` complet (sortie redirigée vers fichier, jamais de pipe) : `01:28 +1100: All tests
  passed!` — mesuré ici avec 5 exécutions du test ciblé tournant en parallèle pendant les premières
  secondes (cf. §4), donc une charge légèrement supérieure au cas isolé ; le rapport annonce 93 s sans
  cette charge, cohérent avec les 88 s mesurés ici.
- `flutter analyze` : `No issues found! (ran in 4.3s)`.
- `dart format --output=none --set-exit-if-changed` sur le fichier de test : `Formatted 1 file (0
  changed)`.
- `git status --short` après restauration de toutes les mutations : arbre propre.

## 8. Coût [mesuré]

**[mesuré]** Le test ciblé coûte 6 à 7 s de temps réel à chaque exécution (mesuré sur 35 lancements, jamais observé
au-delà de 7 s). La suite complète mesurée ici tourne en 88 s. Le test représente donc environ 7 à 8 %
du temps total de la suite — un coût significatif pour un seul test parmi ~1100, à mettre en balance
par Manu avec ce qu'il garde (c'est le seul filet sur cette ligne).

## Instruction de la revendication « tenue par transitivité » [déduit]

Le rapport affirme, à propos de la troisième branche du gel (`awaitingPostureReady`, jamais traversée
par ce scénario) : *« Elle est tenue par transitivité — la garde ne lit qu'une expression — mais aucune
frame observée ne la porte. »*

**[mesuré]** `awaitingPostureReady` (`session_controller.dart:481`) réécrit pour renvoyer
inconditionnellement `false` — une régression réelle et sérieuse : en production, un gel de posture
(issue #77) ne bloquerait plus l'annonce des instants à venir. Le test reste vert
(`00:07 +1: All tests passed!`) : cette mutation ne touche à rien que ce scénario exerce.

**[déduit]** **Verdict sur la revendication : vraie mais partielle, et l'énoncé prête à confusion.** Ce qui est
« tenu par transitivité », c'est uniquement la **fidélité du site d'appel** — `session_screen.dart:1134`
lit l'expression agrégée `ctrl.isTimelineFrozen` sans dupliquer ni cas-particulariser aucune de ses
trois clauses, donc le jour où un scénario de test traversera réellement `awaitingPostureReady`, le
code de production n'aura pas besoin d'être retouché pour se comporter correctement. Mais ce test-ci ne
protège en rien la **correction du contenu** de `awaitingPostureReady` ou de `PostureGate.stillHolds` :
ma mutation le montre — un bug qui casserait cette branche par l'intérieur (comme celui, réel et
signalé le 21/08, qui rétrécissait la garde à `isChallengeActive`) passerait inaperçu tant qu'il ne
touche que la clause posture. « Tenue par transitivité » est donc correct comme constat sur le
*câblage* (pas de duplication de l'expression), mais ne doit pas être lu comme « le comportement de
cette branche est vérifié » — il ne l'est pas, et le rapport le dit d'ailleurs lui-même juste après
(« aucune frame observée ne la porte »). La formulation gagnerait à distinguer explicitement ces deux
niveaux plutôt que de les juxtaposer dans la même phrase.

## Réserves déjà déclarées par l'auteur — non recomptées

Confirmées par lecture du scénario, non retestées en détail (déjà admises, pas des trouvailles) :
- la troisième branche du gel n'est jamais entrée dans ce scénario (aucun step `awaitReady` ni break de
  posture dans `_session` du test) ;
- le chemin où la joueuse joue le défi jusqu'au bout (`MAINTIENS`) n'est pas emprunté, seul `PASSE`
  l'est ;
- la moitié aval du câblage (ce que `MovementAnimation` fait de `upcomingSteps` une fois reçu) reste
  sans filet.

## Ce que je n'ai pas pu établir

- Je n'ai pas fait varier le scénario pour emprunter le chemin `MAINTIENS` jusqu'au bout du défi : je
  ne sais donc pas si les fenêtres de gel y ont la même forme (durées, nombre de frames) que sur le
  chemin `PASSE` testé ici. C'est la réserve de l'auteur, je ne l'ai pas comblée.
- Je n'ai pas construit de scénario qui active réellement `awaitingPostureReady` (aurait demandé
  d'assembler un `Session` avec `initialPose`/breaks scriptés compatibles avec ce harnais) : je ne peux
  donc confirmer ni infirmer directement, sur ce scénario, que la troisième branche fonctionne en
  pratique — seulement, par mutation, qu'elle n'est **pas couverte** par ce test (cf. section
  transitivité).
- Je n'ai pas cherché à provoquer un décalage d'une frame entre la lecture de `ctrl.isTimelineFrozen`
  et celle de `anim.upcomingSteps` (un bug où l'écran lirait un état d'un tick différent) : je m'appuie
  sur la garantie structurelle du framework de test (reconstruction synchrone à chaque `pump()`) plutôt
  que sur une mutation dédiée, faute d'un point d'injection simple pour un tel décalage dans ce
  harnais.
- Je n'ai muté que deux points hors sujet (un argument cosmétique de `MovementAnimation`, le contenu de
  `awaitingPostureReady`) plutôt qu'un balayage exhaustif de `session_screen.dart` et
  `session_controller.dart` : le temps alloué à cette relecture unique ne permettait pas plus, et ces
  deux mutations suffisent à établir que le test n'est pas un déclencheur généraliste.
