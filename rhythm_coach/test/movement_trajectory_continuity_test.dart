import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';

void main() {
  group('_computeFutureBeats (via computeFutureBeatsForTest)', () {
    test(
      'sans upcomingSteps, extrapole indéfiniment la consigne courante '
      '(comportement historique préservé — scénario prouvé rouge avant '
      'l\'ajout de upcomingSteps : 3 beats head/throat après 1800 ms)',
      () {
        final beats = computeFutureBeatsForTest(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 1000),
          flipped: false,
          lastBeatAt: DateTime.now(),
        );

        final beyond1800 = beats.where(
          (b) => !b.isAnchor && b.t * 3000 > 1800,
        );
        expect(beyond1800, isNotEmpty);
        expect(
          beyond1800.every(
            (b) =>
                b.idx == Position.head.index || b.idx == Position.throat.index,
          ),
          isTrue,
        );
      },
    );

    test(
      'avec upcomingSteps, ne prédit plus head/throat après la fin de la '
      'consigne (même famille : rhythm -> hold, enchaînement direct sans '
      'passage par tip)',
      () {
        final beats = computeFutureBeatsForTest(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 1000),
          flipped: false,
          lastBeatAt: DateTime.now(),
          elapsed: const Duration(seconds: 10, milliseconds: 200),
          upcomingSteps: const [
            UpcomingMovementStep(
              mode: SessionMode.hold,
              from: Position.full,
              to: Position.full,
              bpm: 60,
              startSecond: 12, // 12000 - 10200 = 1800 ms
            ),
          ],
        );

        final beyond1800 = beats.where(
          (b) => !b.isAnchor && b.t * 3000 > 1800,
        );
        expect(beyond1800, isNotEmpty);
        expect(
          beyond1800.any(
            (b) =>
                b.idx == Position.head.index || b.idx == Position.throat.index,
          ),
          isFalse,
          reason: 'la trajectoire ne doit plus annoncer head/throat une '
              'fois le step suivant entamé',
        );
        expect(
          beyond1800.any((b) => b.idx == Position.tip.index),
          isFalse,
          reason: 'rhythm -> hold sont dans la même famille (bouche) : pas '
              'de remontée par tip',
        );
      },
    );

    test(
      'avec upcomingSteps, passe par tip au franchissement d\'une frontière '
      'de famille (rhythm [bouche] -> hand [pas bouche])',
      () {
        final beats = computeFutureBeatsForTest(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 1000),
          flipped: false,
          lastBeatAt: DateTime.now(),
          elapsed: const Duration(seconds: 10, milliseconds: 200),
          upcomingSteps: const [
            UpcomingMovementStep(
              mode: SessionMode.hand,
              from: Position.mid,
              to: Position.full,
              bpm: 60,
              startSecond: 12,
            ),
          ],
        );

        expect(beats.any((b) => !b.isAnchor && b.idx == Position.tip.index),
            isTrue);
        final beyondBoundary = beats.where(
          (b) => !b.isAnchor && b.t * 3000 > 1800,
        );
        expect(
          beyondBoundary.any(
            (b) =>
                b.idx == Position.head.index || b.idx == Position.throat.index,
          ),
          isFalse,
        );
      },
    );

    test(
      'lick est hors de la famille bouche : rhythm -> lick passe par tip',
      () {
        final beats = computeFutureBeatsForTest(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 1000),
          flipped: false,
          lastBeatAt: DateTime.now(),
          elapsed: const Duration(seconds: 10, milliseconds: 200),
          upcomingSteps: const [
            UpcomingMovementStep(
              mode: SessionMode.lick,
              from: Position.head,
              to: Position.mid,
              bpm: 60,
              startSecond: 12,
            ),
          ],
        );

        expect(beats.any((b) => !b.isAnchor && b.idx == Position.tip.index),
            isTrue);
      },
    );

    test(
      'même famille : le premier point du step suivant respecte son '
      'transitionGap, pas l\'instant nominal de la frontière (BeepEngine '
      'retarde le démarrage du nouveau step, cf. transitionGap)',
      () {
        final beats = computeFutureBeatsForTest(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 1000),
          flipped: false,
          lastBeatAt: DateTime.now(),
          elapsed: const Duration(seconds: 11, milliseconds: 200),
          upcomingSteps: const [
            UpcomingMovementStep(
              mode: SessionMode.hold,
              from: Position.full,
              to: Position.full,
              bpm: 60,
              startSecond: 12, // frontière nominale = 800 ms depuis `now`
              transitionGap: Duration(milliseconds: 600),
            ),
          ],
        );

        final fullPoints =
            beats.where((b) => !b.isAnchor && b.idx == Position.full.index);
        expect(fullPoints, isNotEmpty);
        final firstFullMs =
            fullPoints.map((b) => b.t * 3000).reduce((a, b) => a < b ? a : b);
        expect(firstFullMs, greaterThan(1300));
        expect(firstFullMs, lessThan(1500));
      },
    );

    test(
      'frontière de famille : le point tip respecte le transitionGap du '
      'step suivant, pas l\'instant nominal de la frontière',
      () {
        final beats = computeFutureBeatsForTest(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 1000),
          flipped: false,
          lastBeatAt: DateTime.now(),
          elapsed: const Duration(seconds: 11, milliseconds: 200),
          upcomingSteps: const [
            UpcomingMovementStep(
              mode: SessionMode.hand,
              from: Position.mid,
              to: Position.full,
              bpm: 60,
              startSecond: 12, // frontière nominale = 800 ms depuis `now`
              transitionGap: Duration(milliseconds: 1500),
            ),
          ],
        );

        final tipPoints =
            beats.where((b) => !b.isAnchor && b.idx == Position.tip.index);
        expect(tipPoints, isNotEmpty);
        final tipMs =
            tipPoints.map((b) => b.t * 3000).reduce((a, b) => a < b ? a : b);
        expect(tipMs, greaterThan(2200));
        expect(tipMs, lessThan(2400));
      },
    );

    test(
      'suckle head reste dans la famille bouche, suckle balls en sort',
      () {
        List<({double t, double idx, bool isAnchor})> beatsFor(
                Position sucklePosition) =>
            computeFutureBeatsForTest(
              mode: SessionMode.rhythm,
              from: Position.head,
              to: Position.throat,
              beatDuration: const Duration(milliseconds: 1000),
              flipped: false,
              lastBeatAt: DateTime.now(),
              elapsed: const Duration(seconds: 10, milliseconds: 200),
              upcomingSteps: [
                UpcomingMovementStep(
                  mode: SessionMode.suckle,
                  from: sucklePosition,
                  to: sucklePosition,
                  bpm: 60,
                  startSecond: 12,
                ),
              ],
            );

        expect(
          beatsFor(Position.head)
              .any((b) => !b.isAnchor && b.idx == Position.tip.index),
          isFalse,
          reason: 'aspirer le gland garde la bouche en place',
        );
        expect(
          beatsFor(Position.balls)
              .any((b) => !b.isAnchor && b.idx == Position.tip.index),
          isTrue,
          reason: 'aspirer les bourses sort la bouche de la verge',
        );
      },
    );
  });

  group('resolveUpcomingMovementSteps', () {
    test('ignore les steps text-only et ceux déjà passés', () {
      final result = resolveUpcomingMovementSteps(
        steps: [
          const SessionStep(time: 5, text: 'déjà joué', from: Position.head),
          const SessionStep(time: 20, text: 'commentaire seul'),
          const SessionStep(time: 30, mode: SessionMode.hand, to: Position.mid),
        ],
        defaultMode: SessionMode.rhythm,
        afterSecond: 10,
        currentMode: SessionMode.rhythm,
        currentFrom: Position.tip,
        currentTo: Position.head,
        currentBpm: 90,
      );

      expect(result, hasLength(1));
      expect(result.single.mode, SessionMode.hand);
      expect(result.single.startSecond, 30);
    });

    test(
      'hérite mode/bpm (sticky) quand le step ne les précise pas ; `to` '
      'ne l\'est jamais (même règle que BeepEngine.applyStep)',
      () {
        final result = resolveUpcomingMovementSteps(
          steps: [
            const SessionStep(time: 15, to: Position.throat), // hérite bpm+mode
            const SessionStep(time: 25, bpm: 110), // hérite mode ; to=null
          ],
          defaultMode: SessionMode.rhythm,
          afterSecond: 0,
          currentMode: SessionMode.rhythm,
          currentFrom: Position.tip,
          currentTo: Position.head,
          currentBpm: 90,
        );

        expect(result, hasLength(2));
        expect(result[0].mode, SessionMode.rhythm);
        expect(result[0].bpm, 90);
        expect(result[0].to, Position.throat);
        expect(result[1].bpm, 110);
        expect(result[1].to, isNull);
      },
    );

    test('hold/beg/suckle : from vient de step.to, pas de step.from', () {
      final result = resolveUpcomingMovementSteps(
        steps: [
          const SessionStep(
              time: 15, mode: SessionMode.hold, to: Position.full),
        ],
        defaultMode: SessionMode.rhythm,
        afterSecond: 0,
        currentMode: SessionMode.rhythm,
        currentFrom: Position.tip,
        currentTo: Position.head,
        currentBpm: 90,
      );

      expect(result.single.from, Position.full);
      expect(result.single.to, Position.full);
    });

    test(
      'transitionGap suit BeepEngine.transitionGap : même mode 300 ms, '
      'changement de mode 600 ou 1500 ms selon _needsBigGap',
      () {
        final result = resolveUpcomingMovementSteps(
          steps: [
            const SessionStep(time: 5, mode: SessionMode.rhythm, bpm: 100),
            const SessionStep(
                time: 10, mode: SessionMode.hold, to: Position.full),
            const SessionStep(
                time: 15,
                mode: SessionMode.hand,
                from: Position.head,
                to: Position.full),
          ],
          defaultMode: SessionMode.rhythm,
          afterSecond: 0,
          currentMode: SessionMode.rhythm,
          currentFrom: Position.tip,
          currentTo: Position.head,
          currentBpm: 90,
        );

        expect(result[0].transitionGap, const Duration(milliseconds: 300),
            reason: 'rhythm -> rhythm : même mode');
        expect(result[1].transitionGap, const Duration(milliseconds: 600),
            reason: 'rhythm -> hold : changement de mode, needsBigGap=false');
        expect(result[2].transitionGap, const Duration(milliseconds: 1500),
            reason: 'hold -> hand : changement de mode, needsBigGap=true');
      },
    );
  });
}
