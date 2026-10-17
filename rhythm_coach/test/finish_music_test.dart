import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
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
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  group('AmbienceEngine.startFinishMusic', () {
    test('démarre le fichier au point qui place le sommet dans untilPeak',
        () async {
      final engine = _OffsetRecordingEngine();
      await engine.startFinishMusic(const Duration(seconds: 25));
      expect(engine.offsets.single,
          AmbienceEngine.finishMusicPeak - const Duration(seconds: 25));
      expect(engine.isFinishMusicPlaying, isTrue);
    });

    test('montée plus longue que le sommet : départ au début du fichier',
        () async {
      final engine = _OffsetRecordingEngine();
      await engine.startFinishMusic(
          AmbienceEngine.finishMusicPeak + const Duration(seconds: 30));
      expect(engine.offsets.single, Duration.zero);
    });
  });

  test(
      'la musique démarre au début de la montée, calée sur le final, et '
      "s'éteint au post-final", () async {
    final ambience = _FinishRecordingAmbience();
    late SessionController ctrl;
    ambience.onEvent = (e) => ambience.events.add((e, ctrl.elapsedSeconds));
    ctrl = _buildController(ambience);
    await ctrl.start();
    await _waitUntil(() => ctrl.isFinished);

    final starts = ambience.events.where((e) => e.$1.startsWith('start'));
    expect(starts.map((e) => e.$1), ['start 4s'],
        reason: 'un seul départ, sommet dans 4 s (final à 8, montée à 4)');
    expect(starts.single.$2, 4);
    final fades = ambience.events.where((e) => e.$1 == 'fade');
    expect(fades, isNotEmpty);
    expect(fades.first.$2, 11, reason: 'premier step du post-final');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition non atteinte en ${timeout.inSeconds} s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

SessionController _buildController(AmbienceEngine ambience) {
  return SessionController(
    session: const Session(
      id: 'finish',
      name: 'finish',
      description: '',
      durationSeconds: 13,
      defaultMode: SessionMode.rhythm,
      silentFinishStartTime: 4,
      finalStepTime: 8,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
        SessionStep(time: 2, mode: SessionMode.rhythm, bpm: 60, duration: 2),
        SessionStep(time: 4, mode: SessionMode.rhythm, bpm: 90, duration: 4),
        SessionStep(time: 8, mode: SessionMode.hold, to: Position.full),
        SessionStep(time: 11, mode: SessionMode.breath, duration: 2),
      ],
    ),
    tts: TtsService(),
    beep: _SilentBeepEngine(),
    ambience: ambience,
    punishmentBundle: const PunishmentBundle(failPhrases: [], punishments: []),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
  );
}

class _OffsetRecordingEngine extends AmbienceEngine {
  final List<Duration> offsets = [];

  @override
  Future<void> startFinishPlayback(Duration offset) async {
    offsets.add(offset);
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

class _FinishRecordingAmbience extends AmbienceEngine {
  final List<(String, int)> events = [];
  void Function(String) onEvent = (_) {};

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
  @override
  Future<void> startFinishMusic(Duration untilPeak) async =>
      onEvent('start ${untilPeak.inSeconds}s');
  @override
  Future<void> fadeOutFinishMusic(
          {Duration duration = const Duration(seconds: 3)}) async =>
      onEvent('fade');
  @override
  Future<void> stopFinishMusic() async {}
}
