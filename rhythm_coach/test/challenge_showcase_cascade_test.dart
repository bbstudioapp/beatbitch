import 'dart:math';

import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChallengeService.buildForSession — cascade showcase', () {
    test('showcase=endurance + axe pilotant prouvé → pick branche prioritaire',
        () {
      final svc = ChallengeService();
      // Profil avec UN axe profondeur (rhythmDepthMax) ET un axe endurance
      // (holdThroatStreak) prouvés. Sans showcase, pickOverloadAxis aurait
      // tiré aléatoirement. Avec showcase=endurance, on doit voir l'axe
      // endurance choisi.
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 3.0,
          comfort: 3.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
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
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
      expect(challenge.isExploratory, isFalse);
      expect(challenge.branch, SpecializationBranch.endurance);
    });

    test(
        'showcase=endurance mais aucun axe endurance prouvé → fallback overload',
        () {
      final svc = ChallengeService();
      // Profil avec uniquement profondeur (pas endurance) prouvée.
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 3.0,
          comfort: 3.0,
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
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      // Fallback : overload pioche l'axe profondeur (seul candidat).
      expect(challenge!.axis, CapabilityAxis.rhythmDepthMax);
    });

    test('showcase=null → comportement standard (pickOverloadAxis)', () {
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
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
    });

    test('showcase=endurance + axe excluded → fallback', () {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.holdFullStreak: CapabilityAxisState(
          best: 8.0,
          comfort: 8.0,
          successRate: 0.9,
          lastSeenSession: 2,
        ),
      });
      // L'axe le plus ancien (holdThroatStreak avec lastSeen=1) est exclu.
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: {CapabilityAxis.holdThroatStreak},
        rng: Random(0),
        isTutorial: false,
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      // Pickaxisofbranch retombe sur holdFullStreak (autre axe endurance).
      expect(challenge!.axis, CapabilityAxis.holdFullStreak);
    });

    test(
        'showcase=endurance + 2 axes endurance prouvés → pick le plus ancien (lastSeen min)',
        () {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 5, // plus récent
        ),
        CapabilityAxis.holdFullStreak: CapabilityAxisState(
          best: 8.0,
          comfort: 8.0,
          successRate: 0.9,
          lastSeenSession: 2, // plus ancien
        ),
      });
      final challenge = svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      // Plus ancien `lastSeenSession` → holdFullStreak.
      expect(challenge!.axis, CapabilityAxis.holdFullStreak);
    });

    test('showcase=obeissance (aucun axe pilotant) → fallback overload', () {
      final svc = ChallengeService();
      // L'obéissance n'a pas d'axe capability (branchOf retournera null
      // pour tous les axes pilotants). La cascade showcase doit
      // graciously retomber sur pickOverloadAxis.
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
        showcaseBranch: SpecializationBranch.obeissance,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
    });
  });
}
