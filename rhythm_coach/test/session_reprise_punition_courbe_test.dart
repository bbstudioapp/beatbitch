import 'dart:async';
import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// À la reprise après une punition, la courbe annonce la suite de la séance à
/// son heure : la tenue `full` du step à 7 s n'apparaît pas devant le curseur
/// tant que la séance a encore plusieurs secondes de rythme à jouer.
///
/// Les frontières de la courbe sont épinglées en horloge murale. La punition
/// arrête l'horloge de séance des secondes durant : une épingle posée avant le
/// FAIL est dans le passé à la reprise. Le prix : temps réel, `Stopwatch`
/// n'étant pas simulé par `flutter_test`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const audioEventChannels = [
    EventChannel('xyz.luan/audioplayers.global/events'),
    EventChannel('xyz.luan/audioplayers/events/ambience_loop'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, (call) async => null);
    }
    for (final name in wakelockChannels) {
      messenger.setMockMessageHandler(
        name,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    }
    for (final channel in audioEventChannels) {
      messenger.setMockStreamHandler(
          channel, MockStreamHandler.inline(onListen: (_, __) {}));
    }
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, null);
    }
    for (final name in wakelockChannels) {
      messenger.setMockMessageHandler(name, null);
    }
    for (final channel in audioEventChannels) {
      messenger.setMockStreamHandler(channel, null);
    }
  });

  testWidgets(
      'FAIL puis saut de section : la tenue suivante n\'apparaît pas tout de '
      'suite devant le curseur', (tester) async {
    final run = await _playResume(
      tester,
      session: _session,
      punish: (ctrl) => ctrl.triggerFail(),
      frozen: (ctrl) => ctrl.failPhase != null,
    );
    expect(run.elapsedAtResume.inSeconds, 4,
        reason: 'la reprise doit sauter au step de 4 s');
    _expectNoHoldAhead(run.samples);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'mini-punition puis restauration du loop : la tenue n\'apparaît pas '
      'tout de suite devant le curseur', (tester) async {
    final run = await _playResume(
      tester,
      session: _session,
      punish: (ctrl) => ctrl.debugRunMiniPunishment(_rhythmPunishment),
      frozen: (ctrl) => ctrl.failPhase != null,
    );
    expect(run.elapsedAtResume.inSeconds, 2,
        reason: 'la reprise doit repartir de l\'instant du FAIL');
    _expectNoHoldAhead(run.samples);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'attente de posture : la tenue n\'apparaît pas tout de suite devant le '
      'curseur une fois la mise en place confirmée', (tester) async {
    final run = await _playResume(
      tester,
      session: _postureSession,
      frozen: (ctrl) => ctrl.awaitingPostureReady,
      whileFrozen: (ctrl, frozenFor) {
        if (frozenFor >= const Duration(seconds: 5)) {
          ctrl.confirmPostureReady();
        }
      },
    );
    // Un gel au tick près : l'horloge flotte de part et d'autre de 2 s.
    expect(run.elapsedAtResume.inMilliseconds, inInclusiveRange(1300, 3000),
        reason: 'la reprise doit repartir du step qui a armé l\'attente');
    _expectNoHoldAhead(run.samples);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'défi refusé : la tenue rebasée sur une seconde déjà épinglée '
      'n\'apparaît pas tout de suite devant le curseur', (tester) async {
    final run = await _playResume(
      tester,
      session: _challengeSession,
      frozen: (ctrl) => ctrl.isTimelineFrozen,
      whileFrozen: (ctrl, frozenFor) {
        if (ctrl.challengePhase == ChallengePhase.breath &&
            frozenFor >= const Duration(seconds: 1)) {
          ctrl.triggerChallengePass();
        }
      },
    );
    // Un gel au tick près : l'horloge flotte de part et d'autre de 2 s.
    expect(run.elapsedAtResume.inMilliseconds, inInclusiveRange(1300, 3000),
        reason: 'la reprise doit repartir de l\'instant du défi');
    _expectNoHoldAhead(run.samples);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'mini-punition : l\'écran montre le rythme de la séance dès que le '
      'moteur le reprend', (tester) async {
    final (lag, failingFrames, announcedFrames) = await _screenLagAtResume(
        tester,
        session: _session,
        punish: (ctrl) => ctrl.debugRunMiniPunishment(_holdPunishment));
    expect(lag, lessThan(_lagToleranceMs),
        reason: 'l\'écran a montré le rythme ${lag.inMilliseconds} ms après '
            'le moteur');
    expect(failingFrames, 0,
        reason: 'bandeau de punition encore affiché à côté du rythme restauré');
    expect(announcedFrames, 0,
        reason: 'la courbe annonce la suite sur une horloge de séance gelée');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'FAIL sans section suivante : l\'écran montre le rythme de la séance '
      'dès que le moteur le reprend', (tester) async {
    final (lag, failingFrames, announcedFrames) = await _screenLagAtResume(
        tester,
        session: _singleSection,
        punish: (ctrl) => ctrl.triggerFail());
    expect(lag, lessThan(_lagToleranceMs),
        reason: 'l\'écran a montré le rythme ${lag.inMilliseconds} ms après '
            'le moteur');
    expect(failingFrames, 0,
        reason: 'bandeau de punition encore affiché à côté du rythme restauré');
    expect(announcedFrames, 0,
        reason: 'la courbe annonce la suite sur une horloge de séance gelée');
  }, timeout: const Timeout(Duration(seconds: 120)));
}

void _expectNoHoldAhead(List<_CurveSample> samples) {
  expect(samples, isNotEmpty, reason: 'aucune image après la reprise');
  final early = samples.where((s) =>
      s.holdAheadMs != null &&
      (s.holdAheadMs! < s.expectedMs - _toleranceMs || !s.leadInPainted));
  expect(early, isEmpty,
      reason: 'la tenue doit apparaître à son instant − elapsed devant le '
          'curseur, après ce qui se joue encore. Images en avance (ms depuis '
          'la reprise : 1er point de tenue / attendu, en ms devant le curseur, '
          'autre chose peint avant) : '
          '${early.map((s) => '${s.ms}: ${s.holdAheadMs} / ${s.expectedMs}, ${s.leadInPainted}').join(' | ')}');
}

/// Seuil au-dessus de toute position de rythme de la séance (`throat` = 3) :
/// seule la tenue `full` l'atteint.
final _holdIdx = Position.full.index - 0.5;

/// `elapsed` du contrôleur n'avance qu'au tick de 200 ms, et l'écran
/// l'extrapole d'au plus 250 ms.
const _toleranceMs = 600;

class _CurveSample {
  final int ms;

  /// Premier point de la tenue peint devant le curseur, s'il est dans la
  /// fenêtre.
  final int? holdAheadMs;
  final int expectedMs;

  /// Un point hors tenue est peint entre le curseur et la tenue : sans lui,
  /// la frontière est déjà passée derrière le curseur.
  final bool leadInPainted;
  const _CurveSample(
      this.ms, this.holdAheadMs, this.expectedMs, this.leadInPainted);
}

class _Resumed {
  final Duration elapsedAtResume;
  final List<_CurveSample> samples;
  const _Resumed(this.elapsedAtResume, this.samples);
}

/// Le pont de transition est passé ; la lecture s'arrête avant que la tenue
/// ne commence.
const _settleMs = 300;
const _windowEndMs = 3000;

/// Instant de la tenue `full` sur la timeline courante (un défi la rebase).
Duration _holdAt(SessionController ctrl) => Duration(
    seconds:
        ctrl.session.steps.firstWhere((s) => s.mode == SessionMode.hold).time);

/// Écran de séance monté sur [session] ; la tranche rendue avance l'horloge
/// simulée du temps réel écoulé.
Future<(SessionController, Future<void> Function())> _mount(
    WidgetTester tester, Session session, Punishment punishment) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SessionScreen(
      session: session,
      tts: TtsService(),
      beep: _StateBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle: PunishmentBundle(
        failPhrases: const ['raté'],
        punishments: [punishment],
      ),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      autoStart: true,
      // Endurance haute : respiration d'avant-punition courte.
      staminaProfile: List<double>.filled(700, 100.0),
    ),
  ));
  await tester.pump();
  final ctrl = Provider.of<SessionController>(
      tester.element(find.byType(MovementAnimation)),
      listen: false);

  // Le ticker du contrôleur est une minuterie simulée et son horloge un
  // `Stopwatch` réel : à pas fixe, un gel (−200 ms par tick) glisse.
  var sliceEnd = DateTime.now();
  Future<void> slice() async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    final now = DateTime.now();
    await tester.pump(now.difference(sliceEnd));
    sliceEnd = now;
  }

  return (ctrl, slice);
}

/// Une tranche de banc et sa marge : en deçà du plus petit délai de
/// transition entre deux modes (600 ms).
const _lagToleranceMs = Duration(milliseconds: 400);

/// Écart entre le moteur qui reprend le rythme de la séance à la sortie d'une
/// punition de tenue et l'écran qui le montre, et nombre d'images où l'écran
/// montre ce rythme alors que le contrôleur est encore en `failing`, et nombre
/// d'images où la courbe annonce la suite avant que l'horloge de séance ne
/// reparte.
Future<(Duration, int, int)> _screenLagAtResume(
  WidgetTester tester, {
  required Session session,
  required Future<void> Function(SessionController ctrl) punish,
}) async {
  final (ctrl, slice) = await _mount(tester, session, _holdPunishment);
  var guard = 0;
  while (!(ctrl.isRunning &&
      ctrl.hasConfig &&
      ctrl.elapsed >= const Duration(milliseconds: 2500))) {
    if (++guard > 100) fail('la séance ne démarre pas');
    await slice();
  }
  unawaited(punish(ctrl));

  var punished = false;
  DateTime? engineAt;
  DateTime? screenAt;
  var failingFrames = 0;
  var announcedFrames = 0;
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline) &&
      !(screenAt != null && !ctrl.isFailFlowActive)) {
    await slice();
    if (ctrl.failPhase == FailPhase.punishment &&
        ctrl.currentMode == SessionMode.hold) {
      punished = true;
    }
    if (!punished) continue;
    final now = DateTime.now();
    if (ctrl.currentMode == SessionMode.rhythm) engineAt ??= now;
    final shown =
        tester.widget<MovementAnimation>(find.byType(MovementAnimation)).mode;
    if (shown == SessionMode.rhythm) {
      screenAt ??= now;
      if (ctrl.isFailing || ctrl.failPhase != null) failingFrames++;
      if (ctrl.isFailFlowActive &&
          tester
              .widget<MovementAnimation>(find.byType(MovementAnimation))
              .upcomingSteps
              .isNotEmpty) {
        announcedFrames++;
      }
    }
  }
  expect(punished, isTrue, reason: 'la punition de tenue ne démarre pas');
  expect(engineAt, isNotNull, reason: 'le moteur ne reprend pas le rythme');
  expect(screenAt, isNotNull, reason: 'l\'écran ne montre jamais le rythme');

  ctrl.stop();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpWidget(const SizedBox());
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  return (screenAt!.difference(engineAt!), failingFrames, announcedFrames);
}

/// Lance [punish] à 2,5 s de séance s'il est fourni, laisse passer le gel
/// décrit par [frozen], puis lit la courbe pendant [_settleMs, _windowEndMs)
/// après la reprise, tant que la tenue est à plus d'une demi-seconde.
Future<_Resumed> _playResume(
  WidgetTester tester, {
  required Session session,
  Future<void> Function(SessionController ctrl)? punish,
  required bool Function(SessionController ctrl) frozen,
  void Function(SessionController ctrl, Duration frozenFor)? whileFrozen,
}) async {
  final (ctrl, slice) = await _mount(tester, session, _rhythmPunishment);

  if (punish != null) {
    var guard = 0;
    while (!(ctrl.isRunning &&
        ctrl.hasConfig &&
        ctrl.elapsed >= const Duration(milliseconds: 2500))) {
      if (++guard > 100) fail('la séance ne démarre pas');
      await slice();
    }
    expect(ctrl.elapsed, lessThan(const Duration(seconds: 4)),
        reason: 'le FAIL doit tomber avant le step de 4 s');
    unawaited(punish(ctrl));
  }

  DateTime? frozenAt;
  DateTime? resumedAt;
  Duration? elapsedAtResume;
  final samples = <_CurveSample>[];
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    await slice();
    final now = DateTime.now();
    if (frozen(ctrl)) {
      frozenAt ??= now;
      whileFrozen?.call(ctrl, now.difference(frozenAt));
      continue;
    }
    if (frozenAt == null || !ctrl.isRunning) continue;
    if (resumedAt == null) {
      resumedAt = now;
      elapsedAtResume = ctrl.elapsed;
    }
    final ms = now.difference(resumedAt).inMilliseconds;
    final expectedMs =
        _holdAt(ctrl).inMilliseconds - ctrl.elapsed.inMilliseconds;
    if (ms >= _windowEndMs || expectedMs < 500) break;
    if (ms < _settleMs) continue;
    final ahead = [
      for (final b in _curve(tester))
        if (b.$1 > 0) ((b.$1 * 3000).round(), b.$2),
    ];
    final hold = ahead.where((b) => b.$2 >= _holdIdx);
    final holdAheadMs = hold.isEmpty ? null : hold.map((b) => b.$1).reduce(min);
    samples.add(_CurveSample(
      ms,
      holdAheadMs,
      expectedMs,
      holdAheadMs != null &&
          ahead.any((b) => b.$1 < holdAheadMs && b.$2 < _holdIdx),
    ));
  }
  expect(resumedAt, isNotNull, reason: 'la séance ne reprend pas');

  ctrl.stop();
  // Le step relancé à la reprise n'est pas attendu : son délai de transition
  // est une minuterie simulée, à écouler avant le démontage.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpWidget(const SizedBox());
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  return _Resumed(elapsedAtResume!, samples);
}

/// Points de la courbe peinte : (t ∈ [0,1] de la fenêtre de 3 s, idx).
List<(double, double)> _curve(WidgetTester tester) {
  for (final cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final p = cp.painter;
    if (p != null && p.runtimeType.toString() == '_TrajectoryPainter') {
      return [
        for (final b in (p as dynamic).beats as List)
          ((b as dynamic).t as double, b.idx as double),
      ];
    }
  }
  return const [];
}

const _session = Session(
  id: 'reprise',
  name: 'reprise',
  description: '',
  durationSeconds: 600,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
    SessionStep(
      time: 4,
      mode: SessionMode.rhythm,
      bpm: 120,
      from: Position.tip,
      to: Position.mid,
    ),
    SessionStep(
      time: 7,
      mode: SessionMode.hold,
      from: Position.full,
      to: Position.full,
      duration: 30,
    ),
    SessionStep(
      time: 60,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
  ],
);

/// L'attente de posture s'arme au step de 2 s ; aucun break ne démonte la
/// courbe avant elle.
const _postureSession = Session(
  id: 'reprise-posture',
  name: 'reprise-posture',
  description: '',
  durationSeconds: 600,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
    SessionStep(
      time: 2,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
      awaitReady: true,
    ),
    SessionStep(
      time: 4,
      mode: SessionMode.rhythm,
      bpm: 120,
      from: Position.tip,
      to: Position.mid,
    ),
    SessionStep(
      time: 7,
      mode: SessionMode.hold,
      from: Position.full,
      to: Position.full,
      duration: 30,
    ),
    SessionStep(
      time: 60,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
  ],
);

/// Défi de 1 s armé à 2 s : l'excision retire 14 s de timeline. Le rythme
/// d'après la fenêtre (16 s) est épinglé avant le défi ; la tenue de 30 s,
/// rebasée à 16 s, retombe sur cette seconde.
const _challengeSession = Session(
  id: 'reprise-defi',
  name: 'reprise-defi',
  description: '',
  durationSeconds: 600,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
    SessionStep(time: 2, mode: SessionMode.breath, duration: 14),
    SessionStep(
      time: 16,
      mode: SessionMode.rhythm,
      bpm: 120,
      from: Position.tip,
      to: Position.mid,
    ),
    SessionStep(
      time: 30,
      mode: SessionMode.hold,
      from: Position.full,
      to: Position.full,
      duration: 30,
    ),
    SessionStep(
      time: 120,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
  ],
  challenges: [
    Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 1,
      mode: SessionMode.hold,
      from: Position.throat,
      to: Position.throat,
      comfortAtCalibration: 1,
    ),
  ],
  challengeTriggerTimes: [2],
);

/// Assez longue pour que l'épingle de la tenue (FAIL + 4,5 s) soit passée à
/// la reprise, même sans respiration d'avant-punition.
const _rhythmPunishment = Punishment(
  id: 'rythme',
  name: 'rythme',
  durationSeconds: 5,
  steps: [
    SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      bpm: 90,
      from: Position.tip,
      to: Position.full,
    ),
  ],
);

/// Aucune section après le FAIL : la reprise restaure le loop d'avant.
const _singleSection = Session(
  id: 'reprise-sans-section',
  name: 'reprise-sans-section',
  description: '',
  durationSeconds: 600,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
  ],
);

const _holdPunishment = Punishment(
  id: 'tenue',
  name: 'tenue',
  durationSeconds: 3,
  steps: [
    SessionStep(
      time: 0,
      mode: SessionMode.hold,
      from: Position.full,
      to: Position.full,
      duration: 3,
    ),
  ],
);

/// Moteur réel sans chargement d'échantillons : aucun son, mais `applyStep`
/// met à jour mode et positions comme en production.
class _StateBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
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
