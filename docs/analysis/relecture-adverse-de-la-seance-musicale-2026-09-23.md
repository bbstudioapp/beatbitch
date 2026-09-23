---
type: analyse
sujet: relecture-adverse-de-la-seance-musicale
ecrit_le: 2026-09-23T22:53:02+02:00
auteur: session tss2-relecture-musique · claude-opus-5-5
revision: 2a78f40
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/assets/sessions/session_montee_puissance.json
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/music_clock.dart
  - rhythm_coach/lib/services/music_engine.dart
  - rhythm_coach/test/session_music_controller_test.dart
provenance:
  mesure: 12
  deduit: 24
  document: 4
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1435
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:268
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:307
  - rhythm_coach/lib/services/music_clock.dart:42
---

## Verdict : recalé

[mesuré] Un seul défaut bloque, et il touche **chaque séance jouée jusqu'au bout** : à la fin du morceau, le lecteur remet sa position à 0, l'horloge de séance repart de 0 et la séance ne se termine pas. Il se corrige vite, mais il faut trancher comment (voir R1). Le reste passe.

[déduit] Réserves :
- **R1 — la séance ne se termine pas avec le morceau. Gênante, bloquante.**
- R2 — le record « Iron Lungs » après un FAIL est juste, mais aucun test ne le garde. Gênante pour la suite du chantier (le filet manque), sans effet pour la joueuse aujourd'hui.
- R3 — une tenue déjà terminée est ré-imposée 1 s après le souffle. Non gênante.
- R4 — quitter l'écran pendant le démarrage du morceau laisse la grille du morceau branchée sur le `BeepEngine` partagé. Non gênante.
- R5 — le repli à 3 s est sûr mais muet, sans rien dire. Non gênante.
- R6 — la décision « un FAIL musical ne coûte pas d'humiliation de carrière » est prise à moitié ; c'est à Manu de trancher. Non gênante.
- R7 — sur les 10 repères de l'auteur, 4 ne permettent pas de distinguer un build correct d'un build cassé. Gênante : ils feraient juger Manu sur une illusion. Liste réduite en fin de rapport.
- R8 — 5 comportements non musicaux touchés par la branche ne sont gardés par aucun test (mutations vertes). Non gênante : juste à la lecture, trous préexistants.

[mesuré] Base : `flutter analyze` « No issues found! », `dart format --set-exit-if-changed .` 0 fichier changé, `flutter test` 1167/1167 verts (y compris `challenge_timeline_forecast_test` cette fois), à `2a78f40`.

## 1. Le FAIL et le déroulé des séances non musicales

[mesuré] Lu ligne à ligne dans le diff de `session_controller.dart`, `session_controller_fail_flow.dart`, `beep_engine.dart`, `session.dart` : chaque changement est gardé par `_music != null` / `_music == null`, ou appelé sur un `_music` nul qui rend la main tout de suite. Pour une séance sans morceau, le seul code nouveau qui s'exécute est `_beep.detachMusic()` au `start()`. Il remet `_music`/`_musicPosition` à nul et `_beepGain` à 1,0 et ne change rien si rien n'était attaché. S'y ajoutent des `await` sur un futur nul ou vide dans `pause/resume/stop/_finish/detachAudio`, soit une microtâche de plus. `_trigger` multiplie le volume par `_beepGain`, qui vaut 1,0 hors morceau.

[mesuré] La lecture dit « inchangé ». J'ai demandé à la suite si elle le **garde** : j'ai posé 9 mutations qui cassent le côté non musical d'une garde ajoutée par la branche (condition inversée ou forcée). Chacune a été vérifiée présente une seule fois, suivie de la suite complète, puis restaurée ; l'arbre est propre à la fin.

| [mesuré] Mutation (effet sur une séance **sans** morceau) | Suite complète |
|---|---|
| M1 `failsCount: 0` (plus de malus de fail en carrière) | **verte** 1167/1167 |
| M2 ambiance jamais reprise après pause | **verte** |
| M3 ambiance jamais jouée | rouge (`session_freeze_tts_speaking_test`, par la bande) |
| M4 commentaires aléatoires coupés | **verte** |
| M5 report TTS des steps coupé | rouge (5 tests) |
| M6 phrases de transition coupées | rouge côté musical seulement, plus `challenge_timeline_forecast_test`, le test instable de `tss2-008` : côté non musical, **non gardé** |
| M7 mini-punitions coupées | **verte** |
| M8 `finale_chime` coupé partout | **verte** |
| M9 gain 0,4 sur tous les bips | rouge (`beep_engine_music_grid_test`) |

[déduit] Ces trous étaient déjà là avant la branche : aucune de ces fonctions n'avait de test sur `develop`, et la branche n'en a retiré aucun. La branche ajoute cependant une condition `_music` sur chacune de ces lignes. Demain, une inversion de cette condition casserait les séances ordinaires sans qu'un seul test tombe. Non gênant pour publier : le code est juste à la lecture. C'est à signaler pour la prochaine retouche de ces lignes.

[mesuré] Le filet `14d6bd0` (FAIL ordinaire : `failing`, horloge gelée, phrase, punition, saut de section, bouton inactif sans punition) reste vert à `2a78f40`.

[déduit] Séances enregistrées : `SessionMusic.tryParse` renvoie nul pour une clé absente **ou** mal formée, donc une séance sans morceau s'ouvre comme avant, et une séance au bloc `music` cassé s'ouvre comme séance ordinaire. Une version plus ancienne de l'app ignore la clé. Les 4 JSON ajoutés à `SessionLoader._assetPaths` sont lus par `session_music_content_test` : s'ils cassaient, `loadAll` échouerait pour **toutes** les séances, et ce test tomberait.

[déduit] `BeepEngine` partagé (une instance créée dans `ModeSelectionScreen`, passée aussi à `SoundDemoScreen`) : `stop`, `_finish`, `detachAudio` et `dispose` détachent tous la grille ; une séance ordinaire qui démarre la détache aussi. Il reste un seul trou, R4, dont la cause préexistante est en fiche `tss2-013` au sas.

### R4 — quitter l'écran pendant le démarrage du morceau

[mesuré] Sonde : lecteur qui démarre en 400 ms, `dispose()` à 100 ms. `start()` continue après le `dispose` : il attache la grille au `BeepEngine` partagé (`attachedTrack` non nul), passe en `running`, et lève « A SessionController was used after being disposed ».

[déduit] Le problème de fond existait avant la branche (`start()` n'a pas de garde après ses `await`). Deux choses sont nouvelles : l'attente est plus longue (jusqu'à 9 s au pire, 3 bornes de 3 s) et elle laisse un effet de bord sur un objet partagé. `SoundDemoScreen` jouerait alors son rythme sur une grille figée, donc muette, jusqu'à la prochaine séance ordinaire. Non gênante : il faut quitter l'écran dans la seconde qui suit l'appui sur « commencer ».

## 2. La musique est-elle vraiment l'horloge

### R1 — fin du morceau : la position retombe à 0, la séance ne finit pas

[document] Les trois implémentations du lecteur embarquées (`pubspec.lock` : `audioplayers` 6.6.0, `audioplayers_android` 5.2.1, `audioplayers_darwin` 6.4.0, `audioplayers_web` 5.2.0) remettent la position à 0 en fin de lecture. Android : `WrappedPlayer.onCompletion` → `stop()` → `seek(0)` quand le mode n'est pas `LOOP`. iOS/macOS : `onSoundComplete` → `seek(0)`, quel que soit le mode. Web : `onEnded` → `stop()` → `currentTime = 0`. Côté Dart, `onPlayerComplete` → `stopAndUpdate()` publie cette position sur `onPositionChanged`.

[déduit] `MusicEngine` ne distingue pas la fin de lecture et `MusicClock.report` accepte tout rapport en état `playing` : `elapsed` repart de 0. La condition de fin est `elapsedSeconds >= session.durationSeconds`. Or `duration_seconds` vaut 179 et le morceau dure 178,85 s, donc la position n'atteint jamais 179.

[mesuré] Sonde (contrôleur réel, faux lecteur qui rapporte 178,8 s puis 0 comme les plugins ci-dessus, horloge murale pilotée) : 0,65 s après la fin, `state=running`, `elapsed=0`, `progress=0,0036` ; 6 s plus tard, `elapsed=6` ; la séance ne passe en `finished` que ~179 s après la fin du morceau. Pour la joueuse : le compteur remonte à 2:59, l'écran reste sur le dernier step (`breath`), et on n'entend plus rien pendant 3 minutes. Si elle appuie sur stop, la séance n'est pas comptée comme terminée : `stop()` repasse en `idle` sans passer par `_finish` ni par les stats. Un FAIL après ~171 s tombe dans le même trou (souffle qui déborde la fin).

[déduit] Pourquoi les tests ne le voient pas : `session_music_controller_test` « fin de séance » fait rapporter au faux lecteur 100,2 s sur une séance de 100 s. Le vrai lecteur ne rapporte jamais une position au-delà de la fin du morceau.

[déduit] Deux façons de corriger. La décision revient à Manu ou à la session de correction, pas à la relecture :
(a) Contenu : `duration_seconds` ≤ 178 dans les 4 JSON. C'est une ligne, mais on coupe les 0,85 s d'extinction et il ne reste qu'1 s après la conclusion de t=177.
(b) Moteur : ne plus croire la position après la fin de lecture, par exemple en exposant la fin de lecture dans `MusicPlayerPort` et en laissant l'horloge extrapoler au-delà. Cette voie protège aussi les morceaux à venir.
Dans les deux cas, le test doit faire rapporter 0 en fin de lecture au faux lecteur, comme les vrais plugins. Je n'ai pas corrigé : le défaut est évident, mais le correctif oblige à choisir.

### Le reste de l'horloge

[document] `setSourceAsset` (audioplayers 6.6.0) copie l'asset puis attend `onPrepared`, et tout ça tient dans le `_loadTimeout` de 3 s. `resume()` démarre un `FramePositionUpdater` qui publie la position **tout de suite** puis à chaque frame.

[déduit] Conséquence pour « un lecteur qui démarre à 3,5 s » : sur Android, un lecteur préparé rapporte 0 dès `play()`. Le premier rapport arrive donc dans la borne, et si le son sort en retard, la position reste simplement à 0 : la séance attend le morceau. C'est le bon comportement. Le repli ne se déclenche que si le chargement dépasse 3 s, si `play()` échoue ou si aucun rapport n'arrive.

[déduit] R5 — ce repli est sûr : `_release()` envoie `stop()`, le lecteur Android passe `playing=false`, et un `onPrepared` tardif ne relance rien, donc pas de musique décalée qui sortirait plus tard. Mais il est **muet** : la séance tourne sur l'horloge murale, sans morceau et sans message. Le cas le plus probable est le web (premier téléchargement d'un MP3 de ~4,3 Mo en moins de 3 s). Non gênante tant que le repère « Web » ci-dessous est fait.

[déduit] Pause, reprise, verrouillage : `didChangeAppLifecycleState` met la séance en pause sur `paused/inactive/hidden`, et la reprise se fait à la main. `MusicEngine.pause` fige l'horloge puis met le lecteur en pause. `resume` ré-ancre sur la valeur figée, puis le premier rapport du lecteur recale. Aucun trou vu à la lecture.

[document] Focus audio : l'auteur écrit que le projet « embarque 6.x, jamais lue ». C'est faux pour Android : `pubspec.lock` fige `audioplayers_android` **5.2.1**, la version que l'auteur a lue. `AudioContextConfigFocus.mixWithOthers` y donne `AndroidAudioFocus.none` (`audioplayers_platform_interface` 7.1.1, `audio_context_config.dart:94-98`), et `FocusManager` accorde alors la lecture sans demander le focus ni écouter sa perte. Le morceau ne devrait donc pas se couper au premier bip ; seul le téléphone le prouvera.

## 3. Le FAIL musical

### R2 — record « Iron Lungs » : juste, mais sans filet

[mesuré] Sonde : tenue `full` de 10 à 30 s, FAIL à 13,5 s, reprise de la tenue après le souffle. Code actuel : record = **8** (la partie d'après le souffle seulement, qui est une vraie tenue). Mutation posée (retrait de `_currentHoldFullDuration = 0;` et `_disarmHoldVerifier();` dans `_triggerMusicalFail`, 2 lignes, vérifiées présentes une seule fois puis restaurées) : record = **11**, c'est-à-dire les 3 s d'avant le FAIL et les 8 s d'après comptées comme une seule tenue. Avec cette mutation, les 30 tests des 4 fichiers de la branche (`session_music_controller`, `session_fail_flow_unchanged`, `session_music_screen_wiring`, `session_music_content`) restent verts. Je n'ai pas relancé la suite complète sur cette mutation.

[déduit] Pourquoi aucun test ne le voit : le faux `_Beep` des tests du contrôleur surcharge `applyStep` sans mettre à jour `currentMode`/`currentFrom`, donc `_accrueHoldSecond` ne voit jamais de tenue. Aucun test du contrôleur musical n'exerce le cumul de tenue, ni l'endurance, la salive ou les stats par mode. La sonde les rend visibles avec un faux qui suit le mode. À poser en filet (`/filet-de-securite`), pas dans cette relecture.

### R3 — une tenue terminée ré-imposée 1 s

[mesuré] Sonde : tenue `full` 10 s + 12 s (fin à 22 s), step suivant à 23 s, FAIL à 14,5 s. À 22,5 s, `_endMusicBreath` applique `hold`/`full`/`duration=1` : `max(1, fin − maintenant)` impose 1 s de tenue alors que la tenue est finie.

[déduit] Dans la séance, c'est un FAIL entre ~167,1 et ~168,1 s : 1 s « au fond » ré-imposée à 175, sur l'explosion, après la fin de la tenue finale. Le step ré-appliqué saute aussi `_flushHoldFull`, `markModeUsed` et le choix du fond d'écran. Non gênante : fenêtre d'1 s, effet d'1 s.

### Décision seule — R6

[document] Le calcul de fin de séance est `α × score + β_encore × encores − β_fail × fails + γ × propre`. Le FAIL musical met `failsCount` à 0 (pas de −1,0) mais laisse `clean` à faux : il **coûte** donc encore γ = 1,0, et avec lui `_obedience.onSessionCleanFinish()` et les badges de fin sans faute. Pendant la séance, il n'y a ni `humiliation.onFail` (`malusFail` 5,0) ni `obedience.onFail`. La spec dit seulement « pas de punition ». À Manu de trancher : coût nul, coût partiel (état actuel), ou coût d'un fail ordinaire.

[déduit] Le suivi de capacités ne tourne qu'en carrière (`trackCapabilities: widget.isCareer`). Une séance fixe ne le touche pas, donc le souffle musical ne peut pas fausser le profil.

## 4. Le contenu contre la spec

[mesuré] Relu dans les 4 JSON :
- tenue `throat` 16 s à t=94 (suspens mesuré à 94,67 s) ;
- tenue `full` 12 s à t=163 (163,54 s) ;
- avant 163, aucune amplitude plus profonde que `throat` (tip→head, head→mid ×3, hold throat, head→throat, mid→throat ×2) ;
- `from` strictement moins profond que `to` partout ;
- temps, modes, amplitudes, BPM, durées et bloc `music` identiques dans les 4 langues.

« Tiens / Hold / Halt / Aguanta / Mantenlo » n'apparaît que sur les deux tenues ; ailleurs, « Encaisse / Keep going / Durchhalten / Sigue así ». L'intro renvoie au « bouton rouge », et le bouton FAIL est bien rouge (`0xFFEF5350`).

[déduit] Écarts à la spec, tous justifiés par une mesure dans le rapport de l'auteur : coach du sommet à 141 s au lieu de ~138 ; frontières posées 1 s avant l'événement mesuré. Il n'y a pas de clamp d'amplitude dans `_checkSteps` pour une séance fixe, donc le « niveau dur, figé » tient.

## 5. Les repères pour Manu

[déduit] Sur les 10 repères de l'auteur, 4 ne distinguent pas un build correct d'un build cassé :
- **n°4** (consigne manquée, FAIL vers 120 s) : un souffle lancé à 120 s ne perd que le step de 126 s, qui n'a pas de texte. Il n'y a rien à « redire » dans aucun des deux cas, donc la réponse ne dit rien. Il faut appuyer entre 134 et 140 s, pour que le souffle de 7,9 s couvre « Voilà le sommet » (141 s).
- **n°6** (voix avant/après la grosse caisse) : la marge est de 0,5 à 0,7 s, du même ordre que la latence du TTS. Un build sur l'horloge murale ne serait en retard que de la latence de démarrage du lecteur. Les deux builds peuvent répondre « avant ».
- **n°8** (verrou : « ensemble/décalés ») : les bips lisent la position du morceau de toute façon, donc ils seront « ensemble » même si le câblage de pause est cassé. La bonne question est : le morceau reprend-il là où il s'était arrêté ?
- **n°9** (niveau) : c'est un réglage, pas un test. Il reste nécessaire, puisque le gain de 0,4 a été posé sans rien entendre.

[déduit] Le n°2 vise 150-170 s. Or de 163 à 175 s c'est une tenue, sans bips de rythme, et de 152 à 163 s les bips tombent un temps sur deux. Il vaut mieux écouter de 115 à 150 s, un bip par temps.

[déduit] Le n°7 (ambiance) et le n°5 (reprise sur le temps) sont couverts : le n°7 par les mutations de l'auteur et le test d'écran, le n°5 par le même mécanisme que le n°2. Je les retire de la liste.

## Ce que je n'ai pas pu établir

- [déduit] Que le S21 remette vraiment la position à 0 en fin de morceau : je l'ai lu dans le code des plugins, pas vu sur l'appareil. Le repère « Fin » tranche.
- [déduit] L'irrégularité de `MediaPlayer.getCurrentPosition` sur le téléphone : la grille relit la position à chaque bip, donc cette irrégularité passe directement dans le placement des bips. Je ne connais pas son ampleur.
- [déduit] Rien de ce qui sort du haut-parleur : latence de sortie, retard d'encodeur, niveau relatif bips/voix/morceau.
- [déduit] Le web : combien de temps met le premier chargement du MP3, et si Safari iOS accepte de lancer la lecture après les `await` de `start()` (`_tts.init`, `_beep.init`). Si ce n'est pas le cas, la séance tourne sur le repli muet.
- [mesuré] La mutation Iron Lungs n'a pas été rejouée sur la suite complète, seulement sur les 4 fichiers de la branche.
- [déduit] Un `playerId` fixe (`session_music`) : si deux `MusicEngine` coexistent (relance très rapide de la séance), le `dispose` de l'ancien vise le lecteur natif du nouveau. La fenêtre est de l'ordre de la seconde et je ne l'ai pas mesurée.

## Essais sur le téléphone (après correction de R1)

[déduit] Un mot par réponse ; chacun de 1 à 6 donne une réponse différente sur un build cassé.
1. **Fin** — à 179 s, l'écran de fin s'affiche-t-il ? « oui » / « non » (compteur qui repart de 2:59 = R1).
2. **Continue** — le morceau joue-t-il encore à 20 s, après les premiers bips ? « oui » / « coupé ».
3. **Collés** — entre 115 et 150 s, un bip par temps : « collés » / « décalés » sur la grosse caisse.
4. **FAIL** — « JE PEUX PAS » entre 134 et 140 s : la musique « continue » / « coupe ».
5. **Sommet** — pendant le même essai, « Voilà le sommet » est « absent » / « dit en retard ».
6. **Web** — sur Safari iOS, le morceau « démarre » / « muet ».
7. **Niveau** (réglage, pas un test) — bips et voix sur le morceau : « bien » / « forts » / « faibles ».
