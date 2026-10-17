---
type: analyse
sujet: seance-musicale-etat-de-reprise-au-plafond-de-jetons
ecrit_le: 2026-09-23T21:38:32+02:00
auteur: session tss2-musique · claude-sonnet-5
revision: 479996f
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/models/session_music.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/music_clock.dart
  - rhythm_coach/lib/services/music_engine.dart
provenance:
  mesure: 13
  deduit: 22
  document: 0
  sans_marqueur: 1
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:927
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:50
  - rhythm_coach/lib/services/beep_engine.dart:590
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Où on en est

[mesuré] Arrêt au plafond de jetons (400 000). Branche `feat/seance-musicale`, worktree `~/perso/git/tss2-musique`, partie de `origin/develop` c57bdcd. Rien poussé, rien fusionné. **La séance n'est pas jouable** : le moteur, l'horloge, les bips et le modèle sont là et prouvés ; le contrôleur, le FAIL musical, le contenu (4 langues) et l'interface restent à faire.

Commits (dans l'ordre) :

| Commit | Contenu |
|---|---|
| 14d6bd0 | `test/session_fail_flow_unchanged_test.dart` : filet du FAIL d'une séance **sans** morceau, écrit et vert **avant** tout changement de `lib/` |
| 99ac071 | `SessionMusic` (asset, bpm, `first_beat`, volume) ; `Session.music` optionnel (JSON, `SavedSessionsRepository.save`) ; `SessionLoader` masque une séance à morceau si l'asset n'est pas dans l'`AssetManifest` ; `.gitignore`, `pubspec.yaml`, `assets/audio/music/README.md`, sync R2 `music/v1/` dans `release.yml` (3 jobs) et `web-deploy.yml` |
| 8ffc482 | `MusicClock` (position extrapolée, ré-ancrée à chaque rapport), `MusicEngine` + `MusicPlayerPort` (repli sur l'horloge murale si le lecteur ne rapporte rien en 3 s), `fake_async` en dépendance de dev |
| 479996f | `BeepEngine.attachMusic/detachMusic`, boucle de bips sur la grille du morceau, gain des bips (`beep_gain`, 0,4 par défaut), point d'observation `debugOnTrigger` |

## Ce que les tests établissent [mesuré]

- [mesuré] 43 tests verts dans 5 fichiers (`session_fail_flow_unchanged`, `session_music_model`, `music_clock`, `music_engine`, `beep_engine_music_grid`). `flutter analyze` : « No issues found! » et `dart format --set-exit-if-changed .` propre au commit 479996f. **La suite complète `flutter test` n'a pas été lancée.**
- [mesuré] Bips : sur 179 s, 330 bips sur les 330 premiers temps, tous à ≤ 1 ms de la grille, aucun sauté ni doublé ; 1 mouvement / 2 temps = les temps pairs ; lecteur qui démarre 1,3 s en retard, morceau figé 2 s, saut arrière de 5 s, horloge du lecteur à +0,1 %, pause/reprise : tous restent sur la grille.
- [mesuré] Mutations posées et rouges sur la bonne assertion : modèle 6/6 ; horloge + moteur 8/8 ; grille 10/10 (grille ignorée, pas ignoré, gain absent/non remis à 1, temps visé accumulé, garde anti-doublon, reprogrammation trop tôt, tolérances, sauts d'attente). L'outil de mutation refuse une mutation non posée et signale un échec de chargement (piège rencontré : sous zsh `$T` non quoté n'est pas découpé, donc faux rouge).

## Ce que je n'ai pas pu établir (et ce que les tests n'établissent pas)

[déduit] Rien de ce qui sort du haut-parleur ; la latence réelle d'`audioplayers` sur le téléphone ; le retard d'encodeur MP3 (`ffprobe` donne `start_time=0`, mais un lecteur Android peut ne pas le compenser : décalage constant possible de ~23-50 ms entre bips et grosse caisse) ; `AudioplayersMusicPort` lui-même (non testé, le faux port le remplace) ; la lecture sur le web (`onPositionChanged` y est moins fréquent : la synchro y sera plus lâche, le repli sur l'horloge murale la sauve si rien n'est rapporté) ; aucun test ne touche encore `SessionController`.

## Le morceau, rejoué [mesuré]

[mesuré] Analyse refaite par ffmpeg + numpy sur `assets/audio/music/montee_en_puissance.mp3` (copie locale gitignorée).
- [mesuré] Tempo : 121,96 BPM confirmé (grille sur l'attaque de la basse : 121,964 ; régression sur 272 kicks : 121,945, résidu rms 8,9 ms).
- [mesuré] Grille de la spec (`16,934 + k × 0,49197`) **exacte** : décalage médian du kick −2,6 → +1,6 ms sur les temps 0-255, +10 ms sur 256-278 (attaque plus molle au sommet).
- [mesuré] Temps n°0 : 16,926 s (seuil 20 %), 16,936 (50 %), 16,943 (80 %) selon le détecteur — 16,934 est dans la fourchette.
- [mesuré] **Le premier temps de mesure est le temps ≡ 2 (mod 4)**, pas 0 : les changements tombent aux temps 94, 126, 158, 190. Les blocs de 32 temps de la spec sont décalés de 2 temps.
- [mesuré] Événements mesurés (temps → seconde) : montée d'aigus 62-93 (47,4-63,2 s) puis palier dès 94 (63,2 s) ; deuxième montée 126-157 (78,9-94,2 s) ; **suspens 1 : grosse caisse absente du temps 158 (94,67 s) au 189 (109,92 s)**, avec des coups de riser aux temps 165-166, 173-174, 181-182, retour plein au temps 190 (110,41 s) — 15,7 s ; **chute du sommet : temps 275-277 (152,2-153,7 s)**, kick de retour au 278 ; **suspens final : grosse caisse absente au temps 298 (163,54 s)**, basse faible (−22 à −29 dB contre −15) du 305 au 320, **retour plein au temps 321 (174,86 s)** pendant 2 temps, puis extinction — 11,3 s, pas 12 ; fin du fichier 178,85 s.
- [mesuré] Écarts avec la spec : le suspens final vaut 11,3 s ; ses frontières (152,2 / 163,5 / 174,9) ne tombent **pas** sur des demi-blocs de 16 temps de la spec (152, 164, 176 arrondis). Le tag du fichier décrit des suspens de « 10 et 20 s » — la mesure donne 15,7 et 11,3.

## Ce qui reste, dans l'ordre

**A. `SessionController`** [déduit] (`lib/controllers/session_controller.dart`) — point d'entrée `music` (`MusicEngine?`, créé si `session.music != null`, libéré au `dispose`) :
1. [déduit] `elapsed` (l. 927) : quand la musique est l'horloge, `_music.position` ; sinon inchangé. Le chronomètre continue de tourner (temps joué).
2. [déduit] `start()` : après `_beep.init()`, `await _music.start(track)` (borné) puis `_beep.attachMusic(track, () => _music.position)` ; vrai ou faux (repli), la séance démarre. Pas de commentaires aléatoires, pas d'ambiance (`_syncAmbienceToCurrentMode`), pas de mini-punition.
3. [déduit] `_checkSteps` (l. 1553-1562) : pas de report TTS (`_timelineOffset -= _tickInterval`) en séance musicale — il décalerait la config de bip par rapport à la musique.
4. [déduit] `pause/resume/stop/_finish/detachAudio/dispose` : pause/reprise/arrêt du moteur de musique et `_beep.detachMusic()` sur **toutes** les sorties ; `start()` d'une séance ordinaire appelle aussi `detachMusic()` (le `BeepEngine` est partagé entre séances).
5. [déduit] `_finish` : ne pas jouer le `finale_chime` (poser `_finalChimePlayed`).
6. [déduit] FAIL musical (`session_controller_fail_flow.dart`, branche **en tête** de `triggerFail`, le code des autres séances ne bouge pas) : `_state` reste `running`, ni chronomètre arrêté, ni TTS coupé, ni punition, pas de `obedience/humiliation.onFail` ; `_hadFailThisSession = true`, `_stamina.onFail()`, `_saliva.onFail()` ; `_musicBreathUntil = elapsed + 16 temps (7,87 s)` ; `_failPhase = FailPhase.breath` ; step `breath` au `BeepEngine`. `_checkSteps` : avant l'échéance, avancer `_nextStepIndex` sans rien appliquer ni dire (consignes perdues) ; à l'échéance, ré-appliquer le dernier step de config de `time ≤ position` (une tenue avec sa durée restante), poser `_lastConfigStep`, lever le souffle. `canTriggerFail` : `running && pas de souffle en cours`.
7. [déduit] `debugTick()` `@visibleForTesting` pour piloter `_onTick` sans temps réel.
8. [déduit] Tests (faux `MusicEngine` à position pilotée) : steps déclenchés sur la position, pas sur le chronomètre ; lecteur en retard = aucun step tant que la position reste à 0 ; FAIL : `punishment` jamais joué, musique jamais mise en pause, reprise sur le step actif, steps du souffle perdus, position monotone ; le filet 14d6bd0 reste vert ; mutation « branche musicale prise par toutes les séances » → filet rouge.

**B. Contenu** [déduit] — 4 fichiers `assets/sessions/session_montee_puissance{,_en,_de,_es}.json` (`id` `montee_en_puissance`, `lang`, `duration_seconds` 179, `mode` rhythm, `music` {`asset` `audio/music/montee_en_puissance.mp3`, `bpm` 121.96, `first_beat` 16.934}), à ajouter à `SessionLoader._assetPaths` (retirés au commit 99ac071 pour ne pas casser le chargement). Steps proposés (temps entiers, posés juste avant l'événement mesuré ; bpm 122 = 1 mouvement/temps, 61 = 1/2 temps) :

| t | Événement | Step |
|---|---|---|
| 0 | intro | `breath` 16 s + ouverture « écoute… ça va monter » |
| 16 | temps 0 | rhythm tip→head bpm 61 |
| 55 | temps 78 | rhythm head→mid bpm 61 + « ça monte » |
| 78 | temps 126 | rhythm head→mid bpm 122 + « suis la musique » |
| 94 | temps 158 | hold `mid` 16 s + « tiens… attends qu'elle revienne » |
| 110 | temps 190 | rhythm head→mid bpm 122 |
| 126 | temps 222 | rhythm head→throat bpm 122 |
| 141 | temps 254 | rhythm mid→throat bpm 122 + coach du sommet |
| 152 | temps 275 | rhythm mid→throat bpm 61 + « encore un peu » |
| 163 | temps 298 | hold `throat` 12 s (« tenue au fond ») |
| 175 | temps 321 | mot final (texte seul, très court) |
| 176 | fin | `breath` + conclusion à t=177 |

Tests : `SessionLoader` avec `isAssetBundled` faux/vrai (séance masquée / visible) ; audits existants (`audit_session_patterns`, `content_from_equals_to`, `audit_presets_validity`) verts avec les nouveaux JSON ; `from` strictement plus haut que `to` ; « tiens / hold / halten » seulement dans les textes de tenue, « encaisse / endure / keep going / durchhalten » ailleurs ; mêmes temps dans les 4 langues.

**C. Interface** [déduit] (`lib/screens/session_screen.dart`) : l. 1065 `if (ctrl.isFailing)` → ajouter le souffle musical ; masquer le curseur d'ambiance (`_VolumesBlock`, l. 1246) quand `session.music != null`.

**D. Vérifications finales** [déduit] : `flutter gen-l10n` si un ARB bouge, `flutter analyze`, `dart format --set-exit-if-changed .`, `timeout 900 flutter test > fichier.log 2>&1` (`challenge_timeline_forecast_test` peut échouer sans rapport, `tss2-008`), mutations restantes, puis le rapport final avec les repères ci-dessous.

## Repères pour Manu (à valider quand le build existe)

Un mot par essai ; chacun donne une réponse **différente** sur un build cassé.
1. [déduit] Écouter les 20 dernières secondes de la montée (150-170 s) : les bips sont-ils « collés » ou « décalés » sur la grosse caisse ? Un build qui garderait le loop d'intervalle (122 BPM entier, phase prise au démarrage du step) ne tombe jamais sur la grosse caisse — « décalé » dès la première minute.
2. [déduit] Appuyer sur « JE PEUX PAS » vers 120 s : la musique « continue » ou « coupe » ? Un build qui garde le FAIL ordinaire coupe les bips, joue une punition et saute de section.
3. [déduit] À la reprise, la consigne jouée correspond-elle au passage du morceau (« juste ») ou à celui d'avant (« retard ») ?
4. [déduit] Web (Safari iOS) : la musique démarre-t-elle (« oui » / « non ») ; si « non », la séance doit tourner muette, jamais planter.

## Décisions prises seul (à valider)

- [déduit] Le pas d'une séance à grille se déduit du BPM entier du step : `round(121,96 / bpm)` → 122 = 1 temps, 61 = 2 temps (temps pairs, donc temps forts).
- Lecteur : `AudioContextConfigFocus.mixWithOthers` (Android `AUDIOFOCUS_NONE`) — sans lui, le focus pris par chaque bip mettrait le morceau en pause [déduit de `audioplayers_android` 5.2.1, `FocusManager`/`WrappedPlayer` : perte de focus permanente → `pause()`]. Le même défaut vaut sans doute pour l'ambiance actuelle : à vérifier hors de ce chantier.
- [déduit] Si le lecteur ne rapporte aucune position en 3 s : la séance tourne sur l'horloge murale, sans musique, bips sur la même grille.
- [déduit] Gain des bips 0,4 et volume du morceau 0,85 : valeurs posées **à l'oreille impossible** (aucun son ici) ; réglables dans le JSON (`beep_gain`, `volume`).
- [déduit] FAIL musical : pas de phrase de fail (aucun texte prévu par la spec, et une phrase punitive contredirait « pas de punition »), souffle de 16 temps (7,87 s, un demi-bloc), `_hadFailThisSession` reste vrai (les badges « sans faute » ne se gagnent pas en abandonnant), pénalités obéissance/humiliation non appliquées.
- [déduit] Pas de `finale_chime` ni de `finalStepTime` : le morceau a sa propre explosion (temps 321).
- `SavedSessionsRepository.save` propage `music` ; les deux constructeurs `Session(...)` de mise à niveau/régénération en carrière ne le propagent pas (jamais atteints par cette séance).
- Question de droits Suno : toujours ouverte, à reposer avant la release.
