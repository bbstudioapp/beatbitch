import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> t) =>
    t.map((s) => PhraseEntry(text: s)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

void main() {
  group('Posture initiale — generate()', () {
    test('flag off → free, même avec des postures débloquées', () {
      final gen = CareerSessionGenerator(seed: 7);
      final result = gen.generate(
        level: 12,
        bank: _bank(),
        durationSeconds: 18 * 60,
        unlockedKeys: UnlockKey.values.toSet(),
        // scriptedBreaks: false (défaut)
      );
      expect(result.session.initialPose, Posture.free);
    });

    test('flag on mais rien de débloqué → free', () {
      final gen = CareerSessionGenerator(seed: 7);
      final result = gen.generate(
        level: 3,
        bank: _bank(),
        durationSeconds: 12 * 60,
        unlockedKeys: const {},
        scriptedBreaks: true,
      );
      expect(result.session.initialPose, Posture.free);
    });

    test('flag on + postures débloquées → posture du set disponible', () {
      final gen = CareerSessionGenerator(seed: 7);
      final unlocked = {
        UnlockKey.postureKneeling,
        UnlockKey.postureAllFours,
      };
      final result = gen.generate(
        level: 12,
        bank: _bank(),
        durationSeconds: 18 * 60,
        unlockedKeys: unlocked,
        scriptedBreaks: true,
      );
      expect(
        result.session.initialPose,
        anyOf(Posture.free, Posture.kneeling, Posture.allFours),
      );
    });

    test('tirage déterministe sous seed identique', () {
      final unlocked = {
        UnlockKey.postureSitting,
        UnlockKey.postureKneeling,
        UnlockKey.postureAllFours,
      };
      Posture run() => CareerSessionGenerator(seed: 99)
          .generate(
            level: 12,
            bank: _bank(),
            durationSeconds: 18 * 60,
            unlockedKeys: unlocked,
            scriptedBreaks: true,
          )
          .session
          .initialPose;
      expect(run(), run());
    });
  });

  group('Breaks scénarisés — generate()', () {
    final allPostures = {
      UnlockKey.postureSitting,
      UnlockKey.postureKneeling,
      UnlockKey.postureAllFours,
    };

    Session gen({
      required int durationSeconds,
      bool scriptedBreaks = true,
      Set<UnlockKey> unlocked = const {},
      int seed = 7,
    }) =>
        CareerSessionGenerator(seed: seed)
            .generate(
              level: 12,
              bank: _bank(),
              durationSeconds: durationSeconds,
              unlockedKeys: unlocked,
              scriptedBreaks: scriptedBreaks,
            )
            .session;

    test('flag off → aucun break même sur session longue', () {
      final s = gen(
          durationSeconds: 45 * 60,
          scriptedBreaks: false,
          unlocked: allPostures);
      expect(s.breaks, isEmpty);
    });

    test('session courte (< 28 min) → aucun break', () {
      final s = gen(durationSeconds: 18 * 60, unlocked: allPostures);
      expect(s.breaks, isEmpty);
    });

    test('≥ 28 min et < 45 min → 1 break', () {
      final s = gen(durationSeconds: 35 * 60, unlocked: allPostures);
      expect(s.breaks, hasLength(1));
    });

    test('≥ 45 min → 2 breaks', () {
      final s = gen(durationSeconds: 45 * 60, unlocked: allPostures);
      expect(s.breaks, hasLength(2));
    });

    test('durées dans [60, 120] et ordonnés, hors phase finish', () {
      final s = gen(durationSeconds: 45 * 60, unlocked: allPostures);
      var prevEnd = 0;
      for (final b in s.breaks) {
        expect(b.durationSeconds, inInclusiveRange(60, 120));
        expect(b.time, greaterThan(prevEnd));
        expect(b.endTime, lessThanOrEqualTo(s.silentFinishStartTime!));
        prevEnd = b.endTime;
      }
    });

    test('aucun step d\'effort dans la fenêtre d\'un break (trou d\'effort)',
        () {
      final s = gen(durationSeconds: 45 * 60, unlocked: allPostures);
      for (final b in s.breaks) {
        final inside =
            s.steps.where((st) => st.time >= b.time && st.time < b.endTime);
        expect(inside, isEmpty,
            reason: 'break [${b.time}, ${b.endTime}) doit rester un trou');
      }
    });

    test('postures débloquées → 1ᵉʳ break change de pose (hors free/initiale)',
        () {
      final s = gen(durationSeconds: 35 * 60, unlocked: allPostures);
      final first = s.breaks.first;
      expect(first.newPose, isNotNull);
      expect(first.newPose, isNot(Posture.free));
      expect(first.newPose, isNot(s.initialPose));
    });

    test('2ᵉ break → récup pure (newPose null), continuité de pose', () {
      final s = gen(durationSeconds: 45 * 60, unlocked: allPostures);
      expect(s.breaks[1].newPose, isNull);
    });

    test('aucune posture débloquée → break en récup pure (newPose null)', () {
      final s = gen(durationSeconds: 35 * 60, unlocked: const {});
      expect(s.breaks, hasLength(1));
      expect(s.breaks.first.newPose, isNull);
    });

    test('déterministe sous seed identique', () {
      List<({int time, int dur, Posture? pose})> run() => gen(
            durationSeconds: 45 * 60,
            unlocked: allPostures,
            seed: 99,
          )
              .breaks
              .map((b) => (
                    time: b.time,
                    dur: b.durationSeconds,
                    pose: b.newPose,
                  ))
              .toList();
      expect(run(), run());
    });
  });
}
