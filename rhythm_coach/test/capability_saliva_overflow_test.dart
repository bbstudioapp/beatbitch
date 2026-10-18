import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/main.dart' show milestoneService;
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/saliva_engine.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
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
    milestoneService.setSessionUnlocks(const {
      UnlockKey.sloppySwallowControl,
      UnlockKey.sloppyDroolBasic,
    });
  });

  tearDown(() {
    milestoneService.setSessionUnlocks(const {});
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  test(
      'débordement de salive pendant un « sans avaler » : la série compte en '
      'entier, noswallow monte', () async {
    final svc = CapabilityService();
    await svc.commit(
      const SessionCapabilityReport(
          reached: {CapabilityAxis.noswallowStreak: 4}, sessionCeilings: {}),
      sessionIndex: 1,
    );
    final ctrl = _buildController();
    await ctrl.start();
    ctrl.saliva.seed(SalivaEngine.overflowThreshold - 1);

    await _waitUntil(() => ctrl.saliva.value >= SalivaEngine.overflowThreshold);
    expect(ctrl.isFinished, isFalse);
    await _waitUntil(() => ctrl.isFinished);

    final after = await svc.snapshotProfile();
    const gain = CapabilityRegulator.kRatchetUpGainMin +
        (CapabilityRegulator.kRatchetUpGainMax -
                CapabilityRegulator.kRatchetUpGainMin) *
            0.5;
    expect(after.comfortOf(CapabilityAxis.noswallowStreak),
        closeTo(4 * (1 + gain), 1e-9));
    expect(after.stateOf(CapabilityAxis.noswallowStreak).successRate,
        closeTo(0.65, 1e-9));
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition non atteinte en ${timeout.inSeconds} s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

SessionController _buildController() {
  return SessionController(
    session: const Session(
      id: 'debordement',
      name: 'debordement',
      description: '',
      durationSeconds: 8,
      defaultMode: SessionMode.hold,
      steps: [
        SessionStep(
            time: 0,
            mode: SessionMode.hold,
            from: Position.full,
            to: Position.full,
            duration: 8,
            swallowMode: SwallowMode.forbidden),
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
    trackCapabilities: true,
  );
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
  Future<void> playForMode(SessionMode mode) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
