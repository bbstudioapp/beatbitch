import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
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

Challenge _noswallow({required int threshold}) => Challenge(
      axis: CapabilityAxis.noswallowStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: threshold,
      mode: SessionMode.beg,
      comfortAtCalibration: 30.0,
    );

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
    for (final name in wakelockChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(name, null);
    }
  });

  Future<SessionController> startLive(Challenge challenge) async {
    final ctrl = _buildController(challenge);
    await ctrl.start();
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
    ctrl.onChallengeTapGo();
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.live);
    expect(ctrl.challengePhase, ChallengePhase.live);
    return ctrl;
  }

  test(
      'abandon d\'un défi « sans avaler » : noswallow accusé seul, '
      'à hauteur des secondes tenues', () async {
    final ctrl = await startLive(_noswallow(threshold: 40));
    expect(ctrl.swallowMode, SwallowMode.forbidden);

    await Future<void>.delayed(const Duration(seconds: 5));
    ctrl.onChallengeTapStop();
    expect(ctrl.challengeOutcome, ChallengeOutcome.fail);

    final ceilings = ctrl.capabilitySessionCeilings;
    expect(ceilings[CapabilityAxis.noswallowStreak], inInclusiveRange(4, 6),
        reason: 'plafonds figés à l\'abandon : $ceilings');
    expect(
      CapabilityRegulator.failAccused(ceilings, const CapabilityProfile({})),
      {CapabilityAxis.noswallowStreak},
    );
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('défi « sans avaler » validé au seuil : rien d\'accusé', () async {
    final ctrl = await startLive(_noswallow(threshold: 3));
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.atSeuil,
        timeout: const Duration(seconds: 10));
    expect(ctrl.challengePhase, ChallengePhase.atSeuil);
    ctrl.onChallengeTapStop();
    expect(ctrl.challengeOutcome, ChallengeOutcome.netSuccess);

    expect(ctrl.capabilitySessionCeilings, isEmpty);
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('abandon d\'un défi d\'un autre axe : noswallow non accusé', () async {
    final ctrl = await startLive(const Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 40,
      mode: SessionMode.hold,
      comfortAtCalibration: 30.0,
    ));
    expect(ctrl.swallowMode, SwallowMode.allowed);

    await Future<void>.delayed(const Duration(seconds: 5));
    ctrl.onChallengeTapStop();
    expect(ctrl.challengeOutcome, ChallengeOutcome.fail);

    expect(ctrl.capabilitySessionCeilings,
        isNot(contains(CapabilityAxis.noswallowStreak)));
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 90)));
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

SessionController _buildController(Challenge challenge) {
  return SessionController(
    session: Session(
      id: 'noswallow-abandon',
      name: 'noswallow-abandon',
      description: '',
      durationSeconds: 120,
      defaultMode: SessionMode.rhythm,
      steps: const [
        SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.mid,
          bpm: 40,
          duration: 3,
        ),
        SessionStep(time: 3, mode: SessionMode.breath, duration: 13),
        SessionStep(
          time: 21,
          mode: SessionMode.rhythm,
          from: Position.mid,
          to: Position.full,
          bpm: 50,
          duration: 99,
        ),
      ],
      challenges: [challenge],
      challengeTriggerTimes: const [3],
    ),
    tts: TtsService(),
    beep: BeepEngine(),
    ambience: _SilentAmbienceEngine(),
    punishmentBundle: const PunishmentBundle(
      failPhrases: ['tu craques'],
      punishments: [
        Punishment(id: 'p1', name: 'p1', durationSeconds: 0, steps: []),
      ],
    ),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
    trackCapabilities: true,
  );
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
