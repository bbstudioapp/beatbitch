import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/services/milestone_loader.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les 5 postures (issue #77) se débloquent chacune par une milestone dédiée
/// (`intro_posture_*`, `level` 4/5/6/9/12) livrée en 0.6.0. Une joueuse qui
/// avait déjà dépassé ces niveaux quand les milestones sont apparues doit
/// quand même les voir arriver — c'est exactement le piège payé en 0.6.1 avec
/// le coach Marc (palier franchi avant la sortie ⇒ verrouillé définitivement).
///
/// Ces tests tournent sur le **vrai catalogue** `assets/career/milestones.json`
/// et non sur des milestones répliquées : le point à prouver est une propriété
/// des données autant que du tri.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<LevelMilestone> catalog;
  late Set<String> postureIds;

  /// Profil « déjà avancé » : tous les paliers antérieurs acquittés, seules
  /// les milestones posture restent à faire.
  Set<String> allButPostures() =>
      catalog.map((m) => m.id).toSet()..removeAll(postureIds);

  MilestoneService serviceWith(Set<String> completed) {
    SharedPreferences.setMockInitialValues({});
    final svc = MilestoneService();
    svc.seedForTest(catalog: catalog, completed: completed);
    return svc;
  }

  List<String> pendingIdsFor(
    MilestoneService svc, {
    required int playerLevel,
    required CapabilityProfile capability,
  }) =>
      svc
          .allPendingFor(
            humiliationScore: 100,
            obedience: 100,
            playerLevel: playerLevel,
            allocation: SpecializationAllocation.empty(),
            capabilityProfile: capability,
          )
          .map((m) => m.id)
          .toList();

  /// Nombre de séances pour acquitter les 5 postures depuis un profil avancé,
  /// à raison de [bodyCount] milestones body par séance (cf.
  /// `SessionLengthChoice.maxBodyMilestones` : 1 en courte, 2 en
  /// moyenne/longue). `-1` si le pool s'épuise avant.
  Future<int> sessionsToUnlockAll({
    required int bodyCount,
    required CapabilityProfile capability,
    int playerLevel = 30,
  }) async {
    final svc = serviceWith(allButPostures());
    var sessions = 0;
    while (!postureIds.every(svc.isCompleted)) {
      final picked = svc.pendingForList(
        count: bodyCount,
        humiliationScore: 100,
        obedience: 100,
        playerLevel: playerLevel,
        allocation: SpecializationAllocation.empty(),
        capabilityProfile: capability,
      );
      if (picked.isEmpty) return -1;
      sessions++;
      for (final m in picked) {
        await svc.markCompleted(m.id, hadFail: false);
      }
    }
    return sessions;
  }

  /// Profil de capacités d'une joueuse qui a déjà tenu un hold `full` — la
  /// seule exigence de télémétrie parmi les 5 postures.
  const holdFullProven = CapabilityProfile({
    CapabilityAxis.holdFullStreak: CapabilityAxisState(best: 6),
  });

  /// Joueuse avancée dont l'axe `hold.full.streak` n'a jamais rien produit.
  const noTelemetry = CapabilityProfile({});

  setUpAll(() async {
    catalog = await MilestoneLoader().load();
    postureIds = catalog
        .where((m) => m.id.startsWith('intro_posture_'))
        .map((m) => m.id)
        .toSet();
    expect(postureIds, hasLength(5),
        reason: 'le catalogue doit porter les 5 milestones posture');
  });

  group('Profil déjà avancé — les paliers de posture restent atteignables', () {
    test('les 5 postures sont proposées à un profil niveau 30', () {
      final svc = serviceWith(allButPostures());
      expect(
        pendingIdsFor(svc, playerLevel: 30, capability: holdFullProven),
        containsAll(postureIds),
      );
    });

    test('`level` est un plancher, pas une fenêtre', () {
      final svc = serviceWith(allButPostures());
      // Si `level` était une fenêtre, un niveau très au-dessus du palier
      // ferait disparaître les candidates. On vérifie sur toute la plage,
      // du palier le plus haut (12) à un niveau absurdement élevé.
      for (final level in [12, 20, 30, 99, 999]) {
        expect(
          pendingIdsFor(svc, playerLevel: level, capability: holdFullProven),
          containsAll(postureIds),
          reason: 'postures absentes du pool au niveau $level',
        );
      }
    });

    test('les postures passent en tête de file (règle overdue)', () {
      final svc = serviceWith(allButPostures());
      final pending =
          pendingIdsFor(svc, playerLevel: 30, capability: holdFullProven);
      // Le profil n'a plus que les postures à faire : le tri ne doit pas les
      // reléguer derrière quoi que ce soit.
      expect(pending.take(5).toSet(), postureIds);
      expect(pending.first, 'intro_posture_sitting',
          reason: 'la plus en retard (level 4) doit sortir en premier');
    });

    test('3 séances moyenne/longue suffisent à débloquer les 5', () async {
      expect(
        await sessionsToUnlockAll(bodyCount: 2, capability: holdFullProven),
        3,
      );
    });

    test('5 séances courtes suffisent à débloquer les 5', () async {
      expect(
        await sessionsToUnlockAll(bodyCount: 1, capability: holdFullProven),
        5,
      );
    });
  });

  group('Exigence de capacité — `intro_posture_on_back`', () {
    test('sans donnée sur hold.full.streak, seules 4 postures sont candidates',
        () {
      // Gating métier assumé (`requiresCapability: hold.full.streak ≥ 5`) et
      // non un verrou définitif : l'axe se remplit dès qu'un hold `full` est
      // tenu en séance (`CapabilityTracker`), y compris via un défi. Test de
      // caractérisation — il documente que la 5ᵉ posture attend une preuve
      // physique, pas un niveau.
      final svc = serviceWith(allButPostures());
      final pending =
          pendingIdsFor(svc, playerLevel: 30, capability: noTelemetry);
      expect(pending,
          containsAll(postureIds.difference({'intro_posture_on_back'})));
      expect(pending, isNot(contains('intro_posture_on_back')));
    });

    test('elle devient candidate dès que l\'axe atteint le seuil', () {
      final svc = serviceWith(allButPostures());
      const justUnder = CapabilityProfile({
        CapabilityAxis.holdFullStreak: CapabilityAxisState(best: 4),
      });
      const atThreshold = CapabilityProfile({
        CapabilityAxis.holdFullStreak: CapabilityAxisState(best: 5),
      });
      expect(pendingIdsFor(svc, playerLevel: 30, capability: justUnder),
          isNot(contains('intro_posture_on_back')));
      expect(pendingIdsFor(svc, playerLevel: 30, capability: atThreshold),
          contains('intro_posture_on_back'));
    });
  });
}
