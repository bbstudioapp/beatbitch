import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Après une pause, le curseur reste dans la consigne en cours : la frontière
/// suivante, épinglée en horloge murale avant la pause, recule de toute la
/// durée de la pause. Sur l'appareil, aucune image n'est construite en
/// arrière-plan : la courbe ne voit la pause qu'au retour dans l'appli.
///
/// Le prix : temps réel, `Stopwatch` n'étant pas simulé par `flutter_test`.
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
    for (final channel in audioEventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
              channel,
              MockStreamHandler.inline(
                onListen: (_, __) {},
              ));
    }
  });

  tearDown(() {
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
    for (final channel in audioEventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    }
  });

  for (final (how, leavesApp) in [
    ('retour dans l’appli', true),
    ('reprise sans quitter l’appli', false),
  ]) {
    testWidgets(
        '$how pendant un rythme Gland ↔ Gorge suivi d’une tenue « Tout » : le '
        'curseur ne descend pas à « Tout » avant la tenue', (tester) async {
      final track =
          await _replay(tester, pauseAtMs: 4500, leavesApp: leavesApp);
      final rhythm = [
        for (final s in track)
          if (s.resumed && s.elapsedMs > 5000 && s.elapsedMs < 7800) s,
      ];
      expect(rhythm.map((s) => s.mode).toSet(), {SessionMode.rhythm});
      expect(rhythm.length, greaterThan(30));
      expect(
        [
          for (final s in rhythm)
            if (s.idx > Position.throat.index + 0.5) '$s',
        ],
        isEmpty,
        reason: 'le curseur rejoint la tenue « Tout » à venir',
      );
    });

    testWidgets(
        '$how pendant une tenue « Tout » suivie d’un rythme : le curseur '
        'reste à « Tout » jusqu’à la fin de la tenue', (tester) async {
      final track =
          await _replay(tester, pauseAtMs: 10000, leavesApp: leavesApp);
      final hold = [
        for (final s in track)
          if (s.resumed && s.elapsedMs < 11800) s,
      ];
      expect(hold.map((s) => s.mode).toSet(), {SessionMode.hold});
      expect(hold.length, greaterThan(30));
      expect(
        [
          for (final s in hold)
            if (s.idx < Position.full.index - 0.5) '$s',
        ],
        isEmpty,
        reason: 'le curseur quitte la tenue pour le rythme à venir',
      );
    });

    testWidgets(
        '$how à la fin d’une tenue « Tout », puis rythme Gland ↔ Gorge et '
        'tenue « Tout » : le rythme ne retombe pas à « Tout »', (tester) async {
      final track =
          await _replay(tester, pauseAtMs: 2500, leavesApp: leavesApp);
      final rhythm = [
        for (final s in track)
          if (s.resumed && s.elapsedMs > 3800 && s.elapsedMs < 7800) s,
      ];
      expect(rhythm.map((s) => s.mode).toSet(), {SessionMode.rhythm});
      expect(rhythm.length, greaterThan(30));
      expect(
        [
          for (final s in rhythm)
            if (s.idx > Position.throat.index + 0.5) '$s',
        ],
        isEmpty,
        reason: 'le curseur rejoint la tenue « Tout » qui suit le rythme',
      );
    });
  }
}

class _Sample {
  final int elapsedMs;
  final double idx;
  final SessionMode mode;
  final bool resumed;
  const _Sample(this.elapsedMs, this.idx, this.mode, this.resumed);
  @override
  String toString() =>
      'séance ${elapsedMs}ms : ${mode.name} ${idx.toStringAsFixed(2)}';
}

/// Position du curseur : premier point de la courbe peinte.
double? _cursorIdx(WidgetTester tester) {
  for (final cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final p = cp.painter;
    if (p != null && p.runtimeType.toString() == '_TrajectoryPainter') {
      final beats = (p as dynamic).beats as List;
      if (beats.isEmpty) return null;
      return (beats.first as dynamic).idx as double;
    }
  }
  return null;
}

/// Tenue « Tout » 0-3 s, rythme Gland ↔ Gorge 3-8 s, tenue « Tout » 8-12 s,
/// rythme ensuite. Pause quand la séance atteint [pauseAtMs] : 10 s hors de
/// l'appli sans aucune image construite si [leavesApp], sinon 10 s en
/// `inactive` avec images ; 1 s sur l'écran de pause, puis ▶ et 4 s de jeu.
Future<List<_Sample>> _replay(WidgetTester tester,
    {required int pauseAtMs, required bool leavesApp}) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const hold = SessionMode.hold;
  const rhythm = SessionMode.rhythm;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SessionScreen(
      session: const Session(
        id: 'retour',
        name: 'retour',
        description: '',
        durationSeconds: 40,
        defaultMode: hold,
        steps: [
          SessionStep(
              time: 0,
              mode: hold,
              from: Position.full,
              to: Position.full,
              duration: 3),
          SessionStep(
              time: 3,
              mode: rhythm,
              from: Position.head,
              to: Position.throat,
              bpm: 46,
              duration: 5),
          SessionStep(
              time: 8,
              mode: hold,
              from: Position.full,
              to: Position.full,
              duration: 4),
          SessionStep(
              time: 12,
              mode: rhythm,
              from: Position.head,
              to: Position.throat,
              bpm: 46,
              duration: 28),
        ],
      ),
      tts: TtsService(),
      beep: _StateBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle:
          const PunishmentBundle(failPhrases: [], punishments: []),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      autoStart: true,
    ),
  ));
  await tester.pump();
  final ctrl = Provider.of<SessionController>(
      tester.element(find.byType(MovementAnimation)),
      listen: false);

  final track = <_Sample>[];
  var resumed = false;
  var sliceEnd = DateTime.now();
  Future<void> slice({bool frame = true}) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 16)));
    final now = DateTime.now();
    if (!frame) {
      await tester.binding.delayed(now.difference(sliceEnd));
      sliceEnd = now;
      return;
    }
    await tester.pump(now.difference(sliceEnd));
    sliceEnd = now;
    final idx = _cursorIdx(tester);
    if (idx == null) return;
    track.add(_Sample(
      ctrl.elapsed.inMilliseconds,
      idx,
      tester.widget<MovementAnimation>(find.byType(MovementAnimation)).mode,
      resumed,
    ));
  }

  Future<void> run(int ms, {bool frames = true}) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await slice(frame: frames);
    }
  }

  var guard = 0;
  while (ctrl.elapsed.inMilliseconds < pauseAtMs) {
    if (++guard > 2000) fail('la séance n’atteint pas ${pauseAtMs}ms');
    await slice();
  }
  final lifecycle = tester.binding.handleAppLifecycleStateChanged;
  lifecycle(AppLifecycleState.inactive);
  if (leavesApp) {
    lifecycle(AppLifecycleState.hidden);
    lifecycle(AppLifecycleState.paused);
  }
  await run(10000, frames: !leavesApp);
  expect(ctrl.isPaused, isTrue);
  if (leavesApp) {
    lifecycle(AppLifecycleState.hidden);
    lifecycle(AppLifecycleState.inactive);
  }
  lifecycle(AppLifecycleState.resumed);
  await run(1000);
  await tester.tap(find.byIcon(Icons.play_arrow).last);
  resumed = true;
  await run(4000);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  return track;
}

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
