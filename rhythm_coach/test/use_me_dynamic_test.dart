import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/stats_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// « Utilise-moi » dynamique : un FAIL pendant le mode y met fin, la séance
/// normale reprend pour le temps restant, le bouton se rouvre de plus en plus
/// tard et la durée tenue entre dans les stats.
///
/// Tests en temps réel (le `Stopwatch` du controller n'est pas simulé) : le
/// temps joué est avancé par `debugAddPlayed`, le flow fail dure ≈ 5 s.
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
    SharedPreferences.setMockInitialValues({});
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

  SessionController buildController(_RecordingBeepEngine beep) =>
      SessionController(
        staminaProfile: List<double>.filled(300, 100),
        session: const Session(
          id: 'use-me-dyn',
          name: 'use-me-dyn',
          description: '',
          durationSeconds: 120,
          defaultMode: SessionMode.rhythm,
          steps: [
            SessionStep(
                time: 0, text: 'debut', mode: SessionMode.rhythm, bpm: 80),
            SessionStep(
                time: 100, text: 'suite', mode: SessionMode.rhythm, bpm: 90),
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

  /// Suite « Utilise-moi » : rhythm seul à 280 BPM, jusqu'à la durée choisie.
  Session useMeSuite(SessionController c) => Session(
        id: 'use-me-suite',
        name: 'use-me-suite',
        description: '',
        durationSeconds: c.session.durationSeconds - c.elapsedSeconds - 2,
        defaultMode: SessionMode.rhythm,
        steps: const [
          SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 280),
        ],
      );

  /// Reste de séance normal : rhythm à 90 BPM puis un breath.
  Session normalRemainder(SessionController c) => Session(
        id: 'normal-remainder',
        name: 'normal-remainder',
        description: '',
        durationSeconds: c.session.durationSeconds - c.elapsedSeconds,
        defaultMode: SessionMode.rhythm,
        steps: const [
          SessionStep(
              time: 0, text: 'retour', mode: SessionMode.rhythm, bpm: 90),
          SessionStep(time: 20, mode: SessionMode.breath, duration: 5),
        ],
      );

  Future<void> enterUseMe(SessionController ctrl) => ctrl.requestUpgrade(
        insistentBeg: const SessionStep(
            time: 0, text: 'supplie', mode: SessionMode.beg, duration: 2),
        upcomingSession: useMeSuite(ctrl),
        useMe: true,
      );

  test('un FAIL en « Utilise-moi » ramène la séance normale, durée tenue',
      () async {
    final beep = _RecordingBeepEngine();
    final ctrl = buildController(beep);
    var hookCalls = 0;
    int? remainingAtHook;
    ctrl.onUseMeEnded = (c) async {
      hookCalls++;
      remainingAtHook = c.session.durationSeconds - c.elapsedSeconds;
      return normalRemainder(c);
    };
    await ctrl.start();
    await enterUseMe(ctrl);
    expect(ctrl.useMeActive, isTrue);
    expect(
        ctrl.session.steps.every((s) => (s.bpm ?? 0) >= 200 || s.bpm == null),
        isTrue,
        reason: 'la suite d\'« Utilise-moi » est bien en place avant le FAIL');

    // Le temps réel doit passer : le 1ᵉʳ step d'escalade (t+2 s) est joué, et
    // `elapsedSeconds` n'est plus nul au FAIL.
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    ctrl.debugAddPlayed(const Duration(seconds: 30));
    int escalated() => beep.appliedSteps.where((s) => s.bpm == 280).length;
    final escalatedBefore = escalated();
    expect(escalatedBefore, greaterThan(0), reason: 'sonde non vide');
    await ctrl.triggerFail();

    expect(hookCalls, 1);
    expect(escalated(), escalatedBefore,
        reason: 'la boucle d\'escalade n\'est pas rejouée à la sortie du flow');
    expect(ctrl.useMeActive, isFalse, reason: 'le FAIL met fin au mode');
    final normal = ctrl.session.steps;
    expect(normal.any((s) => s.mode == SessionMode.breath), isTrue,
        reason: 'la séance normale a du repos, pas l\'escalade non-stop');
    expect(normal.every((s) => (s.bpm ?? 0) < 200), isTrue,
        reason: 'plus aucun step d\'escalade (280 BPM) dans la timeline');
    expect(beep.appliedSteps.last.bpm, 90,
        reason: 'le 1ᵉʳ step normal est joué à la sortie du flow, pas sauté '
            'ni remplacé par la boucle d\'escalade');
    expect(ctrl.session.durationSeconds, 120,
        reason: 'la fin tombe à la durée choisie au départ');
    expect(remainingAtHook, ctrl.session.durationSeconds - ctrl.elapsedSeconds,
        reason: 'le temps passé en « Utilise-moi » est déduit : la suite '
            'normale ne couvre que le reste');
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
      'le délai de réouverture passe de 2 à 3 puis 4 min, un FAIL hors mode '
      'ne l\'allonge pas', () async {
    final ctrl = buildController(_RecordingBeepEngine());
    ctrl.onUseMeEnded = (c) async => normalRemainder(c);
    await ctrl.start();

    expect(ctrl.useMeUnlockDelay, const Duration(minutes: 2));
    ctrl.debugAddPlayed(const Duration(minutes: 2));
    expect(ctrl.useMeUnlocked, isTrue);

    await ctrl.triggerFail();
    expect(ctrl.useMeUnlocked, isFalse, reason: 'le FAIL remet le compteur');
    expect(ctrl.useMeUnlockDelay, const Duration(minutes: 2),
        reason: 'un FAIL hors « Utilise-moi » n\'allonge pas le délai');

    await enterUseMe(ctrl);
    await ctrl.triggerFail();
    expect(ctrl.useMeUnlockDelay, const Duration(minutes: 3));
    ctrl.debugAddPlayed(const Duration(minutes: 2, seconds: 59));
    expect(ctrl.useMeUnlocked, isFalse, reason: '2 min 59 < 3 min');
    ctrl.debugAddPlayed(const Duration(seconds: 2));
    expect(ctrl.useMeUnlocked, isTrue);

    await enterUseMe(ctrl);
    await ctrl.triggerFail();
    expect(ctrl.useMeUnlockDelay, const Duration(minutes: 4));
    ctrl.debugAddPlayed(const Duration(minutes: 3, seconds: 59));
    expect(ctrl.useMeUnlocked, isFalse);
    ctrl.debugAddPlayed(const Duration(seconds: 2));
    expect(ctrl.useMeUnlocked, isTrue);
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
      'une mini-punition n\'est pas un FAIL : compteur, mode et délai '
      'intacts', () async {
    final ctrl = buildController(_RecordingBeepEngine());
    var hookCalls = 0;
    ctrl.onUseMeEnded = (c) async {
      hookCalls++;
      return normalRemainder(c);
    };
    await ctrl.start();
    ctrl.debugAddPlayed(const Duration(minutes: 2));
    expect(ctrl.useMeUnlocked, isTrue);

    await ctrl.debugRunMiniPunishment(miniPunishment);
    expect(ctrl.useMeUnlocked, isTrue,
        reason: 'la mini-punition ne remet pas le compteur à zéro');

    await enterUseMe(ctrl);
    await ctrl.debugRunMiniPunishment(miniPunishment);
    expect(ctrl.useMeActive, isTrue, reason: 'elle ne met pas fin au mode');
    expect(hookCalls, 0);
    expect(ctrl.useMeUnlockDelay, const Duration(minutes: 2));
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
      'la durée tenue en « Utilise-moi » est un record de stats, rien hors '
      'du mode', () async {
    final ctrl = buildController(_RecordingBeepEngine());
    ctrl.onUseMeEnded = (c) async => normalRemainder(c);
    await ctrl.start();

    ctrl.debugAddPlayed(const Duration(seconds: 30));
    await ctrl.triggerFail();
    expect((await StatsService().snapshot()).maxUseMeSec, 0,
        reason: 'un FAIL hors « Utilise-moi » n\'écrit rien');

    await enterUseMe(ctrl);
    ctrl.debugAddPlayed(const Duration(seconds: 90));
    await ctrl.triggerFail();
    expect((await StatsService().snapshot()).maxUseMeSec, 90);

    await enterUseMe(ctrl);
    ctrl.debugAddPlayed(const Duration(seconds: 40));
    await ctrl.triggerFail();
    expect((await StatsService().snapshot()).maxUseMeSec, 90,
        reason: 'record : une tenue plus courte ne l\'écrase pas');
    await ctrl.stop();
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
