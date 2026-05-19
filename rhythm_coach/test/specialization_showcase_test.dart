import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/career/services/specialization_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Garde-fous sur la file showcase : un point spé attribué en fin de
/// séance doit être visiblement honoré par la séance suivante.
///
/// 1. `SpecializationService.invest` empile la branche dans la file FIFO ;
///    `peekShowcase` / `consumeShowcase` permettent au call site de
///    récupérer la dette puis la solder.
/// 2. `MilestoneService.allPendingFor(showcaseBranch:)` remonte une
///    milestone qui touche la branche, dominant `branchScore` et l'aging.
/// 3. La règle *overdue* reste prioritaire : un showcase ne saute pas un
///    rattrapage système.

SpecializationAllocation _alloc(Map<SpecializationBranch, int> pts) {
  final base = <SpecializationBranch, int>{
    for (final b in SpecializationBranch.values) b: 0,
  };
  base.addAll(pts);
  return SpecializationAllocation(points: base, lastRespecMs: null);
}

/// minLevel par défaut = 5 pour pouvoir tester à playerLevel=5 sans
/// déclencher la règle *overdue* (`lag ≥ 3`). Les tests qui veulent
/// l'overdue passent leur propre minLevel.
LevelMilestone _milestone({
  required String id,
  required int humilRequired,
  List<SpecializationBranch> branches = const [],
  int minLevel = 5,
}) {
  return LevelMilestone(
    id: id,
    humilRequired: humilRequired.toDouble(),
    displayLabel: id,
    sequence: const [
      SessionStep(
        time: 0,
        from: Position.head,
        to: Position.mid,
        bpm: 80,
        duration: 10,
        mode: SessionMode.rhythm,
      ),
    ],
    durationSeconds: 10,
    unlocks: const [UnlockKey.basics], // arbitraire ici, hors scope du test
    branches: branches,
    minLevel: minLevel,
  );
}

void main() {
  group('SpecializationService — file showcase', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('invest empile la branche en fin de file', () async {
      final svc = SpecializationService();
      // Niveau 10 → 5 points dispo (10 ~/ 2). Trois invest successifs.
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.invest(SpecializationBranch.endurance, 10);
      await svc.invest(SpecializationBranch.profondeur, 10);
      expect(await svc.pendingShowcase(), [
        SpecializationBranch.profondeur,
        SpecializationBranch.endurance,
        SpecializationBranch.profondeur,
      ]);
    });

    test('peekShowcase retourne la tête sans la retirer', () async {
      final svc = SpecializationService();
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.invest(SpecializationBranch.endurance, 10);
      expect(await svc.peekShowcase(), SpecializationBranch.profondeur);
      // Pas de retrait : 2e peek renvoie la même tête.
      expect(await svc.peekShowcase(), SpecializationBranch.profondeur);
      expect(await svc.pendingShowcase(), hasLength(2));
    });

    test('peekShowcase null quand la file est vide', () async {
      final svc = SpecializationService();
      expect(await svc.peekShowcase(), isNull);
    });

    test('consumeShowcase retire la première occurrence de la branche',
        () async {
      final svc = SpecializationService();
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.invest(SpecializationBranch.endurance, 10);
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.consumeShowcase(SpecializationBranch.profondeur);
      expect(await svc.pendingShowcase(), [
        SpecializationBranch.endurance,
        SpecializationBranch.profondeur,
      ]);
    });

    test('consumeShowcase d\'une branche absente = no-op', () async {
      final svc = SpecializationService();
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.consumeShowcase(SpecializationBranch.sloppy);
      expect(await svc.pendingShowcase(), [SpecializationBranch.profondeur]);
    });

    test('respec vide la file', () async {
      final svc = SpecializationService();
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.invest(SpecializationBranch.endurance, 10);
      await svc.respec();
      expect(await svc.pendingShowcase(), isEmpty);
    });

    test('resetAll vide la file', () async {
      final svc = SpecializationService();
      await svc.invest(SpecializationBranch.profondeur, 10);
      await svc.resetAll();
      expect(await svc.pendingShowcase(), isEmpty);
    });
  });

  group('MilestoneService.allPendingFor — showcaseBranch', () {
    test(
        'remonte une milestone qui touche la branche showcase au-dessus '
        'd\'une autre branche', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'm_endurance',
            humilRequired: 0,
            branches: [SpecializationBranch.endurance],
          ),
          _milestone(
            id: 'm_profondeur',
            humilRequired: 0,
            branches: [SpecializationBranch.profondeur],
          ),
        ],
      );
      // Allocation favorise endurance (5 pts) — sans showcase, c'est
      // m_endurance qui gagne le tri.
      final alloc = _alloc({
        SpecializationBranch.endurance: 5,
        SpecializationBranch.profondeur: 0,
      });
      final withoutShowcase = svc.pendingFor(
        humiliationScore: 0,
        obedience: 0,
        playerLevel: 5,
        allocation: alloc,
      );
      expect(withoutShowcase?.id, 'm_endurance');
      // Avec showcase=profondeur, m_profondeur remonte malgré 0 pt spé.
      final withShowcase = svc.pendingFor(
        humiliationScore: 0,
        obedience: 0,
        playerLevel: 5,
        allocation: alloc,
        showcaseBranch: SpecializationBranch.profondeur,
      );
      expect(withShowcase?.id, 'm_profondeur');
    });

    test('showcase sans candidate matchante = comportement standard', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'm_endurance',
            humilRequired: 0,
            branches: [SpecializationBranch.endurance],
          ),
          _milestone(
            id: 'm_sloppy',
            humilRequired: 0,
            branches: [SpecializationBranch.sloppy],
          ),
        ],
      );
      final alloc = _alloc({SpecializationBranch.endurance: 3});
      // Showcase=profondeur mais aucune milestone profondeur dans le pool.
      final pick = svc.pendingFor(
        humiliationScore: 0,
        obedience: 0,
        playerLevel: 5,
        allocation: alloc,
        showcaseBranch: SpecializationBranch.profondeur,
      );
      // m_endurance gagne (branchScore 3 > sloppy 0). Showcase neutre.
      expect(pick?.id, 'm_endurance');
    });

    test('règle overdue reste prioritaire sur le showcase', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          // minLevel=2, playerLevel=8 → lag=6, overdue (≥ 3).
          _milestone(
            id: 'm_overdue',
            humilRequired: 0,
            branches: [SpecializationBranch.sloppy],
            minLevel: 2,
          ),
          // minLevel=8, playerLevel=8 → lag=0, à l'heure. Pas overdue.
          _milestone(
            id: 'm_showcase',
            humilRequired: 0,
            branches: [SpecializationBranch.profondeur],
            minLevel: 8,
          ),
        ],
      );
      // Aucun point investi → branchAdvance=0 partout → overdue calcul
      // n'est pas annulé par la garde `branchAdvance ≥ 3`.
      final alloc = _alloc({});
      final pick = svc.pendingFor(
        humiliationScore: 0,
        obedience: 0,
        playerLevel: 8,
        allocation: alloc,
        showcaseBranch: SpecializationBranch.profondeur,
      );
      // m_overdue passe en tête malgré le showcase sur l'autre milestone :
      // rattrapage système avant nice-to-have UX.
      expect(pick?.id, 'm_overdue');
    });
  });
}
