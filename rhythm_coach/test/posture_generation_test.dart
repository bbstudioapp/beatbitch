import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/posture.dart';
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
}
