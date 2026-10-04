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
            if (m == SessionMode.hold) 'micro': _p(['MICRO']),
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
        expect(holdMoveGroups(hold, h.moves), hasLength(h.moves.length),
            reason: 'aucun mouvement ne chevauche le précédent');
        expect(frames.last.at.inMilliseconds, lessThan(h.duration! * 1000),
            reason: 'le dernier retour tombe avant la fin de la tenue');
        if (h.moves.first.kind == HoldMoveKind.micro) continue;
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
      final holds = _holds(seed, 14)
          .where((h) => h.moves.any((m) => m.kind == HoldMoveKind.excursion));
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

  test('des rafales de micro-mouvements, seules sur leur tenue, annoncées', () {
    var bursts = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final steps = CareerSessionGenerator(seed: seed)
          .generate(
            level: 14,
            bank: _bank(),
            durationSeconds: 20 * 60,
            unlockedKeys: UnlockKey.values.toSet(),
          )
          .session
          .steps;
      for (var i = 0; i < steps.length; i++) {
        final h = steps[i];
        if (h.mode != SessionMode.hold) continue;
        final micro = h.moves.where((m) => m.kind == HoldMoveKind.micro);
        if (micro.isEmpty) continue;
        bursts++;
        expect(h.moves, hasLength(1), reason: 'jamais avec des A/R');
        final m = micro.single;
        expect(m.duration!, inInclusiveRange(3, 6));
        expect(m.at + m.duration!, lessThanOrEqualTo(h.duration! - 0.5));
        final cue = steps.where((s) =>
            s.isTextOnly &&
            s.text == 'MICRO' &&
            s.time >= h.time &&
            s.time <= h.time + 1 + m.at.ceil());
        expect(cue, hasLength(1), reason: 'seed $seed t=${h.time}');
      }
    }
    expect(bursts, greaterThan(0));
  });
}
