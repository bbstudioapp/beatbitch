import 'dart:math';

import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ChallengeService.buildForSession — cascade showcase', () {
    test('showcase=endurance + axe pilotant prouvé → pick branche prioritaire',
        () async {
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
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
      expect(challenge.isExploratory, isFalse);
      expect(challenge.branch, SpecializationBranch.endurance);
    });

    test(
        'showcase=endurance mais aucun axe endurance prouvé → fallback overload',
        () async {
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
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      // Fallback : overload pioche l'axe profondeur (seul candidat).
      expect(challenge!.axis, CapabilityAxis.rhythmDepthMax);
    });

    test('showcase=null → comportement standard (pickOverloadAxis)', () async {
      final svc = ChallengeService();
      // Profondeur prouvée throat pour passer le gating profondeur posé
      // par bug 5 (les défis throat exigent rhythm.depth_max.comfort ≥ 3).
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
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
    });

    test('showcase=endurance + axe excluded → fallback', () async {
      final svc = ChallengeService();
      // Profondeur full prouvée pour permettre les défis holdFullStreak.
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 4.0,
          comfort: 4.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
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
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: {CapabilityAxis.holdThroatStreak},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      // Pickaxisofbranch retombe sur holdFullStreak (autre axe endurance).
      expect(challenge!.axis, CapabilityAxis.holdFullStreak);
    });

    test(
        'showcase=endurance + 2 axes endurance prouvés → pick le plus ancien (lastSeen min)',
        () async {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 4.0,
          comfort: 4.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
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
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        showcaseBranch: SpecializationBranch.endurance,
      );
      expect(challenge, isNotNull);
      // Plus ancien `lastSeenSession` → holdFullStreak.
      expect(challenge!.axis, CapabilityAxis.holdFullStreak);
    });

    test('showcase=obeissance (aucun axe pilotant) → fallback overload',
        () async {
      final svc = ChallengeService();
      // L'obéissance n'a pas d'axe capability (branchOf retournera null
      // pour tous les axes pilotants). La cascade showcase doit
      // graciously retomber sur pickOverloadAxis.
      // Profondeur throat prouvée pour passer le gating posé par bug 5.
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
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        showcaseBranch: SpecializationBranch.obeissance,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
    });
  });
}

/// Ces tests ne portent pas sur le plafond de durée par palier : celui du
/// plus long des formats ne tronque aucun de leurs seuils.
final _noTruncationCap = SessionLengthChoice.longue.maxChallengeDurationSeconds;
