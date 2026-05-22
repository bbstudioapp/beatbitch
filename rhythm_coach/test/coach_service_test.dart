import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/services/coach_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // Phase 19.10 : déblocage des coachs par temps cumulé (totalSeconds).
  // Seuils actuels du catalogue (cf. `CoachCatalog.defaults`) :
  //   tier 1 (Lina)     : 0
  //   tier 2 (Hélène)   : 3 600   = 1 h
  //   tier 3 (Jade)     : 10 800  = 3 h
  //   tier 4 (Morgan)   : 25 200  = 7 h
  //   tier 5 (Victoria) : 54 000  = 15 h
  //   tier 6 (Nyx)      : 90 000  = 25 h
  group('CoachService — règle d\'avancement (Phase 19.10)', () {
    test('au démarrage, seul le Principal du palier 1 est débloqué', () async {
      final s = CoachService();
      await s.load();

      final tier1Principal = s.principalOfTier(1)!;
      expect(s.isUnlocked(tier1Principal), isTrue);
      for (final c in s.coaches) {
        if (c.id == tier1Principal.id) continue;
        expect(s.isUnlocked(c), isFalse,
            reason: '${c.id} ne doit pas être débloqué au start');
      }
      expect(s.currentTier, 1);
    });

    test(
        'advancesTier renvoie true uniquement pour le Principal du tier courant',
        () async {
      final s = CoachService();
      await s.load();

      final tier1Principal = s.principalOfTier(1)!;
      final tier2Principal = s.principalOfTier(2)!;
      expect(s.advancesTier(tier1Principal), isTrue);
      expect(s.advancesTier(tier2Principal), isFalse,
          reason: 'Le palier 2 n\'est pas encore atteint');
    });

    test(
        'syncFromTotalSeconds(3600) ouvre le palier 2 et débloque son Principal',
        () async {
      final s = CoachService();
      await s.load();

      final unlocked = await s.syncFromTotalSeconds(3600);
      expect(s.currentTier, 2);
      expect(unlocked.length, 1);
      expect(unlocked.first.id, s.principalOfTier(2)!.id);
      expect(s.isUnlocked(s.principalOfTier(2)!), isTrue);
    });

    test('joueuse à 10 h cumulées (36000 s) débloque jusqu\'à Morgan (tier 4)',
        () async {
      final s = CoachService();
      await s.load();
      final unlocked = await s.syncFromTotalSeconds(10 * 3600);
      expect(s.currentTier, 4);
      // Tiers 2, 3, 4 ouverts d'un coup.
      expect(unlocked.length, 3);
    });

    test('syncFromTotalSeconds ne régresse jamais le tier', () async {
      final s = CoachService();
      await s.load();

      await s.syncFromTotalSeconds(10800); // tier 3
      expect(s.currentTier, 3);

      // 30 min = en dessous du seuil tier 2.
      final unlocked = await s.syncFromTotalSeconds(1800);
      expect(unlocked, isEmpty);
      expect(s.currentTier, 3, reason: 'Le tier ne doit jamais redescendre');
    });

    test('syncFromTotalSeconds saute plusieurs paliers en un appel', () async {
      final s = CoachService();
      await s.load();

      final unlocked = await s.syncFromTotalSeconds(25200); // 7h → tier 4
      expect(s.currentTier, 4);
      expect(unlocked.length, 3, reason: 'Tiers 2, 3 et 4 ouverts d\'un coup');
    });

    test('après un Principal de tier inférieur, advancesTier reste false',
        () async {
      final s = CoachService();
      await s.load();
      await s.syncFromTotalSeconds(10800); // tier 3
      final tier1 = s.principalOfTier(1)!;
      expect(s.advancesTier(tier1), isFalse);
      // Mais tier1 reste sélectionnable (entraînement libre).
      final status = s.evaluate(
        tier1,
        playerTotalSeconds: 10800,
        handsEnabled: true,
      );
      expect(status, CoachSelectionStatus.selectedFreeTraining);
    });

    test('coach non débloqué → lockedTier', () async {
      final s = CoachService();
      await s.load();
      final tier3 = s.principalOfTier(3)!;
      final status = s.evaluate(
        tier3,
        playerTotalSeconds: 0,
        handsEnabled: true,
      );
      expect(status, CoachSelectionStatus.lockedTier);
    });

    test(
        'refonte 0.5.0 : handsEnabled ignoré côté evaluate (hand piloté '
        'par la milestone, pas le coach)', () async {
      final s = CoachService();
      await s.load();
      await s.syncFromTotalSeconds(25200); // tier 4 — Jade débloquée
      final jade = s.coaches.firstWhere((c) => c.id == 'coach_03_jade');
      // handsEnabled=false ne doit PLUS bloquer la sélection :
      // l'ancien `blockedRequiresHands` n'existe plus.
      final status = s.evaluate(
        jade,
        playerTotalSeconds: 25200,
        handsEnabled: false,
      );
      expect(
        status,
        anyOf(
          CoachSelectionStatus.selectedAdvancing,
          CoachSelectionStatus.selectedFreeTraining,
        ),
        reason: 'hands désactivé ne doit plus bloquer un coach — le hand '
            'obligatoire est désormais piloté par la milestone',
      );
    });

    test(
        'coach factice avec minPlayerSeconds élevé → lockedTier (cas ordre des checks)',
        () async {
      // Le check `lockedTier` passe AVANT `blockedMinPlayerSeconds` —
      // un coach jamais ouvert reste lockedTier même si son seuil temps
      // serait franchi.
      const phantom = Coach(
        id: 'phantom',
        name: 'Phantom',
        title: 'Test',
        archetype: CoachArchetype.brutal,
        publicBio: '',
        specialties: [],
        tier: 1,
        isPrincipal: false,
        requirements: CoachRequirement(minPlayerSeconds: 999999),
      );
      final s = CoachService(coaches: [phantom, ...CoachCatalog.defaults]);
      await s.load();
      final status = s.evaluate(
        phantom,
        playerTotalSeconds: 0,
        handsEnabled: true,
      );
      expect(status, CoachSelectionStatus.lockedTier);
    });

    test('persistance : recharger le service restitue la sélection', () async {
      final s1 = CoachService();
      await s1.load();
      await s1.syncFromTotalSeconds(3600);
      final tier2 = s1.principalOfTier(2)!;
      await s1.selectCoach(tier2);

      final s2 = CoachService();
      await s2.load();
      expect(s2.currentTier, 2);
      expect(s2.selectedCoachId, tier2.id);
      expect(s2.isUnlocked(tier2), isTrue);
    });
  });
}
