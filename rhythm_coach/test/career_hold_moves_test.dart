import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/hold_move.dart';
import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'boost': _p(['b']),
            'finale': _p(['f']),
            if (m == SessionMode.hold) 'moves': _p(['CONSIGNE']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

List<SessionStep> _holds(int seed, int level) =>
    CareerSessionGenerator(seed: seed)
        .generate(
          level: level,
          bank: _bank(),
          durationSeconds: 20 * 60,
          unlockedKeys: UnlockKey.values.toSet(),
        )
        .session
        .steps
        .where((s) => s.mode == SessionMode.hold)
        .toList();

void main() {
  test('au niveau 14, des tenues reçoivent des allers-retours valides', () {
    var withMoves = 0;
    var down = 0;
    for (var seed = 1; seed <= 20; seed++) {
      for (final h in _holds(seed, 14)) {
        if (h.moves.isEmpty) continue;
        withMoves++;
        final hold = h.to ?? h.from!;
        expect(h.duration!, greaterThanOrEqualTo(6));
        final frames = holdKeyframes(hold, h.moves);
        expect(frames, hasLength(h.moves.length * 3),
            reason: 'aucun aller-retour ne chevauche le précédent');
        expect(frames.last.at.inMilliseconds, lessThan(h.duration! * 1000),
            reason: 'le dernier retour tombe avant la fin de la tenue');
        for (final m in h.moves) {
          expect(m.kind, HoldMoveKind.excursion);
          if (m.to!.index > hold.index) {
            down++;
            expect(m.to, Position.full, reason: 'vers le bas : le fond');
          } else {
            expect(m.to!.index, lessThan(hold.index));
          }
        }
      }
    }
    expect(withMoves, greaterThan(0));
    expect(down, greaterThan(0), reason: 'des allers-retours vers le fond');
  });

  test('la consigne est donnée à la première tenue qui en a, une seule fois',
      () {
    for (var seed = 1; seed <= 10; seed++) {
      final holds = _holds(seed, 14).where((h) => h.moves.isNotEmpty);
      if (holds.isEmpty) continue;
      expect(holds.first.text, contains('CONSIGNE'), reason: 'seed $seed');
      expect(holds.skip(1).where((h) => h.text.contains('CONSIGNE')), isEmpty);
    }
  });

  test('sous le niveau plancher, aucune tenue n\'en reçoit', () {
    for (var seed = 1; seed <= 10; seed++) {
      expect(
          _holds(seed, CareerLevelGates.holdMovesFloorLevel - 1)
              .where((h) => h.moves.isNotEmpty),
          isEmpty);
    }
  });

  test('même graine, mêmes allers-retours', () {
    expect(_holds(7, 14).map((h) => h.moves).toList(),
        _holds(7, 14).map((h) => h.moves).toList());
  });
}
