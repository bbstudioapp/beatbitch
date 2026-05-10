import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/models/specialization.dart';

void main() {
  group('CoachCatalogValidator', () {
    test('catalogue par défaut est cohérent (zéro warning)', () {
      final issues = CoachCatalogValidator.validate(CoachCatalog.defaults);
      expect(issues, isEmpty,
          reason: 'le catalogue codé doit être valide : ${issues.join("; ")}');
    });

    test('palier manquant entre 1 et 3 → warning', () {
      const lina = Coach(
        id: 'a',
        name: 'A',
        title: '',
        archetype: CoachArchetype.bienveillant,
        publicBio: '',
        specialties: [],
        tier: 1,
        isPrincipal: true,
      );
      const jade = Coach(
        id: 'c',
        name: 'C',
        title: '',
        archetype: CoachArchetype.taquinSadique,
        publicBio: '',
        specialties: [],
        tier: 3,
        isPrincipal: true,
      );
      final issues = CoachCatalogValidator.validate([lina, jade]);
      expect(issues.any((s) => s.contains('Palier 2')), isTrue);
    });

    test('deux Principals au même palier → warning', () {
      const a = Coach(
        id: 'a',
        name: 'A',
        title: '',
        archetype: CoachArchetype.bienveillant,
        publicBio: '',
        specialties: [],
        tier: 1,
        isPrincipal: true,
      );
      const b = Coach(
        id: 'b',
        name: 'B',
        title: '',
        archetype: CoachArchetype.strict,
        publicBio: '',
        specialties: [],
        tier: 1,
        isPrincipal: true,
      );
      final issues = CoachCatalogValidator.validate([a, b]);
      expect(issues.any((s) => s.contains('2 Principals')), isTrue);
    });

    test('minPlayerLevel non strictement croissant → warning', () {
      const t1 = Coach(
        id: 'a',
        name: 'A',
        title: '',
        archetype: CoachArchetype.bienveillant,
        publicBio: '',
        specialties: [],
        tier: 1,
        isPrincipal: true,
        requirements: CoachRequirement(minPlayerLevel: 10),
      );
      const t2 = Coach(
        id: 'b',
        name: 'B',
        title: '',
        archetype: CoachArchetype.strict,
        publicBio: '',
        specialties: [],
        tier: 2,
        isPrincipal: true,
        requirements: CoachRequirement(minPlayerLevel: 5), // < 10 KO
      );
      final issues = CoachCatalogValidator.validate([t1, t2]);
      expect(issues.any((s) => s.contains('strictement supérieur')), isTrue);
    });
  });

  group('requiredBranchPoints', () {
    test('parsing JSON', () {
      final r = CoachRequirement.fromJson({
        'requiredBranchPoints': {'profondeur': 3, 'sloppy': 1},
      });
      expect(r.requiredBranchPoints[SpecializationBranch.profondeur], 3);
      expect(r.requiredBranchPoints[SpecializationBranch.sloppy], 1);
    });

    test('valeurs <=0 ou non-numériques ignorées', () {
      final r = CoachRequirement.fromJson({
        'requiredBranchPoints': {
          'profondeur': 0,
          'sloppy': -2,
          'unknown': 5,
        },
      });
      expect(r.requiredBranchPoints, isEmpty);
    });

    test(
        'seuil non atteint → blockedInsufficientBranchPoints (à intégrer côté CoachService)',
        () {
      // Smoke test : on s'assure juste que la structure est correcte ;
      // l'évaluation côté CoachService est testée dans coach_service_test.
      const r = CoachRequirement(
        requiredBranchPoints: {SpecializationBranch.resilience: 3},
      );
      expect(r.requiredBranchPoints[SpecializationBranch.resilience], 3);
    });
  });
}
