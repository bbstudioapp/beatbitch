import 'dart:async';

import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/main.dart' show milestoneService;
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/session_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Disposition de l'écran de séance en cours : une seule ligne de boutons dont
/// « JE PEUX PAS » reste le plus large et le plus plein, « UTILISE-MOI » qui
/// n'apparaît qu'après 2 minutes sans FAIL, réglages de volume derrière une
/// icône, flèche de retour au comportement inchangé, mode immersif rétabli.
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
  final uiModes = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    uiModes.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        uiModes.add(call.arguments as String);
      }
      return null;
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
    milestoneService.setSessionUnlocks({UnlockKey.begLibre});
  });

  tearDown(() {
    milestoneService.setSessionUnlocks(<UnlockKey>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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

  final failButton = find.byKey(const Key('session-fail-button'));
  final useMeButton = find.byKey(const Key('session-useme-button'));
  final settingsButton = find.byKey(const Key('session-settings-button'));
  final backButton = find.byKey(const Key('session-back-button'));

  SessionController ctrlOf(WidgetTester tester) =>
      Provider.of<SessionController>(
          tester.element(find.byType(SessionBackground)),
          listen: false);

  Future<void> settle(WidgetTester tester, [int steps = 10]) async {
    for (var i = 0; i < steps; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  SessionScreen screen({TtsService? tts, AmbienceEngine? ambience}) =>
      SessionScreen(
        session: const Session(
          id: 'v2',
          name: 'Carrière',
          description: '',
          durationSeconds: 600,
          defaultMode: SessionMode.rhythm,
          steps: [
            SessionStep(
                time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 600),
          ],
        ),
        tts: tts ?? _Voice(0.4),
        beep: _SilentBeepEngine(),
        ambience: ambience ?? _Ambience(0.2),
        punishmentBundle: const PunishmentBundle(
            failPhrases: ['raté'], punishments: [_punishment]),
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
        isCareer: true,
        onRequestUpgrade: (_) async {},
        autoStart: true,
      );

  Future<void> pumpScreen(WidgetTester tester, SessionScreen s,
      {Size size = const Size(390, 850)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: s,
    ));
    await settle(tester);
    for (var i = 0; i < 60 && !ctrlOf(tester).isRunning; i++) {
      await settle(tester, 1);
    }
  }

  testWidgets(
      'boutons : « JE PEUX PAS » seul sur la ligne tant que '
      '« UTILISE-MOI » n\'est pas débloqué', (tester) async {
    await pumpScreen(tester, screen());

    expect(failButton, findsOneWidget);
    expect(useMeButton, findsNothing);
    expect(tester.getSize(failButton).width, greaterThan(390 * 0.8));
  });

  testWidgets(
      'boutons : une ligne, « JE PEUX PAS » plus large, plein et '
      'tapable, « UTILISE-MOI » à côté et semi-transparent', (tester) async {
    await pumpScreen(tester, screen());
    ctrlOf(tester).debugAddPlayed(SessionController.useMeUnlockAfter);
    await settle(tester, 10);

    expect(useMeButton, findsOneWidget);
    final fail = tester.getRect(failButton);
    final useMe = tester.getRect(useMeButton);
    expect(fail.center.dy, closeTo(useMe.center.dy, 1));
    expect(useMe.right, lessThanOrEqualTo(fail.left));
    expect(fail.width, greaterThan(useMe.width));
    expect(fail.height, inInclusiveRange(48, 64));
    final ctrl = ctrlOf(tester);

    double opacityOf(Finder f) => tester
        .widgetList<Opacity>(
            find.ancestor(of: f, matching: find.byType(Opacity)))
        .fold(1.0, (acc, o) => acc * o.opacity);
    expect(opacityOf(failButton), 1.0);
    final failFill = tester
        .widget<Material>(find
            .descendant(of: failButton, matching: find.byType(Material))
            .first)
        .color!;
    expect(failFill.a, 1.0);
    expect(opacityOf(useMeButton), closeTo(0.6, 0.01));

    await tester.tap(failButton);
    await settle(tester, 3);
    expect(ctrl.isFailing, isTrue);
    await tester.runAsync(ctrl.stop);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('règle des 2 minutes : sans FAIL, un FAIL remet à zéro',
      (tester) async {
    await pumpScreen(tester, screen());
    final ctrl = ctrlOf(tester);

    const second = Duration(seconds: 1);
    const unlock = SessionController.useMeUnlockAfter;
    expect(ctrl.useMeUnlocked, isFalse);
    ctrl.debugAddPlayed(unlock - ctrl.playedElapsed - second);
    expect(ctrl.useMeUnlocked, isFalse);
    ctrl.debugAddPlayed(second * 2);
    expect(ctrl.useMeUnlocked, isTrue);

    unawaited(ctrl.triggerFail());
    await tester.pump();
    expect(ctrl.isFailing, isTrue);
    expect(ctrl.useMeUnlocked, isFalse);
    ctrl.debugAddPlayed(unlock - second);
    expect(ctrl.useMeUnlocked, isFalse);
    ctrl.debugAddPlayed(second * 2);
    expect(ctrl.useMeUnlocked, isTrue);
    await tester.runAsync(ctrl.stop);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('réglages : curseurs derrière une icône, mêmes volumes écrits',
      (tester) async {
    final tts = _Voice(0.4);
    final ambience = _Ambience(0.2);
    await pumpScreen(tester, screen(tts: tts, ambience: ambience));

    expect(find.byType(Slider), findsNothing);
    await tester.tap(settingsButton);
    await settle(tester, 3);

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.map((s) => s.value), containsAll(<double>[0.4, 0.2]));

    await tester.drag(find.byType(Slider).first, const Offset(40, 0));
    await tester.drag(find.byType(Slider).last, const Offset(40, 0));
    await settle(tester, 2);
    expect(tts.setVolumes, isNotEmpty);
    expect(tts.setVolumes.last, isNot(0.4));
    expect(ambience.volume, isNot(0.2));
  });

  testWidgets(
      'plein écran : pas de barre d\'application, mode immersif '
      'posé puis rétabli à la sortie', (tester) async {
    await pumpScreen(tester, screen());
    expect(find.byType(AppBar), findsNothing);
    expect(uiModes.last, 'SystemUiMode.immersiveSticky');

    await tester.pumpWidget(const SizedBox());
    expect(uiModes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets(
      'flèche de retour : même confirmation qu\'avant, sortie '
      'rétablit le mode immersif', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Text('accueil')),
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => screen()));
    await settle(tester);

    await tester.tap(backButton);
    await settle(tester, 2);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Continuer'));
    await settle(tester, 6);
    expect(find.byType(AlertDialog), findsNothing);
    expect(ctrlOf(tester).isRunning, isTrue);

    await tester.tap(backButton);
    await settle(tester, 2);
    await tester.tap(find.text('Arrêter'));
    for (var i = 0;
        i < 40 && find.byType(SessionScreen).evaluate().isNotEmpty;
        i++) {
      await settle(tester, 1);
    }
    expect(find.text('accueil'), findsOneWidget);
    expect(uiModes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('fond : dégradé bas seul en séance, voile uniforme ailleurs',
      (tester) async {
    await pumpScreen(tester, screen());
    expect(
        tester
            .widget<SessionBackground>(find.byType(SessionBackground))
            .bottomVeilOnly,
        isTrue);
  });
}

const _punishment = Punishment(
  id: 'p',
  name: 'p',
  durationSeconds: 1,
  steps: [SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 1)],
);

class _Voice extends TtsService {
  _Voice(this._v);
  double _v;
  final List<double> setVolumes = [];
  @override
  double get volume => _v;
  @override
  Future<void> setVolume(double v) async {
    _v = v;
    setVolumes.add(v);
  }
}

class _Ambience extends _SilentAmbienceEngine {
  _Ambience(this._v);
  double _v;
  @override
  double get volume => _v;
  @override
  Future<void> setVolume(double v) async => _v = v;
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
