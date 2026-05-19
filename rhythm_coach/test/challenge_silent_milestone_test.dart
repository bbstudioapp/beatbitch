import 'package:beat_bitch/career/models/capability_requirement.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LevelMilestone _milestone({
  required String id,
  required List<CapabilityRequirement> requiresCapability,
  List<UnlockKey> unlocks = const [],
  List<UnlockKey> requires = const [],
}) {
  return LevelMilestone(
    id: id,
    humilRequired: 0,
    displayLabel: id,
    sequence: const [],
    durationSeconds: 1,
    unlocks: unlocks,
    requires: requires,
    requiresCapability: requiresCapability,
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Bouchonner le canal de localisation : le service y touche par
    // ailleurs (loader assets), pas nécessaire ici.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('milestonesAcquittableByChallenge', () {
    test('axe matche + seuil atteint → milestone retournée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
        ],
      );
      svc.seedForTest(catalog: [m]);
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 12.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, hasLength(1));
      expect(out.first.id, 'm1');
    });

    test('axe matche mais seuil pas atteint → ignorée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
        ],
      );
      svc.seedForTest(catalog: [m]);
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 8.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });

    test('autre axe poussé → ignorée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
        ],
      );
      svc.seedForTest(catalog: [m]);
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.biffleStreak,
        reached: 30.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });

    test('déjà acquittée → ignorée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
        ],
      );
      svc.seedForTest(catalog: [m], completed: {'m1'});
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 12.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });

    test('unlocks pré-requis manquants → ignorée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
        ],
        requires: [UnlockKey.throatHoldShort],
      );
      svc.seedForTest(catalog: [m]);
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 12.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });

    test('autres requiresCapability satisfaits par profile → acquittée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
          const CapabilityRequirement(
              axis: CapabilityAxis.gorgeApneeStreak, min: 5.0),
        ],
      );
      svc.seedForTest(catalog: [m]);
      // Le profil porte déjà gorgeApneeStreak >= 5.
      const profile = CapabilityProfile({
        CapabilityAxis.gorgeApneeStreak: CapabilityAxisState(best: 8.0),
      });
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 12.0,
        profile: profile,
        acquiredUnlocks: const {},
      );
      expect(out, hasLength(1));
    });

    test('autres requiresCapability non satisfaits → ignorée', () {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
          const CapabilityRequirement(
              axis: CapabilityAxis.gorgeApneeStreak, min: 5.0),
        ],
      );
      svc.seedForTest(catalog: [m]);
      // Profil vide : gorgeApneeStreak non satisfait → ignorée.
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 12.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });

    test('milestone sans requiresCapability → ignorée (rien à acquitter)', () {
      final svc = MilestoneService();
      final m = _milestone(id: 'm1', requiresCapability: const []);
      svc.seedForTest(catalog: [m]);
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 100.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });
  });

  group('markCompletedViaChallenge', () {
    test('persiste comme acquittée, idempotent', () async {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm1',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 10.0),
        ],
      );
      svc.seedForTest(catalog: [m]);
      expect(svc.isCompleted('m1'), isFalse);
      await svc.markCompletedViaChallenge('m1');
      expect(svc.isCompleted('m1'), isTrue);
      // Idempotent.
      await svc.markCompletedViaChallenge('m1');
      expect(svc.isCompleted('m1'), isTrue);
    });
  });
}
