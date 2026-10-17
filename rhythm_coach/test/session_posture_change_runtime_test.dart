import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Moteur TTS factice qui complète toujours : sans lui, l'anti-coupure de
  /// `_checkSteps` différerait les steps et brouillerait la mesure.
  void installFakeTtsEngine() {
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
    installFakeTtsEngine();
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

  const punishments = PunishmentBundle(
    failPhrases: ['tu craques'],
    punishments: [
      Punishment(
        id: 'p',
        name: 'p',
        durationSeconds: 1,
        steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
      ),
    ],
  );

  SessionController buildController({
    required BeepEngine beep,
    List<ScriptedBreak> breaks = const [],
    List<PostureChange> postureChanges = const [],
  }) =>
      SessionController(
        staminaProfile: List<double>.filled(120, 100),
        session: Session(
          id: 'posture-change',
          name: 'posture-change',
          description: '',
          durationSeconds: 60,
          defaultMode: SessionMode.rhythm,
          initialPose: Posture.free,
          breaks: breaks,
          postureChanges: postureChanges,
          steps: const [
            SessionStep(
                time: 0, text: 'debut', mode: SessionMode.rhythm, bpm: 80),
            SessionStep(
                time: 1, text: 'apres-1', mode: SessionMode.rhythm, bpm: 90),
            SessionStep(
                time: 30, text: 'apres-30', mode: SessionMode.rhythm, bpm: 100),
          ],
        ),
        tts: TtsService(),
        beep: beep,
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: punishments,
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );

  test(
      'un changement de position annonce la pose, coupe le bip et met la '
      'séance en attente jusqu\'à la validation', () async {
    final beep = _TrackingBeepEngine();
    final ctrl = buildController(
      beep: beep,
      postureChanges: const [PostureChange(time: 1, pose: Posture.kneeling)],
    );
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    expect(ctrl.currentPose, Posture.kneeling);
    expect(ctrl.awaitingPostureReady, isTrue);
    expect(beep.pauseCalls, greaterThanOrEqualTo(1));
    expect(beep.appliedSteps.map((s) => s.text), isNot(contains('apres-1')),
        reason: 'l\'effort attend la validation');

    final frozenAt = ctrl.elapsedSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(ctrl.elapsedSeconds, lessThanOrEqualTo(frozenAt),
        reason: 'la séance est en attente');

    ctrl.confirmPostureReady();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(ctrl.awaitingPostureReady, isFalse);
    expect(beep.appliedSteps.map((s) => s.text), contains('apres-1'),
        reason: 'le step posé sur le changement relance l\'effort');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('passer la pause saute à sa fin et relance l\'effort', () async {
    final beep = _TrackingBeepEngine();
    final ctrl = buildController(
      beep: beep,
      breaks: const [ScriptedBreak(time: 1, durationSeconds: 29)],
    );
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.breakActive, isTrue);

    ctrl.skipBreak();
    expect(ctrl.breakActive, isFalse);
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(30));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(beep.appliedSteps.map((s) => s.text), contains('apres-30'));
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'pause sans changement de position : rien à valider');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('passer une pause qui change de position demande la mise en place',
      () async {
    final ctrl = buildController(
      beep: _TrackingBeepEngine(),
      breaks: const [
        ScriptedBreak(time: 1, durationSeconds: 29, newPose: Posture.allFours),
      ],
    );
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    ctrl.skipBreak();
    expect(ctrl.currentPose, Posture.allFours);
    expect(ctrl.awaitingPostureReady, isTrue);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('sans validation, la séance reprend seule au bout de 2 min', () {
    fakeAsync((async) {
      final ctrl = buildController(
        beep: _TrackingBeepEngine(),
        breaks: const [ScriptedBreak(time: 0, durationSeconds: 30)],
        postureChanges: const [
          PostureChange(time: 30, pose: Posture.kneeling),
        ],
      );
      ctrl.start();
      async.elapse(const Duration(seconds: 3));
      expect(ctrl.breakActive, isTrue);
      ctrl.skipBreak();
      async.elapse(const Duration(milliseconds: 400));
      expect(ctrl.awaitingPostureReady, isTrue);

      async.elapse(const Duration(seconds: 118));
      expect(ctrl.awaitingPostureReady, isTrue,
          reason: 'la joueuse a jusqu\'à 2 min pour se mettre en place');
      async.elapse(const Duration(seconds: 2));
      expect(ctrl.awaitingPostureReady, isFalse);

      ctrl.stop();
      async.elapse(const Duration(seconds: 3));
    });
  });
}

class _TrackingBeepEngine extends BeepEngine {
  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<SessionStep> appliedSteps = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(
    SessionStep step,
    SessionMode sessionMode,
  ) async {
    appliedSteps.add(step);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

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
