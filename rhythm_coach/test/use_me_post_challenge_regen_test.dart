import 'dart:async';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/main.dart' show milestoneService;
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'capability_use_me_bench.dart';

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
    SharedPreferences.setMockInitialValues(
        {...benchPrefsSeed(), 'cap.use_me_held_migrated': true});
    milestoneService.seedForTest(catalog: [
      const LevelMilestone(
        id: 'm_beg',
        humilRequired: 0,
        displayLabel: 'm_beg',
        sequence: [],
        durationSeconds: 1,
        unlocks: [UnlockKey.begLibre],
      ),
    ], completed: {
      'm_beg'
    });
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

  const punishments = PunishmentBundle(
    failPhrases: ['tu craques'],
    punishments: [
      Punishment(
        id: 'mini',
        name: 'mini',
        durationSeconds: 1,
        steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
      ),
    ],
  );

  const normalStep = SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 120);
  const regenStep = SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 110);
  const useMeStep = SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 280);

  const challenge = Challenge(
    axis: CapabilityAxis.holdThroatStreak,
    kind: ChallengeAxisKind.duration,
    targetThreshold: 5,
    mode: SessionMode.hold,
    from: Position.throat,
    to: Position.throat,
  );

  // `unlockedKeys` vide alors que milestoneService porte begLibre : le défi
  // passé élargit les unlocks, donc le vrai `_finalizeChallengeAcquittals`
  // appelle `onPostChallengeRegen`.
  SessionController build(_RecordingBeepEngine beep) => SessionController(
        staminaProfile: List<double>.filled(300, 100),
        session: Session(
          id: 'useme-regen',
          name: 'useme-regen',
          description: '',
          durationSeconds: 20,
          defaultMode: SessionMode.rhythm,
          steps: const [normalStep],
          challenges: const [challenge],
          challengeTriggerTimes: const [1],
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
        trackCapabilities: true,
        careerLevel: 10,
        unlockedKeys: const {},
      );

  Future<void> pressUseMe(SessionController c) => c.requestUpgrade(
        insistentBeg: const SessionStep(
            time: 0, text: 'supplie', mode: SessionMode.beg, duration: 2),
        upcomingSession: Session(
          id: 'use-me-suite',
          name: 'use-me-suite',
          description: '',
          durationSeconds: c.session.durationSeconds - c.elapsedSeconds - 2,
          defaultMode: SessionMode.rhythm,
          steps: const [useMeStep],
        ),
        useMe: true,
      );

  Session regenSuite(SessionController c) => Session(
        id: 'post-challenge-regen',
        name: 'post-challenge-regen',
        description: '',
        durationSeconds: c.session.durationSeconds - c.elapsedSeconds,
        defaultMode: SessionMode.rhythm,
        steps: const [regenStep],
      );

  Future<void> until(bool Function() cond, {required int maxMs}) async {
    for (var i = 0; i < maxMs ~/ 100 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Arme le défi, le passe, et tient la régénération post-défi en vol
  /// jusqu'à ce que [release] soit complété.
  Future<SessionController> passChallengeWithRegenHeld(
    _RecordingBeepEngine beep,
    Completer<void> release,
  ) async {
    final ctrl = build(beep);
    beep.useMeActive = () => ctrl.useMeActive;
    var regenCalls = 0;
    ctrl.onPostChallengeRegen = (c) async {
      regenCalls++;
      await release.future;
      await c.requestPostChallengeRegen(upcomingSession: regenSuite(c));
    };
    ctrl.onUseMeEnded = (c) async => regenSuite(c);
    await ctrl.start();
    await until(() => ctrl.isChallengeActive, maxMs: 5000);
    expect(ctrl.isChallengeActive, isTrue, reason: 'défi armé');
    ctrl.triggerChallengePass();
    await until(() => regenCalls == 1, maxMs: 2000);
    expect(regenCalls, 1, reason: 'la régénération post-défi est en vol');
    expect(ctrl.isChallengeActive, isFalse,
        reason: 'le bouton « Utilise-moi » est de nouveau rendu');
    expect(ctrl.state, SessionState.running);
    return ctrl;
  }

  test(
      'appui « Utilise-moi » pendant la régénération post-défi : l\'escalade '
      'reste installée et aucun step normal ne joue sous le drapeau', () async {
    final beep = _RecordingBeepEngine();
    final release = Completer<void>();
    final ctrl = await passChallengeWithRegenHeld(beep, release);

    await pressUseMe(ctrl);
    expect(ctrl.useMeActive, isTrue);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ctrl.session.steps.where((s) => s.useMe), isNotEmpty,
        reason: 'la régénération post-défi ne remplace pas l\'escalade');
    expect(ctrl.session.steps.where((s) => s.bpm == regenStep.bpm), isEmpty);

    await until(() => ctrl.state == SessionState.finished, maxMs: 40000);
    expect(ctrl.state, SessionState.finished);
    final underFlag = beep.applied.where((a) => a.useMeActive).toList();
    expect(underFlag.map((a) => a.step.mode),
        containsAllInOrder([SessionMode.beg, SessionMode.rhythm]),
        reason: 'sonde non vide : le beg puis l\'escalade ont joué');
    expect(underFlag.where((a) => !a.step.useMe), isEmpty,
        reason: 'temps compté « Utilise-moi » = steps « Utilise-moi » seuls');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('sans appui, la régénération post-défi s\'installe', () async {
    final beep = _RecordingBeepEngine();
    final release = Completer<void>();
    final ctrl = await passChallengeWithRegenHeld(beep, release);

    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ctrl.useMeActive, isFalse);
    expect(ctrl.session.steps.map((s) => s.bpm), contains(regenStep.bpm));
    expect(
        ctrl.session.steps.map((s) => s.bpm), isNot(contains(normalStep.bpm)));
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));
}

class _AppliedStep {
  final SessionStep step;
  final bool useMeActive;
  const _AppliedStep(this.step, this.useMeActive);
}

class _RecordingBeepEngine extends BeepEngine {
  final List<_AppliedStep> applied = [];
  bool Function() useMeActive = () => false;

  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    applied.add(_AppliedStep(step, useMeActive()));
  }

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
