import 'dart:math';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/ambience_pack.dart';
import 'package:beat_bitch/models/final_category.dart';
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

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    for (final c in const [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
    for (final name in const [
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
          '.toggle',
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
          '.isEnabled',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        name,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    }
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('le pack lit ses clips de climax, fichier seul ou liste', () {
    AmbiencePack read(Object? climax) => AmbiencePack.fromJson({
          'id': 'p',
          'name': 'p',
          'tracks': const {},
          if (climax != null) 'climax': climax,
        });
    expect(read(['a.mp3', 'b.mp3']).climax, ['a.mp3', 'b.mp3']);
    expect(read('a.mp3').climax, ['a.mp3']);
    expect(read(null).climax, isEmpty);
  });

  test('le moteur joue un des clips de climax du pack, rien sans clip',
      () async {
    final engine = _ClimaxRecorder(Random(3));
    await engine.playClimax();
    expect(engine.played, isEmpty);

    engine.setPack(const AmbiencePack(
      id: 'voix',
      name: 'voix',
      tracksByMode: {},
      climax: ['c1.mp3', 'c2.mp3'],
    ));
    for (var i = 0; i < 20; i++) {
      await engine.playClimax();
    }
    expect(engine.played.toSet(), {'c1.mp3', 'c2.mp3'});
  });

  test('le gémissement part avec le chime du step final', () async {
    final ambience = _ClimaxCounter();
    final ctrl = SessionController(
      session: const Session(
        id: 'climax',
        name: 'climax',
        description: '',
        durationSeconds: 6,
        defaultMode: SessionMode.rhythm,
        silentFinishStartTime: 1,
        finalStepTime: 2,
        steps: [
          SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
          SessionStep(time: 2, mode: SessionMode.hold, to: Position.full),
          SessionStep(time: 4, mode: SessionMode.breath, duration: 2),
        ],
      ),
      tts: TtsService(),
      beep: _SilentBeepEngine(),
      ambience: ambience,
      punishmentBundle:
          const PunishmentBundle(failPhrases: [], punishments: []),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
    );
    await ctrl.start();
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ctrl.isFinished && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(ctrl.isFinished, isTrue);
    expect(ambience.climaxAt, hasLength(1),
        reason: 'un seul gémissement par séance');
    expect(ambience.climaxAt.single, inInclusiveRange(2, 3),
        reason: 'au step final, pas avant ni à la fin de séance');
  }, timeout: const Timeout(Duration(seconds: 40)));
}

class _ClimaxRecorder extends AmbienceEngine {
  _ClimaxRecorder(Random r) : super(random: r);
  final List<String> played = [];
  @override
  Future<void> startClimaxPlayback(String asset) async => played.add(asset);
}

class _ClimaxCounter extends AmbienceEngine {
  final List<int> climaxAt = [];
  final Stopwatch _clock = Stopwatch()..start();
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
  Future<void> startFinishMusic(Duration untilPeak, FinishTrack track) async {}
  @override
  Future<void> fadeOutFinishMusic(
      {Duration duration = const Duration(seconds: 3)}) async {}
  @override
  Future<void> stopFinishMusic() async {}
  @override
  Future<void> playClimax() async => climaxAt.add(_clock.elapsed.inSeconds);
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
  @override
  Future<void> playFinaleChime(
      {FinalCategory? category, double volume = 1.0}) async {}
}
