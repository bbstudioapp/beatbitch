import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/challenges/challenge_segment_builder.dart';
import 'package:beat_bitch/models/session.dart' show SessionMode;
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectMonolithic(
  ChallengeSegmentBuilder builder,
  Challenge ch, {
  required int expectedDuration,
}) {
  builder.start(
    challenge: ch,
    profile: null,
    unlocks: <UnlockKey>{},
    rng: Random(42),
  );
  expect(builder.thresholdReached, isFalse,
      reason: 'avant tout `next()`, seuil non atteint');
  expect(builder.elapsedSegmentSeconds, 0);
  final seg = builder.next();
  expect(seg, isNotNull, reason: 'le builder émet bien un premier segment');
  expect(seg!.mode, ch.mode);
  expect(seg.from, ch.from);
  expect(seg.to, ch.to);
  expect(seg.bpm, ch.bpm);
  expect(seg.bpmEnd, ch.bpmEnd);
  expect(seg.duration, expectedDuration);
  expect(builder.thresholdReached, isTrue,
      reason: 'après le segment unique, seuil atteint (monolithique)');
  expect(builder.elapsedSegmentSeconds, expectedDuration);
  // Tous les appels suivants doivent rendre null — le builder est épuisé.
  expect(builder.next(), isNull);
  expect(builder.next(), isNull);
}

void main() {
  group('builderForAxis dispatch', () {
    test('retourne le bon type pour les 4 axes monolithiques de PR-B.1.a', () {
      expect(builderForAxis(CapabilityAxis.holdThroatStreak),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.holdFullStreak),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.biffleBpmMax),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.rhythmDepthMax),
          isA<ChallengeSegmentBuilder>());
    });

    test('retourne le bon type pour les 3 axes rythme BPM de PR-B.1.b', () {
      expect(builderForAxis(CapabilityAxis.rhythmBpmCeilShallow),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.rhythmBpmCeilThroat),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.rhythmBpmCeilFull),
          isA<ChallengeSegmentBuilder>());
    });

    test('retourne le bon type pour les 3 axes endurance/biffle de PR-B.1.c',
        () {
      expect(builderForAxis(CapabilityAxis.biffleStreak),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.rhythmMotionStreak),
          isA<ChallengeSegmentBuilder>());
      expect(builderForAxis(CapabilityAxis.effortNoBreathStreak),
          isA<ChallengeSegmentBuilder>());
    });

    test('throw StateError pour un axe non encore couvert', () {
      expect(() => builderForAxis(CapabilityAxis.gorgeApneeStreak),
          throwsA(isA<StateError>()));
    });
  });

  group('HoldThroatStreakBuilder', () {
    test('émet 1 segment hold throat de durée targetThreshold', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 15,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
        comfortAtCalibration: 10.0,
      );
      _expectMonolithic(builderForAxis(ch.axis), ch, expectedDuration: 15);
    });
  });

  group('HoldFullStreakBuilder', () {
    test('émet 1 segment hold full de durée targetThreshold', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdFullStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 25,
        mode: SessionMode.hold,
        from: Position.full,
        to: Position.full,
        comfortAtCalibration: 18.0,
      );
      _expectMonolithic(builderForAxis(ch.axis), ch, expectedDuration: 25);
    });
  });

  group('BiffleBpmMaxBuilder', () {
    test('émet 1 segment biffle de durée nominalDurationSeconds avec rampe BPM',
        () {
      const ch = Challenge(
        axis: CapabilityAxis.biffleBpmMax,
        kind: ChallengeAxisKind.bpm,
        targetThreshold: 130,
        mode: SessionMode.biffle,
        bpm: 100,
        bpmEnd: 130,
        comfortAtCalibration: 100.0,
      );
      _expectMonolithic(builderForAxis(ch.axis), ch,
          expectedDuration: ch.nominalDurationSeconds);
    });
  });

  group('RhythmDepthMaxBuilder', () {
    test('émet 1 segment rhythm avec from/to/bpm du challenge', () {
      const ch = Challenge(
        axis: CapabilityAxis.rhythmDepthMax,
        kind: ChallengeAxisKind.depthCran,
        targetThreshold: 3,
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
        bpm: 80,
      );
      _expectMonolithic(builderForAxis(ch.axis), ch,
          expectedDuration: ch.nominalDurationSeconds);
    });
  });

  group('RhythmBpmCeilShallowBuilder', () {
    const ch = Challenge(
      axis: CapabilityAxis.rhythmBpmCeilShallow,
      kind: ChallengeAxisKind.bpm,
      targetThreshold: 120,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      bpm: 90,
      bpmEnd: 120,
    );

    test('tire une amplitude dans le pool shallow (tip→head/tip→mid/head→mid)',
        () {
      const expected = {
        (Position.tip, Position.head),
        (Position.tip, Position.mid),
        (Position.head, Position.mid),
      };
      // Multiples seeds pour couvrir le pool ; chaque pick doit y appartenir.
      final picked = <(Position, Position)>{};
      for (var seed = 0; seed < 50; seed++) {
        final builder = builderForAxis(ch.axis);
        builder.start(
          challenge: ch,
          profile: null,
          unlocks: <UnlockKey>{},
          rng: Random(seed),
        );
        final seg = builder.next()!;
        picked.add((seg.from!, seg.to!));
      }
      expect(picked.difference(expected), isEmpty,
          reason: 'aucun pick hors du pool shallow');
      expect(picked.length, greaterThanOrEqualTo(2),
          reason: 'la rng touche au moins 2 amplitudes en 50 tirages');
    });

    test('durée = nominalDurationSeconds (25 s) + BPM rampe préservée', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      final seg = builder.next()!;
      expect(seg.duration, ch.nominalDurationSeconds);
      expect(seg.bpm, 90);
      expect(seg.bpmEnd, 120);
      expect(seg.mode, SessionMode.rhythm);
    });
  });

  group('RhythmBpmCeilThroatBuilder', () {
    const ch = Challenge(
      axis: CapabilityAxis.rhythmBpmCeilThroat,
      kind: ChallengeAxisKind.bpm,
      targetThreshold: 110,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 80,
      bpmEnd: 110,
    );

    test('avec throatPulse : tire dans le pool tip/head/mid → throat', () {
      const expected = {
        (Position.tip, Position.throat),
        (Position.head, Position.throat),
        (Position.mid, Position.throat),
      };
      final picked = <(Position, Position)>{};
      for (var seed = 0; seed < 50; seed++) {
        final builder = builderForAxis(ch.axis);
        builder.start(
          challenge: ch,
          profile: null,
          unlocks: {UnlockKey.throatPulse},
          rng: Random(seed),
        );
        final seg = builder.next()!;
        picked.add((seg.from!, seg.to!));
      }
      expect(picked.difference(expected), isEmpty);
      expect(picked.length, greaterThanOrEqualTo(2));
    });

    test('sans throatPulse : fallback head→mid (safety net)', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      final seg = builder.next()!;
      expect(seg.from, Position.head);
      expect(seg.to, Position.mid);
    });
  });

  group('RhythmBpmCeilFullBuilder', () {
    const ch = Challenge(
      axis: CapabilityAxis.rhythmBpmCeilFull,
      kind: ChallengeAxisKind.bpm,
      targetThreshold: 100,
      mode: SessionMode.rhythm,
      from: Position.mid,
      to: Position.full,
      bpm: 70,
      bpmEnd: 100,
    );

    test(
        'avec fullPulse + throatPulse : pool complet tip/head/mid/throat → full',
        () {
      const expected = {
        (Position.tip, Position.full),
        (Position.head, Position.full),
        (Position.mid, Position.full),
        (Position.throat, Position.full),
      };
      final picked = <(Position, Position)>{};
      for (var seed = 0; seed < 80; seed++) {
        final builder = builderForAxis(ch.axis);
        builder.start(
          challenge: ch,
          profile: null,
          unlocks: {UnlockKey.throatPulse, UnlockKey.fullPulse},
          rng: Random(seed),
        );
        final seg = builder.next()!;
        picked.add((seg.from!, seg.to!));
      }
      expect(picked.difference(expected), isEmpty);
      expect(picked.length, greaterThanOrEqualTo(3),
          reason: '4 candidats, 80 seeds → au moins 3 distincts');
    });

    test('avec fullPulse mais sans throatPulse : exclut throat→full', () {
      const forbidden = (Position.throat, Position.full);
      for (var seed = 0; seed < 50; seed++) {
        final builder = builderForAxis(ch.axis);
        builder.start(
          challenge: ch,
          profile: null,
          unlocks: {UnlockKey.fullPulse},
          rng: Random(seed),
        );
        final seg = builder.next()!;
        expect((seg.from!, seg.to!) == forbidden, isFalse,
            reason: 'throat→full exige throatPulse + fullPulse');
      }
    });

    test('sans fullPulse mais avec throatPulse : retombe sur *→throat', () {
      const allowed = {
        (Position.tip, Position.throat),
        (Position.head, Position.throat),
        (Position.mid, Position.throat),
      };
      for (var seed = 0; seed < 20; seed++) {
        final builder = builderForAxis(ch.axis);
        builder.start(
          challenge: ch,
          profile: null,
          unlocks: {UnlockKey.throatPulse},
          rng: Random(seed),
        );
        final seg = builder.next()!;
        expect(allowed.contains((seg.from!, seg.to!)), isTrue);
      }
    });

    test('sans aucun pulse : fallback head→mid', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      final seg = builder.next()!;
      expect(seg.from, Position.head);
      expect(seg.to, Position.mid);
    });
  });

  group('BiffleStreakBuilder', () {
    const ch = Challenge(
      axis: CapabilityAxis.biffleStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 22,
      mode: SessionMode.biffle,
      comfortAtCalibration: 17.0,
    );

    test('émet 1 segment biffle de durée targetThreshold, BPM constant', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      final seg = builder.next()!;
      expect(seg.mode, SessionMode.biffle);
      expect(seg.duration, 22);
      expect(seg.bpm, isNotNull);
      expect(seg.bpmEnd, isNull, reason: 'pas de rampe, BPM constant');
      expect(builder.thresholdReached, isTrue);
      expect(builder.next(), isNull);
    });
  });

  group('RhythmMotionStreakBuilder', () {
    const ch = Challenge(
      axis: CapabilityAxis.rhythmMotionStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 40,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      comfortAtCalibration: 30.0,
    );

    test('streaming : émet ≥ 3 segments avant `thresholdReached`', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: {UnlockKey.throatPulse},
        rng: Random(1),
      );
      final segs = <SessionStep>[];
      while (!builder.thresholdReached && segs.length < 20) {
        final s = builder.next();
        if (s == null) break;
        segs.add(s);
      }
      expect(segs.length, greaterThanOrEqualTo(3),
          reason:
              'targetThreshold 40s ÷ ~10-15s par segment ≥ 3 sous-segments');
      expect(builder.elapsedSegmentSeconds, greaterThanOrEqualTo(40));
    });

    test(
        'anti-répétition immédiate : segment N != segment N-1 en (mode/from/to)',
        () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: {UnlockKey.fullPulse, UnlockKey.throatPulse},
        rng: Random(7),
      );
      SessionStep? previous;
      for (var i = 0; i < 12; i++) {
        final s = builder.next()!;
        if (previous != null) {
          final samePosition = s.mode == previous.mode &&
              s.from == previous.from &&
              s.to == previous.to;
          expect(samePosition, isFalse,
              reason: 'segment $i identique au précédent (mode/from/to)');
        }
        previous = s;
      }
    });

    test('continue à émettre après thresholdReached (extensions streaming)',
        () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: {UnlockKey.throatPulse},
        rng: Random(2),
      );
      // Drain jusqu'à seuil.
      while (!builder.thresholdReached) {
        builder.next();
      }
      // Extensions : doivent continuer à fournir des segments.
      expect(builder.next(), isNotNull);
      expect(builder.next(), isNotNull);
    });

    test('amplitude bornée par unlocks (sans throatPulse → reste shallow)', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(3),
      );
      for (var i = 0; i < 10; i++) {
        final s = builder.next()!;
        expect(s.to!.index, lessThanOrEqualTo(Position.mid.index),
            reason: 'sans throatPulse, `to` ne peut pas dépasser mid');
      }
    });

    test('aucun step `breath` dans la séquence', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: {UnlockKey.fullPulse, UnlockKey.throatPulse},
        rng: Random(4),
      );
      for (var i = 0; i < 15; i++) {
        final s = builder.next()!;
        expect(s.mode, isNot(SessionMode.breath),
            reason: 'défi non-stop : aucun breath autorisé');
      }
    });
  });

  group('EffortNoBreathStreakBuilder', () {
    const ch = Challenge(
      axis: CapabilityAxis.effortNoBreathStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 35,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      comfortAtCalibration: 25.0,
    );

    test('streaming + holds intercalés sur 100 tirages', () {
      // Multiple seeds : 30 % de chance → au moins quelques holds devraient
      // sortir sur 100 tirages cumulés (~30 attendus).
      var holdCount = 0;
      var totalCount = 0;
      for (var seed = 0; seed < 5; seed++) {
        final builder = builderForAxis(ch.axis);
        builder.start(
          challenge: ch,
          profile: null,
          unlocks: {UnlockKey.fullPulse, UnlockKey.throatPulse},
          rng: Random(seed),
        );
        for (var i = 0; i < 20; i++) {
          final s = builder.next()!;
          if (s.mode == SessionMode.hold) holdCount++;
          totalCount++;
        }
      }
      expect(holdCount, greaterThan(0),
          reason: 'avec 30 % proba et 100 tirages, au moins 1 hold attendu');
      expect(holdCount, lessThan(totalCount ~/ 2),
          reason: 'mais pas la moitié — c\'est un défi rythme, pas hold');
    });

    test('aucun hold si aucun unlock hold disponible', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      for (var i = 0; i < 20; i++) {
        final s = builder.next()!;
        expect(s.mode, isNot(SessionMode.hold),
            reason: 'sans throatPulse/fullPulse, pool de holds vide');
      }
    });

    test('aucun step `breath` (no-breath par contrat)', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: {UnlockKey.fullPulse, UnlockKey.throatPulse},
        rng: Random(0),
      );
      for (var i = 0; i < 20; i++) {
        final s = builder.next()!;
        expect(s.mode, isNot(SessionMode.breath));
      }
    });

    test('thresholdReached après cumul ≥ targetThreshold', () {
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: {UnlockKey.throatPulse},
        rng: Random(0),
      );
      while (!builder.thresholdReached) {
        builder.next();
      }
      expect(builder.elapsedSegmentSeconds, greaterThanOrEqualTo(35));
    });
  });

  group('invariants communs', () {
    test('`elapsedSegmentSeconds` croît monotonément', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 12,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
        comfortAtCalibration: 8.0,
      );
      final builder = builderForAxis(ch.axis);
      builder.start(
        challenge: ch,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      final before = builder.elapsedSegmentSeconds;
      builder.next();
      final after = builder.elapsedSegmentSeconds;
      expect(after, greaterThanOrEqualTo(before));
    });

    test('`start()` est ré-entrant : re-pose le builder à zéro', () {
      const ch1 = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 10,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
      );
      final builder = builderForAxis(ch1.axis);
      builder.start(
        challenge: ch1,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      builder.next();
      expect(builder.thresholdReached, isTrue);
      // Réutilisation hypothétique : on re-`start` avec un nouveau challenge.
      const ch2 = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 20,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
      );
      builder.start(
        challenge: ch2,
        profile: null,
        unlocks: <UnlockKey>{},
        rng: Random(0),
      );
      expect(builder.thresholdReached, isFalse);
      expect(builder.elapsedSegmentSeconds, 0);
      final seg = builder.next();
      expect(seg, isNotNull);
      expect(seg!.duration, 20);
    });
  });
}
