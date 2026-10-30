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

  const bank = PhraseBank(
    byMode: {},
    congrats: [],
    intros: [],
    breakEntry: [PhraseEntry(text: 'phrase-entree')],
    breakResume: [PhraseEntry(text: 'phrase-reprise')],
    breakPostureChange: {
      Posture.kneeling: [PhraseEntry(text: 'phrase-genoux')],
    },
  );

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

  // Pause [1, 1 + durée) puis le step d'effort que le générateur pose toujours
  // juste après le trou.
  SessionController buildController({
    required BeepEngine beep,
    required int breakSeconds,
    Posture? newPose,
    Posture initialPose = Posture.free,
  }) =>
      SessionController(
        staminaProfile: List<double>.filled(120, 100),
        session: Session(
          id: 'pose-au-debut',
          name: 'pose-au-debut',
          description: '',
          durationSeconds: 60,
          defaultMode: SessionMode.rhythm,
          initialPose: initialPose,
          breaks: [
            ScriptedBreak(
              time: 1,
              durationSeconds: breakSeconds,
              newPose: newPose,
            ),
          ],
          steps: [
            const SessionStep(
                time: 0, text: 'debut', mode: SessionMode.rhythm, bpm: 80),
            SessionStep(
                time: 1 + breakSeconds,
                text: 'apres-pause',
                mode: SessionMode.rhythm,
                bpm: 90),
          ],
        ),
        tts: TtsService(),
        beep: beep,
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: punishments,
        phraseBank: bank,
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );

  Future<void> settle(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test(
      'une pause qui change de position l\'annonce dès son entrée : pose '
      'posée, phrase de pose seule, bip coupé, horloge gelée jusqu\'à la '
      'mise en place', () async {
    final beep = _TrackingBeepEngine();
    final ctrl = buildController(
      beep: beep,
      breakSeconds: 2,
      newPose: Posture.kneeling,
    );
    await ctrl.start();
    await settle(1600);

    expect(ctrl.breakActive, isTrue);
    expect(ctrl.currentPose, Posture.kneeling,
        reason: 'la pose est annoncée et posée au début de la pause');
    expect(ctrl.awaitingPostureReady, isTrue,
        reason: 'la mise en place est attendue avant que la pause ne court');
    expect(beep.pauseCalls, greaterThanOrEqualTo(1));
    expect(spoken, contains('phrase-genoux'));
    expect(spoken, isNot(contains('phrase-entree')),
        reason: 'une seule phrase : la 2e couperait la 1re');

    final frozenAt = ctrl.elapsedSeconds;
    await settle(1200);
    expect(ctrl.elapsedSeconds, lessThanOrEqualTo(frozenAt),
        reason: 'la pause ne court pas pendant la mise en place');
    expect(ctrl.breakActive, isTrue);

    ctrl.confirmPostureReady();
    await settle(2600);

    expect(ctrl.breakActive, isFalse, reason: 'la pause court puis finit');
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'rien à valider à la sortie : la joueuse est déjà en place');
    expect(beep.appliedSteps.map((s) => s.text), contains('apres-pause'),
        reason: 'l\'effort reprend à la fin de la pause');
    expect(spoken, contains('phrase-reprise'));
    expect(spoken.where((s) => s == 'phrase-genoux'), hasLength(1),
        reason: 'la pose n\'est pas annoncée une 2e fois à la sortie');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('passer la pause pendant la mise en place garde l\'attente', () async {
    final ctrl = buildController(
      beep: _TrackingBeepEngine(),
      breakSeconds: 29,
      newPose: Posture.kneeling,
    );
    await ctrl.start();
    await settle(1600);
    expect(ctrl.awaitingPostureReady, isTrue);

    ctrl.skipBreak();

    expect(ctrl.breakActive, isFalse);
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(30));
    expect(ctrl.awaitingPostureReady, isTrue,
        reason: 'sauter la pause ne dispense pas de se mettre en place');
    expect(ctrl.currentPose, Posture.kneeling);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('passer la pause une fois en place n\'attend plus rien', () async {
    final ctrl = buildController(
      beep: _TrackingBeepEngine(),
      breakSeconds: 29,
      newPose: Posture.kneeling,
    );
    await ctrl.start();
    await settle(1600);
    ctrl.confirmPostureReady();

    ctrl.skipBreak();

    expect(ctrl.breakActive, isFalse);
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'la joueuse est déjà en place');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('une pause sans changement de position n\'attend rien', () async {
    final beep = _TrackingBeepEngine();
    final ctrl = buildController(beep: beep, breakSeconds: 2);
    await ctrl.start();
    await settle(1600);

    expect(ctrl.breakActive, isTrue);
    expect(ctrl.awaitingPostureReady, isFalse);
    expect(ctrl.currentPose, Posture.free);
    expect(spoken, contains('phrase-entree'));

    await settle(2400);
    expect(ctrl.breakActive, isFalse);
    expect(ctrl.awaitingPostureReady, isFalse);
    expect(spoken, contains('phrase-reprise'));
    expect(beep.appliedSteps.map((s) => s.text), contains('apres-pause'));

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('une pause qui rend la position libre l\'applique sans attente',
      () async {
    final ctrl = buildController(
      beep: _TrackingBeepEngine(),
      breakSeconds: 2,
      newPose: Posture.free,
      initialPose: Posture.kneeling,
    );
    await ctrl.start();
    expect(ctrl.currentPose, Posture.kneeling);
    await settle(1600);

    expect(ctrl.breakActive, isTrue);
    expect(ctrl.currentPose, Posture.free,
        reason: 'la libération est annoncée dès le début de la pause');
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: '`free` : aucun repositionnement à valider');
    expect(spoken, contains('phrase-entree'),
        reason: 'pas de phrase de pose pour `free` : l\'entrée neutre parle');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));
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
