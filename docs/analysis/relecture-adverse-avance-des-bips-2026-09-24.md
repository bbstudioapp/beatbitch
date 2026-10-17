---
type: analyse
sujet: relecture-adverse-avance-des-bips
ecrit_le: 2026-09-24T12:56:38+02:00
auteur: session tss2-relecture-avance · claude-opus-5-5
revision: 70727c9
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/lib/career/services/debug_settings_service.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
provenance:
  mesure: 11
  deduit: 15
  document: 7
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:947
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:271
  - rhythm_coach/lib/screens/session_screen.dart:1255
  - rhythm_coach/lib/services/beep_engine.dart:508
  - rhythm_coach/lib/services/beep_engine.dart:590
  - rhythm_coach/lib/services/beep_engine.dart:604
---

## Verdict : publiable avec réserves

[mesuré] Relu : `git diff ebcc57a..70727c9`. L'avance avance bien le son de tous les bips que joue le contenu musical actuel. Le curseur, les consignes, la voix et le souffle d'un FAIL restent sur la même horloge que les bips. Avance à 0 : le comportement est inchangé. Une réserve gênante : dès 152 ms d'avance, la séance se termine avant la fin du morceau, et les essais « Fin » et « Souffle » ne jugent plus le câblage de fin (`tss2-014`). Je n'ai rien corrigé.

[mesuré] À `70727c9` : `flutter analyze` « No issues found! », `dart format --set-exit-if-changed .` 0 fichier changé sur 325, suite complète 1183/1183. Arbre propre en fin de relecture : sondes et mutations restaurées par `git checkout`.

| [déduit] Réserve | Classement |
|---|---|
| R1 — avance ≥ 152 ms : fin de séance avant la fin du morceau, essais « Fin » et « Souffle » aveugles | gênante |
| R2 — build release : avance toujours à 0, le retard reste entier pour toute release | non gênante (attendu d'un outil d'essai), à décider ensuite |
| R3 — queue du morceau coupée, jusqu'à 248 ms ; le rapport relu parle à tort de « derniers bips coupés » | non gênante |
| R4 — image et musique : l'image avance avec les bips, l'écart image/musique n'est pas mesuré | non gênante |
| R5 — écriture de la préférence ni bornée ni rattrapée, sur un `onPressed` sans `await` | non gênante |

## Piste 1 — l'avance avance-t-elle vraiment le son ?

[document] Chemins de bip du `BeepEngine` pendant une séance à morceau :
- `rhythm`, `lick` et `hand` passent par `_startBeatLoop`, qui bascule sur `_startGridLoop` quand un morceau est attaché (`beep_engine.dart:508`). La grille lit `lead()` = position + avance, deux fois (`:590` et `:604`). **Décalé.**
- `hold`, `breath` et le `beg` avec position sont des sons uniques joués par `applyStep`. `applyStep` est appelé par le contrôleur quand `elapsedSeconds` franchit l'heure d'un step. Or `elapsed` = position + avance (`session_controller.dart:947`). **Décalé**, au pas du tick (200 ms) près, comme avant.
- Le souffle d'un FAIL musical (`_triggerMusicalFail`) : un son unique au moment de l'appui, puis `_endMusicBreath` quand `elapsed` dépasse `_musicBreathUntil`. Les deux valeurs sont lues sur la même horloge décalée (`session_controller_fail_flow.dart:271`). **Cohérent.**
- `biffle`, `suckle` et la fin de `freestyle` ne passent pas par la grille : ni morceau, ni avance. **Non décalés**, mais absents du contenu musical actuel.

[document] Le contenu (`session_montee_puissance.json`, dans ses 4 langues) n'emploie que `breath`, `rhythm` (61 et 122 BPM) et `hold`. Aucun défi n'y est déclaré. Le seul lecteur de la position du morceau hors du contrôleur est la grille (`grep` de `MusicEngine`, `isMusical`, `beatTime`).

[mesuré] Mutations jouées, chacune vérifiée posée (motif unique, `git diff --stat` non vide), puis restaurée. Les trois fichiers de tests touchés par le diff ont été rejoués sous chacune (36 tests).

| [mesuré] Mutation | Résultat |
|---|---|
| M0 : avance retirée de `lead()` et de `elapsed` (celle du rapport relu) | 3 rouges, les messages du rapport à l'identique (`16.814` contre `16.934`, `0.200` contre `0.000`, `42.120` contre `42.000`) |
| Ma : seul `now = lead()` (`:590`) ramené à `position()` | 2 rouges (grille) : `Expected 16.814000, Actual 16.877860` ; `Expected 0.200000, Actual 0.084864` |
| Mb : seul `elapsed` sans avance | 1 rouge (contrôleur) : `Expected 42.120000, Actual 42.000000` |
| Mc : propagation au `BeepEngine` retirée du setter | 1 rouge : `Expected 0.400000, Actual 0.120000` |
| Md : propagation au `BeepEngine` retirée de `start` | 1 rouge : `Expected 0.120000, Actual 0.000000` |
| Me : `notifyListeners()` retiré du setter | 1 rouge (écran) : `Found 0 widgets with text "10 ms"` |
| Mf : `&& ctrl.isMusical` retiré de l'écran | 1 rouge (témoin séance ordinaire) : le libellé debug apparaît |
| Mg : écriture de la préférence retirée | 1 rouge : `Expected <400>, Actual <120>` |
| Mh : garde `_music == null ? 0 :` du getter retirée | verte : mutant équivalent, `_musicBeepAdvanceMs` n'est jamais écrit hors séance musicale |

[déduit] Chaque rouge tombe sur l'assertion qui nomme la ligne mutée, pas sur une erreur de montage.

Ce que je n'ai pas pu établir : que le déclenchement plus tôt d'un `_trigger` se traduise par un son plus tôt de la même durée sur le S21. Le déclenchement est « tire et oublie » vers le pool `audioplayers` ; s'il a une latence variable, l'avance la décale sans la réduire. Aucune mesure audio ici.

## Piste 2 — son et image restent-ils d'accord ?

[document] L'écran ne lit que `ctrl.elapsed` (curseur, courbe, minuteur, frontières des consignes) et `beatStream` (l'orbe), émis dans le même appel que le bip (`_emitPositionBeat`). La voix du coach part au franchissement de step, donc sur `elapsed`. Tout ce qui est visible ou parlé avance de N, comme les bips ; seul le morceau ne bouge pas.

[déduit] Entre le bip entendu et l'image, rien ne change : ils partent du même appel, avant comme après. Entre l'image et la musique, l'écart grandit de N : l'orbe tombait sur la position rapportée par le décodeur, il la précède maintenant de N. Selon les latences d'affichage et de sortie du morceau (non mesurées), l'image peut paraître en avance sur la musique. C'est R4, non gênante : la question posée à Manu porte sur les bips.

[mesuré] Fin de séance. Le morceau dure 178,848 s (`ffprobe`), la séance 179 s : la queue fait 152 ms. La séance se termine quand `elapsed` ≥ 179 s, soit position ≥ 179 s − N. Sonde jetable dans `session_music_controller_test.dart` (séance de 100 s, lecteur posé à 99,849 s, aucun événement de fin émis, retirée depuis) :

| [mesuré] Avance | État | `elapsed` | Morceau |
|---|---|---|---|
| 100 ms | `running` | 99,949 s | attaché, attend l'événement de fin |
| 160 ms | `finished` | 100,009 s | arrêté par `_finish`, sans événement de fin |
| 400 ms | `finished` | 100,249 s | arrêté par `_finish`, sans événement de fin |

[déduit] **R1, gênante.** Dès que N ≥ 152 ms, la séance réelle se termine sur son horloge décalée pendant que le morceau joue encore. L'événement de fin (`completions`, correctif R1 du 23/09) n'est plus sollicité. L'essai « Fin » répondrait « oui » même avec un câblage cassé ; c'est pourtant le seul juge de `tss2-014` (M6 toujours verte). L'essai « Souffle » aussi : un FAIL entre 172 et 175 s ouvre un souffle de 7,87 s (16 temps), qui déborde 179 s, et `_onTick` termine la séance avant la fin du morceau. Le code n'est pas faux ; c'est le protocole d'essai qui perd sa discrimination. Il faut jouer « Fin » et « Souffle » avec l'avance à 0 (visible à l'écran, réglable), ou dans une autre installation.

[mesuré] **R3, non gênante.** `_finish` arrête le lecteur (`_releaseMusic`) : la fin du morceau est coupée de N − 152 ms, 248 ms au plus. `ffmpeg volumedetect` sur les dernières 400 ms : moyenne −46,6 dB, crête −34,4 dB, soit un fondu. Le rapport relu annonce « les derniers bips peuvent être coupés » [document] : le contenu finit par une tenue (163 à 175 s) puis un `breath` (176 s), deux sons uniques. Il n'y a aucun bip de grille en fin de séance, rien à couper.

[déduit] Souffle d'un FAIL en cours de séance : `_musicBreathUntil` est posé et comparé sur la même horloge décalée. Changer N pendant le souffle raccourcit ou allonge ce souffle de la variation, 10 ms par appui.

## Piste 3 — réglage en pleine séance

[mesuré] Sonde jetable sur la grille (`beep_engine_music_grid_test.dart`, faux lecteur en temps mural, retirée depuis) : 160 appuis de ±10 ms, un toutes les 70 ms, de 0 à 400 et retour, deux fois, pendant un step à 122 BPM. Résultat : 34 bips aux temps n°0 à 33, consécutifs, aucun sauté ni doublé, retard maximal 10 ms sur le temps visé à l'avance courante.

[mesuré] Saut brutal inatteignable depuis l'écran, qui avance par 10 ms : 0 → 400 ms d'un coup à 20,1 s, puis 400 → 0 ms à 25,1 s. À la montée, le bip en attente part dès que le timer sonne (20,303 s, pour 19,978 s visé) et le suivant suit 166 ms plus tard (20,469 s). À la descente, un trou de 892 ms (24,897 → 25,789 s). Ni doublé ni sauté : la garde `justPlayed` tient dans les deux sens.

[déduit] Côté contrôleur : un appui déplace `elapsed` de ±10 ms. `_nextStepIndex` ne recule jamais : un recul ne rejoue aucune consigne, une avance consomme au plus 10 ms plus tôt une frontière qui tombait là. Le curseur saute de 10 ms. Acceptable pour un réglage d'essai.

Ce que je n'ai pas pu établir : l'effet d'un appui sur le vrai plugin, avec la position interpolée de `MusicClock` et sa gigue.

## Piste 4 — avance à 0

[mesuré] Tests musique (7 fichiers) : 75/75 à `ebcc57a` (branche détachée dans ce worktree puis rebasculée), 80/80 à `70727c9`. Le diff n'ajoute que des tests, aucun n'est modifié. Les 75 tests d'avant tournent donc inchangés sur le nouveau code : c'est le rejeu de caractérisation.

[déduit] À N = 0, `lead()` = `position() + Duration.zero` et `elapsed` = `position + 0` : même valeur, même ordre de lecture. Seule différence de déroulé : `start` attend désormais `DebugSettingsService().getMusicBeepAdvanceMs()` avant `music.start`. C'est un `await` de plus, non borné, protégé par `try/catch` ; `SharedPreferences.getInstance()` est déjà en cache à ce stade de l'app. Non mesuré sur l'appareil.

## Piste 5 — hors séance musicale

[document] `_musicBeepAdvanceMs` n'est lu qu'à l'intérieur de la branche `music != null` de `start`. Le setter sort si `_music == null`, `elapsed` n'ajoute l'avance que si `music != null`. Côté `BeepEngine`, `musicBeepAdvance` n'est lu que dans `_startGridLoop`, qui n'existe qu'avec un morceau attaché.

[déduit] `detachMusic` ne remet pas `musicBeepAdvance` à zéro. Sans effet : hors morceau, la grille ne tourne pas, et chaque séance musicale réécrit la valeur à son `start`. Le témoin écran (Mf) garde l'absence du contrôle dans une séance ordinaire. La suite complète, 1183/1183, couvre les séances ordinaires.

## Piste 6 — build release

[document] Le contrôle est derrière `if (kDebugMode && ctrl.isMusical)` (`session_screen.dart:1255`). `kDebugMode` est une constante de compilation, fausse en release : la ligne n'existe pas dans une build release. Pas testable dans `flutter test`, qui tourne en debug.

[document] La lecture de la préférence au `start` n'est pas gardée par `kDebugMode` : une release **appliquerait** une valeur mémorisée. Elle n'en trouve aucune. Les APK d'essai partent des branches `essai/*`, qui portent `78f45f8` (identifiant `com.beatbitch.app.debug`, préférences séparées). Et sans ce suffixe, un APK debug ne s'installe pas sur une release signée sans désinstaller, ce qui efface les préférences (mémoire du projet, 20/07).

[déduit] **R2** : en release, l'avance vaut toujours 0 ; le retard que Manu entend reste entier pour toute build release. Ce réglage est un instrument de mesure. La valeur trouvée à l'oreille devra ensuite être posée en dur, ou devenir un réglage joueur. Elle dépend probablement de la sortie audio : haut-parleur et casque Bluetooth ont des latences différentes, et une constante unique ne vaudra peut-être pas pour les deux. À trancher après l'essai.

[déduit] Un cas limite : une release construite depuis ce worktree, sans `android/key.properties`, est signée avec la clé debug. Posée par-dessus une debug du même identifiant (branche sans `78f45f8`), elle garde les préférences. Elle appliquerait alors une avance invisible et impossible à régler. Aucun chemin connu ne produit cette installation.

## Piste 7 — les tests rouges

[mesuré] La mutation du rapport relu (M0) est posée (`grep -c` = 1 pour chacun des deux motifs, `git diff --stat` : 2 fichiers, 2 lignes) et rougit exactement les 3 tests annoncés, avec les mêmes messages. Les mutations séparées (Ma à Mg) montrent que chaque ligne du câblage a son propre rouge, sur la bonne assertion. Seul `kDebugMode` n'est gardé par aucun test (Piste 6).

[déduit] Le test « avance = 0 » reste vert sous M0, ce qui est attendu d'un témoin. Il ne garde que l'absence d'effet à 0.

## Hors du diff

[déduit] `biffle`, `suckle` et la fin de `freestyle` ignorent la grille et l'avance en séance musicale : latent, absent du contenu actuel. Fiche `tss2-016` au sas.

## Ce que je n'ai pas pu établir

- [déduit] Qu'une avance de N ms corrige ce que Manu entend : aucune mesure audio, et aucun son joué dans cette relecture.
- [déduit] La valeur du retard sur le S21 : si elle est sous 152 ms, R1 ne se manifeste pas.
- Le comportement du contrôle en build release : lu, pas exécuté.
- [déduit] Que le déclenchement d'un bip ait une latence constante sur l'appareil. Sinon l'avance ne corrige qu'en moyenne.
