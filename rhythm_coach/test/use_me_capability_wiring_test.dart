import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
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
    SharedPreferences.setMockInitialValues(benchPrefsSeed());
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

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(benchPrefsSeed());
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

  const throatStep = SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 120);
  const useMeStep = SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 280);

  SessionController buildController(_RecordingBeepEngine beep, int duration) =>
      SessionController(
        staminaProfile: List<double>.filled(300, 100),
        session: Session(
          id: 'use-me-wiring',
          name: 'use-me-wiring',
          description: '',
          durationSeconds: duration,
          defaultMode: SessionMode.rhythm,
          steps: const [throatStep],
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
      );

  const nextUseMeStep = SessionStep(
      time: 3,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 290);

  Future<void> enterUseMe(SessionController c,
          {List<SessionStep> steps = const [useMeStep]}) =>
      c.requestUpgrade(
        insistentBeg: const SessionStep(
            time: 0, text: 'supplie', mode: SessionMode.beg, duration: 2),
        upcomingSession: Session(
          id: 'use-me-suite',
          name: 'use-me-suite',
          description: '',
          durationSeconds: c.session.durationSeconds - c.elapsedSeconds - 2,
          defaultMode: SessionMode.rhythm,
          steps: steps,
        ),
        useMe: true,
      );

  Session normalRemainder(SessionController c) => Session(
        id: 'normal-remainder',
        name: 'normal-remainder',
        description: '',
        durationSeconds: c.session.durationSeconds - c.elapsedSeconds,
        defaultMode: SessionMode.rhythm,
        steps: const [throatStep],
      );

  Future<void> untilFinished(SessionController c) async {
    for (var i = 0; i < 400 && c.state != SessionState.finished; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(c.state, SessionState.finished, reason: 'la séance va à son terme');
  }

  test('T6a témoin : un FAIL en rythme normal fige bien un plafond', () async {
    final ctrl = buildController(_RecordingBeepEngine(), 60);
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    await ctrl.triggerFail();
    expect(ctrl.capabilitySessionCeilings,
        containsPair(CapabilityAxis.rhythmBpmCeilThroat, 120.0));
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('T6b requestUpgrade(useMe) puis FAIL : aucun plafond de capacité',
      () async {
    final beep = _RecordingBeepEngine();
    final ctrl = buildController(beep, 120);
    ctrl.onUseMeEnded = (c) async => normalRemainder(c);
    await ctrl.start();
    await enterUseMe(ctrl);
    await Future<void>.delayed(const Duration(milliseconds: 3600));
    expect(beep.appliedSteps.where((s) => s.bpm == 280), isNotEmpty,
        reason: 'sonde non vide : le step 280 BPM est en cours au FAIL');
    await ctrl.triggerFail();
    expect(ctrl.capabilitySessionCeilings, isEmpty);
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('T5 tenue « Utilise-moi » sans FAIL : useMe.held_streak dans le profil',
      () async {
    // Amorçage déjà fait : sinon `stats.max_use_me_sec` remplirait l'axe seul.
    SharedPreferences.setMockInitialValues(
        {...benchPrefsSeed(), 'cap.use_me_held_migrated': true});
    final ctrl = buildController(_RecordingBeepEngine(), 9);
    await ctrl.start();
    await enterUseMe(ctrl);
    await untilFinished(ctrl);
    final after = await CapabilityService().snapshotProfile();
    expect(
        after.bestOf(CapabilityAxis.useMeHeldStreak), greaterThanOrEqualTo(6),
        reason: 'la tenue sans FAIL entre dans le rapport avant le commit');
    expect(after.bestOf(CapabilityAxis.rhythmBpmCeilThroat), 105);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
      'T6c FAIL sans suite normale (hook null) : la boucle 280 BPM rejouée '
      'après le FAIL n\'ajoute rien au gain', () async {
    final beep = _RecordingBeepEngine();
    final ctrl = buildController(beep, 10);
    ctrl.onUseMeEnded = (c) async => null;
    await ctrl.start();
    await enterUseMe(ctrl);
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    final before = beep.appliedSteps.where((s) => s.bpm == 280).length;
    await ctrl.triggerFail();
    await untilFinished(ctrl);
    expect(beep.appliedSteps.where((s) => s.bpm == 280).length,
        greaterThan(before),
        reason: 'sonde non vide : la boucle 280 BPM a bien été rejouée');
    final after = await CapabilityService().snapshotProfile();
    expect(after.bestOf(CapabilityAxis.rhythmBpmCeilThroat), 105,
        reason: 'le best normal ne prend pas le 280 BPM rejoué');
    expect(after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        inInclusiveRange(100, 100.1),
        reason: 'à peine 3 s tenues avant le FAIL (+0,05 %) : les ~7 s '
            'rejouées après le FAIL, comptées, donneraient plus de +0,15 %');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('T6d pause pendant « Utilise-moi » : le temps en pause ne compte pas',
      () async {
    final ctrl = buildController(_RecordingBeepEngine(), 8);
    await ctrl.start();
    await enterUseMe(ctrl);
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    await ctrl.pause();
    await Future<void>.delayed(const Duration(seconds: 4));
    await ctrl.resume();
    await untilFinished(ctrl);
    final after = await CapabilityService().snapshotProfile();
    expect(after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        inInclusiveRange(100, 100.17),
        reason: '8 s de séance = au plus +0,13 % ; les 4 s de pause comptées '
            'feraient +0,2 %');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
      'T6e ~2 min 30 en « Utilise-moi » sans FAIL : le confort BPM monte '
      'd\'environ +2,5 %', () async {
    final ctrl = buildController(_RecordingBeepEngine(), 152);
    await ctrl.start();
    await enterUseMe(ctrl);
    for (var i = 0; i < 1700 && ctrl.state != SessionState.finished; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(ctrl.state, SessionState.finished,
        reason: 'la séance va à son terme');
    final after = await CapabilityService().snapshotProfile();
    expect(after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        inInclusiveRange(102.2, 102.6),
        reason: '~150 s tenues sur 300 s = la moitié de +5 % ; un gain jamais '
            'accordé laisserait 100');
  }, timeout: const Timeout(Duration(seconds: 220)));

  test(
      'T10 FAIL sans suite normale (hook null) : les steps d\'escalade qui '
      'restent ne s\'écrivent pas dans le profil normal', () async {
    final beep = _RecordingBeepEngine();
    final ctrl = buildController(beep, 10);
    ctrl.onUseMeEnded = (c) async => null;
    await ctrl.start();
    await enterUseMe(ctrl, steps: const [useMeStep, nextUseMeStep]);
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    expect(beep.appliedSteps.where((s) => s.bpm == 290), isEmpty,
        reason: 'le step 290 BPM n\'est pas encore arrivé au FAIL');
    await ctrl.triggerFail();
    await untilFinished(ctrl);
    expect(beep.appliedSteps.where((s) => s.bpm == 290), isNotEmpty,
        reason:
            'sonde non vide : le step 290 BPM a été appliqué après le FAIL');
    final after = await CapabilityService().snapshotProfile();
    expect(after.bestOf(CapabilityAxis.rhythmBpmCeilThroat), 105);
    expect(after.bestOf(CapabilityAxis.gorgeCrossingsBpmThroat), 100);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

class _RecordingBeepEngine extends BeepEngine {
  final List<SessionStep> appliedSteps = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    appliedSteps.add(step);
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
