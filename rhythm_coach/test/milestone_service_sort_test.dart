import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm_coach/career/models/level_milestone.dart';
import 'package:rhythm_coach/career/models/specialization.dart';
import 'package:rhythm_coach/career/models/unlock_key.dart';
import 'package:rhythm_coach/career/services/milestone_service.dart';
import 'package:rhythm_coach/models/session.dart';
import 'package:rhythm_coach/models/session_step.dart';

LevelMilestone _milestone({
  required String id,
  required int level,
  required List<SessionStep> sequence,
  List<UnlockKey> unlocks = const [],
  List<SpecializationBranch> branches = const [],
}) {
  return LevelMilestone(
    id: id,
    level: level,
    displayLabel: id,
    sequence: sequence,
    durationSeconds: sequence.fold<int>(
      0,
      (acc, s) => acc + (s.duration ?? 0),
    ),
    unlocks: unlocks,
    branches: branches,
  );
}

SpecializationAllocation _alloc(Map<SpecializationBranch, int> pts) {
  final base = <SpecializationBranch, int>{
    for (final b in SpecializationBranch.values) b: 0,
  };
  base.addAll(pts);
  return SpecializationAllocation(points: base, lastRespecMs: null);
}

/// Step rhythm head→mid 80 BPM 12s : humil requis 0 (deepest=mid bumpé
/// uniquement par milestone, pas humiliation).
SessionStep _stepLow() => const SessionStep(
      time: 0,
      from: Position.head,
      to: Position.mid,
      bpm: 80,
      duration: 12,
      mode: SessionMode.rhythm,
    );

/// Hold mid 8s : humil requis = 4 + 0.3 × 7 = 6.1.
SessionStep _stepMid() => const SessionStep(
      time: 0,
      from: Position.mid,
      duration: 8,
      mode: SessionMode.hold,
    );

/// Hold throat 6s : humil requis = 8 + 1.5 × 5 = 15.5.
SessionStep _stepHigh() => const SessionStep(
      time: 0,
      from: Position.throat,
      duration: 6,
      mode: SessionMode.hold,
    );

void main() {
  group('MilestoneService.pendingForLevel — tri', () {
    test('allocation null → fallback tri par level croissant', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_l5', level: 5, sequence: [_stepLow()]),
          _milestone(id: 'm_l3', level: 3, sequence: [_stepLow()]),
          _milestone(id: 'm_l4', level: 4, sequence: [_stepLow()]),
        ],
      );
      final pick = svc.pendingForLevel(5);
      expect(pick, isNotNull);
      expect(pick!.id, 'm_l3');
    });

    test('allocation vide + level 4 → tie-break level ASC', () {
      // Toutes les milestones ont 0 branchPoints (allocation vide) et
      // même humilFor (step low). Le tri retombe sur level croissant.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'transverse_l4', level: 4, sequence: [_stepLow()]),
          _milestone(id: 'transverse_l2', level: 2, sequence: [_stepLow()]),
          _milestone(id: 'transverse_l3', level: 3, sequence: [_stepLow()]),
        ],
      );
      final pick = svc.pendingForLevel(4, allocation: _alloc({}));
      expect(pick, isNotNull);
      expect(pick!.id, 'transverse_l2');
    });

    test('endurance: 3 level 4 → milestone endurance gagne le transverse', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'transverse',
            level: 2,
            sequence: [_stepLow()],
          ),
          _milestone(
            id: 'intro_hold_mid',
            level: 4,
            sequence: [_stepMid()],
            branches: [SpecializationBranch.endurance],
          ),
        ],
      );
      final pick = svc.pendingForLevel(
        4,
        allocation: _alloc({SpecializationBranch.endurance: 3}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'intro_hold_mid');
    });

    test(
        'resilience: 2 level 5 → multi-branche resilience+endurance gagne biffle',
        () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'intro_biffle',
            level: 5,
            sequence: [_stepLow()],
            branches: [SpecializationBranch.rythmeBiffle],
          ),
          _milestone(
            id: 'intro_resilience_endure',
            level: 5,
            sequence: [_stepLow()],
            branches: [
              SpecializationBranch.resilience,
              SpecializationBranch.endurance,
            ],
          ),
        ],
      );
      final pick = svc.pendingForLevel(
        5,
        allocation: _alloc({SpecializationBranch.resilience: 2}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'intro_resilience_endure');
    });

    test('mêmes branchPoints → tri par humilFor ASC', () {
      // Deux milestones transverses (0 branchPoints chacune) à même level.
      // Celle dont la séquence exige le moins d'humiliation gagne.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'tough',
            level: 5,
            sequence: [_stepHigh()],
          ),
          _milestone(
            id: 'easy',
            level: 5,
            sequence: [_stepLow()],
          ),
        ],
      );
      final pick = svc.pendingForLevel(5, allocation: _alloc({}));
      expect(pick, isNotNull);
      expect(pick!.id, 'easy');
    });
  });
}
