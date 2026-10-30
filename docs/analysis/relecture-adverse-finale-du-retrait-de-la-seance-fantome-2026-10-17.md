---
type: analyse
sujet: relecture-adverse-finale-du-retrait-de-la-seance-fantome
ecrit_le: 2026-10-17T17:40:18+02:00
auteur: session tss2-relecture3-fantome · claude-opus-5-5
revision: a46b6a3
branche: fix/seance-fantome
porte_sur:
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/services/music_engine.dart
  - rhythm_coach/test/session_start_after_dispose_test.dart
provenance:
  mesure: 3
  deduit: 5
  document: 4
  sans_marqueur: 2
sources_citees: []
relu_contre:
  - rhythm_coach/lib/controllers/session_controller.dart:1176
  - rhythm_coach/lib/services/music_engine.dart:100
  - rhythm_coach/test/session_start_after_dispose_test.dart:452
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 2 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

Waiver doc: chiffres sans marqueur — numéros de fiche et hashes de commit, pas des mesures.

Troisième et dernier round de relecture adverse du correctif de la séance fantôme (`tss2-013`), sur le seul diff `0ffb262..a46b6a3` de `fix/seance-fantome`.

## Verdicts

- `a31bdb1` (retrait de la libération après `music.start` et de l'assertion `playing` du test « pendant `music.start` ») : **publiable**.
- `a46b6a3` (rapport) : **publiable avec réserves**.

## Le retrait laisse-t-il un lecteur en lecture sans propriétaire ?

- [document] `MusicEngine.start()` crée le lecteur réel à la demande, juste après `await _release()`. [déduit] Sans lecteur existant, `_release()` se termine sans attente réelle : l'`await` ne rend la main qu'aux microtâches, et un `dispose()` venu de l'écran ne peut pas s'y glisser. Tout `dispose()` atteignable trouve donc le lecteur déjà créé et le libère.
- [document] `SessionController.dispose()` lance `_music?.dispose()` sans l'attendre : abonnements annulés tout de suite, `stop` puis `dispose` du lecteur envoyés (bornés à 300 ms, pas annulés). Après l'annulation de l'abonnement, le premier rapport de position ne peut plus arriver : `music.start` finit en délai dépassé et renvoie faux.
- [document] `audioplayers` 6.6.0 : `resume()` sur un lecteur libéré appelle encore le natif ; Android 5.2.1 lève sur un id retiré. [déduit] Un `setSource`/`resume` en vol arrivé avant le `dispose()` natif est défait par lui ; arrivé après, il lève. Sur Android, rien ne reste en lecture : aucun cas atteignable trouvé où la libération retirée servait.
- [déduit] Le retrait supprime un `stop`/`dispose` tardif, pas tous : un `start()` en vol envoie encore `setSource`/`resume` puis, dans son `catch`, un `stop` natif sur l'id fixe `'session_music'`. Avec un contrôleur musical suivant déjà créé, ils pilotent son lecteur. Fiche `tss2-029` (extension de `tss2-015`).

## L'assertion retirée ne gardait-elle rien ?

- [document] Dans le faux lecteur, la porte est dans `play()` et `play()` ne passe `playing` à vrai que si `created` ; le `dispose()` du `MusicEngine`, lancé par celui du contrôleur, remet `created` à faux avant l'ouverture de la porte.
- [mesuré] Sonde : assertion `playing` remise en tête du test « pendant `music.start` », garde après `music.start` supprimée en entier. La sonde passe ; le test rougit sur `attachedTrack` (`Expected: null`, `Actual: <Instance of 'SessionMusic'>`). Elle ne pouvait rougir sur aucune variante du code d'après `music.start`. Code et test restaurés par copie (`cmp`).

## La garde d'avant est-elle toujours tenue ?

- [mesuré] Garde avant `music.start` retirée : rouge sur « pendant la lecture du réglage d'avance », ligne 193, `Expected: false`, `Actual: <true>`, « morceau laissé en lecture sans propriétaire ». Restaurée par copie (`cmp`).
- [mesuré] Suite complète : +1409, tout vert, sortie 0. `flutter analyze` : aucun problème.

## Réserves

- [déduit] Rapport : « le lecteur réel est déjà libéré par le `dispose()` du contrôleur » est trop affirmatif. La libération est lancée, sans attente ; elle peut finir après `music.start`.
- [déduit] Rapport : la raison donnée (un second `dispose()` enverrait un `stop` natif tardif) est exacte, mais elle laisse croire que le retrait supprime les appels tardifs. Il en reste (`tss2-029`).

## Ce que je n'ai pas pu établir

- [non vérifié] `AudioPlayer` libéré sur iOS et web : seuls le Dart et l'Android ont été lus.
- [non vérifié] L'atteignabilité de `tss2-029` : deux séances musicales à moins de quelques centaines de millisecondes d'écart.
- [non vérifié] Un `dispose()` déclenché depuis une microtâche (pas depuis l'écran) entre `_release()` et la création du lecteur : aucun appelant de ce genre cherché.
