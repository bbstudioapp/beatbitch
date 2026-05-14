import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:shared_preferences/shared_preferences.dart';

LevelMilestone _milestone({
  required String id,
  List<SpecializationBranch> branches = const [],
  List<UnlockKey> unlocks = const [],
  double humilRequired = 0,
}) {
  // Step rhythm head→mid 80 BPM — humil 0, satisfait toujours le cap.
  const lowStep = SessionStep(
    time: 0,
    from: Position.head,
    to: Position.mid,
    bpm: 80,
    duration: 12,
    mode: SessionMode.rhythm,
  );
  return LevelMilestone(
    id: id,
    humilRequired: humilRequired,
    displayLabel: id,
    sequence: const [lowStep],
    durationSeconds: 12,
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

const double _humilFloor = 100.0;
const double _obedFloor = 0.0;

void main() {
  // Évite `MissingPluginException` côté SharedPreferences en mode test.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MilestoneService — sortScore vieillissement', () {
    test(
        "âge faible : branchScore reste dominant, la milestone spé-matchée "
        'fraîche gagne', () {
      // sortScore_trans = 0 + 0.5*2 - 0.1*0 = 1.0
      // sortScore_spec  = 4 + 0   - 0.1*4 = 3.6
      // → spec gagne (3.6 > 1.0).
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'transverse_old',
            // Pas de branches → branchScore = 0.
          ),
          _milestone(
            id: 'spec_match',
            branches: [SpecializationBranch.endurance],
          ),
        ],
        candidacyAge: const {
          'transverse_old': 2,
        },
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.endurance: 4}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'spec_match',
          reason: "tant que branchScore (4) > aging × age (1.0), la spé doit "
              'dominer');
    });

    test(
        "âge élevé : une transverse snobée depuis longtemps double une "
        'spé-matchée fraîche', () {
      // sortScore_trans = 0 + 0.5*10 - 0   = 5.0
      // sortScore_spec  = 4 + 0      - 0.4 = 3.6
      // → trans gagne (5.0 > 3.6) — vieillissement domine au-delà du
      // franchissement (ici environ 8 sessions snobée).
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'transverse_old'),
          _milestone(
            id: 'spec_fresh',
            branches: [SpecializationBranch.endurance],
          ),
        ],
        candidacyAge: const {
          'transverse_old': 10,
        },
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.endurance: 4}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'transverse_old',
          reason: "aging (+5.0) dépasse branchScore (4 - 0.4 = 3.6) → la "
              'transverse remonte');
    });

    test('franchissement net : à 8 snobée, la transverse passe mono 4pts', () {
      // À age=8 : sortScore_trans = 0 + 4.0 = 4.0
      //          sortScore_spec  = 4 - 0.4 = 3.6 → trans passe juste.
      // À age=7 : sortScore_trans = 3.5 → spec gagne encore (3.6 > 3.5).
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'trans_age_8'),
          _milestone(
            id: 'spec_fresh',
            branches: [SpecializationBranch.endurance],
          ),
        ],
        candidacyAge: const {'trans_age_8': 8},
      );
      final pickAt8 = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.endurance: 4}),
      );
      expect(pickAt8!.id, 'trans_age_8',
          reason: '4.0 > 3.6 → la transverse vieille passe');

      // Refait avec age=7 sur trans.
      final svc2 = MilestoneService();
      svc2.seedForTest(
        catalog: [
          _milestone(id: 'trans_age_7'),
          _milestone(
            id: 'spec_fresh',
            branches: [SpecializationBranch.endurance],
          ),
        ],
        candidacyAge: const {'trans_age_7': 7},
      );
      final pickAt7 = svc2.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.endurance: 4}),
      );
      expect(pickAt7!.id, 'spec_fresh',
          reason: '3.5 < 3.6 → la spé garde encore la main');
    });

    test(
        "mode hérité (allocation null) : pas de vieillissement, tri par "
        'humilRequired puis id', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_a'),
          _milestone(id: 'm_b'),
        ],
        candidacyAge: const {
          // Même un âge énorme ne doit pas changer l'ordre en mode hérité.
          'm_b': 999,
        },
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        // allocation: null → mode hérité.
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_a',
          reason: "allocation null → tri par humil puis id alpha — l'âge ne "
              'doit pas remonter m_b');
    });

    test('incrementCandidacyAge incrémente seulement les milestones passées',
        () async {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_a'),
          _milestone(id: 'm_b'),
          _milestone(id: 'm_c'),
        ],
      );
      final mB = svc.findById('m_b')!;
      final mC = svc.findById('m_c')!;
      await svc.incrementCandidacyAge([mB, mC]);
      expect(svc.getCandidacyAge('m_a'), 0);
      expect(svc.getCandidacyAge('m_b'), 1);
      expect(svc.getCandidacyAge('m_c'), 1);
      await svc.incrementCandidacyAge([mB]);
      expect(svc.getCandidacyAge('m_b'), 2);
      expect(svc.getCandidacyAge('m_c'), 1);
    });

    test('markCompleted reset le compteur de candidature', () async {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_done'),
        ],
        candidacyAge: const {'m_done': 5},
      );
      expect(svc.getCandidacyAge('m_done'), 5);
      await svc.markCompleted('m_done', hadFail: false);
      expect(svc.getCandidacyAge('m_done'), 0,
          reason: "markCompleted (sans fail) doit remettre l'âge à 0");
    });

    test('markCompleted avec fail ne reset pas le compteur', () async {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_fail'),
        ],
        candidacyAge: const {'m_fail': 3},
      );
      await svc.markCompleted('m_fail', hadFail: true);
      expect(svc.getCandidacyAge('m_fail'), 3,
          reason: 'avec fail, ni complétion ni reset → âge inchangé');
    });

    test(
        "lowestBranchPoints reste un tie-break léger (poids 0.1) à "
        'branchScore égal', () {
      // Cas : alloc endurance=2, profondeur=2.
      // mono_endurance branchScore=2, lowestBranchPoints=2 → sortScore=2-0.2=1.8
      // multi_endure_profond branchScore=4, lowestBranchPoints=2 → sortScore=4-0.2=3.8
      // multi gagne grâce au branchScore + le tie-break joue à match
      // composite — vérifie surtout que le tie-break inversé fonctionne
      // toujours quand branchScore est égal.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'covers_low_branch',
            // endurance=2, sloppy=0 → score=2, lowest=0
            branches: [
              SpecializationBranch.endurance,
              SpecializationBranch.sloppy,
            ],
          ),
          _milestone(
            id: 'covers_high_branch_only',
            // endurance=2 → score=2, lowest=2
            branches: [SpecializationBranch.endurance],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilFloor,
        obedience: _obedFloor,
        allocation: _alloc({SpecializationBranch.endurance: 2}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'covers_low_branch',
          reason:
              "branchScore égal (2), lowestBranchPoints départage : 0 < 2 → "
              'covers_low_branch gagne');
    });
  });
}
