---
type: analyse
sujet: filet-de-securite-sur-la-garde-de-gel-d-horloge-apres-un-defi
ecrit_le: 2026-08-22T23:04:33+02:00
auteur: session tss2-filet-garde-gel · claude-opus-5
revision: cdacdce
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/test/session_finished_duration_render_test.dart
  - rhythm_coach/test/session_frozen_upcoming_steps_wiring_test.dart
provenance:
  mesure: 15
  deduit: 3
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:937
  - rhythm_coach/lib/screens/session_screen.dart:1134
  - rhythm_coach/test/session_finished_duration_render_test.dart:1
---

## Le trou, rejoué avant d'être outillé

**[document]** Deux sessions, les 21 et 22/08, ont rapporté que supprimer la garde de
`session_screen.dart:1134` — passer les steps à venir même quand l'horloge de séance est gelée —
laissait la suite complète verte.

**[mesuré]** Rejoué ici avant toute écriture : garde retirée du fichier de production, `flutter test`
complet, sortie redirigée vers un fichier. Résultat `01:35 +1099: All tests passed!`, code de sortie
0. Le trou existe : aucun des 1099 tests ne tient cette ligne. La garde a ensuite été restaurée et
`git status` rendu vide avant d'écrire quoi que ce soit.

## Ce que la garde tient

**[document]** `isTimelineFrozen` (`session_controller.dart:937`) vaut
`isChallengeActive || _inPostChallengeBreath || awaitingPostureReady` : l'horloge de séance est gelée
pendant un défi **et** pendant la respiration de récupération qui le suit. Un défaut signalé par Manu
le 21/08 décrivait la courbe rattrapant son retard d'un coup après un défi.

**[déduit]** Le getter est juste et déjà lu ailleurs ; ce qui n'était tenu par personne, c'est son
**usage** à la ligne 1134 — un argument de constructeur, pas une fonction pure. Une sonde sur le
getter seul n'aurait rien protégé.

## Le banc

**[mesuré]** Le test monte `SessionScreen` sur le modèle de
`session_finished_duration_render_test.dart`, seul précédent du projet à le faire, et reprend son
harnais de faux canaux tel quel :

- `flutter_tts` — `getVoices` rend une liste vide, tout le reste `1` ;
- `xyz.luan/audioplayers` et `xyz.luan/audioplayers.global` (méthodes) ;
- leurs deux `EventChannel`, sans lesquels le player d'ambiance lève un `MissingPluginException` qui
  remonte au framework de test ;
- les deux méthodes pigeon de `wakelock_plus`.

Aucun champ inventé : chaque canal simulé rend la forme que la vraie plateforme rend.

**[mesuré]** `BeepEngine` et `AmbienceEngine` sont remplacés par des sous-classes silencieuses — même
choix que le précédent. La séance porte quatre steps et un défi `holdThroatStreak` armé à 2 s,
valeurs du même ordre que celles du test existant.

**[mesuré]** Le `Stopwatch` du contrôleur n'étant pas simulé, la séance est jouée à l'horloge du mur :
`tester.runAsync(Future.delayed(100 ms))` puis `pump(100 ms)`, en boucle. La sonde sort dès que les
trois fenêtres attendues sont observées — 6 s de temps réel par exécution.

**[mesuré]** À chaque frame, la sonde lit deux choses au même instant : `isTimelineFrozen` sur le
`SessionController` obtenu par `Provider.of` depuis l'élément du widget, et la propriété
`upcomingSteps` reçue par `MovementAnimation`. C'est exactement la relation que porte la ligne 1134.
Elle compte trois choses : les frames gelées pendant le défi, les frames gelées après lui, et les
frames hors gel où une trajectoire est bel et bien annoncée — cette dernière interdit qu'un vide
observé sous gel vienne d'une séance qui n'aurait rien à annoncer.

**[mesuré]** Sur le code intact, un passage complet observe 26 frames gelées pendant le défi,
83 après, 47 frames hors gel qui annoncent — et zéro annonce sous gel.

## La preuve rouge

**[mesuré]** Garde retirée, le test tombe sur l'assertion visée (`test.dart line 162`,
`expect(annoncesSousGel, isEmpty)`), message d'échec :

```
Expected: empty
  Actual: [
            'horloge à 1817 ms (défi actif : true) : 3 instants annoncés, le premier à 2 s',
            ...
            'horloge à 2003 ms (défi actif : false) : 1 instants annoncés, le premier à 8 s',
            ...
          ]
l'écran a annoncé des instants à venir alors que l'horloge de séance était gelée, sur 30 des 30
frames gelées observées
```

**[mesuré]** Les deux fenêtres du gel apparaissent dans la liste : `défi actif : true` pendant le
défi, `défi actif : false` après lui. Une garde qui serait rétrécie de `isTimelineFrozen` à
`isChallengeActive` — la régression exacte du défaut du 21/08 — tomberait donc aussi.

**[mesuré]** Sur un passage de diagnostic mené jusqu'au bout de la fenêtre, sans sortie anticipée,
104 des 104 frames gelées annonçaient. La discrimination est totale : aucune frame gelée ne reste
silencieuse sans la garde.

## Déterminisme

**[mesuré]** 10 exécutions consécutives sur le code intact : 10 `All tests passed!`, code de sortie 0
à chaque fois.

**[mesuré]** 10 exécutions consécutives sur le code muté : 10 `Some tests failed.`, et à chaque fois
l'échec porte sur la ligne 162 — jamais sur un seuil de traversée, jamais sur un timeout, jamais sur
une exception de plugin. 27 lignes d'annonce sous gel relevées à chaque exécution.

## État de la suite

**[mesuré]** `flutter analyze` : `No issues found!`. `flutter test` complet :
`01:33 +1100: All tests passed!` — les 1099 d'avant, plus celui-ci. `dart format` passé sur le
fichier livré.

## Ce que je n'ai PAS pu établir

**[mesuré]** La troisième branche du gel, `awaitingPostureReady`, n'est jamais entrée dans ce
scénario : la sonde n'a traversé que `isChallengeActive` et `_inPostChallengeBreath`. Elle est tenue
par transitivité — la garde ne lit qu'une expression — mais aucune frame observée ne la porte.

**[mesuré]** Le défi est refusé par le bouton `PASSE`, chemin joueur réel. Le chemin où la joueuse
**joue** le défi jusqu'au bout (`MAINTIENS`, puis relâche) n'a pas été emprunté ; rien ne dit que les
fenêtres de gel y ont les mêmes durées.

**[déduit]** La sonde tient l'argument `upcomingSteps` au moment où l'écran le passe. Elle ne dit
rien de ce que `MovementAnimation` en fait ensuite — la moitié aval du câblage, signalée par une
relecture du 21/08, reste sans filet. Le banc monté ici la rend accessible : toutes les propriétés
passées au widget se lisent au même endroit. Aucun test ne l'exerce pour l'instant.

**[mesuré]** Les valeurs de `elapsed` observées sous gel ne sont pas strictement constantes (1817 ms,
1858 ms, 1885 ms…) : l'horloge dérive entre deux ticks du contrôleur. Seule la seconde entière —
celle que lit le résolveur — reste stable. Un test qui aurait voulu prouver le gel par l'immobilité
de `elapsed` aurait échoué ; celui-ci lit `isTimelineFrozen`, pas l'horloge.

**[déduit]** Rien ici ne dit que la garde est la **bonne** réponse au défaut du 21/08 — ce point a été
tranché ailleurs, par une installation jouée et une relecture. Ce test constate seulement qu'elle est
en place et interdit qu'elle disparaisse en silence.
