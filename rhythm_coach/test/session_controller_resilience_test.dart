import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm_coach/career/models/specialization.dart';
import 'package:rhythm_coach/controllers/session_controller.dart';

SpecializationAllocation _alloc(int resiliencePts) {
  return SpecializationAllocation(
    points: {
      for (final b in SpecializationBranch.values)
        b: b == SpecializationBranch.resilience ? resiliencePts : 0,
    },
    lastRespecMs: null,
  );
}

void main() {
  group('SessionController.computeMiniPunishmentTrigger', () {
    test('allocation null → jamais de mini-punition', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: null,
          rngValue: 0.0,
        ),
        isFalse,
      );
    });

    test('0 pt résilience → jamais', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: _alloc(0),
          rngValue: 0.0,
        ),
        isFalse,
      );
    });

    test('5 pts résilience + rng=0.0 → déclenche', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: _alloc(5),
          rngValue: 0.0,
        ),
        isTrue,
      );
    });

    test('5 pts résilience + rng=0.24 → déclenche (sous 0.25)', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: _alloc(5),
          rngValue: 0.24,
        ),
        isTrue,
      );
    });

    test('5 pts résilience + rng=0.30 → ne déclenche pas', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: _alloc(5),
          rngValue: 0.30,
        ),
        isFalse,
      );
    });

    test('1 pt résilience → seuil 0.05', () {
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: _alloc(1),
          rngValue: 0.04,
        ),
        isTrue,
      );
      expect(
        SessionController.computeMiniPunishmentTrigger(
          specialization: _alloc(1),
          rngValue: 0.06,
        ),
        isFalse,
      );
    });
  });
}
