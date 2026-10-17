# Relecture adverse — `feat/bips-coherents` @ `93584da` dans la fusion d'octobre (2026-10-17)

Relecteur : Fable 5.1. Branche partie d'`origin/develop` @ `c57bdcd`, 15 commits : 51 fichiers dont
19 mp3, +1744/−317. Relue telle qu'elle est dans la fusion (HEAD `6ab1e82`). Consigne : réfuter, pas
valider. Aucun son écouté : les qualités sonores (bips « très bien », lick identifiable, tenue qui
résonne) restent le jugement de Manu du 06/10. Rien de modifié hors ce rapport ; sonde jetable
supprimée, mutations restaurées par copie, arbre propre vérifié.

## Ce que la joueuse vit

Bips sourds d'une même famille (rampe tip→full d'un seul son transposé), son de tenue qui résonne, sons
de lick par position, souffle « coup étouffé + bouffée d'air ». Deux packs d'ambiance voix (bruitages
par palier de profondeur, variantes tirées au hasard), gémissements réservés au climax. Une musique de
montée pendant le finish, sommet calé sur le final, fondu au post-final. Pack et volumes retenus d'un
lancement à l'autre.

## Ce qui a été vérifié

| Vérification | Résultat |
|---|---|
| Commit `docs(audio)` `93584da` | 0 ligne de code différente hors commentaires |
| Suite ciblée (7 fichiers de test de la branche, dans les 126 verts des quatre travaux) | verte |
| Les 4 `ambience_packs*.json` | identiques hors `lang` (clés, fichiers, paliers, climax) |
| `.gitignore` ↔ assets : `assets/audio/ambience/*.mp3` et `assets/audio/music/*.mp3` ignorés ; `release.yml` et `web-deploy.yml` synchronisent `ambience/v1/` et `music/v1/` depuis R2 ; les 22 bips (`*_beep`, `finale_chime`, `freestyle_*`) et `finish_music.mp3` sont trackés | cohérent ; les 27 mp3 référencés par les packs sont tous sous `audio/ambience/` (R2) |
| Lecteurs `finish_music` et `ambience_climax` : `positionUpdater = null` (`ambience_engine.dart:305`, `208`) | conforme au correctif `fix/audio-suivi-position` |
| Focus audio Android `none` sur ambiance, climax et finish | posé dans `_withoutFocus` pour les trois |
| `restore(packs)` branché dans `mode_selection_screen.dart:70` | câblage présent ; le test `volume_and_ambience_persistence_test` ne teste que le moteur, pas l'écran (déjà noté dans la mémoire du 03/10) |
| Correctif `03181a9` « pas de musique de finish en séance musicale » | présent (`session_controller.dart:1784`) |

## Mutations (restaurées par copie)

| Id | Ligne mutée | Suite | Résultat |
|---|---|---|---|
| M7 | `session_controller.dart:1784` — garde `_music != null` retirée | `finish_music_test` + `session_music_*` (89) | **verte : non gardée** — le correctif `03181a9` n'a aucun test |
| M8 | `session_controller_fail_flow.dart:99` et `:464` — `_finishMusicStarted = false` retiré sur fail | `finish_music_test` + `*fail*` (9) | **verte : non gardée** — la relance de la musique après un fail dans le finish n'est pas testée |
| M14 | `ambience_engine.dart:246` — palier « profond » à partir de `full` au lieu de `throat` | `ambience_variants_test` + `ambience_climax_test` | rouge (2) : gardée |

## Sonde jetable : course entre démarrage et fondu

`startFinishMusic` (`ambience_engine.dart:287-301`) attend `startFinishPlayback` (jusqu'à 3 s de
timeout) **avant** de poser `_finishPlaying = true`. `fadeOutFinishMusic` (`:323`) sort immédiatement
si `_finishPlaying` est faux. Un fail qui tombe pendant ce démarrage demande donc un fondu qui ne fait
rien, puis le démarrage aboutit et la musique joue pendant la punition.

Sonde : faux `startFinishPlayback` de 300 ms, fondu demandé à 50 ms, attendu `isFinishMusicPlaying`
faux → **rouge : `true`**. Fenêtre réelle = durée de `setSource + seek + resume` sur l'appareil
(quelques dizaines à quelques centaines de ms, 3 s au pire) ; l'événement déclencheur (fail dans cette
fenêtre) est rare. `stopFinishMusic` n'a pas ce défaut (il incrémente `_finishGen` sans condition).

## Ce que je n'ai pas pu établir

1. ⚠️ **`finish_music.mp3` est un morceau Suno tracké dans le dépôt public** (`9baff98`, tags ffprobe
   « Holding the Tension », auteur `kwizer15`, 90 s, 1,8 Mo). La vérification des CGU Suno du 07/10
   (mémoire `project_seance_musicale`) conclut qu'un morceau de l'offre gratuite n'est pas couvert pour
   une diffusion publique. Les morceaux de séance ont été tenus hors dépôt (R2) pour cette raison ;
   celui-ci est dans l'historique git. Ce n'est pas un défaut de code : c'est une décision de Manu.
2. **Sommet de la musique vs instant réel du chime.** Le départ est calé sur `finalT − step.time` en
   temps de séance ; un gel d'horloge entre ce step et le final (posture, défi, `awaitReady`) décale le
   sommet d'autant. Je n'ai pas vérifié si une phase de finish peut contenir un gel.
3. **Démarrage sans fondu d'entrée.** Si aucun step ne tombe entre `max(finishStart, finalT − 70)` et le
   final (longue tenue), la musique part au step suivant, déjà engagée dans sa montée. Non mesuré sur
   les séances générées.
4. **`tools/generate_beeps.sh`** régénère 15 sinus dans `assets/audio/` : lancé par mégarde, il écrase
   les bips ElevenLabs trackés (la mémoire du 02/10 le note déjà). `CLAUDE.md` (lignes 72, 94, 336,
   855) le documente encore comme outil de régénération. Mineure, documentaire.
5. **Volume voix écrit dans les prefs à chaque `onChanged` du curseur** (`session_screen.dart:1004`),
   pas à `onChangeEnd` : des dizaines d'écritures par glissement. Sans conséquence constatée.
6. Le `restore` de l'écran d'accueil n'est gardé par aucun test (déjà noté le 03/10).

## Verdict

**Publiable avec réserves.**

- Bloquante : aucune au sens du code. **(1) bloque la release** si la lecture des CGU du 07/10 tient :
  un fichier Suno tracké dans un dépôt public, et déjà dans l'historique.
- À trancher par Manu : (1) ; la course démarrage/fondu (musique pendant une punition, rare) ; (2).
- Mineures : deux lignes non gardées (M7, M8) ; (3) ; (4) ; (5) ; (6).
