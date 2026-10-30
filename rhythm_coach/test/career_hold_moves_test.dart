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
            if (m == SessionMode.hold) 'lick_balls': _p(['LICK']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

List<SessionStep> _steps(int seed, int level,
        {Set<UnlockKey>? unlocked,
        AnatomyProfile anatomy = AnatomyProfile.defaults}) =>
    CareerSessionGenerator(seed: seed)
        .generate(
          level: level,
          bank: _bank(),
          durationSeconds: 20 * 60,
          unlockedKeys: unlocked ?? UnlockKey.values.toSet(),
          anatomy: anatomy,
        )
        .session
        .steps;

List<SessionStep> _holds(int seed, int level) =>
    _steps(seed, level).where((s) => s.mode == SessionMode.hold).toList();

int _licks(Iterable<SessionStep> steps) => steps
    .where((s) => s.moves.any((m) => m.kind == HoldMoveKind.lickBalls))
    .length;

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
        if (h.moves.first.kind != HoldMoveKind.excursion) continue;
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

  test('lick balls : tenues full seulement, seul mouvement, annoncé', () {
    var licks = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final steps = _steps(seed, 14);
      for (final h in steps) {
        final lick = h.moves.where((m) => m.kind == HoldMoveKind.lickBalls);
        if (lick.isEmpty) continue;
        licks++;
        expect(h.mode, SessionMode.hold);
        expect(h.to ?? h.from, Position.full);
        expect(h.moves, hasLength(1));
        final m = lick.single;
        expect(m.duration!, inInclusiveRange(3, 8));
        expect(m.at + m.duration!, lessThanOrEqualTo(h.duration! - 0.5));
        final cue = steps.where((s) =>
            s.isTextOnly &&
            s.text == 'LICK' &&
            s.time >= h.time &&
            s.time <= h.time + 1 + m.at.ceil());
        expect(cue, hasLength(1), reason: 'seed $seed t=${h.time}');
      }
    }
    expect(licks, greaterThan(0));
  });

  test('pas de lick balls sans la zone ni sans son déblocage', () {
    for (var seed = 1; seed <= 20; seed++) {
      expect(
          _licks(
              _steps(seed, 14, anatomy: const AnatomyProfile(hasBalls: false))),
          0);
      expect(
          _licks(_steps(seed, 14,
              unlocked: UnlockKey.values.toSet()..remove(UnlockKey.lickBalls))),
          0);
    }
  });
}
