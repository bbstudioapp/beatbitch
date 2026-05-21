import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/capability_requirement.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/models/anatomy_profile.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Régression : « bloquée au niveau 9 en boucle » (post-update v0.4.0).
///
/// Cause : `session_screen.dart._recordCareerCompletion` re-calculait
/// `hasPendingAtCurrentLevel` via `MilestoneService.pendingFor` **sans**
/// passer `anatomy`, alors que `career_screen.dart` au start le passait.
/// Conséquence pour une joueuse `hasBalls=false` + `biffle.streak < 10` :
/// pool start = vide (anatomy filtre `intro_balls_lick`, capability filtre
/// `intro_biffle_fast`) → rien inséré ; pool end = non-vide (anatomy absent,
/// `intro_balls_lick` redevient candidate) → level-up bloqué indéfiniment.
LevelMilestone _ballsMilestone() {
  return const LevelMilestone(
    id: 'intro_balls_lick',
    minLevel: 9,
    humilRequired: 5,
    displayLabel: 'Balls',
    sequence: [
      SessionStep(
        time: 0,
        mode: SessionMode.lick,
        from: Position.throat,
        to: Position.balls,
        bpm: 55,
        duration: 14,
      ),
    ],
    durationSeconds: 14,
    unlocks: [UnlockKey.lickBalls],
  );
}

LevelMilestone _biffleFastMilestone() {
  return const LevelMilestone(
    id: 'intro_biffle_fast',
    minLevel: 9,
    humilRequired: 5,
    displayLabel: 'Biffle fast',
    sequence: [
      SessionStep(
        time: 0,
        mode: SessionMode.biffle,
        bpm: 120,
        duration: 14,
      ),
    ],
    durationSeconds: 14,
    unlocks: [],
    requiresCapability: [
      CapabilityRequirement(axis: CapabilityAxis.biffleStreak, min: 10),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Régression bug niveau 9 — call site end-of-session', () {
    test(
        "scénario du bug reproduit : sans anatomy, le pool reste non-vide "
        "alors que toutes les milestones devraient être filtrées "
        "(=> level-up bloqué)", () async {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [_ballsMilestone(), _biffleFastMilestone()]);

      final emptyProfile = await CapabilityService().snapshotProfile();

      // Simule le call site BUGUÉ (avant fix) : anatomy oublié.
      final pendingBug = svc.pendingFor(
        humiliationScore: 100,
        obedience: 100,
        playerLevel: 9,
        capabilityProfile: emptyProfile,
        // anatomy: oublié → bug.
      );
      expect(
        pendingBug,
        isNotNull,
        reason:
            'Sans anatomy, intro_balls_lick reste candidate → hasPendingAtCurrentLevel = true '
            '→ level-up refusé en boucle (= bug reproduit).',
      );
      expect(pendingBug!.id, 'intro_balls_lick');

      // Simule le call site CORRIGÉ : anatomy passé.
      final pendingFixed = svc.pendingFor(
        humiliationScore: 100,
        obedience: 100,
        playerLevel: 9,
        capabilityProfile: emptyProfile,
        anatomy: const AnatomyProfile(hasBalls: false),
      );
      expect(
        pendingFixed,
        isNull,
        reason:
            'Avec anatomy passé, intro_balls_lick filtrée + intro_biffle_fast filtrée '
            '(capability vide) → pool effectivement vide → level-up libre.',
      );
    });

    // Phase 19.12 — le garde-fou statique sur `_recordCareerCompletion`
    // est retiré : la fonction ne fait plus que `recordSessionCompleted()`,
    // il n'y a plus de call `pendingFor` à pincer côté end-of-session
    // (la notion de level-up disparaît avec le retrait de `maxLevel`).
  });
}
