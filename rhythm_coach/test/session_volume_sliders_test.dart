import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

/// Le chiffre annoncé en fin de séance est le temps réellement joué, défi
/// compris — lu sur le texte **rendu** par l'écran.
///
/// `session_time_accounting_invariant_test.dart` verrouille les deux autres
/// clauses de la comptabilité du temps (ce qui décide la fin, ce qui est
/// crédité aux statistiques). Celle-ci se fermait sur la ligne qui alimente
/// le panneau, faute de pouvoir lire le chiffre rendu ; elle se lit
/// maintenant pour de vrai.
///
/// Le prix : un défi joué à l'horloge du mur. `Stopwatch` n'est pas simulé
/// par `flutter_test`, et c'est le gel de la timeline pendant le défi qui
/// fait diverger les deux horloges — sans divergence, les deux câblages
/// rendraient le même chiffre et le test ne prouverait rien. Une fois
/// l'écart creusé, le bouton de debug de l'écran (`debugFinishSuccess`)
/// clôt le reste par arithmétique plutôt qu'en attendant la séance.
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

  testWidgets(
      "les curseurs de volume s'ouvrent sur les volumes choisis, pas au maximum",
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
        session: const Session(
          id: 'volumes',
          name: 'volumes',
          description: '',
          durationSeconds: 30,
          defaultMode: SessionMode.rhythm,
          steps: [
            SessionStep(
                time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 30),
          ],
        ),
        tts: _VoiceAt(0.4),
        beep: _SilentBeepEngine(),
        ambience: _AmbienceAt(0.2),
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
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final values =
        tester.widgetList<Slider>(find.byType(Slider)).map((s) => s.value);
    expect(values, containsAll(<double>[0.4, 0.2]));
    expect(values, isNot(contains(1.0)));
  });
}

class _VoiceAt extends TtsService {
  _VoiceAt(this._v);
  final double _v;
  @override
  double get volume => _v;
}

class _AmbienceAt extends _SilentAmbienceEngine {
  _AmbienceAt(this._v);
  final double _v;
  @override
  double get volume => _v;
}

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
