import 'dart:convert';

import 'package:beat_bitch/services/diagnostic_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

PackageInfo _info() => PackageInfo(
      appName: 'BeatBitch',
      packageName: 'app.bbstudio.beatbitch',
      version: '0.4.1',
      buildNumber: '9',
    );

Future<DiagnosticExportService> _build({
  required Map<String, Object> seed,
  DateTime? at,
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return DiagnosticExportService(
    prefs: prefs,
    packageInfo: _info(),
    platform: 'android',
    locale: 'fr',
    exportedAt: at ?? DateTime.utc(2026, 5, 17, 14, 32, 5),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiagnosticExportService — métadonnées', () {
    test('schemaVersion, exportedAt, appVersion, platform, locale présents',
        () async {
      final svc = await _build(seed: const <String, Object>{});
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      expect(payload['schemaVersion'], DiagnosticExportService.schemaVersion);
      expect(payload['exportedAt'], '2026-05-17T14:32:05.000Z');
      expect(payload['appVersion'], '0.4.1+9');
      expect(payload['platform'], 'android');
      expect(payload['locale'], 'fr');
    });

    test('defaultFilename est horodaté UTC à la seconde', () async {
      final svc = await _build(
        seed: const <String, Object>{},
        at: DateTime.utc(2026, 1, 3, 4, 5, 6),
      );
      expect(svc.defaultFilename(), 'beatbitch-export-20260103-040506.json');
    });

    test('JSON produit est parsable et indenté', () async {
      final svc = await _build(seed: const <String, Object>{});
      final raw = svc.buildJson(const DiagnosticExportOptions());
      expect(raw, contains('\n  "schemaVersion"'),
          reason: 'JSON doit être indenté.');
      final round = json.decode(raw);
      expect(round, isA<Map<String, dynamic>>());
    });
  });

  group('DiagnosticExportService — sections par défaut (prefs vides)', () {
    test('toutes les catégories sont présentes', () async {
      final svc = await _build(seed: const <String, Object>{});
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      const expected = [
        'career',
        'specialization',
        'stats',
        'humiliation',
        'obedience',
        'capabilities',
        'milestones',
        'badges',
        'coach',
        'anatomy',
        'surprise',
        'settings',
        'savedSessions',
        'customConfigs',
        'consent',
      ];
      for (final k in expected) {
        expect(payload.containsKey(k), isTrue, reason: 'missing $k');
      }
    });

    test('valeurs par défaut connues quand prefs vides', () async {
      final svc = await _build(seed: const <String, Object>{});
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      final career = payload['career'] as Map<String, dynamic>;
      expect(career['maxLevel'], 1);
      expect(career['completedSessions'], 0);
      expect(career['includeHand'], true);

      final stats = payload['stats'] as Map<String, dynamic>;
      expect(stats['totalSeconds'], 0);
      expect(stats['sessionsCompleted'], 0);

      expect(payload['humiliation'], {'careerScore': 0.0});
      expect(payload['obedience'], {'level': 0.0});

      expect((payload['capabilities'] as Map)['axes'], isEmpty);
      expect((payload['badges'] as Map), isEmpty);

      final anatomy = payload['anatomy'] as Map<String, dynamic>;
      expect(anatomy['hasBalls'], true);

      final consent = payload['consent'] as Map<String, dynamic>;
      expect(consent['adultConsentAccepted'], false);
      expect(consent['onboardingShown'], false);
    });
  });

  group('DiagnosticExportService — exclusions par défaut', () {
    test('aucune clé `nicknames` quand includeNicknames=false', () async {
      final svc = await _build(seed: const <String, Object>{
        'user_profile_prenom': 'Alice',
        'user_profile_custom_nicknames': <String>['ma_pute_a_moi'],
        'user_profile_disabled_default_nicknames': <String>['salope'],
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      expect(payload.containsKey('nicknames'), isFalse,
          reason: 'Les surnoms personnalisés ne doivent jamais sortir tant que '
              'la joueuse n\'a pas activé le toggle.');
      final serialized = svc.buildJson(const DiagnosticExportOptions());
      expect(serialized, isNot(contains('Alice')));
      expect(serialized, isNot(contains('ma_pute_a_moi')));
      expect(serialized, isNot(contains('salope')));
    });

    test('jamais de calibration caméra dans le payload', () async {
      final svc = await _build(seed: const <String, Object>{
        'cam_motion.axis': 'horizontal',
        'cam_motion.min': 0.12,
        'cam_motion.max': 0.87,
      });
      final payload = svc
          .buildPayload(const DiagnosticExportOptions(includeNicknames: true));
      // Aucune section ne doit faire ressortir la calibration personnelle.
      final raw =
          svc.buildJson(const DiagnosticExportOptions(includeNicknames: true));
      expect(raw, isNot(contains('cam_motion')));
      expect(raw, isNot(contains('horizontal')));
      // Sanité : la fonction tourne quand même.
      expect(payload['schemaVersion'], DiagnosticExportService.schemaVersion);
    });
  });

  group('DiagnosticExportService — toggle includeNicknames', () {
    test('inclus → section nicknames avec prénom + listes', () async {
      final svc = await _build(seed: const <String, Object>{
        'user_profile_prenom': 'Alice',
        'user_profile_custom_nicknames': <String>['perso1', 'perso2'],
        'user_profile_disabled_default_nicknames': <String>['salope'],
      });
      final payload = svc
          .buildPayload(const DiagnosticExportOptions(includeNicknames: true));

      expect(payload.containsKey('nicknames'), isTrue);
      final nicknames = payload['nicknames'] as Map<String, dynamic>;
      expect(nicknames['prenom'], 'Alice');
      expect(nicknames['custom'], ['perso1', 'perso2']);
      expect(nicknames['disabledDefaults'], ['salope']);
    });
  });

  group('DiagnosticExportService — sections renseignées', () {
    test('career + spécialisation + stats reflètent les prefs', () async {
      final svc = await _build(seed: const <String, Object>{
        'career.max_level': 9,
        'career.last_level': 9,
        'career.completed_sessions': 42,
        'career.include_hand': false,
        'specialization.points.endurance': 3,
        'specialization.points.profondeur': 2,
        'specialization.respec_count': 1,
        'specialization.last_respec_ms': 1700000000000,
        'stats.total_seconds': 12345,
        'stats.throatfucks': 678,
        'stats.sessions_completed': 25,
        'stats.daily_streak': 3,
        'stats.humiliation_level': 87.5,
        'stats.obedience_level': 42.0,
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      final career = payload['career'] as Map<String, dynamic>;
      expect(career['maxLevel'], 9);
      expect(career['lastLevel'], 9);
      expect(career['completedSessions'], 42);
      expect(career['includeHand'], false);

      final spec = payload['specialization'] as Map<String, dynamic>;
      final points = spec['points'] as Map<String, dynamic>;
      expect(points['endurance'], 3);
      expect(points['profondeur'], 2);
      expect(points['rythmeBiffle'], 0);
      expect(spec['respecCount'], 1);
      expect(spec['lastRespecMs'], 1700000000000);

      final stats = payload['stats'] as Map<String, dynamic>;
      expect(stats['totalSeconds'], 12345);
      expect(stats['throatfucks'], 678);
      expect(stats['sessionsCompleted'], 25);
      expect(stats['dailyStreak'], 3);

      expect((payload['humiliation'] as Map)['careerScore'], 87.5);
      expect((payload['obedience'] as Map)['level'], 42.0);
    });

    test('capabilities expose seulement les axes ayant au moins une clé',
        () async {
      final svc = await _build(seed: const <String, Object>{
        'cap.gorge.apnee_streak.best': 12.0,
        'cap.gorge.apnee_streak.comfort': 9.0,
        'cap.gorge.apnee_streak.sr': 0.65,
        'cap.gorge.apnee_streak.seen': 17,
        'cap.legacy_migrated': true,
      });
      final caps =
          svc.buildPayload(const DiagnosticExportOptions())['capabilities']
              as Map<String, dynamic>;

      expect(caps['legacyMigrated'], true);
      final axes = caps['axes'] as Map<String, dynamic>;
      expect(axes.containsKey('gorge.apnee_streak'), isTrue);
      final entry = axes['gorge.apnee_streak'] as Map<String, dynamic>;
      expect(entry['best'], 12.0);
      expect(entry['comfort'], 9.0);
      expect(entry['successRate'], 0.65);
      expect(entry['lastSeenSession'], 17);
      // Un axe sans aucune clé n'apparaît pas.
      expect(axes.containsKey('rhythm.depth_max'), isFalse);
    });

    test('badges traduit les indices stockés en noms de tier', () async {
      final svc = await _build(seed: const <String, Object>{
        'badge.tier.marathonien': 3, // BadgeTier index 3 = gold
        'badge.tier.ironLungs': 0, // none
      });
      final badges = svc.buildPayload(const DiagnosticExportOptions())['badges']
          as Map<String, dynamic>;
      expect(badges['marathonien'], 'gold');
      expect(badges['ironLungs'], 'none');
      // Pas de clé pour les familles non persistées.
      expect(badges.containsKey('throatQueen'), isFalse);
    });

    test('milestones decodes JSON listes/maps proprement', () async {
      final svc = await _build(seed: const <String, Object>{
        'career.milestones_completed': '["intro_basics","intro_lick_full"]',
        'career.milestone_retries': '{"intro_basics":1}',
        'career.milestone_candidacy_seen': '{"intro_basics":3}',
      });
      final m = svc.buildPayload(const DiagnosticExportOptions())['milestones']
          as Map<String, dynamic>;
      expect(m['completed'], ['intro_basics', 'intro_lick_full']);
      expect(m['retries'], {'intro_basics': 1});
      expect(m['candidacySeen'], {'intro_basics': 3});
    });

    test('milestones ne casse pas si JSON corrompu', () async {
      final svc = await _build(seed: const <String, Object>{
        'career.milestones_completed': 'not a json',
        'career.milestone_retries': '[]', // type inattendu
      });
      final m = svc.buildPayload(const DiagnosticExportOptions())['milestones']
          as Map<String, dynamic>;
      expect(m['completed'], isEmpty);
      expect(m['retries'], isEmpty);
    });

    test('surprise et settings reflètent les toggles persistés', () async {
      final svc = await _build(seed: const <String, Object>{
        'surprise.enabled': true,
        'surprise.window_seconds': 3600,
        'surprise.alert_count': 2,
        'surprise.duration_min_s': 60,
        'surprise.duration_max_s': 180,
        'debug.show_humiliation_bar': true,
        'debug.camera_hold_check': true,
        'pref.show_session_remaining_time': true,
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      final surprise = payload['surprise'] as Map<String, dynamic>;
      expect(surprise['enabled'], true);
      expect(surprise['windowSeconds'], 3600);
      expect(surprise['alertCount'], 2);
      expect(surprise['durationMinSeconds'], 60);
      expect(surprise['durationMaxSeconds'], 180);

      final settings = payload['settings'] as Map<String, dynamic>;
      expect(settings['showHumiliationBar'], true);
      expect(settings['cameraHoldCheck'], true);
      expect(settings['showSessionRemainingTime'], true);
      expect(settings['showBackgroundMedia'], true);
      expect(settings['showStaminaBar'], false);
    });
  });
}
