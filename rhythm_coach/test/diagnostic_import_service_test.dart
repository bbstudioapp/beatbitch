import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/diagnostic_export_service.dart';
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

  test('restaure le drapeau d\'amorçage et la tenue max « Utilise-moi »',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await DiagnosticImportService(prefs).apply(<String, dynamic>{
      'capabilities': {
        'axes': {
          'useMe.held_streak': {
            'best': 300.0,
            'comfort': 300.0,
            'successRate': 0.5,
            'lastSeenSession': -1,
          },
        },
        'useMeHeldMigrated': true,
      },
      'stats': {'maxUseMeSec': 300},
    });

    expect(prefs.getBool('cap.use_me_held_migrated'), true);
    expect(prefs.getInt('stats.max_use_me_sec'), 300);
  });

  test(
      'un export sans amorçage : l\'axe ne dépend pas des stats de l\'appareil',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cap.use_me_held_migrated': true,
      'stats.max_use_me_sec': 500,
    });
    final prefs = await SharedPreferences.getInstance();
    await DiagnosticImportService(prefs).apply(<String, dynamic>{
      'capabilities': {'axes': {}},
    });

    expect(prefs.getBool('cap.use_me_held_migrated'), isNull);
    expect(prefs.getInt('stats.max_use_me_sec'), isNull);
    final profile = await CapabilityService().snapshotProfile();
    expect(profile.stateOf(CapabilityAxis.useMeHeldStreak).hasData, isFalse);
  });

  test('aller-retour export → import : l\'axe « Utilise-moi » suit la joueuse',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cap.use_me_held_migrated': true,
      'stats.max_use_me_sec': 240,
      'cap.useMe.held_streak.best': 240.0,
      'cap.useMe.held_streak.comfort': 240.0,
    });
    final source = DiagnosticExportService(
      prefs: await SharedPreferences.getInstance(),
      packageInfo: PackageInfo(
          appName: 'BeatBitch',
          packageName: 'app.bbstudio.beatbitch',
          version: '0.7.0',
          buildNumber: '1'),
      platform: 'android',
      locale: 'fr',
      exportedAt: DateTime.utc(2026, 10, 18),
    );
    final exported = json.decode(
            json.encode(source.buildPayload(const DiagnosticExportOptions())))
        as Map<String, dynamic>;

    SharedPreferences.setMockInitialValues(<String, Object>{
      'stats.max_use_me_sec': 999,
    });
    await DiagnosticImportService(await SharedPreferences.getInstance())
        .apply(exported);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('cap.use_me_held_migrated'), true);
    expect(prefs.getInt('stats.max_use_me_sec'), 240);
    final profile = await CapabilityService().snapshotProfile();
    expect(profile.bestOf(CapabilityAxis.useMeHeldStreak), 240);
  });
}
