---
type: analyse
sujet: la-seance-fantome-start-survit-a-dispose
ecrit_le: 2026-10-17T16:45:52+02:00
auteur: session tss2-seance-fantome · claude-sonnet-5-5
revision: ca62921
branche: fix/seance-fantome
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/test/session_start_after_dispose_test.dart
provenance:
  mesure: 5
  deduit: 2
  document: 4
  sans_marqueur: 1
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1090
  - rhythm_coach/lib/controllers/session_controller.dart:1915
  - rhythm_coach/lib/controllers/session_controller.dart:2480
  - rhythm_coach/lib/controllers/session_controller.dart:2493
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

# Séance fantôme : `start()` survivait à `dispose()` (tss2-013)

## Constat

[document] `SessionController.start()` attend `_tts.init`, `_beep.init`, `music.start` (séance à morceau) et le wakelock alors que `_state` vaut encore `idle`. Le retour arrière est donc libre (`PopScope(canPop: ctrl.isIdle || …)`), et `dispose()` ne change pas `_state`. `start()` ne testait rien après ses `await`.

[mesuré] Rejoué contre `ef73c5f` avec des portes que le test tient puis ouvre (`test/session_start_after_dispose_test.dart`, commit `37fb7f1`) : six cas rouges sur huit, les deux témoins verts.

- [mesuré] `applyStep` sur le `BeepEngine` partagé après `dispose()` : attendu 0, obtenu 1 (cas `_tts.init`, wakelock, `music.start`).
- Profil écrit par une séance jamais jouée (cas `_beep.init`, `detachAudio`), séance de 1 s : `stats.total_seconds`, `stats.sessions_completed`, `stats.sessions_no_fail_streak`, `stats.last_session_day`, `stats.daily_streak`, `stats.obedience_level`, `stats.humiliation_level`, `badge.tier.sansBroncher` en plus de `stats.modes_used_mask`. Même liste que la sonde de la fiche.
- `_finish()` appelé sur un contrôleur libéré : mêmes clés ajoutées au profil.
- `detachAudio()` pendant `start()` : même défaut (le ticker annulé est relancé).
- Séance à morceau : la grille du morceau est attachée au `BeepEngine` partagé après `dispose()`.
- Témoins verts : `dispose()` après la fin de `start()` (aucun `applyStep` de plus, horloge figée) ; séance à morceau menée jusqu'au bout (grille attachée, wakelock pris).

[mesuré] Le premier jet masquait le fond derrière l'assert de debug « A SessionController was used after being disposed » ; les assertions sur `applyStep`, l'état, l'horloge et le profil passent maintenant avant celle-là.

## Correctif (`fcf81f1`)

[document] `session_controller.dart`, une garde `if (_released) return;` sur l'état, pas sur un nom de méthode : `_released` est posé par `dispose()` et par `detachAudio()` et n'est jamais rebaissé.

- [document] l. 1161 après `_tts.init`, l. 1167 après `_beep.init`, l. 1177 après `music.start` (la grille n'est pas attachée) ;
- après le wakelock : si libéré, `WakelockPlus.disable()` borné par `_wakelockTimeout`, puis retour ;
- l. 1916, première ligne de `_finish()` : aucune écriture ne part d'un contrôleur libéré.

## Mutations

[mesuré] Chaque garde retirée seule, restauration par `cp` puis `cmp` (identique), arbre propre après.

| Garde retirée | Test rouge | Assertion |
|---|---|---|
| après `_tts.init` | `_tts.init` | `_beep.init()` appelé après `dispose()` (0 → 1) |
| après `_beep.init` | `_beep.init` et `detachAudio` | wakelock enclenché (0 → 1) |
| après `music.start` | séance à morceau | grille laissée sur le `BeepEngine` |
| bloc wakelock entier | wakelock | `applyStep` après `dispose()` |
| `WakelockPlus.disable()` seul | wakelock | écran maintenu allumé (`false` → `true`) |
| `_finish` : garde d'entrée | `_finish` | clés ajoutées au profil |
| les quatre gardes de `start()` ensemble | cinq cas de `start()` | retour au défaut d'origine |

## Vérifications de fin

[mesuré] `flutter analyze` : « No issues found! ». `dart format --set-exit-if-changed .` : 0 fichier changé. `flutter test` : 1407 tests, tous verts.

## Ce que je n'ai pas pu établir

- [déduit] La lecture du réglage d'avance des bips (`getMusicBeepAdvanceMs`) n'a pas de garde propre : un `dispose()` pendant cette lecture est rattrapé par la garde après `music.start`, après un lancement de lecteur inutile. Non testé : la lecture de `SharedPreferences` ne se retient pas.
- [déduit] Le wakelock est relâché sans condition à l'abandon tardif, y compris après `detachAudio()`, alors que `dispose()` ne le relâche pas quand le contrôleur est déjà détaché. Course théorique avec la séance suivante ; le chemin « encore » ne la produit pas (`start()` est terminé quand `detachAudio()` est appelé).
- [document] `_finish()` est gardé à l'entrée seulement. Un `dispose()` en cours de clôture continue d'écrire : une séance réellement jouée reste comptée, comme les autres usages de `_released` dans `_finish`.
- [non vérifié] `stop()` pendant `start()` en vol : même fenêtre, non examinée.
- [non vérifié] Durée réelle de la fenêtre sur téléphone, comportement en arrière-plan Android, aucune écoute (interdit).
- [non vérifié] Déterminisme du nouveau banc : un seul passage vert, plus les sept mutations ; pas de relances répétées. Trois cas attendent 0,5 à 2,5 s d'horloge réelle.
- Commentaires : seuls `start()` et la doc de `_released` sont nettoyés (commit `ca62921`, code identique hors commentaires). Le reste de `session_controller.dart` (environ 2 500 lignes, dont `_finish`) n'a pas été balayé : plafond de jetons.
