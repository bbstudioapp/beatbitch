import 'dart:io';

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

    test(
        'session_screen._recordCareerCompletion DOIT passer anatomy à '
        'pendingFor (garde-fou contre régression silencieuse)', () {
      // Garde-fou statique : le call site `pendingFor` dans
      // `_recordCareerCompletion` doit propager `widget.anatomy`. Oublier
      // ce paramètre est invisible côté typage (anatomy est optionnel)
      // mais fatal côté gameplay (cf. test précédent). Ce test pince le
      // bloc exact pour fail si le fix disparaît.
      final src = File('lib/screens/session_screen.dart').readAsStringSync();
      final block = RegExp(
        r'_recordCareerCompletion[\s\S]+?milestoneService\.pendingFor\([\s\S]+?\);',
      ).firstMatch(src);
      expect(block, isNotNull,
          reason: '_recordCareerCompletion doit appeler pendingFor');
      expect(
        block!.group(0),
        contains('anatomy:'),
        reason: 'Le call pendingFor au end-of-session DOIT recevoir anatomy '
            'pour rester cohérent avec le filtre du start (career_screen). '
            "Sinon : milestone exclue au start (ex. balls) redevient candidate "
            'au end → level-up bloqué indéfiniment (bug post-update v0.4.0).',
      );
    });
  });
}
