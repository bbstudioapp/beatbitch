import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/specialization.dart';

void main() {
  const branchA = SpecializationBranch.profondeur;
  const branchB = SpecializationBranch.obeissance;
  const branchC = SpecializationBranch.sloppy;

  Coach makeCoach({required List<SpecializationBranch> specialties}) {
    return Coach(
      id: 'test',
      name: 'Test',
      title: 'Test',
      archetype: CoachArchetype.strict,
      publicBio: '',
      specialties: specialties,
      tier: 1,
      isPrincipal: true,
    );
  }

  SpecializationAllocation alloc(Map<SpecializationBranch, int> points) {
    return SpecializationAllocation(
      points: {
        for (final b in SpecializationBranch.values) b: points[b] ?? 0,
      },
      lastRespecMs: null,
    );
  }

  group('Coach.effectiveAllocation', () {
    test('coach sans specialties → allocation joueuse retournée telle quelle',
        () {
      final coach = makeCoach(specialties: const []);
      final player = alloc({branchA: 3, branchB: 1});
      final eff = coach.effectiveAllocation(player);
      expect(identical(eff, player), isTrue,
          reason: 'pas d\'allocation alternative à construire');
    });

    test('joueuse 0 pt sur une branche du coach → effective = 2 (boost)', () {
      final coach = makeCoach(specialties: const [branchA, branchB]);
      final player = alloc({});
      final eff = coach.effectiveAllocation(player);
      expect(eff.pointsIn(branchA), 2);
      expect(eff.pointsIn(branchB), 2);
      expect(eff.pointsIn(branchC), 0,
          reason: 'branche hors specialties inchangée');
    });

    test('joueuse 1 pt sur une branche du coach → effective = 2 (boost)', () {
      final coach = makeCoach(specialties: const [branchA]);
      final player = alloc({branchA: 1});
      final eff = coach.effectiveAllocation(player);
      expect(eff.pointsIn(branchA), 2);
    });

    test('joueuse 3 pts sur une branche du coach → effective inchangée (3)',
        () {
      final coach = makeCoach(specialties: const [branchA]);
      final player = alloc({branchA: 3});
      final eff = coach.effectiveAllocation(player);
      expect(eff.pointsIn(branchA), 3,
          reason: 'pas de double bonus quand la joueuse a déjà investi');
    });

    test('joueuse 5 pts sur une branche du coach → effective inchangée (5)',
        () {
      final coach = makeCoach(specialties: const [branchA]);
      final player = alloc({branchA: 5});
      final eff = coach.effectiveAllocation(player);
      expect(eff.pointsIn(branchA), 5);
    });

    test('branche hors specialties → jamais touchée même si 0', () {
      final coach = makeCoach(specialties: const [branchA]);
      final player = alloc({branchB: 0, branchC: 4});
      final eff = coach.effectiveAllocation(player);
      expect(eff.pointsIn(branchB), 0);
      expect(eff.pointsIn(branchC), 4);
    });

    test('lastRespecMs propagé', () {
      final coach = makeCoach(specialties: const [branchA]);
      const player = SpecializationAllocation(
        points: {},
        lastRespecMs: 1234567890,
      );
      final eff = coach.effectiveAllocation(player);
      expect(eff.lastRespecMs, 1234567890);
    });

    test('allocation vide + coach 2 spés → 2 pts dans chacune, reste à 0', () {
      final coach = makeCoach(specialties: const [branchA, branchB]);
      final eff = coach.effectiveAllocation(SpecializationAllocation.empty());
      expect(eff.pointsIn(branchA), 2);
      expect(eff.pointsIn(branchB), 2);
      expect(eff.pointsIn(branchC), 0);
      // Branches non touchées : leurs 0 pt persistent.
      for (final b in SpecializationBranch.values) {
        if (b != branchA && b != branchB) {
          expect(eff.pointsIn(b), 0);
        }
      }
    });
  });
}
