import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
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

Session _gen({
  required int durationSeconds,
  required bool scriptedBreaks,
  required int seed,
}) =>
    CareerSessionGenerator(seed: seed)
        .generate(
          level: 12,
          bank: _bank(),
          durationSeconds: durationSeconds,
          unlockedKeys: UnlockKey.values.toSet(),
          scriptedBreaks: scriptedBreaks,
        )
        .session;

int _pauseSeconds(Session s) =>
    s.breaks.fold(0, (sum, b) => sum + b.durationSeconds);

void main() {
  // Une séance sans pause se termine au plus tard une fois le dernier bloc
  // fini ; la même graine avec pauses a un tirage différent, d'où la marge.
  const tolerance = 90;
  const seeds = 40;

  group('Temps de pause hors temps d\'effort — generate()', () {
    for (final minutes in [20, 35]) {
      test('$minutes min : effort = durée choisie à ${tolerance}s près', () {
        var withBreaks = 0;
        for (var seed = 1; seed <= seeds; seed++) {
          final d = minutes * 60;
          final s = _gen(durationSeconds: d, scriptedBreaks: true, seed: seed);
          final base =
              _gen(durationSeconds: d, scriptedBreaks: false, seed: seed);
          if (s.breaks.isNotEmpty) withBreaks++;
          final effort = s.durationSeconds - _pauseSeconds(s);
          expect(
            (effort - base.durationSeconds).abs(),
            lessThanOrEqualTo(tolerance),
            reason: 'seed $seed : effort $effort s, sans pause '
                '${base.durationSeconds} s, pauses ${_pauseSeconds(s)} s',
          );
        }
        expect(withBreaks, greaterThan(seeds ~/ 2),
            reason: 'le test ne mesure rien sans pause');
      });
    }

    test('séance courte sans pause : durée choisie à la tolérance près', () {
      for (var seed = 1; seed <= seeds; seed++) {
        final s =
            _gen(durationSeconds: 5 * 60, scriptedBreaks: true, seed: seed);
        final base =
            _gen(durationSeconds: 5 * 60, scriptedBreaks: false, seed: seed);
        expect(s.breaks, isEmpty);
        expect((s.durationSeconds - base.durationSeconds).abs(),
            lessThanOrEqualTo(tolerance));
      }
    });
  });
}
