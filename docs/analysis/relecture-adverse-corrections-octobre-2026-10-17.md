---
type: analyse
sujet: relecture-adverse-corrections-octobre
ecrit_le: 2026-10-17T12:55:49+02:00
auteur: session tss2-relecture-corrections · claude-fable-5-1
revision: fcc7c05
branche: fix/corrections-octobre
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/ambience_engine.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/beep_engine_hold_swing_pause_test.dart
  - rhythm_coach/test/finish_music_test.dart
  - rhythm_coach/test/session_music_controller_test.dart
  - rhythm_coach/test/session_punishment_breath_screen_test.dart
  - rhythm_coach/test/session_reprise_punition_courbe_test.dart
provenance:
  mesure: 14
  deduit: 9
  document: 12
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1020
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:545
  - rhythm_coach/lib/screens/session_screen.dart:905
  - rhythm_coach/lib/services/ambience_engine.dart:331
  - rhythm_coach/lib/services/beep_engine.dart:690
  - rhythm_coach/lib/widgets/movement_animation.dart:854
---

# Relecture adverse — corrections d'octobre

[document] Relu : `fix/corrections-octobre` (7 commits au-dessus de `chore/fusion-octobre` @ `58ed4e3`), écrits par
claude-opus-5-5. Consigne : réfuter, pas valider. Rien fusionné, rien poussé, aucun fichier de code ni de test
modifié ; chaque rejeu et chaque mutation restaurés par copie depuis une sauvegarde, vérifiés par `cmp`, arbre
propre après chaque chaîne. Rien vu ni entendu sur le téléphone.

## Verdicts

| Commit | Objet | Verdict |
|---|---|---|
| `8b10083` | courbe : épingles de frontière oubliées hors liste | publiable avec réserves |
| `fecf23d` | punition : `_notify()` avant le délai de transition | publiable avec réserves — à trancher par Manu |
| `c96bbe4` | audio : allers-retours d'une tenue ancrée après pause | publiable avec réserves |
| `1ef5068` | audio : fondu qui annule un démarrage en vol | publiable avec réserves |
| `5fbb5ac` | tests M7 / M8 | publiable |
| `56266ca` | test M2 | publiable |

Waiver doc: tableau des verdicts — chaque ligne renvoie à sa section, marquée.

## Méthode et chiffres de lot

[mesuré] Référence sur `HEAD` (`fcc7c05`) : les 5 fichiers de test neufs, 46 verts en 1 min 12 s. Suite
complète : 1374 verts en 2 min 10 s (1361 + 13, comme annoncé). `flutter analyze` : « No issues found! ».

[mesuré] Rejeu de chaque cause : le seul fichier `lib/` du correctif ramené à sa version `58ed4e3` (copie depuis
l'objet git, jamais `git checkout`), test lancé, fichier restauré par copie, `cmp` vert. Même protocole pour
chaque mutation. Journaux dans le scratchpad de session, non conservés.

## 1. `8b10083` — courbe : épingles de frontière

[mesuré] **Cause rejouée.** `movement_animation.dart` d'avant : 4 rouges sur 4 routes, tous sur « Images en
avance » (`Expected: empty`). Premier point de tenue peint / attendu, en ms devant le curseur : FAIL + saut
1184 / 2019 ; mini-punition 1113 / 4061 ; posture 1672 / 4668 ; défi refusé 3119 / 13515. Les deux tests de
retard d'écran du même fichier restent verts : ils ne lisent pas ce fichier.

[mesuré] **Mutation « épingles vidées seulement quand la liste est vide »** (`if (widget.upcomingSteps.isEmpty)
_boundaryPins.clear();` à la place du `removeWhere`) : **6 verts**. Le banc ne distingue pas le correctif écrit
(une épingle par frontière encore annoncée) d'un correctif plus grossier (tout jeter quand la liste se vide) :
les quatre routes passent par `upcomingSteps: const []` (`session_screen.dart:905`, `isTimelineFrozen ||
isFailing`).

[mesuré] **Mutation « tout jeter à chaque recalcul »** (`_boundaryPins.clear()` inconditionnel), banc + les 13
`movement_*` : 1 rouge, `movement_rembobinage_tenue_gorge_test` (« step reporté pendant que la voix parle : la courbe ne rembobine pas à chaque tick »), 65 verts. Les épingles ont donc un rôle que la suite garde ; le correctif, qui ne retire que celles des secondes sorties de la liste, laisse ce test vert dans la suite complète.

[déduit] **La réserve de l'auteur « rebase sans liste vide » a-t-elle un cas ?** Une épingle code l'instant
mural d'une *seconde* de séance, pas d'un step : elle ne périme que si le lien `elapsed` ↔ horloge murale bouge
(gel, saut de `_timelineOffset`). Relevé des écritures de `_timelineOffset` et des remplacements de `_session` :
`_skipToNextSection` (sous `isFailing`), le gel de `_onTick` (`isTimelineFrozen`), `_excisChallengeFromSession`
et `requestPostChallengeRegen` (défi ou respiration post-défi, donc `isTimelineFrozen`), `_finish` (fin de
séance). `requestUpgrade` (« Utilise-moi ») remplace les steps **sans** toucher au lien : une épingle survivante y
reste juste. Je n'ai trouvé aucun rebase hors liste vide qui déplace le lien ; la réserve me paraît sans cas
concret — lecture, pas mesure.

[déduit] **Séance musicale** : `elapsed` y vient de la position du lecteur (`session_controller.dart:951`) ; un
lecteur qui tarde déplace le lien sans vider la liste. Préexistant et non touché : le correctif ne retire que les
épingles des secondes sorties de la liste. Non mesuré.

[déduit] **Pause** : la liste reste pleine, rien n'est retiré, `_resumeClock` décale les épingles comme avant.
`movement_reprise_pause_test.dart` : vert dans la suite complète.

[document] **Non établi.** Le rendu sur téléphone. L'effet d'une épingle survivante en séance musicale. Le
nettoyage des commentaires du fichier, annoncé non fait par l'auteur, reste à faire.

**Verdict : publiable avec réserves** — mineures : banc insensible à la forme exacte du filtre (mutation
verte) ; nettoyage de commentaires non fait.

## 2. `fecf23d` — punition : `_notify()` avant le délai

[mesuré] **Cause rejouée.** `session_controller_fail_flow.dart` d'avant : 2 rouges, « l'écran a montré le rythme
583 ms après le moteur » (mini-punition) et 664 ms (FAIL sans section suivante). Les 4 routes de courbe du même
fichier restent vertes.

[déduit] **Ce que le `_notify()` avancé fait voir.** À cet instant `_state == failing`, `_failPhase ==
punishment`, `_currentPunishment != null` : posés avant `_runPunishment`, remis à zéro seulement dans le
`finally` (`session_controller_fail_flow.dart:476-505` et `:227-258`). L'écran rend donc, pendant le délai de
transition du moteur (600 ms tenue → rythme) : `_StateBadge(failing)` et `_FailPhaseIndicator` « Punition —
<nom> » (`session_screen.dart:836-841`) **à côté** de la courbe du loop restauré (`MovementAnimation(mode:
ctrl.currentMode)`, lu sur le moteur, `session_controller.dart:1020`), avec `upcomingSteps` vide (`isFailing`) et
`elapsed` figé (`_stopwatch` relancé après). Avant le correctif, bandeau et courbe basculaient ensemble, 600 ms
trop tard.

[mesuré] **Sonde jetable** (copie du banc de l'auteur qui imprime chaque image où `ctrl.isFailing` et où la courbe
montre `rhythm`) : sur les deux routes (mini-punition, FAIL sans section suivante), 4 à 5 images consécutives montrent `state = failing`, `failPhase = punishment` **et** la courbe en `rhythm`, de 0 à 430-470 ms après la bascule du moteur ; `running` arrive à 611 et 639 ms. L'état intermédiaire dure tout le délai de transition, sur les deux routes. Sonde supprimée, arbre propre.

[déduit] Le chemin normal (`_checkSteps` → `applyStep` non attendu, `session_controller.dart:1686`) notifie lui
aussi pendant le délai : le correctif aligne la reprise sur lui. Mais sur le chemin normal, aucun bandeau de
punition ne reste affiché à côté.

[document] **Non établi.** Si le bandeau « Punition » visible 600 ms de plus que la courbe de la séance gêne ou
passe inaperçu : c'est un choix visible, et le rapport de l'auteur en déclare « aucun ». Une alternative (remettre
`_failPhase`/`_state` avant `_restorePreviousLoop`, ou notifier à l'instant du premier bip) n'a pas été explorée.
`_CurrentInstruction(text: ctrl.currentDisplayText)` pendant la fenêtre : non lu. Le rendu sur téléphone.

**Verdict : publiable avec réserves** — à trancher par Manu : l'état intermédiaire bandeau-punition + courbe de la
séance pendant un délai de transition.

## 3. `c96bbe4` — tenue ancrée : allers-retours après pause

[mesuré] **Cause rejouée.** `beep_engine.dart` d'avant : 2 rouges « aucun bip après la pause (pause à 2528 ms /
2501 ms) ».

[mesuré] **Mutations.**
- `_holdResumedAtMs = originMs;` retiré de `_startHoldSwingLoop` (ligne 692) : rouge ×2 — la pause ne mesure plus
  la progression, les allers-retours repartent de zéro.
- `_holdElapsedMs = 0;` retiré de la branche swing d'`applyStep` (ligne 332) : **vert** sur
  `beep_engine_hold_swing_pause_test`, `beep_engine_hold_swing_test`, `beep_engine_anchored_beat_test`,
  `session_controller_hold_verifier_swing_test` (16 tests). Trou : avant le correctif la boucle d'allers-retours
  ignorait `_holdElapsedMs` ; depuis elle le lit, et ce reset est ce qui empêche une tenue ancrée d'hériter la
  progression d'une tenue précédente mise en pause (ses premiers allers-retours seraient sautés). Aucun test ne
  tient cette ligne.
- `_playHoldOneShot(_to!);` retiré d'`applyStep` (ligne 331) : rouge ×2, mais sur la garde « la tenue ne sonne
  pas » (2 s d'attente du premier bip), pas sur une assertion du coup de départ ; les trois autres fichiers
  restent verts. Le coup de départ d'une tenue ancrée n'est gardé que par ricochet.

[déduit] **Pause pendant le gap de transition** (`tss2-022`, préexistant) : `_holdResumedAtMs` est nul pendant
le gap (ligne 283), donc `pause()` n'actualise pas `_holdElapsedMs`. `resume()` **dans** le gap lance une boucle
d'allers-retours avec la progression d'une tenue antérieure ; la fin du gap la remplace (`_holdElapsedMs = 0`,
nouvelle boucle) — l'erreur se résorbe seule. `resume()` **après** le gap : la boucle partie pendant la pause
(tss2-022) est coupée et les allers-retours repartent de zéro, là où le code d'avant laissait le silence. Non
mesuré.

[déduit] **Pause/reprise répétées** : `pause()` pose `_holdElapsedMs = now − originMs` avec `originMs = reprise −
progression`, donc la progression s'accumule hors pauses. Juste par construction, non mesuré. **Fin de step
pendant la pause** : le ticker du contrôleur est arrêté, l'horloge de séance ne bouge pas, les minuteries du
moteur sont coupées par `_stopLoop`.

[déduit] Détail : la comparaison stricte `<` du saut ne **saute pas** un aller-retour tombé exactement à
l'instant de la pause, elle le rejoue à 1 ms — l'inverse de ce qu'écrit l'auteur. Sans conséquence audible.

[mesuré] **Déterminisme.** Test en temps réel (`Future.delayed`, tolérance ±120 ms). 5 relances du fichier seul : 5 × 2 verts (13 s chacune). Suite complète, fichiers en parallèle : vert.

[document] **Non établi.** Le rendu sonore réel. La tenue de la tolérance de 120 ms sous une charge plus forte
que celle des relances faites.

[document] **Verdict : publiable avec réserves** — mineure : le reset `_holdElapsedMs = 0` de la branche swing n'est tenu
par aucun test (mutation verte).

## 4. `1ef5068` — fondu pendant un démarrage de musique de finish

[mesuré] **Cause rejouée.** `ambience_engine.dart` d'avant : 1 rouge (`Expected: false`, `Actual: <true>`) ;
les 35 autres tests du lot finish (`finish_music_test`, `ambience_climax_test`,
`session_music_controller_test`), dont M8, restent verts.

[mesuré] **Mutation « bump inconditionnel »** (`_finishGen++` sans la condition `_finishStartGen ==
_finishGen`) : **36 verts**. Le rapport affirme qu'« un fondu demandé pendant un autre fondu reste sans effet,
comme avant (sinon le premier s'interromprait à mi-volume) » : c'est cette condition qui le garantit, et rien ne
la tient. Deux fondus à moins de 3 s sont atteignables : fondu de fin de montée (`session_controller.dart:1786`)
puis FAIL (`session_controller_fail_flow.dart:100`).

[déduit] **Relance légitime après fondu (M8)** : `startFinishMusic` repose `_finishStartGen = ++_finishGen`, le
fondu précédent n'y touche plus. Juste par lecture ; les deux tests M8 sont verts avec le correctif. **Risque
voisin, mineur** : un démarrage encore en vol quand le suivant commence (délai de garde 3 s, flow de fail court)
voit `gen != _finishGen` et appelle `_finishPlayer?.stop()` — le lecteur est partagé, il coupe le nouveau
démarrage. Même famille que `stopFinishMusic` + relance (préexistant) ; le correctif ouvre ce chemin au fondu.
Non construit ; fiche `tss2-024` au sas.

[document] Le test lit `isFinishMusicPlaying`, pas l'arrêt du lecteur ; `_finishPlayer` est nul dans le faux
moteur, donc le `stop()` n'est pas exercé (reconnu par l'auteur). `_finishStartGen` n'est jamais remis à nul :
la condition reste exacte (« démarrage en vol ou échoué »).

**Verdict : publiable avec réserves** — mineure : « fondu pendant fondu » affirmé, non gardé (mutation verte).

## 5. `5fbb5ac` et `56266ca` — tests seuls

[mesuré] M7 (garde `_music != null` de `session_controller.dart:1784` retirée) : rouge sur le seul test M7 (« la musique de finish ne joue pas par-dessus le morceau »), 32 verts. M8 (ligne 99 du flow
de fail supprimée) : rouge sur le seul test « un FAIL pendant la montée relance la musique » ; la mini-punition reste verte, la mutation vise bien la ligne du FAIL. M2 (garde de `session_screen.dart:905` réduite à `failPhase == punishment`) : rouge sur le seul test M2 (« pendant la phrase et la respiration d'avant-punition, l'écran n'annonce pas la suite »), 4 verts.

[mesuré] **Déterminisme** des bancs d'écran (reprise, respiration, finish), relancés ensemble : 3 passages des trois fichiers ensemble (référence + 2 relances) : 17 verts à chaque fois en 1 min 12 s ; aucun rouge dans la suite complète.

[document] **Verdicts : `5fbb5ac` publiable ; `56266ca` publiable.**

## Ce que je n'ai pas pu établir

- [document] Rien vu ni entendu sur le téléphone, pour les quatre correctifs.
- [document] Épingles : aucun cas concret de « rebase sans liste vide » trouvé, mais par lecture seulement ; la séance
  musicale n'est pas mesurée.
- [document] Le poids visuel de l'état intermédiaire du §2 : compté au banc, pas jugé à l'œil.
- [document] `tss2-022` reste ouvert ; `c96bbe4` ne l'aggrave pas et ne le corrige pas.
- [document] Nettoyage des commentaires des quatre fichiers : non fait par l'auteur, hors mandat ici.
