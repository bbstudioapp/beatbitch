import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un défi de tenue se joue au tap, sans doigt posé sur l'écran : un tap
/// lance le défi, qui tourne ensuite sur sa propre horloge, et un tap le
/// clôt — abandon avant le seuil, validation au seuil.
///
/// Le bouton de départ est repéré par sa couleur et non par son libellé, pour
/// que le test tape le même bouton quel que soit le geste qu'il annonce.
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

  testWidgets('tenue gorge : un tap lance le défi, un tap le valide au seuil',
      (tester) async {
    final (ctrl, t) = await _armChallenge(tester);

    await _tapGoAndReachLive(tester, ctrl);

    await _runRealTime(tester,
        until: () => ctrl.challengePhase != ChallengePhase.live);
    expect(ctrl.challengePhase, ChallengePhase.atSeuil,
        reason: 'sans doigt posé, le défi court jusqu\'au seuil');

    await tester.tap(find.text(t.challengeTapStopAtSeuil));
    await tester.pump();
    expect(ctrl.challengePhase, ChallengePhase.ended);
    expect(ctrl.challengeOutcome, ChallengeOutcome.netSuccess);

    await _dispose(tester);
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('tenue gorge : un tap pendant le défi l\'abandonne',
      (tester) async {
    final (ctrl, t) = await _armChallenge(tester);

    await _tapGoAndReachLive(tester, ctrl);

    await tester.tap(find.text(t.challengeTapStopLive));
    await tester.pump();
    expect(ctrl.challengePhase, ChallengePhase.ended);
    expect(ctrl.challengeOutcome, ChallengeOutcome.fail);

    await _dispose(tester);
  }, timeout: const Timeout(Duration(seconds: 120)));
}

/// Monte l'écran et joue jusqu'à l'armement du défi (phase `breath`).
Future<(SessionController, AppLocalizations)> _armChallenge(
    WidgetTester tester) async {
  await DebugSettingsService().setSkipSessionButton(true);
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_host());
  await tester.pump();
  final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

  final pass = find.text(t.challengePassButton);
  await _runRealTime(tester, until: () => pass.evaluate().isNotEmpty);
  final ctrl =
      Provider.of<SessionController>(tester.element(pass), listen: false);
  expect(ctrl.challengePhase, ChallengePhase.breath);
  return (ctrl, t);
}

/// Tape le bouton de départ, puis laisse passer le compte à rebours et plus
/// que la seconde de tolérance accordée à un doigt qui décroche.
Future<void> _tapGoAndReachLive(
    WidgetTester tester, SessionController ctrl) async {
  final go = find.byWidgetPredicate(
      (w) => w is Material && w.color == const Color(0xFFFFB300));
  expect(go, findsOneWidget);
  await tester.tap(go);
  await tester.pump();
  expect(ctrl.challengePhase, ChallengePhase.countdown);

  await _runRealTime(tester,
      until: () => ctrl.challengePhase != ChallengePhase.countdown);
  expect(ctrl.challengePhase, ChallengePhase.live,
      reason: 'le tap a lancé le compte à rebours ; le doigt levé ne doit '
          'pas le ramener à l\'annonce du défi');

  await _runRealTime(tester, hold: const Duration(milliseconds: 2500));
  expect(ctrl.challengePhase, ChallengePhase.live,
      reason: 'aucun doigt posé : le défi continue sur sa propre horloge');
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
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

/// `Stopwatch` n'est pas simulé par `flutter_test` : le défi se joue à
/// l'horloge du mur, par tranches de `runAsync` suivies d'un `pump`.
Future<void> _runRealTime(
  WidgetTester tester, {
  bool Function()? until,
  Duration hold = Duration.zero,
}) async {
  final deadline = DateTime.now()
      .add(hold > Duration.zero ? hold : const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    if (until != null && until()) return;
  }
  if (until != null) fail('condition non atteinte en 20 s');
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
