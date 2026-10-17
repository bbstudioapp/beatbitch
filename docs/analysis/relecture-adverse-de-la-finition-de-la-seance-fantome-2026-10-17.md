---
type: analyse
sujet: relecture-adverse-de-la-finition-de-la-seance-fantome
ecrit_le: 2026-10-17T17:28:32+02:00
auteur: session tss2-relecture2-fantome · claude-opus-5-5
revision: d0a4d6a
branche: fix/seance-fantome
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/services/music_engine.dart
  - rhythm_coach/test/session_start_after_dispose_test.dart
provenance:
  mesure: 4
  deduit: 2
  document: 5
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1176
  - rhythm_coach/lib/controllers/session_controller.dart:1920
  - rhythm_coach/lib/services/music_engine.dart:96
---

# Relecture adverse de la finition de la séance fantôme

Périmètre : `bd57731..d0a4d6a` sur `fix/seance-fantome` (`59835a6`, `cc4bcd3`, `d0a4d6a`).

## Verdicts

| Commit | Verdict |
|---|---|
| `59835a6` correctif lecteur orphelin | publiable avec réserves |
| `cc4bcd3` banc des arrêts de `_finish` | publiable |
| `d0a4d6a` rapport | publiable avec réserves |

## `59835a6` — garde avant `music.start`, libération après

[document] Pour une séance musicale normale, `_released` vaut faux aux deux gardes : le chemin `music.start` → `attachMusic` est inchangé. `_released` n'est jamais remis à faux ; seuls `dispose()` et `detachAudio()` le posent.

[mesuré] Code d'origine (les deux gardes retirées) : rouge sur le test neuf, `Expected: false Actual: <true>` (`playing`). Garde d'avant seule retirée : rouge `Expected: <0> Actual: <1>` (`loads`), y compris joué seul (`--plain-name`) ; `playing` et `created` passent, donc la libération d'après est exécutée et nettoie le lecteur. Libération d'après seule retirée : vert, 10 tests sur 10.

[document] audioplayers 6.6.0 : `AudioPlayer.dispose()` passe l'état à `disposed` ; un second `dispose()` appelle `stop()`, qui envoie `_platform.stop(playerId)` puis lève `AudioPlayer has been disposed` en posant l'état. `_bounded` l'attrape, borné à 300 ms par appel. Android 5.2.1 : `create` écrase `players[playerId]`, `dispose` le retire.

[déduit] En production, la libération d'après ne s'exécute que si `dispose()` tombe pendant `music.start` ; le `dispose()` du contrôleur a alors déjà libéré le lecteur réel, et un lecteur libéré ne rejoue pas (`resume` lève). Elle ne change donc rien au son : elle envoie un `stop` natif tardif sur l'identifiant fixe `'session_music'`, qui atteint le lecteur d'un contrôleur suivant s'il existe déjà (`tss2-015`). Le chemin d'échec de `MusicEngine.start` envoie déjà ce même `stop` au même instant : le surcoût est marginal. Pas de blocage : au plus deux appels bornés avant le `return`.

Recommandation : **retirer** la libération d'après. Elle ne garde aucune fenêtre que le lecteur réel laisse ouverte, aucun test ne la tient, et la régression qu'elle amortirait (garde d'avant retirée) est déjà rouge sur le banc. La garder reste défendable comme défense en profondeur ; à trancher par Manu.

Réserve : le `expect(b.port.playing, isFalse)` ajouté au test « pendant `music.start` » n'est pas une preuve rouge — sur le code d'origine le faux lecteur libéré ne rejoue pas, l'assertion était déjà verte.

## `cc4bcd3` — banc

[mesuré] Banc vert ×3 (10 tests, sortie 0). M3 (garde de `_finish` déplacée sous les trois arrêts) : rouge sur le test neuf, `Expected: <1> Actual: <2>` (arrêts du `BeepEngine`).

[document] Fidélité : `created`, `playing`, `loads`, `stops` sont des compteurs d'observation, aucun n'est lu par le code de production ; l'interface `MusicPlayerPort` est inchangée. `_GatedPrefsStore` hérite d'`InMemorySharedPreferencesStore` et ne surcharge que `getAll()` ; `setUp` remet le store par `setMockInitialValues`.

[déduit] Écart sans effet sur le verdict : le faux `play()` après `dispose()` rend la main sans rien faire, le vrai lève. Les deux finissent dans le chemin d'échec de `MusicEngine.start`. Le faux est plus pessimiste que le vrai si `positions` est relu après `dispose()` (il se « recrée ») : il ne peut pas masquer un défaut.

## `d0a4d6a` — rapport

[document] « première ligne de `_finish()` » : exacte, bornée à l'entrée de la clôture ; les écrivains par tick non gardés et `tss2-025` sont nommés.

[document] « la garde après `music.start` ne faisait que `return` … `start()` lançait ensuite un lecteur que personne n'arrêtait » : exacte, confirmée par le rouge sur le code d'origine.

Réserve : « la garde d'avant ferme la seule fenêtre atteignable » suit le marqueur [mesuré] du paragraphe, mais c'est une déduction : une mutation verte prouve qu'aucun test ne tient la ligne, pas que la fenêtre est inatteignable.

## Suite

[mesuré] `flutter test` complet : +1409, sortie 0. `flutter analyze` : aucun problème. `dart format --set-exit-if-changed .` : 368 fichiers, 0 modifié, sortie 0. Arbre propre après chaque mutation (`cmp`).

## Ce que je n'ai pas pu établir

- Comportement d'un `AudioPlayer` libéré sur iOS et web (seul le code Android et Dart a été lu).
- Délai réel entre `dispose()` et la fin de `music.start` sur le téléphone, donc la probabilité qu'un contrôleur suivant possède déjà `'session_music'`.
