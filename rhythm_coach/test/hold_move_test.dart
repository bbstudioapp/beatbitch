import 'package:beat_bitch/models/hold_move.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionStep.moves', () {
    final json = {
      'time': 40,
      'mode': 'hold',
      'to': 'throat',
      'duration': 20,
      'moves': [
        {'type': 'excursion', 'at': 4.5, 'to': 'tip'},
        {'type': 'excursion', 'at': 12, 'to': 'full'},
        {'type': 'micro', 'at': 16, 'duration': 3},
      ],
    };

    test('lu depuis le JSON et réécrit à l\'identique', () {
      final step = SessionStep.fromJson(json);
      expect(step.moves, const [
        HoldMove(kind: HoldMoveKind.excursion, at: 4.5, to: Position.tip),
        HoldMove(kind: HoldMoveKind.excursion, at: 12, to: Position.full),
        HoldMove(kind: HoldMoveKind.micro, at: 16, duration: 3),
      ]);
      expect(SessionStep.fromJson(step.toJson()).moves, step.moves);
      expect(step.mode, SessionMode.hold);
    });

    test('survit au rebase de timeline', () {
      expect(SessionStep.fromJson(json).rebased(90).moves, hasLength(3));
    });

    test('un mouvement mal formé est ignoré, le step reste lisible', () {
      final step = SessionStep.fromJson({
        'time': 0,
        'mode': 'hold',
        'to': 'throat',
        'moves': [
          {'type': 'excursion', 'at': 2},
          {'type': 'inconnu', 'at': 3},
          {'type': 'excursion', 'at': -1, 'to': 'tip'},
          'n\'importe quoi',
          {'type': 'excursion', 'at': 5, 'to': 'head'},
        ],
      });
      expect(step.moves.single.to, Position.head);
    });

    test('sans clé moves : liste vide, rien d\'écrit', () {
      final step = SessionStep.fromJson({'time': 0, 'mode': 'hold'});
      expect(step.moves, isEmpty);
      expect(step.toJson().containsKey('moves'), isFalse);
    });
  });

  group('holdKeyframes', () {
    test('un aller-retour : départ, bip à l\'arrivée, bip au retour', () {
      final k = holdKeyframes(Position.throat, const [
        HoldMove(kind: HoldMoveKind.excursion, at: 4, to: Position.tip),
      ]);
      final leg = excursionLeg(Position.throat, Position.tip);
      expect(leg, const Duration(milliseconds: 560));
      expect(k.map((e) => (e.at, e.idx, e.beep)).toList(), [
        (const Duration(seconds: 4), 3.0, null),
        (const Duration(seconds: 4) + leg, 0.0, Position.tip),
        (const Duration(seconds: 4) + leg * 2, 3.0, Position.throat),
      ]);
    });

    test('vers le bas aussi, et triés par instant', () {
      final k = holdKeyframes(Position.throat, const [
        HoldMove(kind: HoldMoveKind.excursion, at: 9, to: Position.head),
        HoldMove(kind: HoldMoveKind.excursion, at: 3, to: Position.full),
      ]);
      expect(k.first.at, const Duration(seconds: 3));
      expect(k[1].beep, Position.full);
      expect(k[4].beep, Position.head);
    });

    test('un aller-retour qui chevauche le précédent est ignoré', () {
      final k = holdKeyframes(Position.throat, const [
        HoldMove(kind: HoldMoveKind.excursion, at: 3, to: Position.tip),
        HoldMove(kind: HoldMoveKind.excursion, at: 3.5, to: Position.full),
      ]);
      expect(k, hasLength(3));
    });
  });

  test('les mouvements d\'une tenue à venir arrivent jusqu\'à la courbe', () {
    final upcoming = resolveUpcomingMovementSteps(
      steps: const [
        SessionStep(
          time: 30,
          mode: SessionMode.hold,
          to: Position.throat,
          moves: [
            HoldMove(kind: HoldMoveKind.excursion, at: 2, to: Position.tip),
          ],
        ),
      ],
      defaultMode: SessionMode.rhythm,
      afterSecond: 20,
      currentMode: SessionMode.rhythm,
      currentFrom: Position.head,
      currentBpm: 60,
    );
    expect(upcoming.single.moves.single.to, Position.tip);
  });

  group('micro-mouvements', () {
    test('rafale de petits va-et-vient, tic à chaque sommet, retour en place',
        () {
      final k = holdKeyframes(Position.throat, const [
        HoldMove(kind: HoldMoveKind.micro, at: 2, duration: 3),
      ]);
      expect(k.first.at, const Duration(seconds: 2));
      expect(k.first.idx, 3.0);
      expect(k.last.idx, 3.0, reason: 'la rafale finit sur la position tenue');
      final peaks = k.where((f) => f.beep != null).toList();
      expect(peaks.length, closeTo(3000 / 340, 1.5), reason: '~3 par seconde');
      for (final p in peaks) {
        expect(p.idx, closeTo(3 - microAmplitude, 1e-9));
        expect(p.volume, microTickVolume);
        expect(p.beep, Position.throat);
      }
      expect((k.last.at - k.first.at).inMilliseconds,
          inInclusiveRange(3000, 3340));
    });

    test('au bout, les micro-mouvements partent vers le bas', () {
      final k = holdKeyframes(Position.tip, const [
        HoldMove(kind: HoldMoveKind.micro, at: 0, duration: 1),
      ]);
      expect(k.where((f) => f.beep != null).first.idx, microAmplitude);
    });

    test('un groupe par mouvement', () {
      final g = holdMoveGroups(Position.throat, const [
        HoldMove(kind: HoldMoveKind.excursion, at: 1, to: Position.tip),
        HoldMove(kind: HoldMoveKind.micro, at: 5, duration: 2),
      ]);
      expect(g, hasLength(2));
      expect(g.first, hasLength(3));
    });
  });

  group('lick balls', () {
    test('position tenue inchangée, coups de langue réguliers sur balls', () {
      final k = holdKeyframes(Position.full, const [
        HoldMove(kind: HoldMoveKind.lickBalls, at: 2, duration: 4),
      ]);
      expect(k.map((f) => f.idx).toSet(), {4.0},
          reason: 'la courbe reste plate à full');
      expect(k.first.at, const Duration(seconds: 2));
      expect(k.last.at, const Duration(seconds: 6));
      final licks = k.where((f) => f.beep != null).toList();
      expect(licks.length, 4000 ~/ lickBallsPeriod.inMilliseconds);
      for (final l in licks) {
        expect(l.beep, Position.balls);
        expect(l.volume, lickBallsVolume);
      }
      expect(k.every((f) => f.tongue), isTrue);
    });

    test('le groupe porte la langue, pas les autres mouvements', () {
      final g = holdMoveGroups(Position.full, const [
        HoldMove(kind: HoldMoveKind.micro, at: 0, duration: 2),
        HoldMove(kind: HoldMoveKind.lickBalls, at: 4, duration: 3),
      ]);
      expect(g, hasLength(2));
      expect(g.first.any((f) => f.tongue), isFalse);
      expect(g.last.every((f) => f.tongue), isTrue);
    });

    test('lickingAt vrai seulement pendant le léchage', () {
      const moves = [
        HoldMove(kind: HoldMoveKind.lickBalls, at: 2, duration: 3),
      ];
      expect(holdLickingAt(Position.full, moves, const Duration(seconds: 1)),
          isFalse);
      expect(
          holdLickingAt(
              Position.full, moves, const Duration(milliseconds: 2100)),
          isTrue);
      expect(
          holdLickingAt(
              Position.full, moves, const Duration(milliseconds: 4900)),
          isTrue);
      expect(holdLickingAt(Position.full, moves, const Duration(seconds: 5)),
          isFalse);
    });
  });
}
