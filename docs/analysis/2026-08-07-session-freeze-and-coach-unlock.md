# Retour utilisateur 0.6.0 — séance figée et coach indisponible

**Date d'analyse** : 2026-08-07 · **Version concernée** : 0.6.0 (build 15) · **Base de code** : `develop` (identique à `release/0.6.0` sur `lib/`)

Deux problèmes distincts sont rapportés dans le même message. Ils n'ont aucun
mécanisme commun et sont traités séparément.

Symptômes rapportés, tels que décrits :

1. **La séance se fige sur la première consigne.** La première instruction reste
   affichée indéfiniment, la suivante n'arrive jamais. Mettre en pause puis
   reprendre ne débloque rien. Le bouton « Utilise-moi » ne fait rien non plus.
   Le phénomène touche la quasi-totalité des séances lancées. L'utilisateur
   signale avoir rencontré **quelque chose de similaire en 0.5**.
2. **Le nouveau coach (Marc) n'apparaît pas**, alors qu'il estime être « quelques
   niveaux » au-dessus du seuil annoncé.

> **Troisième problème, rapporté ensuite** — la cible d'un défi de montée en
> vitesse affiche un nombre absurde (« ramp up to 956 BPM ») qui grossit à chaque
> rencontre. Analysé à part :
> [`2026-08-07-challenge-bpm-target-runaway.md`](2026-08-07-challenge-bpm-target-runaway.md).
> Le projet de réponse en bas de page couvre les **trois** points.

---

## Problème 1 — la séance ne passe jamais à la consigne suivante

### Ce qui fait avancer une séance

Une séance n'a qu'un seul moteur d'avancement :

- `SessionController.start()` démarre un `Timer.periodic(200 ms)`
  (`_startTicker`, `lib/controllers/session_controller.dart:1136`) ;
- chaque tick appelle `_onTick` → `_checkSteps`
  (`lib/controllers/session_controller.dart:1167` et `:1335`) ;
- `_checkSteps` consomme tous les steps dont `time <= elapsedSeconds`, applique
  la config au `BeepEngine` et déclenche le TTS de la consigne.

Il n'y a **pas** d'événement audio, pas d'attente de fin de lecture, pas de
callback du moteur de bips dans cette chaîne : tout dépend de l'horloge logique
`elapsedSeconds`, elle-même dérivée du `Stopwatch` corrigé par `_timelineOffset`.

### Cause établie : un report de step qui n'a aucune borne

`lib/controllers/session_controller.dart:1370-1373`

```dart
if (step.text.isNotEmpty && _tts.isSpeaking) {
  _timelineOffset -= _tickInterval;
  break;
}
```

Intention : ne pas couper une phrase en cours (flutter_tts est en `QUEUE_FLUSH`,
un `speak()` interrompt le précédent). Le step porteur de texte est donc différé
en **reculant l'horloge logique d'un tick**, et il se rejouera au tick suivant.

Le report est **rejoué indéfiniment tant que `isSpeaking` est vrai**. Aucun
compteur, aucune échéance. Si le flag reste collé à `true` :

- l'horloge logique recule exactement autant qu'elle avance → `elapsedSeconds`
  est gelé ;
- aucun step suivant n'est consommé → la consigne affichée
  (`_lastSpokenResolvedText`, exposée par `currentDisplayText:881`) ne change
  plus jamais ;
- `elapsedSeconds >= session.durationSeconds` n'arrive jamais → la séance ne se
  termine pas non plus.

C'est exactement le symptôme décrit : première consigne pour toujours, seconde
jamais.

À noter : le seul autre endroit du contrôleur qui attend le TTS, le polling
avant le `finale_chime`, **est borné** par une échéance de 8 s
(`lib/controllers/session_controller.dart:1572`). L'absence de borne ligne 1370
ressemble donc à un oubli, pas à un choix.

### Pourquoi `isSpeaking` peut rester collé à `true`

`lib/services/tts_service.dart:206-209`

```dart
_tts.setStartHandler(() => _speaking = true);
_tts.setCompletionHandler(() => _speaking = false);
_tts.setCancelHandler(() => _speaking = false);
_tts.setErrorHandler((msg) => _speaking = false);
```

Le flag ne redescend **que** sur un callback du moteur de synthèse. Il n'existe
aucun watchdog : si le moteur signale le début d'un énoncé et ne signale jamais
ni fin, ni annulation, ni erreur, le flag reste à `true` pour le reste de la vie
du service.

Les trois plateformes ont un mode de défaillance connu qui produit exactement
ça :

- **Android** — `flutter_tts` détecte une connexion morte au service de synthèse
  (`ismServiceConnectionUsable`), remet son `ttsStatus` à `null` et recrée un
  `TextToSpeech`. À partir de là, **tous** les appels entrants sont mis en file
  d'attente (`pendingMethodCalls`) et ne reçoivent de réponse qu'au prochain
  `onInit` réussi. Si l'utterance en cours était déjà démarrée, aucun `onDone` /
  `onStop` / `onError` n'est émis pour elle.
- **Web / PWA iOS** — le plugin web ne relaie `speak.onComplete` que sur
  l'événement `onEnd` de la Web Speech API. Sur Safari, cet événement est connu
  pour ne pas être émis quand la synthèse est interrompue (perte de focus,
  verrouillage de l'écran, énoncé long). Le plugin embarque d'ailleurs un
  contournement `pause()/resume()` toutes les 14 s pour les voix non locales.
- **Windows** — le code du projet documente déjà le problème :
  « `awaitSpeakCompletion(true)` est défaillant sur Windows (SAPI) : SAPI n'émet
  pas toujours l'event de complétion attendu »
  (`lib/services/tts_service.dart:196-200`).

Autrement dit : le défaut est dans l'application (report sans borne + flag sans
watchdog), le déclencheur est dans l'environnement.

### Pourquoi la pause ne débloque rien

`lib/controllers/session_controller.dart:1063-1075`

```dart
Future<void> pause() async {
  if (_state != SessionState.running) return;
  _stopwatch.stop();
  _ticker?.cancel();
  ...
  await _tts.stop();        // ← peut ne jamais rendre la main
  await _beep.pause();
  await _ambience.pause();
  _state = SessionState.paused;
  notifyListeners();
}
```

L'état ne bascule en `paused` qu'**après** les `await`. Or, quand le plugin
Android a mis ses appels en file d'attente (cas ci-dessus), `_tts.stop()` ne
complète jamais. Conséquence :

- le ticker et le chronomètre sont déjà arrêtés ;
- `_state` reste `running` → l'overlay « reprendre »
  (`_PausedOverlay`, `lib/screens/session_screen.dart:1415`) ne s'affiche jamais,
  puisqu'il est conditionné à l'état `paused` ;
- `resume()` sort immédiatement (`if (_state != SessionState.paused) return`,
  `:1077`).

La séance est alors arrêtée **sans être en pause**, et plus aucun geste ne la
relance. `stop()` (`:1088`) présente exactement le même schéma — c'est la
signature du symptôme « le bouton pour arrêter n'a aucun effet » de
l'[issue #317](https://github.com/bbstudioapp/beatbitch/issues/317).

À noter : en build de production, les boutons play/pause/stop de l'écran de jeu
sont masqués (`_showSessionControls`, off par défaut). Ce que l'utilisateur peut
appeler « pause » est donc soit l'overlay, soit le passage de l'app en
arrière-plan, qui appelle `_controller.pause()`
(`lib/screens/session_screen.dart:411-421`) — les deux tombent sur le même mur.

### Pourquoi le bouton « Utilise-moi » semble mort

`lib/screens/session_screen.dart:1164-1170` : le bouton est actif tant que
`ctrl.isRunning`. Dans l'état gelé décrit ci-dessus, l'état est **toujours**
`running` : le bouton est donc cliquable et le clic est bien pris en compte —
la régénération de séance peut même aboutir. Mais la timeline reste gelée par la
même garde ligne 1370, donc **rien ne change à l'écran**. Le bouton ne fait rien
de visible parce que la séance ne progresse plus, pas parce qu'il est cassé.

### Reproduction

Reproduit de façon déterministe en test, sans appareil :
`rhythm_coach/test/session_freeze_tts_speaking_test.dart`.

Un faux moteur TTS branché sur le canal `flutter_tts` :

| Scénario | Résultat |
|---|---|
| émet `speak.onStart`, jamais `speak.onComplete` | consigne bloquée sur `un`, `elapsedSeconds == 0`, état `running` — **gel permanent** |
| émet `speak.onStart` puis `speak.onComplete` | progression normale jusqu'à `trois` |
| canal qui ne répond plus à `stop` | `pause()` ne termine pas, `isPaused == false`, `resume()` sans effet |

```
flutter test test/session_freeze_tts_speaking_test.dart
00:07 +3: All tests passed!
```

> ⚠️ Ce sont des **tests de caractérisation** : ils décrivent le défaut tel qu'il
> existe aujourd'hui. Ils devront être inversés (assertions de non-régression)
> quand le correctif sera livré.

Ce qui **n'a pas** été reproduit : le décrochage du moteur TTS lui-même sur
l'appareil de l'utilisateur. C'est le maillon manquant (cf. questions plus bas).

### Est-ce une régression 0.6.0 ?

**Non.** La garde ligne 1370 est présente depuis le commit initial du dépôt
(`git log -S "step.text.isNotEmpty && _tts.isSpeaking"`), et le schéma
`await` non borné dans `pause()` / `stop()` n'a pas été modifié en 0.6.0. Cela
concorde avec « j'avais des soucis similaires avec la version précédente » :

- 0.5.2 a corrigé un cas voisin (« démarrage bloqué sur iOS ») en rendant les
  inits de `start()` best-effort — mais uniquement contre les **exceptions**,
  pas contre les Futures qui ne se complètent jamais ;
- 0.5.3 / #317 a rapporté le même schéma en fin de séance ; le correctif 0.6.0
  (`6ebdb84`) a borné `seek`/`stop` côté `BeepEngine`, **sans** toucher aux
  appels TTS équivalents.

Piste (non démontrée) d'aggravation en 0.6.0 : le briefing d'intro est désormais
concaténé avec l'annonce de posture (`6a1a223`), ce qui allonge l'énoncé de
démarrage. Sur Web Speech en particulier, plus l'énoncé est long, plus le risque
que la fin ne soit jamais signalée est élevé. À confirmer avec la plateforme
réelle de l'utilisateur.

### Écarté

- **Gate de posture** (`_awaitingReady`, `:1506`) : gèle bien la séance, mais est
  borné par un timeout de sécurité de 90 s et affiche son propre bouton.
- **Défi bloqué au seuil** (`ChallengePhase.atSeuil`) : gèle aussi la timeline et
  n'a effectivement pas de timeout, mais il affiche sa propre bannière et son
  bouton STOP, et masque la consigne centrale — l'UI décrite ne correspond pas.
- **Blocage dans `start()` avant le passage en `running`** : possible en théorie
  (les inits `_tts.init()` / `_beep.init()` sont `await` sans borne dans des
  `try/catch` qui n'attrapent pas un hang), mais alors aucune consigne ne serait
  affichée du tout, et le bouton « Utilise-moi » serait grisé plutôt
  qu'inopérant. Reste un candidat de repli si les réponses de l'utilisateur
  contredisent le scénario principal.

### Correctif proposé — non appliqué

Trois niveaux, du plus sûr au plus structurel :

1. **Borner le report** (`session_controller.dart:1370`) : ne différer un step
   que N ticks (ou ~3 s), puis le consommer quoi qu'il arrive. Au pire une
   phrase est coupée — c'est déjà le comportement nominal de `QUEUE_FLUSH`.
   C'est le minimum qui supprime le gel permanent.
2. **Borner les appels au canal TTS** dans `pause()`, `stop()` et `start()`, sur
   le modèle exact de ce qui a été fait pour l'audio en 0.6.0 :
   `await _tts.stop().timeout(const Duration(milliseconds: 300), onTimeout: () {})`.
   Rend les commandes de séance insensibles à un canal muet.
3. **Watchdog dans `TtsService`** : armer un timer au `setStartHandler` qui
   repose `_speaking = false` après une durée max plausible d'énoncé. Attaque la
   cause côté service plutôt que chaque appelant.

Le point 1 seul suffit à ce que la séance ne se fige plus ; le point 2 est
nécessaire pour que l'utilisateur puisse au minimum reprendre ou arrêter.

### Ce qu'il manque — questions à poser à l'utilisateur

Le chaînon non tranché est **pourquoi** le moteur de synthèse décroche chez lui,
et sur quelle plateforme. Questions, par ordre d'utilité :

1. Sur quoi tourne l'app : l'APK Android, la PWA installée depuis Safari sur
   iOS, ou la version Windows/Linux ? (Le mode de défaillance n'est pas le même.)
2. Pendant le blocage, **entend-il encore les bips / le rythme** ? Et la voix de
   la coach s'est-elle fait entendre au moins une fois (briefing d'intro,
   décompte de mise en place, première consigne) ?
3. Le décompte de temps restant bouge-t-il, ou est-il figé lui aussi ?
   (Profil → Debug → afficher le minuteur, s'il l'a activé.)
4. Y a-t-il un écran « je suis en place » (posture) avant le blocage ?
5. Version exacte, modèle d'appareil, version d'OS, langue de l'app.
6. Sur Android : quel moteur de synthèse vocale est sélectionné dans les
   réglages système, et la voix de sa langue est-elle bien installée hors ligne ?
7. Un `adb logcat` pendant une séance qui se bloque, s'il est en mesure de le
   produire, tranchera immédiatement (les messages `Utterance ID has …` du
   plugin TTS disent si la fin d'énoncé est signalée).

---

## Problème 2 — le coach Marc n'est pas disponible

### La condition réelle de déblocage

Contrairement à ce que « quelques niveaux de plus » laisse supposer, **les coachs
ne dépendent pas du niveau de carrière**. Ils dépendent du *temps de jeu
cumulé* :

- `lib/career/models/coach_catalog.dart:59-73` — Marc : `tier: 3`,
  `isPrincipal: true`, `requirements.minPlayerSeconds: 5400` (1 h 30 cumulée) ;
- Jade, Morgan, Victoria et Nyx ont été décalées d'un cran (tiers 4 à 7) pour
  lui faire place ;
- le déblocage est effectué exclusivement par
  `CoachService.syncFromTotalSeconds` (`lib/career/services/coach_service.dart:169`),
  appelé à l'ouverture de l'écran carrière.

### Cause établie : les tiers déjà franchis ne sont jamais revisités

`lib/career/services/coach_service.dart:169-184`

```dart
Future<List<Coach>> syncFromTotalSeconds(int totalSeconds) async {
  final reachedTier = _maxReachableTier(totalSeconds);
  if (reachedTier <= _currentTier) return const [];

  final newlyUnlocked = <Coach>[];
  for (var t = _currentTier + 1; t <= reachedTier; t++) {   // ← tiers > courant
    final p = principalOfTier(t);
    if (p != null && _unlockedIds.add(p.id)) newlyUnlocked.add(p);
  }
  ...
}
```

La boucle ne visite que les tiers **strictement supérieurs** au tier courant
persisté (`coach.current_tier`). Marc a été inséré au tier 3 par une mise à
jour : toute personne dont le tier persisté valait déjà 3 ou plus avant
l'installation de la 0.6.0 ne repassera jamais par ce tier, et **Marc ne sera
jamais ajouté à `coach.unlocked_ids`**, quel que soit son temps de jeu.

Le seul garde-fou existant, `_ensureCurrentTierPrincipalUnlocked()`
(`:139-142`), ne rattrape que le Principal du tier **courant** — pas ceux des
tiers inférieurs.

L'écart avec ce qui a été annoncé est donc double :

- le CHANGELOG 0.6.0 annonce « placé au tier 3 (entre Hélène et Jade) » sans
  préciser que le palier se gagne en **temps de jeu cumulé** et non en niveau ;
- pour les profils installés de longue date, la condition annoncée est de toute
  façon inatteignable : le déblocage n'est pas rétroactif.

### Reproduction

`rhythm_coach/test/coach_backfill_lower_tier_test.dart` — deux cas :

| Profil persisté | Temps de jeu | Résultat |
|---|---|---|
| `current_tier = 4`, Marc absent du set | 200 000 s (≫ 5400) | Marc reste `lockedTier` — **jamais débloqué** |
| `current_tier = 2` | 6 000 s | Marc débloqué normalement |

```
flutter test test/coach_backfill_lower_tier_test.dart
00:00 +2: All tests passed!
```

Le second cas confirme que la mécanique fonctionne pour les nouveaux profils :
seuls les profils déjà au-delà du tier 3 sont touchés — c'est-à-dire précisément
les joueuses et joueurs les plus avancés.

### Correctif proposé — non appliqué

Remplacer la logique incrémentale par une **réconciliation complète** : à chaque
`syncFromTotalSeconds` (et/ou au `load()`), débloquer tout Principal dont
`requirements.minPlayerSeconds <= totalSeconds`, indépendamment du tier courant.
C'est idempotent, rétro-compatible, et immunise le catalogue contre toute
insertion future de coach à un tier intermédiaire.

L'early-return `if (reachedTier <= _currentTier) return const []` doit sauter :
c'est lui qui empêche le rattrapage.

Un export diagnostic de l'utilisateur (Profil → DIAGNOSTIC → Exporter mes
données) confirmerait le diagnostic en une lecture : il suffit d'y regarder
`coach.current_tier` et `coach.unlocked_ids`.

---

## Résumé

| | Problème 1 — séance figée | Problème 2 — coach absent | Problème 3 — cible BPM |
|---|---|---|---|
| Cause | report de step sans borne quand `isSpeaking` reste vrai (`session_controller.dart:1370`) + `await` TTS non bornés dans `pause()`/`stop()` | déblocage limité aux tiers > tier courant (`coach_service.dart:171-179`) | le succès d'un défi BPM crédite la vitesse **demandée** et non celle jouée → boucle `comfort × 1,30` sans borne (`session_controller_challenge.dart:714`) |
| Reproduit | oui, en test | oui, en test | oui, en test |
| Déclencheur tranché | **non** — dépend de la plateforme et du moteur TTS, info manquante | oui, complet | oui, complet |
| Régression 0.6.0 | non, défaut préexistant | oui, introduite par l'ajout de Marc au tier 3 | non, actif depuis v0.5.0 |

Détail du problème 3 :
[`2026-08-07-challenge-bpm-target-runaway.md`](2026-08-07-challenge-bpm-target-runaway.md).

---

## Projet de réponse à l'utilisateur (à relire avant envoi)

> Thanks a lot for taking the time to write all this. All three points are real
> bugs, and two of them are now fully explained.
>
> **1. The stuck session.** We found how it happens. A session moves from one
> instruction to the next on an internal timer, and that timer holds back the
> next instruction while the coach's voice is still speaking, so a line never
> gets cut off mid-sentence. That wait has no time limit: if the phone's
> text-to-speech engine starts a sentence and never reports that it finished,
> the session waits forever. That matches everything you describe — first
> instruction stuck on screen, no second one, and the "use me" button doing
> nothing (the button works, the session behind it is frozen). Pause and resume
> don't help for the same reason: the pause command also waits on the speech
> engine, so the session ends up stopped without ever entering the "paused"
> state.
>
> You're right that it isn't entirely new — that waiting logic has been there
> from the start, and a related freeze was reported at the *end* of sessions in
> 0.5.3. So 0.6.0 didn't break it, but it clearly hits you far more often now,
> and we don't know why yet. That's the part we can't answer from the code
> alone: we can reproduce the freeze when the speech engine goes silent, but not
> *why* it goes silent on your device. A few answers would help a lot:
>
> - Are you using the Android APK, the iOS PWA (installed from Safari), or the
>   Windows/Linux build?
> - While it's stuck, do you still hear the beeps/rhythm? And did you hear the
>   coach's voice at all before it froze (intro briefing, countdown, first
>   instruction)?
> - Is the remaining-time counter frozen too, or still counting down?
> - Do you get a "I'm in position" screen (posture) before it freezes?
> - Which app version, phone model and OS version, and which app language?
> - On Android: which text-to-speech engine is selected in your system settings,
>   and is the offline voice for your language installed?
>
> **2. The missing coach.** Confirmed, and it's on us. Marc was added at tier 3,
> between Hélène and Jade. Coach tiers unlock from your *total time played*, not
> from your career level — and the unlock only ever looks at tiers above the one
> you've already reached. Since you were already past tier 3 before updating,
> that tier is never re-checked, so Marc can never unlock. It has nothing to do
> with your progress being too low: it's the opposite — you're too far ahead for
> the current unlock logic to catch up. There's no workaround on your side; it
> needs a fix in the app.
>
> **3. The 956 BPM speed ramp.** You read it exactly right on both counts: that
> number is a *target*, not a measurement, and the actual speed is already
> maxed out (the audio engine caps at 300 BPM, so anything above that is just a
> number on screen).
>
> Here's why it grows. The target is computed from what the app believes your
> comfortable tempo is on that axis, times 1.3. When you complete the challenge,
> the app records the *requested* speed as if you had held it — instead of the
> speed it was actually able to play. So every completed run pushes your stored
> comfort up, and the next target is ~30 % higher again. Ten or so runs is
> enough to get from a normal tempo to the four-digit range. It also inflates an
> internal progression score the same way, which is the part we'll have to be
> careful about: fixing the calculation won't un-inflate a profile that already
> drifted, and we haven't settled how to repair that yet. For the record this
> isn't new in 0.6.0 either — it's been doing this since 0.5.0.
>
> One reassuring bit: **the challenge is not impossible to pass.** The BPM number
> isn't a win condition — the run is won by staying with it for its duration
> (25 s for that one), and GIVE UP is simply the only button shown while it's
> running. You were never stuck on it.
>
> If you can send a diagnostic export (Profile → DIAGNOSTIC → Export my data),
> it would let us confirm the exact state of your profile — useful for both the
> coach and the BPM issue.
>
> Sorry you couldn't properly try the new features — thanks again for the
> detailed report, it's genuinely useful.
