import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

const SessionStep _stepLow = SessionStep(
  time: 0,
  from: Position.head,
  to: Position.mid,
  bpm: 80,
  duration: 12,
  mode: SessionMode.rhythm,
);

LevelMilestone _milestone({
  required String id,
  List<UnlockKey> unlocks = const [],
  List<UnlockKey> requires = const [],
  List<SpecializationBranch> branches = const [],
  double humilRequired = 0.0,
}) {
  return LevelMilestone(
    id: id,
    humilRequired: humilRequired,
    displayLabel: id,
    sequence: const [_stepLow],
    durationSeconds: 12,
    unlocks: unlocks,
    requires: requires,
    branches: branches,
  );
}

void main() {
  group('MilestoneService.pendingForList — sélection 2 body distinctes', () {
    test('count=2 sur pool large : retourne 2 candidates distinctes', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _milestone(id: 'm_a'),
        _milestone(id: 'm_b'),
        _milestone(id: 'm_c'),
      ]);
      final picked = svc.pendingForList(
        count: 2,
        humiliationScore: 100.0,
        obedience: 0.0,
      );
      expect(picked.length, 2);
      expect(picked.map((m) => m.id).toSet().length, 2,
          reason: 'pas de doublon entre les 2 picks');
    });

    test('count=2 sur pool 1 milestone : retombe à 1', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _milestone(id: 'only_one'),
      ]);
      final picked = svc.pendingForList(
        count: 2,
        humiliationScore: 100.0,
        obedience: 0.0,
      );
      expect(picked.length, 1);
      expect(picked.first.id, 'only_one');
    });

    test('count=2 sur pool vide : retourne liste vide', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: const []);
      final picked = svc.pendingForList(
        count: 2,
        humiliationScore: 100.0,
        obedience: 0.0,
      );
      expect(picked, isEmpty);
    });

    test('count=0 : retourne liste vide même si pool fourni', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [_milestone(id: 'm_a')]);
      final picked = svc.pendingForList(
        count: 0,
        humiliationScore: 100.0,
        obedience: 0.0,
      );
      expect(picked, isEmpty);
    });

    test(
        'exclusion mutuelle : m2.requires inclut un unlock de m1 → '
        'm2 écartée du 2ᵉ pick', () {
      // m1 débloque `basics`. m2 demande `basics`. Au pick #1, m2 n'est PAS
      // candidate (allPendingFor filtre déjà sur requires.every(hasUnlock)).
      // Donc seul m1 est éligible au pick #1. Au pick #2, si on tentait
      // de réutiliser allPendingFor en simulant m1 acquittée, m2 serait
      // candidate — pendingForList doit alors l'exclure pour ne pas forcer
      // l'ordre pédagogique strict dans la même séance.
      //
      // Pour tester ça, on a besoin d'une 3ᵉ milestone indépendante qui
      // peut être pickée au #2 sans dépendre de m1 (sinon le pool serait
      // strictement [m1] et le test ne discriminerait rien).
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _milestone(id: 'm1', unlocks: [UnlockKey.basics]),
        _milestone(id: 'm2_depends_m1', requires: [UnlockKey.basics]),
        _milestone(id: 'm3_independent'),
      ]);
      final picked = svc.pendingForList(
        count: 2,
        humiliationScore: 100.0,
        obedience: 0.0,
      );
      expect(picked.length, 2);
      final ids = picked.map((m) => m.id).toSet();
      expect(ids.contains('m2_depends_m1'), isFalse,
          reason:
              'm2 dépend pédagogiquement de m1, jamais dans la même séance');
      // Avec le tri d'allPendingFor (humil ASC + id ASC), m1 puis m3.
      expect(ids, {'m1', 'm3_independent'});
    });

    test(
        '2ᵉ candidate sans dépendance sur la 1ʳᵉ : pas d\'exclusion injustifiée',
        () {
      // m1 débloque `basics`. m2 a un unlock distinct (`encore`) et ne
      // dépend pas de m1. Les 2 doivent être pickées ensemble.
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _milestone(id: 'm1', unlocks: [UnlockKey.basics]),
        _milestone(id: 'm2_unrelated', unlocks: [UnlockKey.encore]),
      ]);
      final picked = svc.pendingForList(
        count: 2,
        humiliationScore: 100.0,
        obedience: 0.0,
      );
      expect(picked.length, 2);
      expect(picked.map((m) => m.id).toSet(), {'m1', 'm2_unrelated'});
    });
  });
}
