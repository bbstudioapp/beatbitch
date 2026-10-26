import 'package:beat_bitch/career/models/capability_requirement.dart';
import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart'
    show kChallengeBreathDurationSeconds;
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/main.dart' show milestoneService;
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bodyId = 'm_body';
const _defiId = 'm_defi';

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
    milestoneService.seedForTest(catalog: const [
      LevelMilestone(
        id: _bodyId,
        humilRequired: 0,
        displayLabel: _bodyId,
        sequence: [],
        durationSeconds: 3,
        unlocks: [UnlockKey.sloppyDroolBasic],
      ),
      LevelMilestone(
        id: _defiId,
        humilRequired: 0,
        displayLabel: _defiId,
        sequence: [],
        durationSeconds: 1,
        unlocks: [UnlockKey.holdHead],
        acquittableByCapability: [
          CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 5.0),
        ],
      ),
    ]);
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

  test('sans régénération, le jalon joué avant le défi est acquitté', () async {
    final ctrl = _buildController();
    await _playToEnd(ctrl);

    expect(milestoneService.isCompleted(_defiId), isTrue,
        reason: 'le défi réussi doit acquitter le jalon de capacité');
    expect(milestoneService.isCompleted(_bodyId), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
      'après une régénération post-défi, le jalon joué avant le défi '
      'est acquitté à la fin de séance', () async {
    final ctrl = _buildController();
    var regens = 0;
    ctrl.onPostChallengeRegen = (c) async {
      regens++;
      await c.requestPostChallengeRegen(upcomingSession: _upcoming);
    };
    await _playToEnd(ctrl);

    expect(regens, 1, reason: 'la régénération post-défi doit avoir tourné');
    expect(ctrl.session.id, endsWith(':postchallenge'));
    expect(milestoneService.isCompleted(_defiId), isTrue,
        reason: 'le défi réussi doit acquitter le jalon de capacité');
    expect(milestoneService.isCompleted(_bodyId), isTrue,
        reason: 'jalon joué en [0, 3 s) avant le défi, perdu par la '
            'séance régénérée : il ne sera jamais acquitté');
  }, timeout: const Timeout(Duration(seconds: 90)));
}

Future<void> _playToEnd(SessionController ctrl) async {
  await ctrl.start();
  await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
  expect(ctrl.challengePhase, ChallengePhase.breath);
  ctrl.onChallengeHoldStart();
  await _waitUntil(() => ctrl.challengePhase == ChallengePhase.atSeuil);
  expect(ctrl.challengePhase, ChallengePhase.atSeuil);
  ctrl.onChallengeHoldEnd();
  await _waitUntil(() => ctrl.state == SessionState.finished,
      timeout: const Duration(seconds: 60));
  expect(ctrl.state, SessionState.finished);
}

const _challenge = Challenge(
  axis: CapabilityAxis.holdThroatStreak,
  kind: ChallengeAxisKind.duration,
  targetThreshold: 5,
  mode: SessionMode.hold,
  from: Position.throat,
  to: Position.throat,
  comfortAtCalibration: 4,
);

const _upcoming = Session(
  id: 'suite',
  name: 'suite',
  description: '',
  durationSeconds: 3,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 3),
  ],
);

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

SessionController _buildController() {
  return SessionController(
    session: const Session(
      id: 'regen-jalon',
      name: 'regen-jalon',
      description: '',
      durationSeconds: 24,
      defaultMode: SessionMode.rhythm,
      noStats: true,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 3),
        SessionStep(time: 3, mode: SessionMode.breath, duration: kTriggerDur),
        SessionStep(time: 21, mode: SessionMode.rhythm, bpm: 40, duration: 3),
      ],
      milestoneId: _bodyId,
      milestoneStartTime: 0,
      milestoneDurationSeconds: 3,
      challenges: [_challenge],
      challengeTriggerTimes: [3],
    ),
    tts: TtsService(),
    beep: _SilentBeepEngine(),
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
    careerLevel: 5,
    capabilityProfile: const CapabilityProfile({}),
  );
}

const kTriggerDur = kChallengeBreathDurationSeconds;

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
