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

  Widget screen(String coach) => MaterialApp(
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
          coachTag: coach,
        ),
      );

  test("sans fond d'intro : son premier plan de jeu, sinon le dégradé", () {
    final svc = BackgroundsService.instance
      ..setBundle(bundle(const [
        'lina-v3-a1-play-01_play_lina',
        'lina-v3-a1-play-02_play_lina',
        'pov-A-gag_pov_hold_full',
      ]));
    for (final coach in ['lina', 'marc']) {
      for (final previous in ['lina-v3-a1-play-02', 'pov-A-gag']) {
        svc.setById(previous);
        expect(svc.pickIntro(coach), coach == 'lina');
        expect(svc.current.value?.id,
            coach == 'lina' ? 'lina-v3-a1-play-01' : isNull,
            reason: '$coach après $previous');
      }
    }
  });

  testWidgets(
      "l'intro d'une coach sans fond d'intro n'affiche pas le fond de la séance précédente",
      (tester) async {
    final svc = BackgroundsService.instance
      ..setBundle(bundle(const [
        'lina-v3-a1-play-01_play_lina',
        'jade-v3-a1-play-01_play_jade',
      ]));
    svc.pickForContext(const BackgroundContext(mode: 'hold', coach: 'lina'));
    expect(svc.current.value?.id, 'lina-v3-a1-play-01',
        reason: 'témoin : la séance de Lina laisse son fond');
    await tester.pumpWidget(screen('jade'));
    await tester.pump();
    expect(svc.current.value?.id, 'jade-v3-a1-play-01',
        reason: 'intro de Jade : ${svc.current.value?.id}');
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
