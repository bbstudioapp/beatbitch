import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

SessionStep _step({
  SessionMode mode = SessionMode.rhythm,
  String text = 'consigne',
  int bpm = 60,
}) {
  return SessionStep(
    time: 0,
    text: text,
    mode: mode,
    bpm: bpm,
    from: Position.head,
    to: Position.tip,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BeepEngine.stepSerial', () {
    test('avance à chaque step appliqué, y compris à configuration identique',
        () {
      final beep = BeepEngine();
      expect(beep.stepSerial, 0);

      final step = _step();
      beep.applyStep(step, SessionMode.rhythm).ignore();
      expect(beep.stepSerial, 1);

      beep.applyStep(step, SessionMode.rhythm).ignore();
      expect(
        beep.stepSerial,
        2,
        reason: 'le même step réappliqué passe quand même par le gap',
      );
    });

    test('n\'avance pas sur un step text-only', () {
      final beep = BeepEngine();
      beep
          .applyStep(
            const SessionStep(time: 0, text: 'juste une phrase'),
            SessionMode.rhythm,
          )
          .ignore();
      expect(beep.stepSerial, 0);
    });
  });
}
