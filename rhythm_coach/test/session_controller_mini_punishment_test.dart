import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/controllers/session_controller.dart';

void main() {
  group('SessionController.computeMiniPunishmentTrigger', () {
    test('rate 0 → jamais de mini-punition', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          rate: 0.0,
          rngValue: 0.0,
        ),
        isFalse,
      );
    });

    test('rate négatif → jamais', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          rate: -0.5,
          rngValue: 0.0,
        ),
        isFalse,
      );
    });

    test('rng strictement sous le rate → déclenche', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          rate: 0.20,
          rngValue: 0.0,
        ),
        isTrue,
      );
      expect(
        SessionController.computeMiniPunishmentTrigger(
          rate: 0.20,
          rngValue: 0.19,
        ),
        isTrue,
      );
    });

    test('rng au seuil ou au-dessus → ne déclenche pas', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          rate: 0.20,
          rngValue: 0.20,
        ),
        isFalse,
      );
      expect(
        SessionController.computeMiniPunishmentTrigger(
          rate: 0.20,
          rngValue: 0.30,
        ),
        isFalse,
      );
    });
  });
}
