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
      expect(k.map((e) => (e.at, e.position, e.beep)).toList(), [
        (const Duration(seconds: 4), Position.throat, false),
        (const Duration(seconds: 4) + leg, Position.tip, true),
        (const Duration(seconds: 4) + leg * 2, Position.throat, true),
      ]);
    });

    test('vers le bas aussi, et triés par instant', () {
      final k = holdKeyframes(Position.throat, const [
        HoldMove(kind: HoldMoveKind.excursion, at: 9, to: Position.head),
        HoldMove(kind: HoldMoveKind.excursion, at: 3, to: Position.full),
      ]);
      expect(k.first.at, const Duration(seconds: 3));
      expect(k[1].position, Position.full);
      expect(k[4].position, Position.head);
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
}
