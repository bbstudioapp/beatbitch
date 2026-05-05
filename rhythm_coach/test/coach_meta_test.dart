import 'package:flutter_test/flutter_test.dart';

import 'package:rhythm_coach/career/models/coach.dart';
import 'package:rhythm_coach/career/models/coach_catalog.dart';
import 'package:rhythm_coach/career/models/specialization.dart';

void main() {
  group('CoachMeta.fromJson', () {
    test('parse complet', () {
      final m = CoachMeta.fromJson({
        'id': 'whatever',
        'name': 'Lina Override',
        'archetype': 'strict',
        'specialties': ['endurance', 'sloppy'],
        'tier': 4,
        'isPrincipal': true,
        'requirements': {
          'requiresHands': true,
          'minPlayerLevel': 12,
          'mustHaveUnlockedBranches': ['profondeur'],
        },
      });
      expect(m.name, 'Lina Override');
      expect(m.archetype, CoachArchetype.strict);
      expect(m.specialties,
          [SpecializationBranch.endurance, SpecializationBranch.sloppy]);
      expect(m.tier, 4);
      expect(m.isPrincipal, isTrue);
      expect(m.requirements!.requiresHands, isTrue);
      expect(m.requirements!.minPlayerLevel, 12);
      expect(m.requirements!.mustHaveUnlockedBranches,
          [SpecializationBranch.profondeur]);
    });

    test('JSON vide → CoachMeta.empty', () {
      final m = CoachMeta.fromJson({});
      expect(m.isEmpty, isTrue);
      expect(m.name, isNull);
      expect(m.tier, isNull);
    });

    test('archetype inconnu → null (ignoré)', () {
      final m = CoachMeta.fromJson({'archetype': 'inexistant'});
      expect(m.archetype, isNull);
    });

    test('branches inconnues filtrées silencieusement', () {
      final m = CoachMeta.fromJson({
        'specialties': ['profondeur', 'made_up_branch', 'sloppy'],
      });
      expect(m.specialties,
          [SpecializationBranch.profondeur, SpecializationBranch.sloppy]);
    });

    test('name vide ou whitespace → null', () {
      expect(CoachMeta.fromJson({'name': ''}).name, isNull);
      expect(CoachMeta.fromJson({'name': '  '}).name, isNull);
    });

    test('isPrincipal non-booléen → null', () {
      expect(CoachMeta.fromJson({'isPrincipal': 'true'}).isPrincipal, isNull);
      expect(CoachMeta.fromJson({'isPrincipal': 1}).isPrincipal, isNull);
    });
  });

  group('Coach.withMeta — merge override', () {
    test('override total remplace tous les champs présents', () {
      final base = CoachCatalog.defaults.first; // Lina, tier 1, bienveillant
      const m = CoachMeta(
        name: 'NotLina',
        archetype: CoachArchetype.brutal,
        specialties: [SpecializationBranch.resilience],
        tier: 9,
        isPrincipal: false,
        requirements: CoachRequirement(minPlayerLevel: 50),
      );
      final updated = base.withMeta(m);
      expect(updated.id, base.id, reason: 'id ne change jamais');
      expect(updated.name, 'NotLina');
      expect(updated.archetype, CoachArchetype.brutal);
      expect(updated.specialties, [SpecializationBranch.resilience]);
      expect(updated.tier, 9);
      expect(updated.isPrincipal, isFalse);
      expect(updated.requirements.minPlayerLevel, 50);
    });

    test('override partiel : champs null = défauts conservés', () {
      final base = CoachCatalog.defaults.first;
      final updated = base.withMeta(const CoachMeta(tier: 5));
      expect(updated.tier, 5);
      expect(updated.name, base.name);
      expect(updated.archetype, base.archetype);
      expect(updated.specialties, base.specialties);
      expect(updated.isPrincipal, base.isPrincipal);
      expect(updated.requirements, base.requirements);
    });

    test('CoachMeta.empty est un no-op', () {
      final base = CoachCatalog.defaults.first;
      final updated = base.withMeta(CoachMeta.empty);
      expect(updated.id, base.id);
      expect(updated.name, base.name);
      expect(updated.tier, base.tier);
      expect(updated.requirements, base.requirements);
    });
  });

  group('CoachPhrasePack — title / publicBio overrides', () {
    test('fromJson lit title + publicBio', () {
      final pack = CoachPhrasePack.fromJson({
        'title': 'Coach maison',
        'publicBio': 'Bio overridée.',
      });
      expect(pack.title, 'Coach maison');
      expect(pack.publicBio, 'Bio overridée.');
    });

    test('chaînes vides ou whitespace → null', () {
      expect(CoachPhrasePack.fromJson({'title': '', 'publicBio': '   '}).title,
          isNull);
      expect(CoachPhrasePack.fromJson({'title': '', 'publicBio': '   '})
          .publicBio,
          isNull);
    });

    test('Coach.withPhrases applique le title si non-null, garde sinon', () {
      final base = CoachCatalog.defaults.first;
      final updated = base.withPhrases(
          const CoachPhrasePack(title: 'Nouveau titre'));
      expect(updated.title, 'Nouveau titre');
      expect(updated.publicBio, base.publicBio,
          reason: 'publicBio non fourni → défaut');

      final unchanged = base.withPhrases(const CoachPhrasePack());
      expect(unchanged.title, base.title);
      expect(unchanged.publicBio, base.publicBio);
    });
  });

  group('Pipeline complet (meta + pack)', () {
    test('meta puis pack : isPrincipal vient du meta, title vient du pack', () {
      final base = CoachCatalog.defaults.first;
      final withMeta = base.withMeta(
          const CoachMeta(isPrincipal: false, tier: 99));
      final withBoth = withMeta.withPhrases(
          const CoachPhrasePack(title: 'X'));
      expect(withBoth.isPrincipal, isFalse);
      expect(withBoth.tier, 99);
      expect(withBoth.title, 'X');
      expect(withBoth.name, base.name, reason: 'name pas overridé');
    });
  });
}
