import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/services/coach_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoachLoader — overrides JSON ne dégradent pas les seeds', () {
    test(
      'catalogue chargé depuis assets garde les minPlayerSeconds de CoachCatalog.defaults',
      () async {
        final loaded = await CoachLoader().load();

        // Régression : des blocs `requirements` legacy (Phase 19 :
        // `minPlayerLevel`, `requiresHands`) traînaient dans les JSON coach.
        // `CoachMeta.fromJson` les lisait, `withMeta` écrasait les seeds
        // 3600/10800/… par 0, et `CoachService.attachPhrases` pétait son
        // assert au boot. Le contrat documenté dans `CoachRequirement.fromJson`
        // est : « les overrides JSON ne touchent pas les requirements » —
        // donc le catalogue chargé doit avoir exactement les mêmes
        // `minPlayerSeconds` que `CoachCatalog.defaults`.
        final expectedById = {
          for (final c in CoachCatalog.defaults)
            c.id: c.requirements.minPlayerSeconds,
        };
        for (final c in loaded) {
          expect(
            c.requirements.minPlayerSeconds,
            expectedById[c.id],
            reason:
                'coach ${c.id} : minPlayerSeconds chargé ne matche pas le seed '
                '(override JSON résiduel ?)',
          );
        }

        // Et le catalogue final doit passer la validation (suite stricte).
        final issues = CoachCatalogValidator.validate(loaded);
        expect(
          issues,
          isEmpty,
          reason: 'catalogue post-load incohérent : ${issues.join("; ")}',
        );
      },
    );
  });

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
        requirements: CoachRequirement(minPlayerSeconds: 10),
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
        requirements: CoachRequirement(minPlayerSeconds: 5), // < 10 KO
      );
      final issues = CoachCatalogValidator.validate([t1, t2]);
      expect(issues.any((s) => s.contains('strictement supérieur')), isTrue);
    });
  });
}
