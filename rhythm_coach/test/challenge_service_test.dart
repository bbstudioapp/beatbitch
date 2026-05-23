import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ChallengeService.buildForSession', () {
    test('tutoriel : axe robuste hold throat 5 s, isTutorial flag posé',
        () async {
      final svc = ChallengeService();
      final challenge = await svc.buildForSession(
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

    test('non-tutoriel : pickOverloadAxis utilisé, seuil = comfort × 1.30',
        () async {
      final svc = ChallengeService();
      final profile = _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
      // 10 × 1.30 = 13.
      expect(challenge.targetThreshold, 13);
      expect(challenge.comfortAtCalibration, 10.0);
    });

    test('axe BPM : rampe comfort → comfort × 1.30 (bpm/bpmEnd)', () async {
      final svc = ChallengeService();
      final profile =
          _profileWithComfort(CapabilityAxis.rhythmBpmCeilThroat, 100);
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.rhythmBpmCeilThroat);
      expect(challenge.kind, ChallengeAxisKind.bpm);
      // 100 × 1.30 = 130.
      expect(challenge.targetThreshold, 130);
      // Rampe : démarre au comfort, monte au seuil cible.
      expect(challenge.bpm, 100);
      expect(challenge.bpmEnd, 130);
      expect(challenge.mode, SessionMode.rhythm);
      // Convention rhythm : from < to (amplitude obligatoire).
      expect(challenge.from, Position.head);
      expect(challenge.to, Position.throat);
    });

    test('axe profondeur : seuil = comfort + 1 cran', () async {
      final svc = ChallengeService();
      // rhythmDepthMax comfort = 2 (mid) → seuil = cran 3 (throat).
      final profile = _profileWithComfort(CapabilityAxis.rhythmDepthMax, 2);
      final challenge = await svc.buildForSession(
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

    test(
        'axes exclus du pickOverloadAxis : fallback exploratoire sur axes vierges (Phase 2)',
        () async {
      final svc = ChallengeService();
      final profile = _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: {CapabilityAxis.holdThroatStreak},
        rng: Random(0),
        isTutorial: false,
      );
      // Phase 2 : le seul axe avec donnée est exclu, mais d'autres axes
      // pilotants sont vierges → fallback exploratoire actif.
      expect(challenge, isNotNull);
      expect(challenge!.isExploratory, isTrue);
      expect(challenge.axis, isNot(CapabilityAxis.holdThroatStreak));
    });

    test('profil vide → exploratoire valide (Phase 2)', () async {
      final svc = ChallengeService();
      final challenge = await svc.buildForSession(
        profile: const CapabilityProfile({}),
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      // Phase 2 : profil vide → fallback exploratoire (axe vierge tiré au
      // hasard parmi `CapabilityClamps.overloadableAxes`).
      expect(challenge, isNotNull);
      expect(challenge!.isExploratory, isTrue);
    });

    test(
      'axe franchissement gorge : targetCrossings posé selon attemptsCount',
      () async {
        final svc = ChallengeService();
        final profile =
            _profileWithComfort(CapabilityAxis.rhythmBpmCeilThroat, 100);
        // 1er essai (attemptsCount = 0) → 5 franchissements.
        final first = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
        );
        expect(first?.axis, CapabilityAxis.rhythmBpmCeilThroat);
        expect(first?.targetCrossings, 5);

        // Incrémente le compteur — le 2e essai monte à 8.
        await svc.incrementAttempts(CapabilityAxis.rhythmBpmCeilThroat);
        final second = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
        );
        expect(second?.targetCrossings, 8);

        // 3e essai → 12.
        await svc.incrementAttempts(CapabilityAxis.rhythmBpmCeilThroat);
        final third = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
        );
        expect(third?.targetCrossings, 12);
      },
    );

    test(
      'axe non-franchissement : targetCrossings null',
      () async {
        final svc = ChallengeService();
        final profile =
            _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
        final challenge = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
        );
        expect(challenge?.axis, CapabilityAxis.holdThroatStreak);
        expect(challenge?.targetCrossings, isNull);
      },
    );

    test(
      'tutoriel : targetCrossings null (le tuto est hold, pas franchissement)',
      () async {
        final svc = ChallengeService();
        final challenge = await svc.buildForSession(
          profile: null,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(42),
          isTutorial: true,
        );
        expect(challenge?.isTutorial, isTrue);
        expect(challenge?.targetCrossings, isNull);
      },
    );
  });

  group('crossingsTargetForAttempts', () {
    test('progression no-limit : 5, 8, 12, 17, 23, 30 …', () {
      expect(crossingsTargetForAttempts(0), 5);
      expect(crossingsTargetForAttempts(1), 8);
      expect(crossingsTargetForAttempts(2), 12);
      expect(crossingsTargetForAttempts(3), 17);
      expect(crossingsTargetForAttempts(4), 23);
      expect(crossingsTargetForAttempts(5), 30);
      // Pas de cap : à 10 défis, 80 franchissements.
      expect(crossingsTargetForAttempts(10), 80);
    });

    test('valeurs négatives → 5 (cas défensif)', () {
      expect(crossingsTargetForAttempts(-1), 5);
      expect(crossingsTargetForAttempts(-99), 5);
    });
  });

  group('ChallengeService.branchOf', () {
    test('mapping axes → branches connues', () async {
      expect(ChallengeService.branchOf(CapabilityAxis.holdThroatStreak),
          SpecializationBranch.endurance);
      expect(ChallengeService.branchOf(CapabilityAxis.rhythmDepthMax),
          SpecializationBranch.profondeur);
      expect(ChallengeService.branchOf(CapabilityAxis.biffleStreak),
          SpecializationBranch.rythmeBiffle);
      expect(ChallengeService.branchOf(CapabilityAxis.noswallowStreak),
          SpecializationBranch.sloppy);
    });

    test('axes non pilotants par branche → null', () async {
      expect(ChallengeService.branchOf(CapabilityAxis.handStreak), isNull);
      expect(ChallengeService.branchOf(CapabilityAxis.lickStreak), isNull);
      expect(ChallengeService.branchOf(CapabilityAxis.breathMinDose), isNull);
    });
  });

  group('ChallengeService.thresholdFor', () {
    test('maximize duration : comfort × 1.30', () async {
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.duration,
          10,
          CapabilityAxis.holdThroatStreak,
        ),
        13,
      );
    });

    test('maximize bpm : comfort × 1.30', () async {
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          100,
          CapabilityAxis.rhythmBpmCeilThroat,
        ),
        130,
      );
    });

    test('minimize bpm : comfort / 1.30 (rampe descendante)', () async {
      // 60 / 1.30 ≈ 46.
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          60,
          CapabilityAxis.rhythmBpmFloorThroat,
        ),
        46,
      );
    });

    test('minimize bpm : plancher à 18 si la division descend plus bas',
        () async {
      // 20 / 1.30 ≈ 15 → planché à 18.
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          20,
          CapabilityAxis.rhythmBpmFloorShallow,
        ),
        18,
      );
    });

    test('maximize depthCran : +1 cran', () async {
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.depthCran,
          2, // mid
          CapabilityAxis.rhythmDepthMax,
        ),
        3, // throat
      );
    });

    test('depthCran : clamp au dernier cran disponible', () async {
      // comfort = dernier cran → +1 sortirait de la plage, clampé.
      final lastCran = Position.values.length - 1;
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.depthCran,
          lastCran.toDouble(),
          CapabilityAxis.rhythmDepthMax,
        ),
        lastCran,
      );
    });
  });

  group('Challenge.nominalDurationSeconds', () {
    // Construit un Challenge minimal pour tester le getter selon (kind, axis).
    Challenge mk(CapabilityAxis axis, ChallengeAxisKind kind,
        {int threshold = 1}) {
      return Challenge(
        axis: axis,
        kind: kind,
        targetThreshold: threshold,
        mode: SessionMode.rhythm,
      );
    }

    test('axes durée : durée = targetThreshold', () async {
      expect(
        mk(CapabilityAxis.holdThroatStreak, ChallengeAxisKind.duration,
                threshold: 15)
            .nominalDurationSeconds,
        15,
      );
      expect(
        mk(CapabilityAxis.biffleStreak, ChallengeAxisKind.duration,
                threshold: 22)
            .nominalDurationSeconds,
        22,
      );
    });

    test('axes BPM : durée par axe — table de calibration', () async {
      final cases = <CapabilityAxis, int>{
        CapabilityAxis.rhythmBpmCeilShallow: 25,
        CapabilityAxis.rhythmBpmCeilThroat: 8,
        CapabilityAxis.rhythmBpmCeilFull: 7,
        CapabilityAxis.gorgeCrossingsBpmThroat: 8,
        CapabilityAxis.gorgeCrossingsBpmFull: 7,
        CapabilityAxis.biffleBpmMax: 20,
        CapabilityAxis.rhythmBpmFloorShallow: 20,
        CapabilityAxis.rhythmBpmFloorThroat: 12,
        CapabilityAxis.rhythmBpmFloorFull: 8,
      };
      for (final entry in cases.entries) {
        expect(
          mk(entry.key, ChallengeAxisKind.bpm).nominalDurationSeconds,
          entry.value,
          reason: '${entry.key} doit durer ${entry.value} s',
        );
      }
    });

    test('axe profondeur : rhythmDepthMax = 12 s', () async {
      expect(
        mk(CapabilityAxis.rhythmDepthMax, ChallengeAxisKind.depthCran)
            .nominalDurationSeconds,
        12,
      );
    });

    test('axe BPM non listé : fallback 30 s', () async {
      // breathMinDose est BPM-like (minimize) mais non câblé dans _modeOf —
      // sert ici de proxy d'un axe pilotant pas encore couvert par la table.
      expect(
        mk(CapabilityAxis.breathMinDose, ChallengeAxisKind.bpm)
            .nominalDurationSeconds,
        30,
      );
    });
  });

  group('Challenge.extensionSeconds', () {
    test('plancher à 10 s pour comfort bas', () async {
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

    test('comfort × 0.30 pour comfort élevé', () async {
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
