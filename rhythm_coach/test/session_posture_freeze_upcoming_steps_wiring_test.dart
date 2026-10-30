import 'dart:async';

import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/posture.dart';
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

/// Aucun défi dans la séance : son gel recouvrirait celui de la posture.
///
/// `Stopwatch` n'est pas simulé par `flutter_test` : la séance se joue à
/// l'horloge du mur, d'où le break de 2 s et la boucle `runAsync`/`pump`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
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

  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      switch (call.method) {
        case 'speak':
          unawaited(pushFromEngine('speak.onStart', true));
          Timer(const Duration(milliseconds: 40),
              () => pushFromEngine('speak.onComplete', true));
          return 1;
        case 'stop':
          unawaited(pushFromEngine('speak.onCancel', true));
          return 1;
        case 'getVoices':
          return <dynamic>[];
        default:
          return 1;
      }
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
        .setMockMethodCallHandler(ttsChannel, null);
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
      "attente de posture à la sortie d'une pause, sans défi : la mise en "
      'place confirmée rend la courbe et ses instants à venir', (tester) async {
    await DebugSettingsService().setSkipSessionButton(true);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();
    final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

    var gelPosture = 0;
    var horsGelApresMiseEnPlace = 0;
    var framesDefiActif = 0;
    var miseEnPlaceConfirmee = false;
    final ctrl = Provider.of<SessionController>(
        tester.element(find.byType(MovementAnimation)),
        listen: false);

    final fin = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(fin)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));

      final anims = find.byType(MovementAnimation, skipOffstage: false);
      final anim = anims.evaluate().isEmpty
          ? null
          : tester.widget<MovementAnimation>(anims.first);

      if (ctrl.isChallengeActive) framesDefiActif++;

      if (ctrl.awaitingPostureReady) {
        gelPosture++;
      } else if (miseEnPlaceConfirmee &&
          anim != null &&
          anim.upcomingSteps.isNotEmpty) {
        horsGelApresMiseEnPlace++;
      }

      final enPlace = find.text(t.sessionPostureReadyButton);
      if (!miseEnPlaceConfirmee &&
          gelPosture >= 15 &&
          enPlace.evaluate().isNotEmpty) {
        await tester.tap(enPlace.first);
        miseEnPlaceConfirmee = true;
      }
      if (gelPosture >= 15 && horsGelApresMiseEnPlace >= 10) break;
    }

    expect(gelPosture, greaterThanOrEqualTo(15),
        reason: "le scénario n'est jamais entré en attente de posture");
    expect(framesDefiActif, 0,
        reason: 'un défi actif recouvrirait le gel de posture : ce scénario ne'
            ' prouverait alors rien de plus que son voisin');
    expect(miseEnPlaceConfirmee, isTrue,
        reason: "le bouton de mise en place n'a jamais été trouvé à l'écran");
    expect(horsGelApresMiseEnPlace, greaterThanOrEqualTo(10),
        reason: 'la mise en place confirmée doit rendre à la courbe ses'
            ' instants à venir');
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('le bouton de la bannière de pause passe la pause',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(session: _longBreakSession));
    await tester.pump();
    final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

    SessionController? ctrl;
    var skipped = false;
    final fin = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(fin) && !skipped) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      final skip = find.text(t.sessionBreakSkipButton);
      if (skip.evaluate().isEmpty) continue;
      ctrl = Provider.of<SessionController>(tester.element(skip.first),
          listen: false);
      expect(ctrl.breakActive, isTrue);
      await tester.tap(skip.first);
      await tester.pump();
      skipped = true;
    }

    expect(skipped, isTrue, reason: 'bouton jamais affiché pendant la pause');
    expect(ctrl!.breakActive, isFalse);
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(40));
    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Widget _host({Session session = _session}) => MaterialApp(
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

const _session = Session(
  id: 'posture',
  name: 'posture',
  description: '',
  durationSeconds: 60,
  defaultMode: SessionMode.rhythm,
  initialPose: Posture.free,
  breaks: [
    ScriptedBreak(time: 1, durationSeconds: 2, newPose: Posture.kneeling),
  ],
  steps: [
    SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 1),
    SessionStep(time: 3, mode: SessionMode.rhythm, bpm: 50, duration: 12),
    SessionStep(time: 15, mode: SessionMode.rhythm, bpm: 60, duration: 20),
    SessionStep(time: 35, mode: SessionMode.rhythm, bpm: 70, duration: 25),
  ],
);

const _longBreakSession = Session(
  id: 'pause-longue',
  name: 'pause-longue',
  description: '',
  durationSeconds: 60,
  defaultMode: SessionMode.rhythm,
  breaks: [ScriptedBreak(time: 1, durationSeconds: 39)],
  steps: [
    SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 1),
    SessionStep(time: 40, mode: SessionMode.rhythm, bpm: 50, duration: 20),
  ],
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
