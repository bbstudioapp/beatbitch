import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_music.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Monte l'écran de séance : ce que `session_screen.dart` fait d'une séance à
/// morceau n'est tenu par aucune fonction pure. Le lecteur est le vrai
/// `MusicEngine` sur des canaux muets — il ne rapporte jamais de position, la
/// séance tourne donc sur son repli (horloge murale, après 3 s).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const audioEventChannels = [
    EventChannel('xyz.luan/audioplayers.global/events'),
    EventChannel('xyz.luan/audioplayers/events/ambience_loop'),
    EventChannel('xyz.luan/audioplayers/events/session_music'),
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
              channel, MockStreamHandler.inline(onListen: (_, __) {}));
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

  Future<SessionController> mount(WidgetTester tester, Session session) async {
    await DebugSettingsService().setSkipSessionButton(false);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(session));
    await tester.pump();
    final ctrl = Provider.of<SessionController>(
        tester.element(find.byType(Scaffold).first),
        listen: false);
    await _runRealTime(tester, until: () => ctrl.isRunning);
    return ctrl;
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('session-settings-button')));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> closeSettings(WidgetTester tester) async {
    await tester.tapAt(const Offset(200, 20));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
      'séance à morceau : pas de curseur d\'ambiance, et un JE PEUX PAS '
      'affiche la respiration sans quitter l\'état running', (tester) async {
    final ctrl = await mount(tester, _musical);
    final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

    expect(ctrl.isMusical, isTrue);
    await openSettings(tester);
    expect(find.text(t.sessionVoiceLabel), findsOneWidget,
        reason: 'le curseur de voix reste');
    expect(find.text(t.sessionAmbienceLabel), findsNothing);
    await closeSettings(tester);
    expect(find.text(t.sessionDebugMusicBeepAdvanceLabel), findsOneWidget,
        reason: 'réglage debug de l\'avance des bips');
    expect(find.text('150 ms'), findsOneWidget);
    final plus = find.byTooltip(t.sessionDebugMusicBeepAdvanceIncrease);
    await tester.ensureVisible(plus);
    await tester.tap(plus);
    await tester.pump();
    expect(ctrl.musicBeepAdvanceMs, 160);
    expect(find.text('160 ms'), findsOneWidget);
    expect(find.text(t.sessionFailPhaseBreath.toUpperCase()), findsNothing);

    await tester.tap(find.text(t.sessionFailButton));
    await tester.pump();

    expect(ctrl.state, SessionState.running);
    expect(ctrl.isMusicBreathing, isTrue);
    expect(find.text(t.sessionFailPhaseBreath.toUpperCase()), findsOneWidget,
        reason: 'l\'indicateur de souffle est monté pendant le souffle');

    await tester.tap(find.text(t.sessionFailButton));
    await tester.pump();
    expect(ctrl.isMusicBreathing, isTrue,
        reason: 'le bouton est grisé pendant le souffle');

    await ctrl.stop();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets(
      'témoin : une séance ordinaire garde son curseur d\'ambiance et '
      'n\'affiche pas de souffle', (tester) async {
    final ctrl = await mount(tester, _plain);
    final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

    expect(ctrl.isMusical, isFalse);
    await openSettings(tester);
    expect(find.text(t.sessionAmbienceLabel), findsOneWidget);
    await closeSettings(tester);
    expect(find.text(t.sessionDebugMusicBeepAdvanceLabel), findsNothing);
    expect(find.text(t.sessionFailPhaseBreath.toUpperCase()), findsNothing);

    await ctrl.stop();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 90)));
}

Widget _host(Session session) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
        session: session,
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
    );

Future<void> _runRealTime(
  WidgetTester tester, {
  required bool Function() until,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    if (until()) return;
  }
  fail('condition non atteinte en 40 s');
}

const _steps = [
  SessionStep(time: 0, mode: SessionMode.breath, duration: 5),
  SessionStep(
      time: 5,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      bpm: 61),
];

const _musical = Session(
  id: 'musique-ecran',
  name: 'musique-ecran',
  description: '',
  durationSeconds: 120,
  defaultMode: SessionMode.rhythm,
  steps: _steps,
  music: SessionMusic(
    asset: 'audio/music/test_track.mp3',
    bpm: 121.96,
    firstBeatSeconds: 16.934,
  ),
);

const _plain = Session(
  id: 'ordinaire-ecran',
  name: 'ordinaire-ecran',
  description: '',
  durationSeconds: 120,
  defaultMode: SessionMode.rhythm,
  steps: _steps,
);

class _SilentBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {}
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
