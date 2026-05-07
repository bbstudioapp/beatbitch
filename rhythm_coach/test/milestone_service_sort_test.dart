import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm_coach/career/models/level_milestone.dart';
import 'package:rhythm_coach/career/models/specialization.dart';
import 'package:rhythm_coach/career/models/unlock_key.dart';
import 'package:rhythm_coach/career/services/milestone_service.dart';
import 'package:rhythm_coach/models/session.dart';
import 'package:rhythm_coach/models/session_step.dart';
import 'package:rhythm_coach/services/humiliation_engine.dart';

double _humilMaxOf(Iterable<SessionStep> steps) {
  var best = 0.0;
  for (final s in steps) {
    final r = HumiliationScale.requiredFor(
      mode: s.mode ?? SessionMode.rhythm,
      from: s.from,
      to: s.to,
      bpm: s.bpm,
      duration: s.duration,
    );
    if (r > best) best = r;
  }
  return best;
}

LevelMilestone _milestone({
  required String id,
  required List<SessionStep> sequence,
  List<UnlockKey> unlocks = const [],
  List<SpecializationBranch> branches = const [],
  double? humilRequired,
}) {
  return LevelMilestone(
    id: id,
    humilRequired: humilRequired ?? _humilMaxOf(sequence),
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
/// Convention uniforme hold/beg : la position tenue est dans `to`.
SessionStep _stepMid() => const SessionStep(
      time: 0,
      to: Position.mid,
      duration: 8,
      mode: SessionMode.hold,
    );

/// Hold throat 6s : humil requis = 8 + 1.5 × 5 = 15.5.
SessionStep _stepHigh() => const SessionStep(
      time: 0,
      to: Position.throat,
      duration: 6,
      mode: SessionMode.hold,
    );

/// Helpers communs : humil/obed assez hauts pour que toutes les
/// milestones du test soient candidates (le tri reste l'objet du test).
const double _humilFloor = 100.0;
const double _obedFloor = 0.0;

void main() {
  group('MilestoneService.pendingFor — tri', () {
    test('allocation null → tri par humilRequired ASC, puis id', () {
      // Toutes les sequences ont humil 0 (step low) → tie-break sur l'id.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_c', sequence: [_stepLow()]),
          _milestone(id: 'm_a', sequence: [_stepLow()]),
          _milestone(id: 'm_b', sequence: [_stepLow()]),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_a');
    });

    test('allocation vide → tie-break id ASC à humil égales', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'transverse_c', sequence: [_stepLow()]),
          _milestone(id: 'transverse_a', sequence: [_stepLow()]),
          _milestone(id: 'transverse_b', sequence: [_stepLow()]),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'transverse_a');
    });

    test('endurance: 3 → milestone endurance gagne le transverse', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'transverse',
            sequence: [_stepLow()],
          ),
          _milestone(
            id: 'intro_hold_mid',
            sequence: [_stepMid()],
            branches: [SpecializationBranch.endurance],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.endurance: 3}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'intro_hold_mid');
    });

    test('resilience: 2 → multi-branche resilience+endurance gagne biffle',
        () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'intro_biffle',
            sequence: [_stepLow()],
            branches: [SpecializationBranch.rythmeBiffle],
          ),
          _milestone(
            id: 'intro_resilience_endure',
            sequence: [_stepLow()],
            branches: [
              SpecializationBranch.resilience,
              SpecializationBranch.endurance,
            ],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.resilience: 2}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'intro_resilience_endure');
    });

    test(
        'multi-branches matchant 2 spés battent mono-branche matchant 1 spé '
        'à pts max égaux',
        () {
      // User : endurance=2, profondeur=2.
      // mono : branches=[endurance] → score = 2.
      // multi : branches=[endurance, profondeur] → score = 4.
      // Avec l'ancien tri par max(pointsIn), les deux étaient à 2 et le
      // tie-break humil/id départageait — la couverture multi-spé n'était
      // pas récompensée. Avec la somme, multi passe devant.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'mono_endurance',
            sequence: [_stepLow()],
            branches: [SpecializationBranch.endurance],
          ),
          _milestone(
            id: 'multi_endure_profond',
            sequence: [_stepLow()],
            branches: [
              SpecializationBranch.endurance,
              SpecializationBranch.profondeur,
            ],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({
          SpecializationBranch.endurance: 2,
          SpecializationBranch.profondeur: 2,
        }),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'multi_endure_profond');
    });

    test('mêmes branchPoints → tri par humilRequired ASC', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'tough',
            sequence: [_stepHigh()],
          ),
          _milestone(
            id: 'easy',
            sequence: [_stepLow()],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'easy');
    });
  });

  group('MilestoneService.pendingFor — filtre humiliation + obédiance', () {
    test('humil 0 obed 0 → tolérance +1 → milestone humil≤1 candidate', () {
      // Step hold to:head : humilRequired = 1.0 (cas intro_basics).
      const stepHoldHead = SessionStep(
        time: 0,
        to: Position.head,
        duration: 6,
        mode: SessionMode.hold,
      );
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'one', sequence: [stepHoldHead]),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: 0.0,
        obedience: 0.0,
      );
      expect(pick, isNotNull,
          reason:
              'humil 0 + obed 0 → tolérance 1 → milestone humil≤1 doit être '
              'candidate (cas intro_basics)');
      expect(pick!.id, 'one');
    });

    test('humil 0 obed 0 → milestone humil 6.1 NON candidate', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'tough', sequence: [_stepMid()]),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: 0.0,
        obedience: 0.0,
      );
      expect(pick, isNull,
          reason:
              'humil 0 + obed 0 → tolérance 1 → milestone humil 6.1 hors '
              'fenêtre');
    });

    test('obed 100 → tolérance +3 → milestone humil 3 candidate à humil 0',
        () {
      // hold mid 4s : humil = 4.0 + 0.3*3 = 4.9. À obed 100, tolérance =
      // 1 + 100/50 = 3 → cap effectif = 0+3 = 3. humil 4.9 > 3 → non.
      // hold mid 1s : humil = 4.0 + 0.3*0 = 4.0. Toujours > 3 → non.
      // Donc on prend hold tip 4s : humil = 0. Pas pertinent. Plutôt :
      // construit un milestone à humilRequired explicite = 3.0.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'mid_step',
            sequence: [_stepLow()],
            humilRequired: 3.0,
          ),
          _milestone(
            id: 'high_step',
            sequence: [_stepLow()],
            humilRequired: 4.0,
          ),
        ],
      );
      final pickAtObed0 = svc.pendingFor(
        humiliationScore: 0.0,
        obedience: 0.0,
      );
      expect(pickAtObed0, isNull,
          reason:
              'obed 0 → tolérance 1 → cap=1 → ni humil 3 ni 4 candidates');
      final pickAtObed100 = svc.pendingFor(
        humiliationScore: 0.0,
        obedience: 100.0,
      );
      expect(pickAtObed100, isNotNull,
          reason: 'obed 100 → tolérance 3 → cap=3 → humil 3 candidate');
      expect(pickAtObed100!.id, 'mid_step');
    });
  });
}
