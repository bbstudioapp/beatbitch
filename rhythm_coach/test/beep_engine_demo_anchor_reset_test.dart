import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// `startRhythmDemo` (écran de démo des sons) doit réinitialiser l'ancrage
/// laissé par le dernier step de séance joué — sinon l'écran de démo hérite
/// d'un ancrage qui n'a rien à voir avec les valeurs bpm/from/to qu'il
/// affiche (cf. relecture adverse des étapes 1-2). Sondé via le tout premier
/// battement du loop réel (émis de façon synchrone dans `_startBeatLoop`),
/// pas via `configureBeatSourceForTest` qui écraserait justement l'ancrage
/// et masquerait un oubli de reset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startRhythmDemo réinitialise l\'ancrage hérité d\'un step précédent',
      () async {
    final engine = BeepEngine();
    await engine.init();
    // Ancrage hérité d'un step rythmé précédent (from, ratio 3).
    engine.configureBeatSourceForTest(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      anchor: BeatAnchor.from,
      ratio: 3,
    );

    final intervals = <int>[];
    engine.onBeat = (e) => intervals.add(e.nextInterval.inMilliseconds);
    engine.startRhythmDemo(from: Position.head, to: Position.mid, bpm: 200);
    // Le tick de `_startBeatLoop` est synchrone : un battement est déjà
    // émis au retour de `startRhythmDemo`.
    expect(intervals, hasLength(1));
    // T=300ms à 200bpm — intervalle régulier attendu si l'ancrage a bien
    // été réinitialisé. Avec l'ancrage hérité (from/ratio 3) non réinitialisé,
    // le premier bip (position = to, alternateToggle démarre à true) aurait
    // donné l'intervalle court 150ms.
    expect(intervals.single, 300);

    engine.stop();
  }, timeout: const Timeout(Duration(seconds: 10)));
}
