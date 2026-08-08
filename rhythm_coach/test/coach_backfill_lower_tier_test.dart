import 'package:beat_bitch/career/services/coach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-régression du « nouveau coach indisponible » signalé en 0.6.0.
///
/// Marc a été inséré au tier 3 (`CoachCatalog.defaults`), entre Hélène (2) et
/// Jade, décalée de 3 à 4. Le déblocage passe uniquement par
/// `syncFromTotalSeconds`, qui ne parcourait que les tiers **strictement
/// supérieurs** au tier courant persisté : une joueuse déjà au-delà du tier 3
/// avant la mise à jour ne repassait jamais par ce tier, et Marc restait
/// verrouillé quel que soit son temps de jeu — d'autant plus sûrement qu'elle
/// avait joué longtemps.
///
/// La réconciliation est désormais complète : tout Principal dont le seuil de
/// temps est atteint est débloqué, indépendamment du tier courant.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const marcId = 'coach_07_marc';

  test('un coach ajouté à un tier déjà franchi est rattrapé', () async {
    // Profil d'avant la 0.6.0 : tier 4 atteint, Marc absent du set persisté.
    SharedPreferences.setMockInitialValues({
      'coach.current_tier': 4,
      'coach.unlocked_ids': <String>[
        'coach_01_lina',
        'coach_02_helene',
        'coach_03_jade',
      ],
    });

    final svc = CoachService();
    await svc.load();
    final marc = svc.coaches.firstWhere((c) => c.id == marcId);

    expect(marc.tier, 3);
    expect(svc.isUnlocked(marc), isFalse);

    // 55 h de jeu cumulé, très au-dessus des 5400 s (1 h 30) exigées par Marc.
    final newlyUnlocked = await svc.syncFromTotalSeconds(200000);

    expect(
      newlyUnlocked.map((c) => c.id),
      contains(marcId),
      reason: 'le rattrapage doit visiter les tiers déjà franchis',
    );
    expect(svc.isUnlocked(marc), isTrue);
    expect(
      svc.evaluate(marc, playerTotalSeconds: 200000),
      CoachSelectionStatus.selectedFreeTraining,
      reason: 'Marc est sélectionnable, sans faire progresser le palier 4',
    );
  });

  test('le rattrapage est idempotent', () async {
    SharedPreferences.setMockInitialValues({
      'coach.current_tier': 4,
      'coach.unlocked_ids': <String>[
        'coach_01_lina',
        'coach_02_helene',
        'coach_03_jade',
      ],
    });

    final svc = CoachService();
    await svc.load();

    final first = await svc.syncFromTotalSeconds(200000);
    expect(first.map((c) => c.id), contains(marcId));

    final second = await svc.syncFromTotalSeconds(200000);
    expect(second, isEmpty,
        reason: 'un second appel ne redébloque rien — pas de ré-annonce');
    expect(
      svc.isUnlocked(svc.coaches.firstWhere((c) => c.id == marcId)),
      isTrue,
      reason: 'et le rattrapage du premier appel reste acquis',
    );
  });

  test('sans le temps de jeu requis, rien n\'est débloqué', () async {
    SharedPreferences.setMockInitialValues({
      'coach.current_tier': 2,
      'coach.unlocked_ids': <String>['coach_01_lina', 'coach_02_helene'],
    });

    final svc = CoachService();
    await svc.load();
    final marc = svc.coaches.firstWhere((c) => c.id == marcId);

    // 1 h 06 : au-dessus d'Hélène (3600 s), sous les 5400 s de Marc.
    final newlyUnlocked = await svc.syncFromTotalSeconds(4000);

    expect(newlyUnlocked, isEmpty);
    expect(svc.isUnlocked(marc), isFalse);
    expect(svc.currentTier, 2);
    expect(
      svc.evaluate(marc, playerTotalSeconds: 4000),
      CoachSelectionStatus.lockedTier,
    );
  });

  test('un profil encore sous le tier 3 débloque Marc normalement', () async {
    SharedPreferences.setMockInitialValues({
      'coach.current_tier': 2,
      'coach.unlocked_ids': <String>['coach_01_lina', 'coach_02_helene'],
    });

    final svc = CoachService();
    await svc.load();
    final marc = svc.coaches.firstWhere((c) => c.id == marcId);

    // Juste au-dessus du `minPlayerSeconds` de Marc, sous celui de Jade.
    final newlyUnlocked = await svc.syncFromTotalSeconds(6000);

    expect(newlyUnlocked.map((c) => c.id), contains(marcId));
    expect(svc.isUnlocked(marc), isTrue);
  });
}
