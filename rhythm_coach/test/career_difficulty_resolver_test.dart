import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/career_level.dart';
import 'package:beat_bitch/career/models/session_length_choice.dart';
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

  group('CareerDifficultyResolver.resolveForCareer — Phase 19.6', () {
    test('table de calibration : valeurs par tranche de sessions', () {
      // Joueuse débutante (0 sessions, courte) — équivalent ancien level 1.
      final cfg0 = CareerDifficultyResolver.resolveForCareer(
        sessionsCompleted: 0,
        lengthChoice: SessionLengthChoice.courte,
      );
      expect(cfg0.level, 1);
      expect(cfg0.maxDifficultyCap, 0.25);
      expect(cfg0.regenEndMultiplier, 1.35);
      expect(cfg0.boostsCount, 2);

      // 20 sessions, moyenne — équivalent ancien level 11.
      final cfg20 = CareerDifficultyResolver.resolveForCareer(
        sessionsCompleted: 20,
        lengthChoice: SessionLengthChoice.moyenne,
      );
      expect(cfg20.level, 11);
      expect(cfg20.maxDifficultyCap, closeTo(0.75, 0.001));
      expect(cfg20.regenEndMultiplier, closeTo(2.85, 0.001));
      expect(cfg20.boostsCount, 4);

      // 40 sessions, longue — cap saturé, bonus longue (+1 boost).
      final cfg40 = CareerDifficultyResolver.resolveForCareer(
        sessionsCompleted: 40,
        lengthChoice: SessionLengthChoice.longue,
      );
      expect(cfg40.level, 21);
      expect(cfg40.maxDifficultyCap, 1.0);
      expect(cfg40.regenEndMultiplier, 3.0);
      expect(cfg40.boostsCount, 6, reason: 'longue ajoute +1 boost');

      // 100 sessions : tout est plafonné.
      final cfg100 = CareerDifficultyResolver.resolveForCareer(
        sessionsCompleted: 100,
        lengthChoice: SessionLengthChoice.moyenne,
      );
      expect(cfg100.level, 30);
      expect(cfg100.maxDifficultyCap, 1.0);
      expect(cfg100.regenEndMultiplier, 3.0);
      expect(cfg100.boostsCount, 5);
    });

    test('durée pilotée par lengthChoice (Phase 19.3)', () {
      for (final lc in SessionLengthChoice.values) {
        final cfg = CareerDifficultyResolver.resolveForCareer(
          sessionsCompleted: 10,
          lengthChoice: lc,
        );
        expect(cfg.durationSeconds, lc.durationSeconds,
            reason: '${lc.name} : durée');
      }
    });

    test('bonus longue : +1 boost à compétences égales', () {
      for (final n in [0, 10, 20, 40]) {
        final courte = CareerDifficultyResolver.resolveForCareer(
          sessionsCompleted: n,
          lengthChoice: SessionLengthChoice.courte,
        );
        final longue = CareerDifficultyResolver.resolveForCareer(
          sessionsCompleted: n,
          lengthChoice: SessionLengthChoice.longue,
        );
        expect(longue.boostsCount, courte.boostsCount + 1,
            reason: 'longue à $n sessions doit avoir +1 boost');
      }
    });

    test('sessionsCompleted négatif clampé à 0', () {
      final cfg = CareerDifficultyResolver.resolveForCareer(
        sessionsCompleted: -5,
        lengthChoice: SessionLengthChoice.courte,
      );
      expect(cfg.level, 1);
      expect(cfg.maxDifficultyCap, 0.25);
    });

    test('boostsCount cap absolu à 6 (anti-explosion)', () {
      final cfg = CareerDifficultyResolver.resolveForCareer(
        sessionsCompleted: 100,
        lengthChoice: SessionLengthChoice.longue,
      );
      expect(cfg.boostsCount, lessThanOrEqualTo(6));
    });

    test('monotonie : sessions plus hautes ⇒ cap/regen >= ', () {
      double? prevCap;
      double? prevRegen;
      for (var n = 0; n <= 60; n += 5) {
        final cfg = CareerDifficultyResolver.resolveForCareer(
          sessionsCompleted: n,
          lengthChoice: SessionLengthChoice.courte,
        );
        if (prevCap != null) {
          expect(cfg.maxDifficultyCap, greaterThanOrEqualTo(prevCap));
          expect(cfg.regenEndMultiplier, greaterThanOrEqualTo(prevRegen!));
        }
        prevCap = cfg.maxDifficultyCap;
        prevRegen = cfg.regenEndMultiplier;
      }
    });
  });
}
