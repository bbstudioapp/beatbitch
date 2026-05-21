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

  group('milestonesAcquittableByChallenge — cascade transitive holds', () {
    test(
      'défi hold throat 5 s acquitte hold mid (sans requiresCapability)',
      () {
        // Reproduit le cas signalé : un défi tuto hold throat 5 s doit
        // acquitter immédiatement les milestones d'unlock hold précédentes
        // (intro_hold_mid → hold_mid_short, finals tip/head/mid) — sinon
        // la joueuse les voit réapparaître en session 2 alors que la
        // capacité a été prouvée.
        final svc = MilestoneService();
        final holdMid = _milestone(
          id: 'intro_hold_mid',
          requiresCapability: const [],
          unlocks: [UnlockKey.holdMidShort],
        );
        final finalTip = _milestone(
          id: 'intro_final_hold_tip',
          requiresCapability: const [],
          unlocks: [UnlockKey.finalHoldTip],
        );
        svc.seedForTest(catalog: [holdMid, finalTip]);
        final out = svc.milestonesAcquittableByChallenge(
          axis: CapabilityAxis.holdThroatStreak,
          reached: 5.0,
          profile: const CapabilityProfile({}),
          acquiredUnlocks: const {},
        );
        expect(
          out.map((m) => m.id),
          containsAll(['intro_hold_mid', 'intro_final_hold_tip']),
        );
      },
    );

    test('seuil 2 s sur hold throat → transitivité non déclenchée', () {
      // En dessous du plancher de 3 s, un défi exploratoire qui n'a
      // tenu que 1-2 s ne doit pas faire passer toute la chaîne.
      final svc = MilestoneService();
      final holdMid = _milestone(
        id: 'intro_hold_mid',
        requiresCapability: const [],
        unlocks: [UnlockKey.holdMidShort],
      );
      svc.seedForTest(catalog: [holdMid]);
      final out = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 2.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: const {},
      );
      expect(out, isEmpty);
    });

    test(
      'transitivité respecte requires (pas d\'unlock orphelin)',
      () {
        // Une milestone hold mid qui exige `basics` au préalable ne
        // doit pas être acquittée si `basics` n'a pas été acquis —
        // la transitivité n'est pas un contournement du gating métier.
        final svc = MilestoneService();
        final holdMid = _milestone(
          id: 'intro_hold_mid',
          requiresCapability: const [],
          unlocks: [UnlockKey.holdMidShort],
          requires: [UnlockKey.basics],
        );
        svc.seedForTest(catalog: [holdMid]);
        final out = svc.milestonesAcquittableByChallenge(
          axis: CapabilityAxis.holdThroatStreak,
          reached: 5.0,
          profile: const CapabilityProfile({}),
          acquiredUnlocks: const {},
        );
        expect(out, isEmpty);
        // Avec basics acquis : la transitivité passe.
        final out2 = svc.milestonesAcquittableByChallenge(
          axis: CapabilityAxis.holdThroatStreak,
          reached: 5.0,
          profile: const CapabilityProfile({}),
          acquiredUnlocks: {UnlockKey.basics},
        );
        expect(out2.map((m) => m.id), ['intro_hold_mid']);
      },
    );

    test(
      'défi hold full → cascade transitive sur throat + finals throat',
      () {
        final svc = MilestoneService();
        final throatShort = _milestone(
          id: 'intro_hold_throat_short',
          requiresCapability: const [],
          unlocks: [UnlockKey.throatHoldShort],
        );
        final finalThroat = _milestone(
          id: 'intro_final_hold_throat',
          requiresCapability: const [],
          unlocks: [UnlockKey.finalHoldThroat],
        );
        svc.seedForTest(catalog: [throatShort, finalThroat]);
        final out = svc.milestonesAcquittableByChallenge(
          axis: CapabilityAxis.holdFullStreak,
          reached: 4.0,
          profile: const CapabilityProfile({}),
          acquiredUnlocks: const {},
        );
        expect(
          out.map((m) => m.id),
          containsAll(['intro_hold_throat_short', 'intro_final_hold_throat']),
        );
      },
    );

    test(
      'transitivité respecte les autres requiresCapability',
      () {
        // Une milestone qui exige aussi `rhythm.depth_max ≥ 2` ne doit
        // pas être acquittée par un défi hold throat 5 s si le profil
        // n'a pas la profondeur prouvée par ailleurs.
        final svc = MilestoneService();
        final m = _milestone(
          id: 'intro_hold_throat_short',
          requiresCapability: [
            const CapabilityRequirement(
                axis: CapabilityAxis.rhythmDepthMax, min: 2.0),
          ],
          unlocks: [UnlockKey.throatHoldShort],
        );
        svc.seedForTest(catalog: [m]);
        final out = svc.milestonesAcquittableByChallenge(
          axis: CapabilityAxis.holdFullStreak,
          reached: 5.0,
          profile: const CapabilityProfile({}),
          acquiredUnlocks: const {},
        );
        expect(out, isEmpty);
      },
    );
  });

  group('reconcileFromCapability — rattrapage à froid', () {
    test(
      'profil prouve hold throat 5 s → acquitte les holds shallow rétroactivement',
      () async {
        // Cas reproductible : la cascade transitive est livrée APRÈS que
        // la joueuse ait joué son défi tuto. Son `CapabilityProfile`
        // porte la preuve (`hold.throat.streak.best = 5.0`) mais aucune
        // milestone n'a été acquittée. Le rattrapage au start de session
        // doit acquitter `intro_hold_mid`, `intro_final_hold_tip`, etc.
        final svc = MilestoneService();
        final holdMid = _milestone(
          id: 'intro_hold_mid',
          requiresCapability: const [],
          unlocks: [UnlockKey.holdMidShort],
        );
        final finalTip = _milestone(
          id: 'intro_final_hold_tip',
          requiresCapability: const [],
          unlocks: [UnlockKey.finalHoldTip],
        );
        svc.seedForTest(catalog: [holdMid, finalTip]);
        // Profil sans aucun unlock encore acquitté.
        expect(svc.acquiredUnlockKeys(), isEmpty);
        final profile = CapabilityProfile({
          CapabilityAxis.holdThroatStreak: const CapabilityAxisState(
            best: 5.0,
            comfort: 5.0,
            successRate: 1.0,
            lastSeenSession: 1,
          ),
        });
        final acquitted = await svc.reconcileFromCapability(profile);
        expect(acquitted, 2);
        expect(
          svc.acquiredUnlockKeys(),
          containsAll([UnlockKey.holdMidShort, UnlockKey.finalHoldTip]),
        );
      },
    );

    test('profil vide → no-op (zéro acquittement)', () async {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'intro_hold_mid',
        requiresCapability: const [],
        unlocks: [UnlockKey.holdMidShort],
      );
      svc.seedForTest(catalog: [m]);
      final acquitted =
          await svc.reconcileFromCapability(const CapabilityProfile({}));
      expect(acquitted, 0);
      expect(svc.acquiredUnlockKeys(), isEmpty);
    });

    test('idempotent : second appel ne refait rien', () async {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'intro_hold_mid',
        requiresCapability: const [],
        unlocks: [UnlockKey.holdMidShort],
      );
      svc.seedForTest(catalog: [m]);
      final profile = CapabilityProfile({
        CapabilityAxis.holdThroatStreak: const CapabilityAxisState(
          best: 5.0,
          comfort: 5.0,
          successRate: 1.0,
          lastSeenSession: 1,
        ),
      });
      expect(await svc.reconcileFromCapability(profile), 1);
      expect(await svc.reconcileFromCapability(profile), 0);
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
