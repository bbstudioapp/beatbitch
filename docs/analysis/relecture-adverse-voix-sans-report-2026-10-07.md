# Relecture adverse — `fix/voix-sans-report` @ `cc84720` (2026-10-07)

Correctif écrit par `claude-opus-5-5` en direct avec Manu, jamais relu. Base : `origin/develop` @ `c57bdcd`.
Consigne : chercher à réfuter, pas à valider. Aucun appareil. Le plus risqué des trois : il touche le
cœur de `SessionController` et cinq fichiers voisins.

## Ce que la joueuse vivait

Quand la voix du coach parle, toute la consigne suivante (rythme, position) attend la fin de la
phrase : à-coups aux transitions.

## Cause annoncée, rejouée sur develop

`_checkSteps` (develop, `session_controller.dart:1555-1563`) : pour tout step porteur de texte, si
`_tts.isSpeaking`, le step **entier** est reporté au tick suivant et `_timelineOffset -= 200 ms`.
L'horloge de séance recule donc d'un tick par tick tant que la voix parle (borne 5 s). Deux effets :
la configuration (mode, BPM, position) part en retard ; et les frontières de steps que la courbe
dessine, exprimées sur cette horloge, reculent à chaque report — c'est le rembobinage que
`diag/sauts-transitions` @ `3563b61` et `diag/rembobinage-tenue-gorge` reproduisent (les deux
branches partent de `feat/tenues-vivantes`, pas de develop : leurs tests ne sont pas transplantables
ici, et le correctif ne porte **aucun test du symptôme de courbe**).

Rejoué : avec le contrôleur de develop, le rythme d'un step à t = 1 s s'applique à **3 210 ms**, à la
fin de la phrase de 3 s en cours (sonde P3a).

## Le correctif

Le step s'applique à son heure. Seule sa phrase attend, dans une file `_pendingSpeech` drainée à
chaque tick par `_speakPendingWhenFree` (borne 5 s par phrase, puis elle part en coupant). Il ne
reste qu'un seul décrément de `_timelineOffset` dans tout `lib/` (`_onTick`, sous
`isTimelineFrozen`) : la cause structurelle du rembobinage est retirée. La file est vidée sur
`start`, `stop`, `triggerFail`, mini-punition, `requestUpgrade` et régénération post-défi.

## Preuve rouge

| Sonde | Code | Résultat |
|---|---|---|
| P3a | les 6 fichiers de `lib/controllers` de develop | « seule la phrase attend » rouge sur `rythme < 1400` : 3 210 · « phrase du step final » rouge sur `< 1600` : 1 802 · les 10 autres tests verts |
| P3b | `if (false)` à la place de la condition de mise en attente | rouge sur « la phrase attend la fin de la précédente » (1 006 ms) et sur le test du moteur muet (`trois` au lieu de `deux`) |
| P3c | sonde jetable : step `awaitReady` avec texte pendant une voix de 3 s | hold appliqué à 1 027 ms, annonce prononcée à 3 228 ms, gel tenu (`elapsed = 0`), step suivant jamais consommé |

Restauration par copie, `git status` propre après chaque sonde ; la sonde P3c a été retirée.

## Casse cherchée, chemin par chemin

- **Postures** (`awaitReady`) : la gate s'arme à l'application du step, avant que son annonce soit
  entendue ; `_speakPendingWhenFree` tourne pendant le gel et la prononce dès que la voix se libère
  (P3c). `PostureGate.stillHolds` ne voit plus de décrément hors gel : cohérent avec sa doc corrigée.
- **Breaks** : `_exitBreak` dit sa phrase de reprise, puis `_checkSteps` applique le step d'effort
  **dans le même tick** ; les bips repartent après le `transitionGap`, sous la phrase de reprise. Sur
  develop, le step attendait la fin de la phrase (« silence propre pendant l'annonce », commentaire
  retiré par l'auteur). Changement de comportement assumé, pas testé, pas forcément vu par Manu.
- **Défis** : la machine est pilotée par `elapsedSeconds`, qui ne cale plus pendant une voix. Une
  phrase en attente au moment où `_enterChallengeCountdown` coupe la voix sera prononcée au tick
  suivant, par-dessus le compte à rebours (les chiffres sont sautés tant que `isSpeaking`). Sur
  develop le step reporté était **consommé entier** à ce même instant, bips compris : ce n'est pas
  une régression, c'est le même trou, moins large.
- **FAIL et punition** : `_stopTtsBounded()` puis `_dropPendingSpeech()` sur les deux chemins ; le
  programme de punition parle par son propre ticker.
- **Step final** : exempté de la file (sa phrase part tout de suite, en coupant la voix en cours, car
  `_playFinalChimeAfterAction` sonde `isSpeaking`). Mais les phrases **déjà** en attente ne sont pas
  jetées : une consigne périmée peut être dite après la phrase finale, pendant le chime.
- **Pause** : la file survit à `pause()` ; la phrase part à la reprise. Même effet que le report de
  develop.
- **Affichage** : `_lastSpoken` n'est posé qu'à la prononciation ; `currentDisplayText` suit la voix,
  pas le moteur. Cohérent avec ce qu'on entend.

## Suite complète (branche)

`flutter pub get` OK · `flutter analyze` : « No issues found! » · `flutter test` : **1103 tests,
All tests passed!**

## Ce que je n'ai pas pu établir

- Le **symptôme de courbe** lui-même : aucun test de ce correctif ne monte `MovementAnimation` ; la
  disparition des sauts se déduit du retrait du décrément, elle n'est pas mesurée.
- Le chemin **défi** avec une phrase en attente, et le chemin **break** : raisonnés sur le code, pas
  sondés.
- Sur develop, la phrase du step final part à 1 802 ms alors que la voix dure 3 s : quelque chose
  libère `isSpeaking` avant la fin sur ce chemin. Sans incidence sur le correctif, non expliqué.
- Deux locuteurs dans le même tick (`_updateChallengePhase` puis `_speakPendingWhenFree`) voient
  tous deux `isSpeaking` à faux, `_markSpeaking` n'arrivant qu'au `onStart` du moteur : le second
  coupe le premier. Préexistant sur develop, déposé au sas.

## Verdict : **publiable avec réserves**

1. **Break** : les bips repartent sous la phrase de reprise. À faire entendre à Manu avant de
   publier, ou remettre une attente locale à `_exitBreak` si c'est voulu.
2. **Step final** : vider `_pendingSpeech` quand il part, sinon une consigne périmée peut suivre la
   phrase finale.
3. **Posture** : le bouton « je suis en place » et son délai de 90 s démarrent jusqu'à 5 s avant que
   la consigne soit entendue. À juger.
4. Aucun test ne porte sur la courbe : transplanter la reproduction de `diag/sauts-transitions`
   quand `feat/tenues-vivantes` sera fusionnée, ou en écrire une sur develop.
