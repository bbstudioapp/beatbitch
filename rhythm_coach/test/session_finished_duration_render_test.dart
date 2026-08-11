import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
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

  testWidgets("l'écran de fin annonce le temps joué, défi compris",
      (tester) async {
    await DebugSettingsService().setSkipSessionButton(true);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();
    final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

    // Le défi s'arme à 2 s de timeline, et gèle l'horloge de contenu jusqu'à
    // ce qu'il soit clos.
    await _runRealTime(tester,
        until: () => find.text(t.challengePassButton).evaluate().isNotEmpty);
    // Du temps de jeu passé sur l'écran du défi. Il doit dépasser nettement
    // les 7 s de contenu qui resteront après excision du défi (25 − 13 − 5),
    // sinon les deux horloges se rejoindraient et le test ne trancherait
    // plus entre elles.
    await _runRealTime(tester, hold: const Duration(seconds: 12));

    await tester.tap(find.text(t.challengePassButton));
    await _runRealTime(tester, hold: const Duration(seconds: 1));

    await tester.tap(find.text(t.sessionDebugFinishButton));
    await _runRealTime(tester,
        until: () => find.text(t.sessionFinishedTitle).evaluate().isNotEmpty);

    // Premier écran de fin : les badges sont encore masqués, la durée n'est
    // annoncée qu'une fois « merci » tapé.
    final prefix = t.sessionFinishedDuration('§').split('§').first;
    if (_finishedDuration(tester, prefix) == null) {
      await tester.tap(find.text(t.sessionFinishedDefaultEnd.toUpperCase()));
      await _runRealTime(tester,
          until: () => _finishedDuration(tester, prefix) != null);
    }

    final rendered = _finishedDuration(tester, prefix) ?? '';
    expect(rendered, isNotEmpty,
        reason: "l'écran de fin doit annoncer une durée");
    expect(_secondsIn(rendered), greaterThanOrEqualTo(14),
        reason: 'chiffre rendu « $rendered » : sur l\'horloge de contenu '
            "l'écran annoncerait les 7 s qui restent à la timeline, pas le "
            'temps que la joueuse vient de passer');
  }, timeout: const Timeout(Duration(seconds: 180)));
}

Widget _host() => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
        session: _session,
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

/// Laisse courir l'horloge du mur : sous [WidgetTester.runAsync] les `Timer`
/// du contrôleur sont réels, et `pump()` entre deux tranches rend ce qu'ils
/// ont produit. Avec [hold], attend la durée pleine ; avec [until], jusqu'à
/// la condition.
Future<void> _runRealTime(
  WidgetTester tester, {
  bool Function()? until,
  Duration hold = Duration.zero,
}) async {
  final deadline = DateTime.now()
      .add(hold > Duration.zero ? hold : const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    if (until != null && until()) return;
  }
  if (until != null) fail('condition non atteinte en 40 s');
}

String? _finishedDuration(WidgetTester tester, String prefix) {
  for (final text in tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data)
      .whereType<String>()) {
    if (text.startsWith(prefix)) return text;
  }
  return null;
}

int _secondsIn(String rendered) {
  final withMinutes = RegExp(r'(\d+)\s*min\D+?(\d+)').firstMatch(rendered);
  if (withMinutes != null) {
    return int.parse(withMinutes.group(1)!) * 60 +
        int.parse(withMinutes.group(2)!);
  }
  final minutesOnly = RegExp(r'(\d+)\s*min').firstMatch(rendered);
  if (minutesOnly != null) return int.parse(minutesOnly.group(1)!) * 60;
  return int.parse(RegExp(r'(\d+)').firstMatch(rendered)!.group(1)!);
}

const _challenge = Challenge(
  axis: CapabilityAxis.holdThroatStreak,
  kind: ChallengeAxisKind.duration,
  targetThreshold: 5,
  mode: SessionMode.hold,
  from: Position.throat,
  to: Position.throat,
  comfortAtCalibration: 4,
);

const _session = Session(
  id: 'defi',
  name: 'defi',
  description: '',
  durationSeconds: 25,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
    SessionStep(time: 2, mode: SessionMode.breath, duration: 13),
    SessionStep(time: 20, mode: SessionMode.rhythm, bpm: 40, duration: 5),
  ],
  challenges: [_challenge],
  challengeTriggerTimes: [2],
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
  Future<void> playForMode(SessionMode mode) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
