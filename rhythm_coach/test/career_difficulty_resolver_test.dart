import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/career_level.dart';
import 'package:beat_bitch/career/services/career_difficulty_resolver.dart';

void main() {
  group('CareerDifficultyResolver — Phase 19.1 (no-op)', () {
    test(
        'resolve(level) retourne la même config que CareerLevel.forLevel '
        'pour level ∈ [1..30]', () {
      for (var level = 1; level <= 30; level++) {
        final resolved = CareerDifficultyResolver.resolve(level);
        final direct = CareerLevel.forLevel(level);

        expect(resolved.level, direct.level, reason: 'level=$level');
        expect(resolved.maxDifficultyCap, direct.maxDifficultyCap,
            reason: 'maxDifficultyCap level=$level');
        expect(resolved.regenEndMultiplier, direct.regenEndMultiplier,
            reason: 'regenEndMultiplier level=$level');
        expect(resolved.durationSeconds, direct.durationSeconds,
            reason: 'durationSeconds level=$level');
        expect(resolved.boostsCount, direct.boostsCount,
            reason: 'boostsCount level=$level');
      }
    });

    test('resolve(0) clamp comme forLevel (plancher à 1)', () {
      final resolved = CareerDifficultyResolver.resolve(0);
      expect(resolved.level, 1);
      expect(
          resolved.maxDifficultyCap, CareerLevel.forLevel(0).maxDifficultyCap);
    });

    test('resolve(level haut) plafonne comme forLevel (cap 1.0 / 3.0)', () {
      final resolved = CareerDifficultyResolver.resolve(100);
      expect(resolved.maxDifficultyCap, 1.0);
      expect(resolved.regenEndMultiplier, 3.0);
    });
  });
}
