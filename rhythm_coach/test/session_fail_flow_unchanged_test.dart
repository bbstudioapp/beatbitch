import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
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

/// Caractérise le flow « JE PEUX PAS » d'une séance **sans morceau** : c'est le
/// comportement que la séance musicale ne doit pas toucher. Le test est écrit
/// et vert avant toute modification de `lib/` pour la séance musicale ; il doit
/// le rester.
///
/// Temps réel (le `Stopwatch` du controller n'est pas simulé) : la respiration
/// tirée dans sa fourchette courte (profil de stamina plein) domine, ~4 s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
  final spoken = <String>[];

  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  void installFakeTtsEngine() {
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
    spoken.clear();
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

  const session = Session(
    id: 'fail-unchanged',
    name: 'fail-unchanged',
    description: '',
    durationSeconds: 60,
    defaultMode: SessionMode.rhythm,
    steps: [
      SessionStep(time: 0, text: 'debut', mode: SessionMode.rhythm, bpm: 80),
      SessionStep(
          time: 30,
          text: 'section suivante',
          mode: SessionMode.rhythm,
          bpm: 100),
    ],
  );

  SessionController build(_TrackingBeepEngine beep,
          {PunishmentBundle bundle = punishments}) =>
      SessionController(
        staminaProfile: List<double>.filled(120, 100),
        session: session,
        tts: TtsService(),
        beep: beep,
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: bundle,
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );

  test(
      'séance sans morceau : phrase → respiration → punition, horloge figée, '
      'saut à la section suivante', () async {
    final beep = _TrackingBeepEngine();
    final ctrl = build(beep);
    final seen = <(SessionState, FailPhase?)>[];
    ctrl.addListener(() {
      final entry = (ctrl.state, ctrl.failPhase);
      if (seen.isEmpty || seen.last != entry) seen.add(entry);
    });

    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(ctrl.canTriggerFail, isTrue);
    expect(ctrl.elapsedSeconds, lessThan(2));

    final failing = ctrl.triggerFail();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(ctrl.state, SessionState.failing);
    final frozenAt = ctrl.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(ctrl.elapsed, frozenAt,
        reason: 'pendant le flow fail le chronomètre de séance est arrêté');

    await failing;

    expect(
      seen.where((e) => e.$1 == SessionState.failing).map((e) => e.$2),
      containsAllInOrder([
        FailPhase.phrase,
        FailPhase.breath,
        FailPhase.punishment,
      ]),
    );
    expect(ctrl.state, SessionState.running);
    expect(ctrl.hadFailThisSession, isTrue);
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(30),
        reason: 'saut de section : la timeline rejoint le prochain step de '
            'config au lieu de reprendre là où on s\'était arrêté');
    expect(beep.pauseCalls, greaterThanOrEqualTo(1));
    expect(
      beep.appliedSteps.where((s) => s.mode == SessionMode.breath),
      isNotEmpty,
      reason: 'la respiration passe par le BeepEngine',
    );
    expect(spoken.where((s) => s.contains('tu craques')), isNotEmpty,
        reason: 'la phrase de fail est prononcée');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('le bouton FAIL reste inactif quand aucune punition n\'est chargée',
      () async {
    final beep = _TrackingBeepEngine();
    final ctrl = build(beep,
        bundle: const PunishmentBundle(failPhrases: [], punishments: []));
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(ctrl.canTriggerFail, isFalse);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));
}

class _TrackingBeepEngine extends BeepEngine {
  int pauseCalls = 0;
  final List<SessionStep> appliedSteps = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
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
