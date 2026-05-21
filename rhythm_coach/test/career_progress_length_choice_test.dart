import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/career/services/career_progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('CareerProgressService — SessionLengthChoice (Phase 19.4)', () {
    test('par défaut, courte est retournée si rien n\'est persisté', () async {
      final s = CareerProgressService();
      expect(await s.getLastLengthChoice(), SessionLengthChoice.courte);
    });

    test('set puis get round-trip pour chaque palier', () async {
      final s = CareerProgressService();
      for (final c in SessionLengthChoice.values) {
        await s.setLastLengthChoice(c);
        expect(await s.getLastLengthChoice(), c,
            reason: 'round-trip échoué pour ${c.name}');
      }
    });

    test('clé inconnue → défaut courte (résilience renommage)', () async {
      SharedPreferences.setMockInitialValues({
        'career.last_length_choice': 'inexistant_palier',
      });
      final s = CareerProgressService();
      expect(await s.getLastLengthChoice(), SessionLengthChoice.courte);
    });

    test('resetAll efface le choix persisté', () async {
      final s = CareerProgressService();
      await s.setLastLengthChoice(SessionLengthChoice.longue);
      expect(await s.getLastLengthChoice(), SessionLengthChoice.longue);
      await s.resetAll();
      expect(await s.getLastLengthChoice(), SessionLengthChoice.courte);
    });
  });
}
