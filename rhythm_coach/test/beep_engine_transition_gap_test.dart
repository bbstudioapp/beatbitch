import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BeepEngine.transitionGap', () {
    test('même mode : 300 ms, quel que soit le mode', () {
      for (final mode in SessionMode.values) {
        expect(
          BeepEngine.transitionGap(incoming: mode, previous: mode),
          const Duration(milliseconds: 300),
          reason: mode.name,
        );
      }
    });

    test('changement de mode vers rhythm/hold : 600 ms', () {
      for (final mode in [SessionMode.rhythm, SessionMode.hold]) {
        expect(
          BeepEngine.transitionGap(incoming: mode, previous: SessionMode.beg),
          const Duration(milliseconds: 600),
          reason: mode.name,
        );
      }
    });

    test(
      'changement de mode vers lick/hand/biffle/breath/freestyle/suckle : '
      '1500 ms',
      () {
        for (final mode in [
          SessionMode.lick,
          SessionMode.hand,
          SessionMode.biffle,
          SessionMode.breath,
          SessionMode.freestyle,
          SessionMode.suckle,
        ]) {
          expect(
            BeepEngine.transitionGap(
                incoming: mode, previous: SessionMode.rhythm),
            const Duration(milliseconds: 1500),
            reason: mode.name,
          );
        }
      },
    );

    test('changement de mode vers beg : 1500 ms libre, 600 ms avec to', () {
      expect(
        BeepEngine.transitionGap(
          incoming: SessionMode.beg,
          previous: SessionMode.rhythm,
        ),
        const Duration(milliseconds: 1500),
      );
      expect(
        BeepEngine.transitionGap(
          incoming: SessionMode.beg,
          previous: SessionMode.rhythm,
          incomingTo: Position.throat,
        ),
        const Duration(milliseconds: 600),
      );
    });

    test(
        'previous null (premier step de la séance) compte comme un '
        'changement de mode', () {
      expect(
        BeepEngine.transitionGap(incoming: SessionMode.rhythm, previous: null),
        const Duration(milliseconds: 600),
      );
    });
  });
}
