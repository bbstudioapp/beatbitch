import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/capability_requirement.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

LevelMilestone _m({
  required String id,
  List<SessionStep>? sequence,
  double? humilRequired,
  List<CapabilityRequirement> requiresCapability = const [],
  List<SpecializationBranch> branches = const [],
  int minLevel = 1,
}) {
  final seq = sequence ??
      const [
        SessionStep(
          time: 0,
          from: Position.head,
          to: Position.mid,
          bpm: 80,
          duration: 12,
          mode: SessionMode.rhythm,
        ),
      ];
  return LevelMilestone(
    id: id,
    minLevel: minLevel,
    humilRequired: humilRequired ?? 0.0,
    displayLabel: id,
    sequence: seq,
    durationSeconds: seq.fold<int>(0, (a, s) => a + (s.duration ?? 0)),
    unlocks: const [],
    requiresCapability: requiresCapability,
    branches: branches,
  );
}

SpecializationAllocation _alloc(Map<SpecializationBranch, int> pts) {
  final base = {for (final b in SpecializationBranch.values) b: 0};
  base.addAll(pts);
  return SpecializationAllocation(points: base, lastRespecMs: null);
}

CapabilityProfile _profileWith(Map<CapabilityAxis, double> bests) {
  final states = <CapabilityAxis, CapabilityAxisState>{};
  for (final axis in CapabilityAxis.values) {
    final v = bests[axis];
    states[axis] = v == null
        ? const CapabilityAxisState()
        : CapabilityAxisState(best: v, comfort: v);
  }
  return CapabilityProfile(states);
}

const _humilHigh = 100.0;
const _obedNeutral = 0.0;

void main() {
  group('MilestoneService — gating capability', () {
    test('profil null = mode hérité → requiresCapability ignoré', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(
          id: 'needs_throat',
          requiresCapability: const [
            CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak,
              min: 10,
            ),
          ],
        ),
      ]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        // capabilityProfile omis volontairement
      );
      expect(pick, isNotNull,
          reason: 'sans profil fourni, le gating capacité est neutralisé '
              "(rétro-compat avec les tests / callers hors carrière)");
      expect(pick!.id, 'needs_throat');
    });

    test('profil sans donnée sur l\'axe → milestone bloquée', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(
          id: 'needs_throat',
          requiresCapability: const [
            CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak,
              min: 3,
            ),
          ],
        ),
      ]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith(const {}),
      );
      expect(pick, isNull,
          reason: "best=null → requirement non satisfait → milestone exclue");
    });

    test('best en deçà du seuil → milestone bloquée', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(
          id: 'needs_throat',
          requiresCapability: const [
            CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak,
              min: 5,
            ),
          ],
        ),
      ]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith({
          CapabilityAxis.holdThroatStreak: 4.0,
        }),
      );
      expect(pick, isNull);
    });

    test('best au seuil → milestone candidate', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(
          id: 'needs_throat',
          requiresCapability: const [
            CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak,
              min: 5,
            ),
          ],
        ),
      ]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith({
          CapabilityAxis.holdThroatStreak: 5.0,
        }),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'needs_throat');
    });

    test('multi-requirements : tous doivent être satisfaits', () {
      const reqs = [
        CapabilityRequirement(
          axis: CapabilityAxis.holdThroatStreak,
          min: 5,
        ),
        CapabilityRequirement(
          axis: CapabilityAxis.rhythmBpmCeilThroat,
          min: 120,
        ),
      ];
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [_m(id: 'tough', requiresCapability: reqs)],
      );

      // Un seul axe satisfait → bloqué.
      final partial = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith({
          CapabilityAxis.holdThroatStreak: 5.0,
          // rhythmBpmCeilThroat absent
        }),
      );
      expect(partial, isNull);

      // Les deux satisfaits → candidate.
      final full = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith({
          CapabilityAxis.holdThroatStreak: 5.0,
          CapabilityAxis.rhythmBpmCeilThroat: 130.0,
        }),
      );
      expect(full, isNotNull);
      expect(full!.id, 'tough');
    });

    test('axe minimize : best ≤ min satisfait (planchers BPM)', () {
      // rhythmBpmFloorShallow est minimize : "j'ai tenu jusqu'à 30 BPM en
      // shallow" → best=30. Exigence "best ≤ 40" est satisfaite.
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(
          id: 'slow_master',
          requiresCapability: const [
            CapabilityRequirement(
              axis: CapabilityAxis.rhythmBpmFloorShallow,
              min: 40,
            ),
          ],
        ),
      ]);
      final pickSlow = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith({
          CapabilityAxis.rhythmBpmFloorShallow: 30.0,
        }),
      );
      expect(pickSlow, isNotNull,
          reason: 'best=30 ≤ min=40 → satisfait pour minimize');

      final pickFast = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith({
          CapabilityAxis.rhythmBpmFloorShallow: 60.0,
        }),
      );
      expect(pickFast, isNull,
          reason: 'best=60 > min=40 → non satisfait pour minimize');
    });

    test(
        'pas de requiresCapability + profil neuf → milestone candidate '
        '(rétro-compat parfaite)', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [_m(id: 'plain')]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        capabilityProfile: _profileWith(const {}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'plain');
    });
  });

  group('MilestoneService — tri branche-la-plus-basse', () {
    test(
        'à match spé égal, milestone dont la branche min est moins '
        'investie passe d\'abord', () {
      // User : endurance=3, profondeur=0.
      // m_high : branches=[endurance]                → score=3, lowest=3
      // m_low  : branches=[endurance, profondeur]    → score=3, lowest=0
      // Le critère branche-basse fait gagner m_low (équilibrage variété).
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(id: 'm_high', branches: [SpecializationBranch.endurance]),
        _m(id: 'm_low', branches: [
          SpecializationBranch.endurance,
          SpecializationBranch.profondeur,
        ]),
      ]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
        allocation: _alloc({SpecializationBranch.endurance: 3}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_low',
          reason:
              "à branchScore égal (3=3), milestone touchant aussi profondeur "
              "(min investie chez la joueuse) passe d'abord");
    });

    test(
        'sans allocation → tri branche-basse neutralisé '
        '(tie-break humil puis id)', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _m(id: 'm_b', branches: [SpecializationBranch.endurance]),
        _m(id: 'm_a', branches: [
          SpecializationBranch.endurance,
          SpecializationBranch.profondeur,
        ]),
      ]);
      final pick = svc.pendingFor(
        humiliationScore: _humilHigh,
        obedience: _obedNeutral,
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_a',
          reason: 'sans allocation, lowestBranchPoints=0 partout → '
              "tie-break humil puis id : 'm_a' < 'm_b'");
    });
  });
}
