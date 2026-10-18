import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pendant un défi en direct, le fond suit ce qui est joué : les segments du
/// défi ne passent pas par les steps de la séance, la timeline étant gelée.
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
    BackgroundsService.instance.debugResetForTest();
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

  test('le défi en direct joue le fond du mode du segment, pas celui du breath',
      () async {
    _installBackgrounds(const [
      'fond-respire_lina_breath',
      'fond-tenue_lina_hold',
      'fond-tenue-helene_helene_hold',
    ]);
    final ctrl = _buildController();
    await ctrl.start();

    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
    expect(_fond(), 'fond-respire', reason: 'le déclencheur est un breath');

    ctrl.onChallengeHoldStart();
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.live);
    expect(_fond(), 'fond-tenue',
        reason: 'le défi tient : fond du hold de la coach, pas le breath');

    ctrl.onChallengeTapStop();
    expect(ctrl.challengePhase, ChallengePhase.ended);
    expect(_fond(), 'fond-respire',
        reason: 'le breath de récupération reprend son fond');
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('un fond « challenge » de la coach prime sur celui du mode joué',
      () async {
    _installBackgrounds(const [
      'fond-respire_lina_breath',
      'fond-tenue_lina_hold',
      'fond-defi_lina_challenge',
      'fond-defi-helene_helene_challenge',
    ]);
    final ctrl = _buildController();
    await ctrl.start();

    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
    expect(_fond(), 'fond-respire');

    ctrl.onChallengeHoldStart();
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.live);
    expect(_fond(), 'fond-defi');

    ctrl.onChallengeTapStop();
    expect(_fond(), 'fond-respire');
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

String? _fond() => BackgroundsService.instance.current.value?.id;

/// Catalogue de test : un nom de fichier par entrée, sans extension.
void _installBackgrounds(List<String> names) {
  BackgroundsService.instance.setBundle(BackgroundsBundle(entries: [
    for (final n in names)
      BackgroundsLoader.parseEntry('assets/backgrounds/$n.webp')!,
  ]));
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

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition non atteinte en ${timeout.inSeconds} s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

SessionController _buildController() {
  return SessionController(
    session: const Session(
      id: 'defi',
      name: 'defi',
      description: '',
      durationSeconds: 25,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
        SessionStep(time: 2, mode: SessionMode.breath, duration: 13),
        SessionStep(time: 20, mode: SessionMode.rhythm, bpm: 40, duration: 5),
      ],
      challenges: [_challenge],
      challengeTriggerTimes: [2],
    ),
    tts: TtsService(),
    beep: _SilentBeepEngine(),
    ambience: _SilentAmbienceEngine(),
    coachTag: 'lina',
    punishmentBundle: const PunishmentBundle(failPhrases: [], punishments: []),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
  );
}

/// Neutralise le backend audio : `audioplayers` n'a pas d'implémentation en
/// test.
class _SilentBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(
    SessionStep step,
    SessionMode sessionMode,
  ) async {}
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
