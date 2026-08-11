import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/services/diagnostic_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applique un payload au format export vers les prefs', () async {
    SharedPreferences.setMockInitialValues({
      // Valeur résiduelle d'un chargement précédent : doit être écrasée.
      'career.max_level': 99,
      'cap.hand.streak.best': 123.0,
    });
    final prefs = await SharedPreferences.getInstance();
    final svc = DiagnosticImportService(prefs);

    await svc.apply(<String, dynamic>{
      'career': {'maxLevel': 6, 'lastLevel': null, 'completedSessions': 18},
      'humiliation': {'careerScore': 80.5},
      'obedience': {'level': 100.0},
      'capabilities': {
        'axes': {
          'rhythm.depth_max': {
            'best': 3.0,
            'comfort': 2.0,
            'successRate': 0.55,
            'lastSeenSession': 4,
          },
        },
        'legacyMigrated': true,
      },
      'milestones': {
        'completed': ['intro_basics', 'intro_posture_sitting'],
        'retries': {},
        'candidacySeen': {'intro_biffle': 2},
      },
      'badges': {'throatQueen': 'silver'},
      'settings': {'scriptedBreaks': true},
    });

    expect(prefs.getInt('career.max_level'), 6);
    // lastLevel null → clé absente (déterministe : effacée avant écriture).
    expect(prefs.getInt('career.last_level'), isNull);
    expect(prefs.getInt('career.completed_sessions'), 18);
    expect(prefs.getDouble('stats.humiliation_level'), 80.5);
    expect(prefs.getDouble('stats.obedience_level'), 100.0);

    expect(prefs.getDouble('cap.rhythm.depth_max.best'), 3.0);
    expect(prefs.getDouble('cap.rhythm.depth_max.comfort'), 2.0);
    expect(prefs.getInt('cap.rhythm.depth_max.seen'), 4);
    expect(prefs.getBool('cap.legacy_migrated'), true);
    // Axe non fourni : effacé (pas de résidu du 123.0 initial).
    expect(prefs.getDouble('cap.hand.streak.best'), isNull);

    expect(
      json.decode(prefs.getString('career.milestones_completed')!),
      ['intro_basics', 'intro_posture_sitting'],
    );
    expect(
      json.decode(prefs.getString('career.milestone_candidacy_seen')!),
      {'intro_biffle': 2},
    );

    // Badge : nom de palier → index enum.
    // BadgeTier = {none, bronze, silver, ...} → silver = idx 2.
    expect(prefs.getInt('badge.tier.throatQueen'), 2);

    expect(prefs.getBool('pref.scripted_breaks'), true);
  });
}
