import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/session_finale_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le voile de la pause couvre tout l'écran, y compris sous la barre d'état :
/// une encoche ou une barre d'état visible ne laisse pas de bande claire.
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
    // `audioplayers` s'abonne à ses flux d'événements dès la construction du
    // player d'ambiance : sans ces deux-là, un `MissingPluginException`
    // remonte au framework de test et fait échouer le rendu.
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

  Future<void> pumpSession(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
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
              duration: 30,
            ),
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
      ),
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets("le voile de pause couvre tout l'écran, barre d'état comprise",
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    const statusBar = FakeViewPadding(top: 80, bottom: 48);
    tester.view.padding = statusBar;
    tester.view.viewPadding = statusBar;
    addTearDown(tester.view.reset);
    await pumpSession(tester);
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);

    final veil = find.ancestor(
      of: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.play_arrow && w.size == 72),
      matching: find.byType(BackdropFilter),
    );
    expect(veil, findsOneWidget);
    final rect = tester.getRect(veil);
    expect(rect, const Rect.fromLTWH(0, 0, 1080, 2400));
  });

  testWidgets('la finale garde son état à travers une pause puis une reprise',
      (tester) async {
    await pumpSession(tester);
    await settle(tester);
    final avant = tester.state(find.byType(SessionFinaleOverlay));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    final veil = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.play_arrow && w.size == 72);
    expect(veil, findsOneWidget);
    expect(tester.state(find.byType(SessionFinaleOverlay)), same(avant));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    await tester.tap(veil);
    await settle(tester);
    expect(veil, findsNothing);
    expect(tester.state(find.byType(SessionFinaleOverlay)), same(avant));
  });
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
