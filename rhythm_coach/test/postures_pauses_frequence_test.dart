import 'package:beat_bitch/career/models/challenge.dart';
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
            'attempt': _p(['a']),
            'extension': _p(['e']),
            'fail': _p(['fa']),
            'stop': _p(['st']),
            'success': _p(['su']),
            'skip': _p(['sk']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

const _allPostures = {
  UnlockKey.postureSitting,
  UnlockKey.postureStanding,
  UnlockKey.postureKneeling,
  UnlockKey.postureAllFours,
  UnlockKey.postureOnBack,
};

const _challengePool = [
  Challenge(
    axis: CapabilityAxis.holdThroatStreak,
    kind: ChallengeAxisKind.duration,
    targetThreshold: 10,
    mode: SessionMode.hold,
  ),
  Challenge(
    axis: CapabilityAxis.biffleStreak,
    kind: ChallengeAxisKind.duration,
    targetThreshold: 12,
    mode: SessionMode.biffle,
  ),
];

/// Retard maximal entre l'horaire visé d'un événement et la frontière de bloc
/// où la boucle principale le pose.
const _blockSlack = 150;

Session _gen({
  required int minutes,
  int endurance = 0,
  Set<UnlockKey> unlocked = _allPostures,
  bool scriptedBreaks = true,
  int seed = 7,
  int challengeCount = 0,
}) =>
    CareerSessionGenerator(seed: seed)
        .generate(
          level: 14,
          bank: _bank(),
          durationSeconds: minutes * 60,
          unlockedKeys: unlocked,
          scriptedBreaks: scriptedBreaks,
          specialization: SpecializationAllocation(
            points: {SpecializationBranch.endurance: endurance},
            lastRespecMs: null,
          ),
          challenge: ChallengeInputs(
            challenges: _challengePool.take(challengeCount).toList(),
          ),
        )
        .session;

/// Changements de position effectifs, dans l'ordre : les changements seuls et
/// les pauses qui en portent un.
List<({int time, int end, Posture pose})> _poseEvents(Session s) => [
      for (final c in s.postureChanges)
        (time: c.time, end: c.time, pose: c.pose),
      for (final b in s.breaks)
        if (b.newPose != null) (time: b.time, end: b.endTime, pose: b.newPose!),
    ]..sort((a, b) => a.time.compareTo(b.time));

void main() {
  group('Pauses scénarisées — fréquence selon l\'endurance', () {
    for (final (endurance, interval) in [
      (0, 420),
      (2, 540),
      (5, 720),
      (9, 720)
    ]) {
      test(
          '$endurance pt(s) d\'endurance → une pause toutes les ${interval ~/ 60} min',
          () {
        var sessionsWithBreaks = 0;
        for (final minutes in [25, 40, 60, 90]) {
          for (var seed = 0; seed < 6; seed++) {
            final s = _gen(minutes: minutes, endurance: endurance, seed: seed);
            final finish = s.silentFinishStartTime!;
            for (var k = 0; k < s.breaks.length; k++) {
              final b = s.breaks[k];
              expect(
                  b.time,
                  inInclusiveRange(
                      (k + 1) * interval, (k + 1) * interval + _blockSlack),
                  reason: '$minutes min seed=$seed : pause n°${k + 1}');
              expect(b.durationSeconds, inInclusiveRange(60, 120));
              expect(b.endTime, lessThanOrEqualTo(finish));
            }
            // Le nombre découle de la durée d'effort : aucun créneau dû n'est
            // sauté.
            final effortFinish = finish -
                s.breaks.fold<int>(0, (sum, b) => sum + b.durationSeconds);
            final expected = [
              for (var t = interval;
                  t + 120 + _blockSlack <= effortFinish;
                  t += interval)
                t
            ].length;
            expect(s.breaks.length, greaterThanOrEqualTo(expected),
                reason: '$minutes min seed=$seed : pauses manquantes');
            if (s.breaks.isNotEmpty) sessionsWithBreaks++;
          }
        }
        expect(sessionsWithBreaks, greaterThan(0));
      });
    }

    test('jamais avant 7 min ni pendant la phase finish', () {
      for (final minutes in [8, 12, 15, 20]) {
        for (var seed = 0; seed < 10; seed++) {
          final s = _gen(minutes: minutes, seed: seed);
          for (final b in s.breaks) {
            expect(b.time, greaterThanOrEqualTo(420));
            expect(b.endTime, lessThanOrEqualTo(s.silentFinishStartTime!));
          }
        }
      }
    });

    test('préférence coupée → ni pause ni changement de position', () {
      final s = _gen(minutes: 60, scriptedBreaks: false);
      expect(s.breaks, isEmpty);
      expect(s.postureChanges, isEmpty);
    });
  });

  group('Changements de position — événement à part', () {
    test(
        'le 1er entre 4 et 7 min, puis toutes les 6 à 10 min, parmi les '
        'débloquées, jamais deux fois la même d\'affilée', () {
      var changes = 0;
      for (final minutes in [15, 30, 45, 75]) {
        for (final endurance in [0, 5]) {
          for (var seed = 0; seed < 8; seed++) {
            final s = _gen(minutes: minutes, endurance: endurance, seed: seed);
            final events = _poseEvents(s);
            var previous = s.initialPose;
            var previousEnd = 0;
            for (final e in events) {
              final where =
                  '$minutes min end=$endurance seed=$seed t=${e.time}';
              expect(e.time, greaterThanOrEqualTo(240), reason: where);
              if (previousEnd == 0) {
                expect(e.time, lessThanOrEqualTo(420 + _blockSlack),
                    reason: where);
              }
              expect(e.time, lessThan(s.silentFinishStartTime!), reason: where);
              expect(e.pose, isNot(Posture.free), reason: where);
              expect(e.pose, isNot(previous), reason: where);
              if (previousEnd > 0) {
                expect(e.time - previousEnd,
                    inInclusiveRange(120, 720 + _blockSlack),
                    reason: where);
              }
              previous = e.pose;
              previousEnd = e.end;
            }
            if (minutes >= 30) {
              expect(events, isNotEmpty,
                  reason: '$minutes min seed=$seed : aucun changement');
            }
            changes += s.postureChanges.length;
          }
        }
      }
      expect(changes, greaterThan(0),
          reason: 'aucun changement seul : le balayage ne teste rien');
    });

    test('le 1er changement est tiré entre 4 et 7 min, pas figé', () {
      final firstTimes = <int>{};
      for (var seed = 0; seed < 40; seed++) {
        final s = _gen(minutes: 30, seed: seed, endurance: 0);
        final first = _poseEvents(s).first;
        expect(first.time, inInclusiveRange(240, 420 + _blockSlack),
            reason: 'seed=$seed');
        firstTimes.add(first.time);
      }
      // Un tirage figé à 4 min ne dépasse pas 240 + _blockSlack ; figé à 7 min,
      // il ne descend pas sous 420.
      expect(firstTimes.any((t) => t > 240 + _blockSlack), isTrue,
          reason: 'jamais au-delà de 4 min : $firstTimes');
      expect(firstTimes.any((t) => t < 420), isTrue,
          reason: 'jamais avant 7 min : $firstTimes');
    });

    test('un changement tombe pile sur un step de config (reprise du bip)', () {
      var checked = 0;
      for (var seed = 0; seed < 10; seed++) {
        final s = _gen(minutes: 45, seed: seed);
        for (final c in s.postureChanges) {
          checked++;
          expect(
              s.steps.any((st) => st.time == c.time && st.mode != null), isTrue,
              reason: 'seed=$seed : aucun step de config à t=${c.time}');
        }
      }
      expect(checked, greaterThan(0));
    });

    test('un changement proche d\'une pause se fait pendant la pause', () {
      var breaksWithPose = 0;
      for (final minutes in [30, 60, 90]) {
        for (var seed = 0; seed < 10; seed++) {
          final s = _gen(minutes: minutes, seed: seed);
          for (final b in s.breaks) {
            if (b.newPose != null) breaksWithPose++;
            for (final c in s.postureChanges) {
              expect(
                  c.time >= b.time - 120 && c.time <= b.endTime + 120, isFalse,
                  reason: '$minutes min seed=$seed : changement à ${c.time} '
                      'près de la pause [${b.time},${b.endTime})');
            }
          }
        }
      }
      expect(breaksWithPose, greaterThan(0));
    });

    test('jamais pendant un défi', () {
      var withBoth = 0;
      for (var minutes = 20; minutes <= 90; minutes += 5) {
        for (final count in [1, 2]) {
          for (var seed = 0; seed < 30; seed++) {
            final s = _gen(minutes: minutes, seed: seed, challengeCount: count);
            for (final t in s.challengeTriggerTimes) {
              final next = s.steps
                  .map((st) => st.time)
                  .where((time) => time > t)
                  .fold<int>(s.durationSeconds, (a, b) => a < b ? a : b);
              for (final c in s.postureChanges) {
                withBoth++;
                expect(c.time >= t && c.time < next, isFalse,
                    reason: '$minutes min seed=$seed : changement à ${c.time} '
                        'dans le défi [$t,$next)');
              }
            }
          }
        }
      }
      expect(withBoth, greaterThan(0));
    });

    test('aucune posture débloquée → aucun changement, pauses sans posture',
        () {
      final s = _gen(minutes: 60, unlocked: const {});
      expect(s.postureChanges, isEmpty);
      expect(s.breaks, isNotEmpty);
      expect(s.breaks.every((b) => b.newPose == null), isTrue);
    });

    test('déterministe sous seed identique', () {
      List<(int, Posture)> run() => [
            for (final c in _gen(minutes: 60, seed: 99).postureChanges)
              (c.time, c.pose)
          ];
      expect(run(), run());
    });
  });
}
