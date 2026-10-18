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
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'intro et le décompte de la séance jouent le fond `intro` de la coach.
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
    BackgroundsService.instance.debugResetForTest();
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

  BackgroundsBundle bundle(List<String> names) => BackgroundsBundle(entries: [
        for (final n in names)
          BackgroundsLoader.parseEntry('assets/backgrounds/$n.webp')!,
      ]);

  test("le fond d'intro est celui de la coach, au palier demandé", () {
    final svc = BackgroundsService.instance
      ..setBundle(bundle(const [
        'lina-pack-intro-1_lina',
        'lina-pack-nu1-intro-1_lina_nu1',
        'helene-pack-intro-1_helene',
        'lina-pack-breath-1_lina_breath',
      ]));
    expect(svc.pickIntro('lina'), isTrue);
    expect(svc.current.value?.id, 'lina-pack-intro-1');
    expect(svc.pickIntro('lina', tier: 'nu1'), isTrue);
    expect(svc.current.value?.id, 'lina-pack-nu1-intro-1');
    expect(svc.pickIntro('jade'), isFalse);
    expect(svc.current.value?.id, 'lina-pack-nu1-intro-1',
        reason: 'sans fond intro, le fond courant reste');
  });

  testWidgets("l'écran joue le fond intro de la coach pendant l'intro",
      (tester) async {
    BackgroundsService.instance.setBundle(bundle(const [
      'lina-pack-intro-1_lina',
      'helene-pack-intro-1_helene',
      'lina-pack-breath-1_lina_breath',
    ]));
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
        introText: 'Bonjour',
        coachTag: 'lina',
      ),
    ));
    await tester.pump();
    expect(BackgroundsService.instance.current.value?.id, 'lina-pack-intro-1');
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
