/// Ce que la trajectoire annonce pendant et après un défi.
///
/// Un défi joue des segments produits en direct par son builder, jamais
/// insérés dans `session.steps`, et gèle l'horloge de séance
/// (`isTimelineFrozen`) pendant toute sa durée **et** son breath de récup.
/// Le step trigger — un `breath` de 13 s — reste lui dans la timeline, juste
/// devant l'horloge gelée : la lire pendant le défi annonce ce `breath`, que
/// `MovementAnimation` trace en ligne droite en haut (`tip`), pendant que le
/// moteur tient une gorge. D'où le symptôme « la courbe reste collée en haut
/// pendant un défi, le curseur bouge normalement ».
///
/// Le test mesure les deux lectures côte à côte — celle qui ment et celle que
/// `session_screen.dart` applique — puis vérifie qu'à l'excision de la fenêtre
/// défi, la trajectoire annoncée se recale sur la timeline mutée.
library;

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
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTriggerDur = kChallengeBreathDurationSeconds;
const _kContentAfterChallenge = 21;
const _kLastStep = 51;

const _challenge = Challenge(
  axis: CapabilityAxis.holdThroatStreak,
  kind: ChallengeAxisKind.duration,
  targetThreshold: 5,
  mode: SessionMode.hold,
  from: Position.throat,
  to: Position.throat,
  comfortAtCalibration: 4,
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

  test(
    'la timeline de séance ment pendant un défi et se recale à son excision',
    () async {
      final ctrl = _buildController();
      await ctrl.start();

      final beforeChallenge = _rawForecast(ctrl);
      expect(
        beforeChallenge.map((u) => u.startSecond),
        [3, _kContentAfterChallenge, _kLastStep],
        reason: 'timeline de départ, avant toute mutation',
      );

      await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
      expect(ctrl.challengePhase, ChallengePhase.breath,
          reason: 'le défi doit s\'armer sur son trigger');
      expect(ctrl.isTimelineFrozen, isTrue,
          reason: "l'horloge de séance est gelée dès l'armement");

      ctrl.onChallengeHoldStart();
      await _waitUntil(() => ctrl.challengePhase == ChallengePhase.live);
      expect(ctrl.challengePhase, ChallengePhase.live);
      expect(ctrl.isTimelineFrozen, isTrue,
          reason: 'gelée pendant les segments du défi');

      // Le moteur tient la gorge : c'est ça que la courbe doit montrer.
      expect(ctrl.currentMode, SessionMode.hold);
      expect(ctrl.currentFrom, Position.throat);

      final duringChallenge = _rawForecast(ctrl);
      expect(
        duringChallenge.first.mode,
        SessionMode.breath,
        reason: 'le step trigger est toujours dans la timeline, juste devant '
            "l'horloge gelée : le lire annonce un breath",
      );

      final lying = _curve(ctrl, duringChallenge);
      final applied = _curve(ctrl, const []);
      final throatIdx = Position.throat.index.toDouble();
      final tipIdx = Position.tip.index.toDouble();

      expect(lying.map((p) => p.idx).toList(), contains(tipIdx),
          reason: 'lue crûment, la trajectoire remonte au bout et y reste — '
              'la courbe collée en haut pendant le défi');
      expect(lying.last.idx, tipIdx);
      expect(
        applied.map((p) => p.idx),
        everyElement(closeTo(throatIdx, 0.01)),
        reason: "l'annonce vidée pendant le gel (session_screen.dart) laisse "
            'la courbe sur la gorge, avec le curseur',
      );

      await _waitUntil(() => ctrl.challengePhase == ChallengePhase.atSeuil,
          timeout: const Duration(seconds: 30));
      expect(ctrl.challengePhase, ChallengePhase.atSeuil);
      ctrl.onChallengeHoldEnd();

      // Excision de la fenêtre défi : la trajectoire annoncée doit suivre la
      // mutation de `session.steps` sans attendre le dégel.
      await _waitUntil(() => ctrl.session.steps.length < 4);
      final shift = _kTriggerDur + _challenge.nominalDurationSeconds;
      final afterExcision = _rawForecast(ctrl);
      expect(
        afterExcision.map((u) => u.startSecond),
        [_kContentAfterChallenge - shift, _kLastStep - shift],
        reason: 'le trigger a disparu de la timeline et les steps survivants '
            'ont reculé de $shift s — la trajectoire annoncée le reflète',
      );
      expect(
        afterExcision.map((u) => u.mode),
        [SessionMode.rhythm, SessionMode.hold],
      );

      await _waitUntil(() => !ctrl.isTimelineFrozen,
          timeout: const Duration(seconds: 30));
      expect(ctrl.isTimelineFrozen, isFalse,
          reason: 'le breath post-défi fini, la séance reprend son horloge');
      expect(ctrl.currentMode, SessionMode.rhythm,
          reason: 'le step qui suivait le défi est consommé au dégel');
      expect(_rawForecast(ctrl).map((u) => u.startSecond),
          [_kLastStep - shift]);

      await ctrl.stop();
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}

/// La suite telle que la timeline de séance la décrit — celle que
/// `session_screen.dart` n'annonce que quand l'horloge tourne.
List<UpcomingMovementStep> _rawForecast(SessionController ctrl) =>
    resolveUpcomingMovementSteps(
      steps: ctrl.session.steps,
      defaultMode: ctrl.session.defaultMode,
      afterSecond: ctrl.elapsedSeconds,
      currentMode: ctrl.currentMode,
      currentFrom: ctrl.currentFrom,
      currentTo: ctrl.currentTo,
      currentBpm: ctrl.currentBpm,
    );

List<({double t, double idx, bool isAnchor})> _curve(
  SessionController ctrl,
  List<UpcomingMovementStep> upcoming,
) =>
    computeFutureBeatsForTest(
      mode: ctrl.currentMode,
      from: ctrl.currentFrom,
      to: ctrl.currentTo ?? ctrl.currentFrom,
      beatDuration: Duration(milliseconds: (60000 / ctrl.currentBpm).round()),
      flipped: false,
      frozenIdx: ctrl.currentFrom.index.toDouble(),
      frozenAt: DateTime.now().subtract(const Duration(seconds: 2)),
      elapsed: ctrl.elapsed,
      upcomingSteps: upcoming,
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
      id: 'defi-courbe',
      name: 'defi-courbe',
      description: '',
      durationSeconds: 120,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          bpm: 40,
          duration: 3,
        ),
        SessionStep(time: 3, mode: SessionMode.breath, duration: _kTriggerDur),
        SessionStep(
          time: _kContentAfterChallenge,
          mode: SessionMode.rhythm,
          from: Position.mid,
          to: Position.full,
          bpm: 50,
          duration: 30,
        ),
        SessionStep(
          time: _kLastStep,
          mode: SessionMode.hold,
          from: Position.head,
          to: Position.head,
          duration: 69,
        ),
      ],
      challenges: [_challenge],
      challengeTriggerTimes: [3],
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
  );
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
