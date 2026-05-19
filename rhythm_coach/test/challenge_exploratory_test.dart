import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:beat_bitch/services/obedience_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Challenge.initialEstimateSecondsForAxis', () {
    test('paliers débutante par type d\'axe', () {
      expect(
          Challenge.initialEstimateSecondsForAxis(
              CapabilityAxis.holdThroatStreak),
          5);
      expect(
          Challenge.initialEstimateSecondsForAxis(
              CapabilityAxis.holdFullStreak),
          5);
      expect(
          Challenge.initialEstimateSecondsForAxis(
              CapabilityAxis.gorgeApneeStreak),
          5);
      expect(
          Challenge.initialEstimateSecondsForAxis(CapabilityAxis.biffleStreak),
          8);
      expect(
          Challenge.initialEstimateSecondsForAxis(
              CapabilityAxis.rhythmMotionStreak),
          30);
      expect(
          Challenge.initialEstimateSecondsForAxis(
              CapabilityAxis.noswallowStreak),
          15);
    });
  });

  group('ChallengeService.buildForSession — fallback exploratoire', () {
    test('profil totalement vide → exploratoire valide', () {
      final svc = ChallengeService();
      final challenge = svc.buildForSession(
        profile: const CapabilityProfile({}),
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.isExploratory, isTrue);
      expect(challenge.comfortAtCalibration, isNull);
      // Le seuil correspond à l'initial estimate de l'axe choisi.
      expect(challenge.targetThreshold,
          Challenge.initialEstimateSecondsForAxis(challenge.axis));
    });

    test('profil avec axes vierges + exclusions → pick parmi candidats', () {
      final svc = ChallengeService();
      // Profil totalement vide, mais on exclut explicitement holdThroatStreak.
      final challenge = svc.buildForSession(
        profile: const CapabilityProfile({}),
        ceilings: const {},
        excludeAxes: {CapabilityAxis.holdThroatStreak},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, isNot(CapabilityAxis.holdThroatStreak));
      expect(challenge.isExploratory, isTrue);
    });

    test('profil avec un axe prouvé → hybride (pas exploratoire)', () {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNotNull);
      expect(challenge!.isExploratory, isFalse);
      expect(challenge.comfortAtCalibration, 10.0);
    });

    test('aucun axe candidat (tous exclus) → null', () {
      final svc = ChallengeService();
      // Tous les axes pilotants exclus → ni overload ni exploratoire.
      final allOverloadable = {
        CapabilityAxis.holdThroatStreak,
        CapabilityAxis.holdFullStreak,
        CapabilityAxis.gorgeApneeStreak,
        CapabilityAxis.gorgeEngagementStreak,
        CapabilityAxis.gorgeCrossingsBpmThroat,
        CapabilityAxis.gorgeCrossingsBpmFull,
        CapabilityAxis.rhythmBpmCeilShallow,
        CapabilityAxis.rhythmBpmCeilThroat,
        CapabilityAxis.rhythmBpmCeilFull,
        CapabilityAxis.rhythmDepthMax,
        CapabilityAxis.rhythmMotionStreak,
        CapabilityAxis.noswallowStreak,
        CapabilityAxis.biffleStreak,
        CapabilityAxis.biffleBpmMax,
      };
      final challenge = svc.buildForSession(
        profile: const CapabilityProfile({}),
        ceilings: const {},
        excludeAxes: allOverloadable,
        rng: Random(0),
        isTutorial: false,
      );
      expect(challenge, isNull);
    });
  });

  group('Challenge.extensionSeconds avec comfort=null (exploratoire)', () {
    test('plancher 10 s en l\'absence de comfort prouvé', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 5,
        mode: SessionMode.hold,
        isExploratory: true,
        // comfortAtCalibration: null par défaut.
      );
      expect(ch.extensionSeconds, 10);
    });
  });

  group('Outcomes exploratoires — bumps engine', () {
    test('extension : +1 humil / +1 obed par tient encore (pas de base +2)',
        () {
      // En Phase 2 exploratoire, le SessionController n'appelle pas
      // onChallengeNetSuccess sur netSuccess/extendedSuccess. On vérifie
      // ici les méthodes engines existent et bumpent comme prévu — la
      // logique de routing est testée via la session controller.
      final h = HumiliationEngine();
      final o = ObedienceEngine();
      h.seed(career: 10);
      o.seed(50);
      h.onChallengeExtension();
      o.onChallengeExtension();
      h.onChallengeExtension();
      o.onChallengeExtension();
      expect(h.careerScore, 12.0); // 10 + 1 + 1.
      expect(o.score, 52.0); // 50 + 1 + 1.
    });
  });
}
