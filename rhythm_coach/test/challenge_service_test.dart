import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construit un `CapabilityProfile` minimal avec un comfort posé sur un
/// axe précis. Les autres axes restent vides → `pickOverloadAxis` les
/// ignore (pas de donnée prouvée).
CapabilityProfile _profileWithComfort(CapabilityAxis axis, double comfort) {
  return CapabilityProfile({
    axis: CapabilityAxisState(
      best: comfort,
      comfort: comfort,
      successRate: 0.9,
      lastSeenSession: 1,
    ),
  });
}

void main() {
  group('ChallengeService.buildForSession', () {
    test('tutoriel : axe robuste hold throat 5 s, isTutorial flag posé', () {
      final svc = ChallengeService();
      final challenge = svc.buildForSession(
        profile: null,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(42),
        isTutorial: true,
      );
      expect(challenge, isNotNull);
      expect(challenge!.isTutorial, isTrue);
      expect(challenge.axis, CapabilityAxis.holdThroatStreak);
      expect(challenge.kind, ChallengeAxisKind.duration);
      expect(challenge.targetThreshold, kChallengeTutorialDurationSeconds);
      expect(challenge.mode, SessionMode.hold);
      expect(challenge.from, Position.throat);
      expect(challenge.branch, SpecializationBranch.endurance);
    });

    test('non-tutoriel : pickOverloadAxis utilisé, seuil = comfort × 1.50', () {
      final svc = ChallengeService();
      final profile = _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
      expect(challenge.targetThreshold, 15);
      expect(challenge.comfortAtCalibration, 10.0);
    });

    test('axe BPM : seuil = comfort × 1.50 en BPM', () {
      final svc = ChallengeService();
      final profile =
          _profileWithComfort(CapabilityAxis.rhythmBpmCeilThroat, 100);
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.rhythmBpmCeilThroat);
      expect(challenge.kind, ChallengeAxisKind.bpm);
      expect(challenge.targetThreshold, 150);
      expect(challenge.bpm, 150);
      expect(challenge.mode, SessionMode.rhythm);
      expect(challenge.to, Position.throat);
    });

    test('axe profondeur : seuil = comfort + 1 cran', () {
      final svc = ChallengeService();
      // rhythmDepthMax comfort = 2 (mid) → seuil = cran 3 (throat).
      final profile = _profileWithComfort(CapabilityAxis.rhythmDepthMax, 2);
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.kind, ChallengeAxisKind.depthCran);
      expect(challenge.targetThreshold, 3);
    });

    test('axes exclus : pickOverloadAxis n\'en retient aucun', () {
      final svc = ChallengeService();
      final profile = _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: {CapabilityAxis.holdThroatStreak},
        rng: Random(0),
        isTutorial: false,
      );
      // Seul axe avec donnée a été exclu → null.
      expect(challenge, isNull);
    });

    test('profil vide → null (aucun axe candidat)', () {
      final svc = ChallengeService();
      final challenge = svc.buildForSession(
        profile: const CapabilityProfile({}),
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNull);
    });
  });

  group('ChallengeService.branchOf', () {
    test('mapping axes → branches connues', () {
      expect(ChallengeService.branchOf(CapabilityAxis.holdThroatStreak),
          SpecializationBranch.endurance);
      expect(ChallengeService.branchOf(CapabilityAxis.rhythmDepthMax),
          SpecializationBranch.profondeur);
      expect(ChallengeService.branchOf(CapabilityAxis.biffleStreak),
          SpecializationBranch.rythmeBiffle);
      expect(ChallengeService.branchOf(CapabilityAxis.noswallowStreak),
          SpecializationBranch.sloppy);
    });

    test('axes non pilotants par branche → null', () {
      expect(ChallengeService.branchOf(CapabilityAxis.handStreak), isNull);
      expect(ChallengeService.branchOf(CapabilityAxis.lickStreak), isNull);
      expect(ChallengeService.branchOf(CapabilityAxis.breathMinDose), isNull);
    });
  });

  group('Challenge.extensionSeconds', () {
    test('plancher à 10 s pour comfort bas', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 15,
        mode: SessionMode.hold,
        comfortAtCalibration: 5.0,
      );
      // 5 × 0.30 = 1.5 → planché à 10.
      expect(ch.extensionSeconds, 10);
    });

    test('comfort × 0.30 pour comfort élevé', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 75,
        mode: SessionMode.hold,
        comfortAtCalibration: 50.0,
      );
      // 50 × 0.30 = 15.
      expect(ch.extensionSeconds, 15);
    });
  });
}
