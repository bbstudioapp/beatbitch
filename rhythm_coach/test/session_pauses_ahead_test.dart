import 'dart:async';

import 'package:beat_bitch/career/models/phrase_bank.dart';
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
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  final spoken = <String>[];

  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  setUp(() {
    spoken.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      switch (call.method) {
        case 'speak':
          spoken.add('${call.arguments}');
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

  SessionController buildController(_TrackingBeepEngine beep) =>
      SessionController(
        staminaProfile: List<double>.filled(300, 100),
        session: const Session(
          id: 'pauses-a-venir',
          name: 'pauses-a-venir',
          description: '',
          durationSeconds: 200,
          defaultMode: SessionMode.rhythm,
          breaks: [
            ScriptedBreak(time: 1, durationSeconds: 2),
            ScriptedBreak(time: 30, durationSeconds: 60),
            ScriptedBreak(time: 120, durationSeconds: 90),
          ],
          postureChanges: [
            PostureChange(time: 60, pose: Posture.kneeling),
          ],
          steps: [
            SessionStep(time: 0, text: 'a', mode: SessionMode.rhythm, bpm: 80),
            SessionStep(time: 3, text: 'b', mode: SessionMode.rhythm, bpm: 80),
          ],
        ),
        tts: TtsService(),
        beep: beep,
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: punishments,
        phraseBank: const PhraseBank(byMode: {}, congrats: [], intros: []),
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );

  // Un changement joué avant la régénération : l'index des changements repart
  // de zéro sur la suite régénérée, qui porte les changements restants.
  SessionController buildPlayedChangeController() => SessionController(
        staminaProfile: List<double>.filled(300, 100),
        session: const Session(
          id: 'changement-joue',
          name: 'changement-joue',
          description: '',
          durationSeconds: 200,
          defaultMode: SessionMode.rhythm,
          postureChanges: [
            PostureChange(time: 1, pose: Posture.kneeling),
          ],
          steps: [
            SessionStep(time: 0, text: 'a', mode: SessionMode.rhythm, bpm: 80),
            SessionStep(time: 1, text: 'b', mode: SessionMode.rhythm, bpm: 80),
          ],
        ),
        tts: TtsService(),
        beep: _TrackingBeepEngine(),
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: punishments,
        phraseBank: const PhraseBank(byMode: {}, congrats: [], intros: []),
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );

  const carriedSuite = Session(
    id: 'suite',
    name: 'suite',
    description: '',
    durationSeconds: 60,
    defaultMode: SessionMode.rhythm,
    postureChanges: [
      PostureChange(time: 1, pose: Posture.sitting),
    ],
    steps: [
      SessionStep(time: 0, text: 'c', mode: SessionMode.rhythm, bpm: 80),
      SessionStep(time: 1, text: 'd', mode: SessionMode.rhythm, bpm: 80),
    ],
  );

  Future<SessionController> playedChangeController() async {
    final ctrl = buildPlayedChangeController();
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.currentPose, Posture.kneeling);
    expect(ctrl.unplayedPostureScript.changes, isEmpty);
    ctrl.confirmPostureReady();
    return ctrl;
  }

  test(
      'requestUpgrade : le changement reporté se joue malgré un changement '
      'déjà joué', () async {
    final ctrl = await playedChangeController();
    await ctrl.requestUpgrade(
      insistentBeg: const SessionStep(
        time: 0,
        text: 'beg',
        mode: SessionMode.rhythm,
        bpm: 80,
        duration: 1,
      ),
      upcomingSession: carriedSuite,
    );
    expect(ctrl.unplayedPostureScript.changes.map((c) => c.pose),
        [Posture.sitting]);
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    expect(ctrl.currentPose, Posture.sitting);
    ctrl.dispose();
  });

  test(
      'requestPostChallengeRegen : le changement reporté reste à venir '
      'malgré un changement déjà joué', () async {
    final ctrl = await playedChangeController();
    await ctrl.requestPostChallengeRegen(upcomingSession: carriedSuite);
    expect(ctrl.unplayedPostureScript.changes.map((c) => c.pose),
        [Posture.sitting]);
    ctrl.dispose();
  });

  test('avant toute pause : tout est à venir', () async {
    final ctrl = buildController(_TrackingBeepEngine());
    await ctrl.start();
    final script = ctrl.unplayedPostureScript;
    expect(script.breaks.length, 3);
    expect(script.changes.length, 1);
    expect(ctrl.pauseSecondsAhead, 152);
    ctrl.dispose();
  });

  test('pause en cours : ni comptée parmi les restantes, ni oubliée', () async {
    final ctrl = buildController(_TrackingBeepEngine());
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.breakActive, isTrue);
    final script = ctrl.unplayedPostureScript;
    expect(script.breaks.map((b) => b.time), [30, 120]);
    expect(script.changes.single.time, 60);
    // 150 s de pauses à venir + le reste de la pause active (1 ou 2 s).
    expect(ctrl.pauseSecondsAhead, inInclusiveRange(151, 152));
    ctrl.dispose();
  });
}

class _TrackingBeepEngine extends BeepEngine {
  int pauseCalls = 0;
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
