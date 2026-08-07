import 'package:beat_bitch/career/services/coach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproduction du « nouveau coach indisponible » signalé en 0.6.0.
///
/// Marc a été inséré au tier 3 (`CoachCatalog.defaults`), entre Hélène (2) et
/// Jade, décalée de 3 à 4. Le déblocage passe uniquement par
/// `syncFromTotalSeconds`, qui ne parcourt que les tiers **strictement
/// supérieurs** au tier courant persisté. Une joueuse déjà au-delà du tier 3
/// avant la mise à jour ne repassera donc jamais par ce tier : Marc reste
/// verrouillé quel que soit son temps de jeu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const marcId = 'coach_07_marc';

  test('un coach ajouté à un tier déjà franchi ne se débloque jamais',
      () async {
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
      isNot(contains(marcId)),
      reason: 'la boucle de sync ne visite que les tiers > tier courant',
    );
    expect(svc.isUnlocked(marc), isFalse);
    expect(
      svc.evaluate(marc, playerTotalSeconds: 200000),
      CoachSelectionStatus.lockedTier,
      reason: 'le seuil de temps est atteint, seul le déblocage manque',
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
