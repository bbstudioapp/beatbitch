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
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tant que l'horloge de séance est gelée — pendant un défi, et pendant la
/// respiration de récupération qui le suit — l'écran ne passe aucun instant à
/// venir à `MovementAnimation` : leurs secondes sont celles d'une horloge
/// arrêtée, et la courbe rattraperait son retard d'un coup à la reprise.
///
/// Le câblage vit à un seul endroit (`session_screen.dart`, argument
/// `upcomingSteps`) et aucune fonction pure ne le porte : la sonde monte donc
/// l'écran et lit la propriété reçue par le widget, frame par frame, en
/// regard de `isTimelineFrozen`.
///
/// Le prix : une séance jouée à l'horloge du mur. `Stopwatch` n'est pas
/// simulé par `flutter_test`, et c'est le gel qui fait diverger l'horloge de
/// timeline du temps réel — d'où le défi armé à 2 s et la boucle
/// `runAsync`/`pump` plutôt qu'un `pump` à horloge simulée.
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

  testWidgets(
      "horloge gelée : l'écran n'annonce aucun instant à venir, "
      'pendant le défi comme après lui', (tester) async {
    await DebugSettingsService().setSkipSessionButton(true);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();
    final t = AppLocalizations.of(tester.element(find.byType(SessionScreen)));

    var gelPendantDefi = 0;
    var gelApresDefi = 0;
    var horsGelAnnonce = 0;
    var defiRefuse = false;
    final annoncesSousGel = <String>[];

    final fin = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(fin)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));

      final anims = find.byType(MovementAnimation, skipOffstage: false);
      if (anims.evaluate().isEmpty) continue;
      final anim = tester.widget<MovementAnimation>(anims.first);
      final ctrl = Provider.of<SessionController>(tester.element(anims.first),
          listen: false);

      if (ctrl.isTimelineFrozen) {
        if (defiRefuse) {
          gelApresDefi++;
        } else {
          gelPendantDefi++;
        }
        if (anim.upcomingSteps.isNotEmpty) {
          annoncesSousGel.add('horloge à ${anim.elapsed.inMilliseconds} ms '
              '(défi actif : ${ctrl.isChallengeActive}) : '
              '${anim.upcomingSteps.length} instants annoncés, le premier à '
              '${anim.upcomingSteps.first.startSecond} s');
        }
      } else if (anim.upcomingSteps.isNotEmpty) {
        horsGelAnnonce++;
      }

      final passe = find.text(t.challengePassButton);
      if (!defiRefuse && gelPendantDefi >= 10 && passe.evaluate().isNotEmpty) {
        await tester.tap(passe.first);
        defiRefuse = true;
      }
      if (gelPendantDefi >= 10 && gelApresDefi >= 20 && horsGelAnnonce >= 1) {
        break;
      }
    }

    expect(gelPendantDefi, greaterThanOrEqualTo(10),
        reason: "le scénario n'a pas traversé le défi : rien n'a été"
            ' vérifié sous gel');
    expect(gelApresDefi, greaterThanOrEqualTo(20),
        reason: "le scénario n'a pas traversé le gel qui suit le défi :"
            ' une garde limitée au défi lui-même passerait inaperçue');
    expect(horsGelAnnonce, greaterThanOrEqualTo(1),
        reason: 'hors gel, cette séance doit annoncer des instants à venir ;'
            " sans cela le vide observé sous gel ne prouverait rien");
    expect(annoncesSousGel, isEmpty,
        reason: "l'écran a annoncé des instants à venir alors que l'horloge"
            ' de séance était gelée, sur ${annoncesSousGel.length} des '
            '${gelPendantDefi + gelApresDefi} frames gelées observées : '
            '${annoncesSousGel.take(3).join(' | ')}');
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
  durationSeconds: 60,
  defaultMode: SessionMode.rhythm,
  steps: [
    SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
    SessionStep(time: 2, mode: SessionMode.breath, duration: 10),
    SessionStep(time: 12, mode: SessionMode.rhythm, bpm: 50, duration: 14),
    SessionStep(time: 26, mode: SessionMode.rhythm, bpm: 60, duration: 34),
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
