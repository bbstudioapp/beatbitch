import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LevelMilestone _milestone({
  required String id,
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
    minLevel: 1,
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('consolidatePrerequisites', () {
    test('enfants complétés sans le parent (intro_basics) → parent consolidé',
        () async {
      // Reproduit le bug : un défi tuto acquitte `intro_hold_throat` /
      // `intro_final_hold_head` (requires `basics`) via l'unlock provisoire
      // de `intro_basics` insérée mais jamais consolidée. État persisté =
      // enfants faits, parent en attente → tutoriel ré-inséré.
      final basics =
          _milestone(id: 'intro_basics', unlocks: [UnlockKey.basics]);
      final throat = _milestone(
        id: 'intro_hold_throat',
        unlocks: [UnlockKey.throatHold],
        requires: [UnlockKey.basics],
      );
      final finalHead = _milestone(
        id: 'intro_final_hold_head',
        unlocks: [UnlockKey.finalHoldHead],
        requires: [UnlockKey.basics],
      );
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [basics, throat, finalHead],
        completed: {'intro_hold_throat', 'intro_final_hold_head'},
      );

      expect(svc.isCompleted('intro_basics'), isFalse);
      final added = await svc.consolidatePrerequisites();

      expect(added, 1);
      expect(svc.isCompleted('intro_basics'), isTrue);
      // Et donc plus jamais candidat à la ré-insertion : son unlock est acquis.
      expect(svc.hasUnlock(UnlockKey.basics), isTrue);
    });

    test('idempotent : 2e appel ne consolide rien', () async {
      final basics =
          _milestone(id: 'intro_basics', unlocks: [UnlockKey.basics]);
      final throat = _milestone(
        id: 'intro_hold_throat',
        unlocks: [UnlockKey.throatHold],
        requires: [UnlockKey.basics],
      );
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [basics, throat],
        completed: {'intro_hold_throat'},
      );

      expect(await svc.consolidatePrerequisites(), 1);
      expect(await svc.consolidatePrerequisites(), 0);
    });

    test('chaîne transitive : point fixe consolide tous les ancêtres',
        () async {
      // grandParent → parent → child : seul `child` est complété.
      final grandParent = _milestone(id: 'gp', unlocks: [UnlockKey.basics]);
      final parent = _milestone(
        id: 'p',
        unlocks: [UnlockKey.rhythmMidBasic],
        requires: [UnlockKey.basics],
      );
      final child = _milestone(
        id: 'c',
        unlocks: [UnlockKey.holdMid],
        requires: [UnlockKey.rhythmMidBasic],
      );
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [grandParent, parent, child],
        completed: {'c'},
      );

      final added = await svc.consolidatePrerequisites();
      expect(added, 2);
      expect(svc.isCompleted('p'), isTrue);
      expect(svc.isCompleted('gp'), isTrue);
    });

    test('rien à réparer : set cohérent → 0', () async {
      final basics =
          _milestone(id: 'intro_basics', unlocks: [UnlockKey.basics]);
      final throat = _milestone(
        id: 'intro_hold_throat',
        unlocks: [UnlockKey.throatHold],
        requires: [UnlockKey.basics],
      );
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [basics, throat],
        completed: {'intro_basics', 'intro_hold_throat'},
      );

      expect(await svc.consolidatePrerequisites(), 0);
    });
  });
}
