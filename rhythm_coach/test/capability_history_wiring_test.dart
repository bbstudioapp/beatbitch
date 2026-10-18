import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/capability_history.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Câblage : le vrai `SessionController` écrit une entrée d'historique du
/// profil de capacités à la clôture d'une séance qui met le profil à jour, et
/// aucune sinon.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();

  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      switch (call.method) {
        case 'speak':
          unawaited(pushFromEngine('speak.onStart', true));
          Timer(const Duration(milliseconds: 40),
              () => pushFromEngine('speak.onComplete', true));
          return 1;
        case 'stop':
          unawaited(pushFromEngine('speak.onCancel', true));
          return 1;
        case 'getVoices':
          return <dynamic>[];
        default:
          return 1;
      }
    });
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
    for (final name in wakelockChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        name,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  const miniPunishment = Punishment(
    id: 'mini',
    name: 'mini',
    durationSeconds: 1,
    steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
  );
  const punishments = PunishmentBundle(
    failPhrases: ['tu craques'],
    punishments: [miniPunishment],
  );

  SessionController buildController({bool noStats = false}) =>
      SessionController(
        staminaProfile: List<double>.filled(300, 100),
        session: Session(
          id: 'history-wiring',
          name: 'history-wiring',
          description: '',
          durationSeconds: 9,
          defaultMode: SessionMode.rhythm,
          noStats: noStats,
          steps: const [
            SessionStep(
                time: 0,
                mode: SessionMode.rhythm,
                from: Position.head,
                to: Position.throat,
                bpm: 120)
          ],
        ),
        tts: TtsService(),
        beep: _SilentBeepEngine(),
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: punishments,
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
        trackCapabilities: true,
      );

  Future<void> untilFinished(SessionController c) async {
    for (var i = 0; i < 400 && c.state != SessionState.finished; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(c.state, SessionState.finished, reason: 'la séance va à son terme');
  }

  Future<List<CapabilityHistoryEntry>> history() async =>
      CapabilityHistory.read(await SharedPreferences.getInstance());

  test('séance carrière qui met le profil à jour : une entrée', () async {
    final ctrl = buildController();
    await ctrl.start();
    await untilFinished(ctrl);
    final h = await history();
    expect(h, hasLength(1));
    expect(h.single.sessionIndex, 1,
        reason: 'index = sessions complétées, comme pour le decay');
    expect(h.single.axes, contains('rhythm.bpm_ceil.throat'));
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('séance noStats (n\'écrit pas le profil) : aucune entrée', () async {
    final ctrl = buildController(noStats: true);
    await ctrl.start();
    await untilFinished(ctrl);
    expect(await history(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('historique illisible : la séance se termine et le profil est écrit',
      () async {
    SharedPreferences.setMockInitialValues({'cap.history': '{pas du json'});
    final ctrl = buildController();
    await ctrl.start();
    await untilFinished(ctrl);
    expect(await history(), hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 40)));
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
