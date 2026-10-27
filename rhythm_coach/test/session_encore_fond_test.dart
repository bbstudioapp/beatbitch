import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  tearDown(() {
    BackgroundsService.instance.debugResetForTest();
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

  SessionScreen screen({bool encore = false}) => SessionScreen(
        session: const Session(
          id: 'tenue',
          name: 'tenue',
          description: '',
          durationSeconds: 30,
          defaultMode: SessionMode.hold,
          steps: [
            SessionStep(
                time: 0,
                mode: SessionMode.hold,
                to: Position.throat,
                duration: 30),
          ],
        ),
        tts: TtsService(),
        beep: _SilentBeepEngine(),
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
        coachTag: 'lina',
        keepsBackgroundTier: encore,
      );

  testWidgets("à la séance de plus, la coach garde le palier qu'elle a atteint",
      (tester) async {
    final svc = BackgroundsService.instance
      ..setBundle(BackgroundsBundle(entries: [
        for (final n in const [
          'lina-v3-a1-play-01_play_lina',
          'lina-v3-a3-play-01_play_lina_nu2',
        ])
          BackgroundsLoader.parseEntry('assets/backgrounds/$n.webp')!,
      ]));
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SizedBox(),
    ));

    nav.currentState!.push(MaterialPageRoute(builder: (_) => screen()));
    await _until(tester, () => svc.current.value != null);
    expect(svc.current.value?.id, 'lina-v3-a1-play-01');
    final first = _controllers(tester).single;

    svc.pickForContext(const BackgroundContext(
        mode: 'hold', position: 'throat', coach: 'lina', tier: 'nu2'));
    expect(svc.current.value?.id, 'lina-v3-a3-play-01',
        reason: 'témoin : la séance finit nue');

    nav.currentState!.pushReplacement(
        MaterialPageRoute(builder: (_) => screen(encore: true)));
    await _until(tester, () {
      final ctrls = _controllers(tester);
      return ctrls.length == 1 &&
          !identical(ctrls.single, first) &&
          ctrls.single.isRunning &&
          svc.current.value != null;
    });
    expect(svc.current.value?.id, 'lina-v3-a3-play-01');
  });
}

List<SessionController> _controllers(WidgetTester tester) => [
      for (final e in find
          .descendant(
              of: find.byType(SessionScreen, skipOffstage: false),
              matching: find.byType(Scaffold, skipOffstage: false))
          .evaluate())
        Provider.of<SessionController>(e, listen: false),
    ];

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition non atteinte');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
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
