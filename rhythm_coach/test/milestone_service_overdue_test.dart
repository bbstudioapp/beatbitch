import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests de la règle « overdue » de [MilestoneService.allPendingFor] :
/// quand la joueuse a dépassé le `minLevel` effectif d'une milestone de
/// 3 niveaux ou plus, cette milestone passe en tête du tri, peu importe
/// branchScore/aging — sauf placements `final` (chaîne dramaturgique).
LevelMilestone _milestone({
  required String id,
  required int minLevel,
  List<SpecializationBranch> branches = const [],
  double humilRequired = 0,
  MilestonePlacement placement = MilestonePlacement.body,
  List<UnlockKey> unlocks = const [],
  List<UnlockKey> requires = const [],
}) {
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
    minLevel: minLevel,
    humilRequired: humilRequired,
    displayLabel: id,
    sequence: const [lowStep],
    durationSeconds: 12,
    unlocks: unlocks,
    requires: requires,
    branches: branches,
    placement: placement,
  );
}

SpecializationAllocation _alloc(Map<SpecializationBranch, int> pts) {
  final base = <SpecializationBranch, int>{
    for (final b in SpecializationBranch.values) b: 0,
  };
  base.addAll(pts);
  return SpecializationAllocation(points: base, lastRespecMs: null);
}

const double _humilCeiling = 200.0;
const double _obedFloor = 0.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MilestoneService — règle overdue', () {
    test(
        'overdue (lag=3) prime sur une milestone à l\'heure portée par '
        'un branchScore élevé', () {
      // m_overdue : minLevel=5, lag effectif=3 (playerLevel=8, pas de spé
      // sur cette milestone → branchAdvance=0). sortScore = 0.
      // m_ontime : minLevel=8, 2 branches investies (2 pts chacune) →
      //   branchScore=4, branchAdvance=2 (max d'une branche). effective
      //   minLevel = 6 → lag=2 < 3, PAS overdue.
      // Sans la règle overdue, m_ontime gagne (sortScore 4 > 0).
      // Avec la règle, m_overdue passe en tête.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_overdue', minLevel: 5),
          _milestone(
            id: 'm_ontime',
            minLevel: 8,
            branches: [
              SpecializationBranch.endurance,
              SpecializationBranch.profondeur,
            ],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 8,
        allocation: _alloc({
          SpecializationBranch.endurance: 2,
          SpecializationBranch.profondeur: 2,
        }),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_overdue',
          reason: 'lag=3 → overdue, rattrapage prioritaire sur le match spé');
    });

    test('deux milestones overdue : la plus en retard passe en premier', () {
      // m_lag4 : minLevel=3, playerLevel=7, lag=4.
      // m_lag5 : minLevel=2, playerLevel=7, lag=5.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_lag4', minLevel: 3),
          _milestone(id: 'm_lag5', minLevel: 2),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 7,
        allocation: _alloc({}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_lag5',
          reason: 'lag=5 > lag=4 → la milestone la plus en retard remonte');
    });

    test(
        'tie-break sur deux overdue à lag égal : humilRequired ascendant '
        'puis id alpha', () {
      // Deux overdue à lag=3, humil différents → la moins humiliante passe.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_a_humil_high', minLevel: 5, humilRequired: 10),
          _milestone(id: 'm_b_humil_low', minLevel: 5, humilRequired: 2),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 8,
        allocation: _alloc({}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_b_humil_low',
          reason:
              'lag égal → on ne saute pas de marche, humilRequired ascendant');
    });

    test(
        'finals (placement="final") exclus de la règle overdue : tri '
        'standard sur cette piste', () {
      // 2 finals, dont 1 « en retard » (lag=10). Un body « à l'heure »
      // avec un sortScore élevé. La file body et la file final sont
      // indépendantes — on vérifie ici que la file FINAL ne déclenche pas
      // overdue : pendingFinalFor retourne le tri standard.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'final_late',
            minLevel: 5,
            humilRequired: 30,
            placement: MilestonePlacement.finalApotheose,
          ),
          _milestone(
            id: 'final_early',
            minLevel: 10,
            humilRequired: 5,
            placement: MilestonePlacement.finalApotheose,
          ),
        ],
      );
      // playerLevel=15 → final_late aurait lag=10, final_early lag=5.
      // Sans la règle overdue (cas final), tri standard = humilRequired asc
      // → final_early passe en premier.
      final pick = svc.pendingFinalFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 15,
        allocation: _alloc({}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'final_early',
          reason: 'finals : pas de bascule overdue, on garde le tri humil asc');
    });

    test(
        'branchAdvance déjà actif : pas de double accélérateur, le '
        'minLevel effectif intègre l\'avance de spé', () {
      // m_spe_advanced : minLevel=10, 2 pts profondeur → branchAdvance=2
      // → effectiveMinLevel=8.
      // playerLevel=9 → lag=1 (PAS overdue malgré l'écart brut de 1
      // niveau au-dessus de minLevel=10 ? non, c'est bien sous le seuil ;
      // on vérifie surtout qu'il N'EST PAS overdue alors que le `lag brut`
      // (playerLevel - minLevel) = -1).
      // m_ontime : minLevel=9, lag=0.
      // Aucun overdue → tri standard, branchScore 2 + le match spé
      // donne la victoire à m_spe_advanced.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'm_spe_advanced',
            minLevel: 10,
            branches: [SpecializationBranch.profondeur],
          ),
          _milestone(id: 'm_ontime', minLevel: 9),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 9,
        allocation: _alloc({SpecializationBranch.profondeur: 2}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_spe_advanced',
          reason: 'effectiveMinLevel=8 → lag=1 < 3, pas overdue : le tri '
              'standard repasse et le branchScore gagne');
    });

    test(
        'branchAdvance ≥ 3 neutralise overdue même quand un lag réel '
        'existe (anti double accélérateur)', () {
      // m_spe_maxed : minLevel=10, 4 pts profondeur → branchAdvance=3.
      //   effectiveMinLevel=7. À playerLevel=12, lag effectif=5 → SANS
      //   la garde, overdue serait déclenchée par la spé maxée elle-même
      //   et chaque milestone matchée par cette spé prendrait le pas dès
      //   son apparition, écrasant aging. La garde branchAdvance ≥ 3
      //   désactive overdue ici.
      // m_lag3 : minLevel=9, branchAdvance=0, lag=3 → overdue authentique.
      // → m_lag3 doit gagner.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'm_spe_maxed',
            minLevel: 10,
            branches: [SpecializationBranch.profondeur],
          ),
          _milestone(id: 'm_lag3', minLevel: 9),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 12,
        allocation: _alloc({SpecializationBranch.profondeur: 4}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_lag3',
          reason: 'la spé maxée ne s\'auto-priorise pas par overdue ; le '
              'rattrapage reste au service des milestones vraiment en retard');
    });

    test(
        'branchAdvance ≥ 3 ne déclenche pas un overdue à l\'apparition : '
        'la spé n\'amorce pas la règle de rattrapage', () {
      // m_spe : minLevel=10, 3 pts profondeur → branchAdvance=3 →
      // effectiveMinLevel=7. playerLevel=7 → lag=0. Garantit que la spé
      // n'auto-déclenche pas overdue dès la candidature.
      // m_lag3 : minLevel=4 (vrai en retard, lag=3) → overdue, doit
      // passer en tête.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(
            id: 'm_spe',
            minLevel: 10,
            branches: [SpecializationBranch.profondeur],
          ),
          _milestone(id: 'm_lag3', minLevel: 4),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 7,
        allocation: _alloc({SpecializationBranch.profondeur: 3}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_lag3',
          reason: 'm_spe est juste candidate (lag=0 après avance) ; m_lag3 '
              'a un vrai lag=3, overdue prend le dessus');
    });

    test(
        'mode hérité (allocation == null) : la règle overdue s\'applique '
        'normalement sur minLevel brut', () {
      // m_overdue : minLevel=2, playerLevel=5 → lag=3 → overdue.
      // m_ontime : minLevel=5, lag=0, humilRequired plus bas.
      // Sans la règle, l'ordre par humil ferait gagner m_ontime
      // (humilRequired 0 vs 5). Avec la règle, m_overdue gagne.
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_overdue', minLevel: 2, humilRequired: 5),
          _milestone(id: 'm_ontime', minLevel: 5, humilRequired: 0),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 5,
        // allocation: null → mode hérité, branchAdvance = 0 partout.
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_overdue',
          reason:
              'mode hérité : lag brut = 3 → overdue, prend le pas sur humil asc');
    });

    test(
        'à playerLevel = minLevel + 2 : pas overdue (seuil ≥ 3), tri '
        'normal reprend', () {
      // m_lag2 : minLevel=5, playerLevel=7 → lag=2 < 3 → PAS overdue.
      // m_spe : minLevel=7, branchScore 4 → match spé.
      // → m_spe gagne (overdue ne s'enclenche pas, sortScore 4 > 0).
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_lag2', minLevel: 5),
          _milestone(
            id: 'm_spe',
            minLevel: 7,
            branches: [SpecializationBranch.endurance],
          ),
        ],
      );
      final pick = svc.pendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 7,
        allocation: _alloc({SpecializationBranch.endurance: 4}),
      );
      expect(pick, isNotNull);
      expect(pick!.id, 'm_spe',
          reason: 'seuil overdue strict ≥ 3 : lag=2 reste un cas standard');
    });

    test(
        'allPendingFor : les overdue sortent en tête, suivies des à l\'heure '
        'dans leur ordre standard', () {
      final svc = MilestoneService();
      svc.seedForTest(
        catalog: [
          _milestone(id: 'm_lag3', minLevel: 5),
          _milestone(id: 'm_lag6', minLevel: 2),
          _milestone(
            id: 'm_ontime_spe',
            minLevel: 8,
            branches: [SpecializationBranch.endurance],
          ),
          _milestone(id: 'm_ontime_plain', minLevel: 8),
        ],
      );
      final pending = svc.allPendingFor(
        humiliationScore: _humilCeiling,
        obedience: _obedFloor,
        playerLevel: 8,
        allocation: _alloc({SpecializationBranch.endurance: 4}),
      );
      expect(pending.map((m) => m.id).toList(),
          ['m_lag6', 'm_lag3', 'm_ontime_spe', 'm_ontime_plain'],
          reason:
              'overdue par lag desc puis à l\'heure par sortScore (spé > plain)');
    });
  });
}
