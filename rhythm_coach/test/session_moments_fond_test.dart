import 'dart:async';

import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/main.dart' show milestoneService;
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/play_once_image.dart';
import 'package:beat_bitch/widgets/session_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _names = [
  'lina-v3-a1-play-01_play_lina',
  'lina-v3-a2-play-01_play_lina_nu1',
  'lina-v3-a3-play-01_play_lina_nu2',
  'lina-v3-a1-fail_fail_lina',
  'lina-v3-a2-fail_fail_lina_nu1',
  'lina-v3-a3-fail_fail_lina_nu2',
  'lina-v3-a1-punish_punish_lina',
  'lina-v3-a2-punish_punish_lina_nu1',
  'lina-v3-a3-punish_punish_lina_nu2',
  'lina-v3-a1-milestone_milestone_lina',
  'lina-v3-a2-milestone_milestone_lina_nu1',
  'lina-v3-a3-milestone_milestone_lina_nu2',
  'helene-v3-a1-play-01_play_helene',
  'helene-v3-a1-punish_punish_helene',
  'helene-v3-a2-punish_punish_helene_nu1',
  'helene-v3-a3-punish_punish_helene_nu2',
  'helene-v3-a1-milestone_milestone_helene',
  'helene-v3-a2-milestone_milestone_helene_nu1',
  'helene-v3-a3-milestone_milestone_helene_nu2',
];

const _milestoneId = 'm_fond_etape';

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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    BackgroundsService.instance.setBundle(BackgroundsBundle(entries: [
      for (final n in _names)
        BackgroundsLoader.parseEntry('assets/backgrounds/$n.webp')!,
    ]));
  });

  tearDown(() {
    BackgroundsService.instance.debugResetForTest();
    milestoneService.seedForTest(catalog: const []);
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
      'pendant une punition, l\'écran montre celle de la coach à son palier, '
      'puis reprend le fil', (tester) async {
    await tester.pumpWidget(_app(_screen(coach: 'lina', durationSeconds: 60)));
    final ctrl = _controller(tester);
    await _until(tester, () => ctrl.state == SessionState.running);
    expect(_fond(), 'lina-v3-a1-play-01');

    unawaited(ctrl.debugRunMiniPunishment(_punishment));
    await tester.pump();
    expect(ctrl.state, SessionState.failing);
    expect(_fond(), 'lina-v3-a1-punish');
    expect(_shownAsset('lina-v3-a1-punish_punish_lina'), findsOneWidget);

    await _until(tester, () => ctrl.state == SessionState.running);
    expect(_fond(), 'lina-v3-a1-play-01');
    await _unmount(tester);
  });

  testWidgets('une coach sans punition garde son fond courant', (tester) async {
    await tester.pumpWidget(_app(_screen(coach: 'jade', durationSeconds: 60)));
    final ctrl = _controller(tester);
    await _until(tester, () => ctrl.state == SessionState.running);
    final shown = _fond();

    unawaited(ctrl.debugRunMiniPunishment(_punishment));
    await tester.pump();
    expect(ctrl.state, SessionState.failing);
    expect(_fond(), shown);
    await _until(tester, () => ctrl.state == SessionState.running);
    await _unmount(tester);
  });

  testWidgets(
      'une étape validée montre l\'anim de la coach une fois, à son palier, '
      'puis rend le fond d\'avant', (tester) async {
    milestoneService.seedForTest(catalog: const [
      LevelMilestone(
        id: _milestoneId,
        humilRequired: 0,
        displayLabel: _milestoneId,
        sequence: [],
        durationSeconds: 1,
        unlocks: [UnlockKey.holdHead],
      ),
    ]);
    final shown = <String?>[];
    void record() => shown.add(_fond());
    BackgroundsService.instance.current.addListener(record);
    addTearDown(
        () => BackgroundsService.instance.current.removeListener(record));

    await tester.pumpWidget(_app(_screen(
      coach: 'lina',
      durationSeconds: 3,
      milestoneId: _milestoneId,
    )));
    final ctrl = _controller(tester);
    await _until(tester, () => ctrl.state == SessionState.finished);
    expect(ctrl.sessionMilestoneUnlocks.map((m) => m.id), [_milestoneId]);

    final milestone = BackgroundsService.instance.current.value!;
    expect(milestone.id, startsWith('lina-v3-a'));
    expect(milestone.isMilestone, isTrue, reason: milestone.id);
    final before = shown[shown.length - 2]!;
    expect(before, contains('-play-'));
    expect(milestone.tier, _tierOf(before), reason: 'palier de $before');

    final once = find.byType(PlayOnceImage);
    expect(once, findsOneWidget);
    expect(tester.widget<PlayOnceImage>(once).path, milestone.path);
    tester.widget<PlayOnceImage>(once).onDone();
    await tester.pump();
    expect(_fond(), before);
    await _unmount(tester);
  });

  testWidgets(
      'sans coach, l\'écran garde le fond neutre : jeu, punition, étape '
      'validée', (tester) async {
    milestoneService.seedForTest(catalog: const [
      LevelMilestone(
        id: _milestoneId,
        humilRequired: 0,
        displayLabel: _milestoneId,
        sequence: [],
        durationSeconds: 1,
        unlocks: [UnlockKey.holdHead],
      ),
    ]);
    final shown = <String?>[];
    void record() => shown.add(_fond());
    BackgroundsService.instance.current.addListener(record);
    addTearDown(
        () => BackgroundsService.instance.current.removeListener(record));
    final neutral = find.byKey(const ValueKey('__placeholder__'));
    final media = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName.startsWith('assets/backgrounds/'));

    await tester.pumpWidget(_app(_screen(
      coach: null,
      durationSeconds: 3,
      milestoneId: _milestoneId,
    )));
    final ctrl = _controller(tester);
    await _until(tester, () => ctrl.state == SessionState.running);
    expect(neutral, findsOneWidget);
    expect(media, findsNothing);

    unawaited(ctrl.debugRunMiniPunishment(_punishment));
    await tester.pump();
    expect(ctrl.state, SessionState.failing);
    expect(neutral, findsOneWidget);

    await _until(tester, () => ctrl.state == SessionState.finished);
    expect(ctrl.sessionMilestoneUnlocks.map((m) => m.id), [_milestoneId]);
    await tester.pump(const Duration(seconds: 1));
    expect(neutral, findsOneWidget);
    expect(media, findsNothing);
    expect(find.byType(PlayOnceImage), findsNothing);
    expect(shown.whereType<String>(), isEmpty);
    await _unmount(tester);
  });
}

const _punishment = Punishment(
  id: 'p',
  name: 'p',
  durationSeconds: 1,
  steps: [
    SessionStep(time: 0, mode: SessionMode.hold, to: Position.throat),
  ],
);

String? _tierOf(String id) => BackgroundsLoader.parseEntry(
        'assets/backgrounds/${_names.firstWhere((n) => n.startsWith('${id}_'))}.webp')!
    .tier;

String? _fond() => BackgroundsService.instance.current.value?.id;

Finder _shownAsset(String basename) => find.byWidgetPredicate((w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == 'assets/backgrounds/$basename.webp');

SessionController _controller(WidgetTester tester) =>
    Provider.of<SessionController>(
        tester.element(find.byType(SessionBackground)),
        listen: false);

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition non atteinte');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Widget _app(Widget home) => DefaultAssetBundle(
      bundle: _SilentBackgroundsBundle(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

SessionScreen _screen({
  required String? coach,
  required int durationSeconds,
  String? milestoneId,
}) =>
    SessionScreen(
      session: Session(
        id: 'moments',
        name: 'moments',
        description: '',
        durationSeconds: durationSeconds,
        defaultMode: SessionMode.rhythm,
        steps: [
          SessionStep(
              time: 0,
              mode: SessionMode.rhythm,
              bpm: 40,
              duration: durationSeconds),
        ],
        milestoneId: milestoneId,
        milestoneStartTime: milestoneId == null ? null : 0,
        milestoneDurationSeconds: milestoneId == null ? null : 1,
      ),
      tts: TtsService(),
      beep: _SilentBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle:
          const PunishmentBundle(failPhrases: [], punishments: [_punishment]),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      coachTag: coach,
      autoStart: true,
    );

/// Les fonds sont gitignorés : leur chargement ne doit ni aboutir ni échouer.
class _SilentBackgroundsBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => key.startsWith('assets/backgrounds/')
      ? Completer<ByteData>().future
      : rootBundle.load(key);
}

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
