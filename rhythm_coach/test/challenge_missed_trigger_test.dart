import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart'
    show kChallengeBreathDurationSeconds;
import 'package:beat_bitch/controllers/session_controller.dart';
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

/// Un défi ne s'arme que si l'horloge de timeline traverse sa fenêtre
/// `[trigger, trigger + 13 s)` pendant qu'un tick tourne. La reprise après un
/// « je peux pas » saute à la prochaine section (`_skipToNextSection`) : quand
/// le fail tombe pile sur le trigger, ce saut passait par-dessus la fenêtre et
/// le défi disparaissait sans un mot — la joueuse avait demandé N défis, elle
/// en jouait N-1.
///
/// La course est gagnée par construction, pas par chance : Dart est
/// mono-thread, donc une attente active **synchrone** (aucun `await`) ne peut
/// pas être préemptée par le `Timer.periodic` du ticker. Entre l'instant où
/// `elapsedSeconds` franchit le trigger et l'appel à `triggerFail()`, aucun
/// tick n'a pu armer le défi.
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

  test('un fail pile sur le trigger ne fait pas disparaître le défi', () async {
    final applied = <SessionStep>[];
    final ctrl = _buildController(applied);
    await ctrl.start();

    const triggerStart = 3;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (ctrl.elapsedSeconds < triggerStart) {
      if (DateTime.now().isAfter(deadline)) {
        fail('attente active : elapsedSeconds bloqué sous $triggerStart s');
      }
    }
    // Toujours synchrone depuis la sortie de boucle : aucun tick n'a pu
    // s'intercaler, le défi est encore désarmé.
    expect(ctrl.challengePhase, ChallengePhase.none);
    await ctrl.triggerFail();

    // La reprise ne doit pas avoir enjambé la fenêtre d'armement.
    expect(ctrl.elapsedSeconds,
        lessThan(triggerStart + kChallengeBreathDurationSeconds),
        reason: 'la reprise après fail a sauté par-dessus la fenêtre '
            "d'armement : le défi ne pourra plus jamais s'armer");

    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath,
        timeout: const Duration(seconds: 10));
    expect(ctrl.challengePhase, ChallengePhase.breath,
        reason: 'le défi doit être proposé à la joueuse malgré le fail');
    expect(
        applied.any(
            (s) => s.mode == SessionMode.breath && s.duration == kTriggerDur),
        isTrue,
        reason: 'le step trigger (breath de countdown) doit avoir été joué');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

const kTriggerDur = kChallengeBreathDurationSeconds;

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
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

SessionController _buildController(List<SessionStep> applied) {
  return SessionController(
    session: const Session(
      id: 'defi-trigger-rate',
      name: 'defi-trigger-rate',
      description: '',
      // 3 s de contenu, le trigger défi à 3 s (13 s), l'enveloppe réservée
      // du défi (5 s) laissée vide par le générateur, puis le premier step
      // de contenu suivant à 21 s.
      durationSeconds: 43,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 3),
        SessionStep(time: 3, mode: SessionMode.breath, duration: kTriggerDur),
        SessionStep(
          time: 21,
          mode: SessionMode.hold,
          from: Position.head,
          to: Position.head,
          duration: 22,
        ),
      ],
      challenges: [_challenge],
      challengeTriggerTimes: [3],
    ),
    tts: TtsService(),
    beep: _LoggingBeepEngine(applied),
    ambience: _SilentAmbienceEngine(),
    // `canTriggerFail` exige un bundle non vide des deux côtés. Punition de
    // durée 0 pour que le flow ne coûte pas de temps réel au test.
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
  );
}

class _LoggingBeepEngine extends BeepEngine {
  _LoggingBeepEngine(this.applied);
  final List<SessionStep> applied;
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    applied.add(step);
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
