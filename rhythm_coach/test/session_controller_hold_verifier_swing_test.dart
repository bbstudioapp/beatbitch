import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chantier aimant, étape 4 : un final `hold` ancré (les 3-4 allers-retours
/// voulus par Manu) n'arme pas le `HoldVerifier` — le mouvement est demandé
/// par l'app, pas une dérive à sanctionner. Un hold normal continue de
/// s'armer comme avant.
void main() {
  group('SessionController.shouldArmHoldVerifier', () {
    test('hold normal (non ancré) : s\'arme', () {
      const step = SessionStep(
        time: 0,
        mode: SessionMode.hold,
        to: Position.full,
      );
      expect(
        SessionController.shouldArmHoldVerifier(step, SessionMode.hold),
        isTrue,
      );
    });

    test('final hold ancré (anchor == to) : ne s\'arme pas', () {
      const step = SessionStep(
        time: 0,
        mode: SessionMode.hold,
        to: Position.full,
        anchor: BeatAnchor.to,
        ratio: 9,
      );
      expect(
        SessionController.shouldArmHoldVerifier(step, SessionMode.hold),
        isFalse,
      );
    });

    test('mode hérité du défaut de séance (step.mode == null)', () {
      const anchoredStep = SessionStep(
        time: 0,
        to: Position.full,
        anchor: BeatAnchor.to,
      );
      expect(
        SessionController.shouldArmHoldVerifier(anchoredStep, SessionMode.hold),
        isFalse,
      );
      const plainStep = SessionStep(time: 0, to: Position.full);
      expect(
        SessionController.shouldArmHoldVerifier(plainStep, SessionMode.hold),
        isTrue,
      );
    });

    test('modes non-hold : jamais armé, ancré ou non', () {
      const step = SessionStep(
        time: 0,
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.mid,
        bpm: 90,
        anchor: BeatAnchor.to,
      );
      expect(
        SessionController.shouldArmHoldVerifier(step, SessionMode.rhythm),
        isFalse,
      );
    });
  });
}
