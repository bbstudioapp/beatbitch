import 'dart:async';
import 'dart:math';

import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ce que l'écran **dessine** pendant une punition, lu sur `MovementAnimation`
/// et non sur l'état du moteur de bips : le curseur remonte pendant la
/// respiration entre deux tenues, et la courbe dessine la punition, pas la
/// suite de la séance.
///
/// La chaîne de tenues passe par deux routes : la punition générée en carrière
/// (`deep_hold_chain` du `PunishmentBuilder`) et celle tirée dans
/// `punishments.json` (Custom, scénarios). Le prix : temps réel, `Stopwatch`
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
      'punition carrière : le curseur affiché remonte pendant la respiration '
      'entre les deux tenues', (tester) async {
    final run = await _play(
      tester,
      career: true,
      bundle: const PunishmentBundle(
        failPhrases: ['raté'],
        punishments: [_unusedPunishment],
      ),
    );

    expect(run.punishment.id, 'deep_hold_chain');
    _expectHoldBreathHold(run);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'punition punishments.json : le curseur affiché remonte pendant la '
      'respiration entre les deux tenues', (tester) async {
    final loaded = (await tester
        .runAsync(() => PunishmentLoader().load(locale: const Locale('fr'))))!;
    final chain =
        loaded.punishments.firstWhere((p) => p.id == 'deep_hold_chain');

    final run = await _play(
      tester,
      career: false,
      bundle:
          PunishmentBundle(failPhrases: const ['raté'], punishments: [chain]),
    );

    expect(run.punishment.id, 'deep_hold_chain');
    _expectHoldBreathHold(run);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets(
      'punition : la courbe dessine le rythme de la punition, pas la '
      'respiration qui suit dans la séance', (tester) async {
    _expectCurveFollowsPunishment(
        await _playCurve(tester, (ctrl) => ctrl.triggerFail()));
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'mini-punition : la courbe dessine le rythme de la punition, pas la '
      'respiration qui suit dans la séance', (tester) async {
    _expectCurveFollowsPunishment(await _playCurve(
        tester, (ctrl) => ctrl.debugRunMiniPunishment(_rhythmPunishment)));
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets(
      'FAIL : pendant la phrase et la respiration d\'avant-punition, l\'écran '
      'n\'annonce pas la suite de la séance', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      // Une phrase de fail qui dure : sinon la phase `phrase` passe entre
      // deux images.
      if (call.method == 'speak') {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      return 1;
    });
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
        session: _breathNextSession,
        tts: TtsService(),
        beep: _StateBeepEngine(),
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: const PunishmentBundle(
          failPhrases: ['raté'],
          punishments: [_rhythmPunishment],
        ),
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
        autoStart: true,
        staminaProfile: List<double>.filled(700, 100.0),
      ),
    ));
    await tester.pump();
    final ctrl = Provider.of<SessionController>(
        tester.element(find.byType(MovementAnimation)),
        listen: false);
    MovementAnimation anim() =>
        tester.widget<MovementAnimation>(find.byType(MovementAnimation));

    Future<void> slice() async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    var guard = 0;
    while (!(ctrl.isRunning &&
        ctrl.hasConfig &&
        ctrl.elapsed >= const Duration(milliseconds: 2500))) {
      if (++guard > 100) fail('la séance ne démarre pas');
      await slice();
    }
    expect(anim().upcomingSteps, isNotEmpty,
        reason: 'hors FAIL, la séance annonce sa suite : sans cela le vide '
            'mesuré ensuite ne prouverait rien');
    unawaited(ctrl.triggerFail());

    final seen = {FailPhase.phrase: 0, FailPhase.breath: 0};
    final announced = <String>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline) &&
        ctrl.failPhase != FailPhase.punishment) {
      await slice();
      final phase = ctrl.failPhase;
      if (phase == null || !seen.containsKey(phase)) continue;
      seen[phase] = seen[phase]! + 1;
      final upcoming = anim().upcomingSteps;
      if (upcoming.isNotEmpty) {
        announced.add('${phase.name} : '
            '${upcoming.map((u) => '${u.startSecond} s').join(', ')}');
      }
    }
    expect(seen[FailPhase.phrase], greaterThanOrEqualTo(3),
        reason: 'aucune image pendant la phrase de fail');
    expect(seen[FailPhase.breath], greaterThanOrEqualTo(3),
        reason: 'aucune image pendant la respiration d\'avant-punition');
    expect(announced, isEmpty,
        reason: 'l\'horloge de séance est arrêtée pendant le FAIL : la courbe '
            'ne doit recevoir aucun instant de la séance. Images fautives : '
            '${announced.take(3).join(' | ')}');

    unawaited(ctrl.triggerFail());
    for (var i = 0; i < 50 && ctrl.failPhase != null; i++) {
      await slice();
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
  }, timeout: const Timeout(Duration(seconds: 120)));
}

void _expectCurveFollowsPunishment(List<_CurveSample> samples) {
  expect(samples, isNotEmpty, reason: 'aucune image du rythme de punition');
  final flat = samples.where((s) => s.aheadMax < Position.throat.index);
  expect(flat, isEmpty,
      reason: 'pendant le rythme tip→full de la punition, la courbe doit '
          'monter jusqu\'en bas entre 1 et 3 s devant le curseur. Images '
          'restées en haut (ms depuis le début de la punition : max) : '
          '${flat.map((s) => '${s.ms}: ${s.aheadMax.toStringAsFixed(2)}').join(', ')}');
}

/// Image de la courbe pendant le rythme de la punition.
class _CurveSample {
  final int ms;

  /// Point le plus profond peint entre 1 et 3 s devant le curseur.
  final double aheadMax;
  const _CurveSample(this.ms, this.aheadMax);
}

/// Le temps de la transition respiration → rythme : la courbe n'est pas
/// jugée pendant le pont.
const _curveSettleMs = 800;
const _curveWindowEndMs = 4000;

/// Lance [punish] juste avant la respiration de [_breathNextSession], puis lit
/// la courbe pendant les premières secondes de [_rhythmPunishment]. Rend les
/// images prises dans [_curveSettleMs, _curveWindowEndMs).
Future<List<_CurveSample>> _playCurve(WidgetTester tester,
    Future<void> Function(SessionController ctrl) punish) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SessionScreen(
      session: _breathNextSession,
      tts: TtsService(),
      beep: _StateBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle: const PunishmentBundle(
        failPhrases: ['raté'],
        punishments: [_rhythmPunishment],
      ),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      autoStart: true,
      staminaProfile: List<double>.filled(700, 100.0),
    ),
  ));
  await tester.pump();
  final ctrl = Provider.of<SessionController>(
      tester.element(find.byType(MovementAnimation)),
      listen: false);

  Future<void> slice() async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  var guard = 0;
  while (!(ctrl.isRunning &&
      ctrl.hasConfig &&
      ctrl.elapsed >= const Duration(milliseconds: 2500))) {
    if (++guard > 100) fail('la séance ne démarre pas');
    await slice();
  }
  expect(ctrl.elapsed, lessThan(const Duration(seconds: 4)),
      reason: 'la punition doit tomber avant la respiration de la séance');
  unawaited(punish(ctrl));

  DateTime? startedAt;
  final samples = <_CurveSample>[];
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    await slice();
    if (ctrl.failPhase != FailPhase.punishment) {
      if (startedAt != null) break;
      continue;
    }
    final now = DateTime.now();
    startedAt ??= now;
    final ms = now.difference(startedAt).inMilliseconds;
    if (ms >= _curveWindowEndMs) break;
    if (ms < _curveSettleMs) continue;
    expect(ctrl.currentMode, SessionMode.rhythm);
    final ahead = _curve(tester).where((b) => b.$1 >= 1 / 3 && b.$1 <= 1);
    samples.add(_CurveSample(
        ms, ahead.isEmpty ? double.nan : ahead.map((b) => b.$2).reduce(max)));
  }
  expect(startedAt, isNotNull, reason: 'la punition ne démarre pas');

  unawaited(ctrl.triggerFail());
  for (var i = 0; i < 50 && ctrl.failPhase != null; i++) {
    await slice();
  }
  // Le saut de section relance un step sans l'attendre : son délai de
  // transition est une minuterie simulée, à écouler avant le démontage.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpWidget(const SizedBox());
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  return samples;
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

const _breathNextSession = Session(
  id: 'respiration-ensuite',
  name: 'respiration-ensuite',
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
    SessionStep(time: 4, mode: SessionMode.breath),
    SessionStep(
      time: 60,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
    ),
  ],
);

const _rhythmPunishment = Punishment(
  id: 'rythme',
  name: 'rythme',
  durationSeconds: 8,
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

const _unusedPunishment = Punishment(
  id: 'unused',
  name: 'unused',
  durationSeconds: 1,
  steps: [SessionStep(time: 0, text: 'x')],
);

/// Sous ce seuil dans un même mode, le curseur n'a pas fini sa transition
/// (descente vers la tenue, remontée vers `tip`) : on ne juge pas plus tôt.
const _settle = Duration(milliseconds: 1500);

/// `tip` est la rangée du haut, `y = -1`.
const _topY = -0.9;

/// Ce que l'écran montrait à un instant de la punition.
class _Sample {
  final DateTime at;
  final SessionMode engine;
  final SessionMode screen;
  final double? cursorY;
  const _Sample(this.at, this.engine, this.screen, this.cursorY);
}

/// Suite d'échantillons consécutifs où le moteur reste dans le même mode.
class _Run {
  final SessionMode mode;
  final List<_Sample> samples;
  _Run(this.mode, _Sample first) : samples = [first];

  /// Échantillons pris au moins [_settle] après l'entrée dans le mode.
  List<_Sample> get settled => samples
      .where((s) => s.at.difference(samples.first.at) >= _settle)
      .toList();
}

class _Played {
  final Punishment punishment;
  final List<_Run> runs;
  const _Played(this.punishment, this.runs);
}

void _expectHoldBreathHold(_Played run) {
  final modes = run.runs.map((r) => r.mode).toList();
  expect(modes.take(3).toList(),
      [SessionMode.hold, SessionMode.breath, SessionMode.hold],
      reason: 'le moteur enchaîne tenue → respiration → tenue : $modes');

  final firstHold = run.runs[0].settled;
  final breath = run.runs[1].settled;
  final secondHold = run.runs[2].settled;
  expect(firstHold, isNotEmpty, reason: 'aucune image de la 1re tenue');
  expect(breath, isNotEmpty, reason: 'aucune image de la respiration');
  expect(secondHold, isNotEmpty, reason: 'aucune image de la 2e tenue');

  expect(firstHold.map((s) => (s.cursorY ?? double.nan)),
      everyElement(greaterThan(0.0)),
      reason: 'pendant la 1re tenue le curseur est en bas');
  expect(breath.map((s) => (s.cursorY ?? double.nan)),
      everyElement(lessThan(_topY)),
      reason: 'pendant la respiration le curseur doit être remonté en haut '
          '(y=-1). Moteur : ${breath.map((s) => s.engine.name).toSet()}, '
          'mode reçu par MovementAnimation : '
          '${breath.map((s) => s.screen.name).toSet()}, '
          'y : ${breath.map((s) => (s.cursorY ?? double.nan).toStringAsFixed(2)).toSet()}');
  expect(secondHold.map((s) => (s.cursorY ?? double.nan)),
      everyElement(greaterThan(0.0)),
      reason: 'pendant la 2e tenue le curseur redescend');
}

Future<_Played> _play(
  WidgetTester tester, {
  required bool career,
  required PunishmentBundle bundle,
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SessionScreen(
      session: _session,
      tts: TtsService(),
      beep: _StateBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle: bundle,
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      autoStart: true,
      // Profil d'endurance haut : la respiration qui précède la punition
      // prend sa durée courte.
      staminaProfile: List<double>.filled(700, 100.0),
      // Sans phrase bank ni profil de capacités, `triggerFail` retombe sur
      // `punishments.json` : c'est la seule différence entre les deux routes.
      phraseBank: career ? _bank() : null,
      capabilityProfile: career ? _profile() : null,
      unlockedKeys: UnlockKey.values.toSet(),
      careerLevel: 14,
      seedHumiliationSession: 100,
    ),
  ));
  await tester.pump();
  final ctrl = Provider.of<SessionController>(
      tester.element(find.byType(MovementAnimation)),
      listen: false);

  Future<void> slice() async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  var guard = 0;
  while (!(ctrl.isRunning && ctrl.hasConfig)) {
    if (++guard > 100) fail('la séance ne démarre pas');
    await slice();
  }
  unawaited(ctrl.triggerFail());

  Punishment? punishment;
  final runs = <_Run>[];
  final deadline = DateTime.now().add(const Duration(seconds: 100));
  while (DateTime.now().isBefore(deadline)) {
    await slice();
    if (ctrl.failPhase != FailPhase.punishment) {
      if (punishment != null) break;
      continue;
    }
    punishment ??= ctrl.currentPunishment;
    final animation =
        tester.widget<MovementAnimation>(find.byType(MovementAnimation));
    final sample = _Sample(
      DateTime.now(),
      ctrl.currentMode,
      animation.mode,
      _cursorY(tester),
    );
    if (runs.isEmpty || runs.last.mode != sample.engine) {
      runs.add(_Run(sample.engine, sample));
    } else {
      runs.last.samples.add(sample);
    }
    // Assez vu : entrée dans la 2e tenue, une fois posée.
    if (runs.length >= 3 && runs[2].settled.isNotEmpty) break;
  }
  expect(punishment, isNotNull, reason: 'la punition ne démarre pas');

  // Sortie propre : un second FAIL abandonne la punition en cours.
  unawaited(ctrl.triggerFail());
  for (var i = 0; i < 50 && ctrl.failPhase != null; i++) {
    await slice();
  }
  await tester.pumpWidget(const SizedBox());
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));

  return _Played(punishment!, runs);
}

/// Position du curseur dessiné : dernier `Align` dont `x` n'est ni 0 ni 0.92.
double? _cursorY(WidgetTester tester) {
  for (final a
      in tester.widgetList<Align>(find.byType(Align)).toList().reversed) {
    final al = a.alignment;
    if (al is Alignment && al.x != 0 && (al.x - 0.92).abs() > 0.001) {
      return al.y;
    }
  }
  return null;
}

const _session = Session(
  id: 'punition',
  name: 'punition',
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

List<PhraseEntry> _entries(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _entries(['s']),
            'medium': _entries(['m']),
            'hard': _entries(['h']),
            'boost': _entries(['b']),
            'finale': _entries(['f']),
          },
      },
      congrats: _entries(['bravo']),
      intros: _entries(['intro']),
    );

/// Confort court sur les deux tenues profondes : la chaîne en est raccourcie.
CapabilityProfile _profile() => const CapabilityProfile({
      CapabilityAxis.holdThroatStreak: CapabilityAxisState(best: 3, comfort: 3),
      CapabilityAxis.holdFullStreak: CapabilityAxisState(best: 3, comfort: 3),
    });

/// Moteur réel sans chargement d'échantillons : `_pools` reste vide, donc
/// aucun son, mais `applyStep` met à jour mode et positions comme en
/// production.
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
