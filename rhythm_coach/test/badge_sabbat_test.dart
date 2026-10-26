import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/badge.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/badge_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/diagnostic_export_service.dart';
import 'package:beat_bitch/services/diagnostic_import_service.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/stats_service.dart';
import 'package:beat_bitch/services/tts_service.dart';

final _inWindow = DateTime(2026, 11, 8, 23, 59, 59);
final _afterWindow = DateTime(2026, 11, 9);
final _nextYear = DateTime(2027, 10, 27);

StatsSnapshot _snap({int sabbat = 0}) => StatsSnapshot(
      totalSeconds: 0,
      throatfucks: 0,
      biffles: 0,
      holdThroatSeconds: 0,
      holdFullSeconds: 0,
      sessionsCompleted: 0,
      sessionsNoFailStreak: 0,
      modesUsedMask: 0,
      maxHoldFullAtomic: 0,
      dailyStreak: 0,
      encoresAsked: 0,
      quickiesCompleted: 0,
      sabbatSessions: sabbat,
      humiliationLevel: 0,
      obedienceLevel: 0,
    );

Future<List<BadgeFamily>> _shown(DateTime now, {int sabbat = 0}) async =>
    (await BadgeService(clock: () => now).currentStates(_snap(sabbat: sabbat)))
        .map((s) => s.definition.family)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Badge Sabbat — affichage', () {
    final permanent =
        BadgeFamily.values.where((f) => f != BadgeFamily.sabbat).toList();

    test('non obtenu : montré pendant la fenêtre, caché hors fenêtre',
        () async {
      expect(await _shown(_inWindow), [...permanent, BadgeFamily.sabbat]);
      expect(await _shown(_afterWindow), permanent);
      expect(await _shown(_nextYear), [...permanent, BadgeFamily.sabbat]);
    });

    test('obtenu : montré toute l\'année', () async {
      expect(await _shown(_afterWindow, sabbat: 1),
          [...permanent, BadgeFamily.sabbat]);
    });

    test('paliers 1 / 3 / 6 / 10 séances', () {
      final def = BadgeDefinition.forFamily(BadgeFamily.sabbat);
      expect(def.tierFor(0), BadgeTier.none);
      expect(def.tierFor(1), BadgeTier.bronze);
      expect(def.tierFor(2), BadgeTier.bronze);
      expect(def.tierFor(3), BadgeTier.silver);
      expect(def.tierFor(6), BadgeTier.gold);
      expect(def.tierFor(10), BadgeTier.platinium);
    });

    test('les autres badges ne dépendent pas de la date', () async {
      final states =
          await BadgeService(clock: () => _afterWindow).currentStates(_snap());
      final reference =
          await BadgeService(clock: () => _inWindow).currentStates(_snap());
      expect(
        states.map((s) => (s.definition.family, s.tier, s.value)),
        reference
            .where((s) => s.definition.family != BadgeFamily.sabbat)
            .map((s) => (s.definition.family, s.tier, s.value)),
      );
    });
  });

  group('Compteur Sabbat — fin de séance', () {
    const audioChannels = [
      MethodChannel('xyz.luan/audioplayers'),
      MethodChannel('xyz.luan/audioplayers.global'),
    ];
    const wakelockChannels = [
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
          '.toggle',
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
          '.isEnabled',
    ];

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async {
        if (call.method == 'getVoices') return <dynamic>[];
        return 1;
      });
      for (final c in audioChannels) {
        messenger.setMockMethodCallHandler(c, (call) async => null);
      }
      for (final name in wakelockChannels) {
        messenger.setMockMessageHandler(
          name,
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
      }
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'), null);
      for (final c in audioChannels) {
        messenger.setMockMethodCallHandler(c, null);
      }
    });

    test('une séance complétée avec Lilith compte et débloque le bronze',
        () async {
      await _playToEnd(coachTag: 'lilith');
      expect((await StatsService().snapshot()).sabbatSessions, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('badge.tier.sabbat'), BadgeTier.bronze.index);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('une séance avec une autre coach ne compte pas', () async {
      await _playToEnd(coachTag: 'helene');
      expect((await StatsService().snapshot()).sabbatSessions, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('badge.tier.sabbat'), isNull);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  test('le compteur Sabbat fait l\'aller-retour export → import', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'stats.sabbat_sessions': 4,
    });
    final exported = json.decode(json.encode(DiagnosticExportService(
      prefs: await SharedPreferences.getInstance(),
      packageInfo: PackageInfo(
          appName: 'BeatBitch',
          packageName: 'app.bbstudio.beatbitch',
          version: '0.7.0',
          buildNumber: '1'),
      platform: 'android',
      locale: 'fr',
      exportedAt: DateTime.utc(2026, 10, 30),
    ).buildPayload(const DiagnosticExportOptions()))) as Map<String, dynamic>;

    SharedPreferences.setMockInitialValues(<String, Object>{
      'stats.sabbat_sessions': 99,
    });
    await DiagnosticImportService(await SharedPreferences.getInstance())
        .apply(exported);
    expect((await StatsService().snapshot()).sabbatSessions, 4);
  });

  test('la remise à zéro des stats efface le compteur Sabbat', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'stats.sabbat_sessions': 4,
    });
    await StatsService().resetAll();
    expect((await StatsService().snapshot()).sabbatSessions, 0);
  });
}

Future<void> _playToEnd({required String coachTag}) async {
  final ctrl = SessionController(
    session: const Session(
      id: 'sabbat',
      name: 'sabbat',
      description: '',
      durationSeconds: 2,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
      ],
    ),
    tts: TtsService(),
    beep: _SilentBeepEngine(),
    ambience: _SilentAmbienceEngine(),
    punishmentBundle: const PunishmentBundle(failPhrases: [], punishments: []),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
    coachTag: coachTag,
  );
  await ctrl.start();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ctrl.isFinished) {
    if (DateTime.now().isAfter(deadline)) fail('séance non terminée');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

class _SilentBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _SilentAmbienceEngine extends AmbienceEngine {
  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> playForMode(SessionMode mode, {Position? depth}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
