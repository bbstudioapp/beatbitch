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
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/mode_badge_row.dart';
import 'package:beat_bitch/widgets/session_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Disposition de l'écran de séance en cours : « JE PEUX PAS » plein et
/// immobile, « UTILISE-MOI » sur sa propre ligne au-dessus, qui
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

  SessionScreen screen({
    TtsService? tts,
    AmbienceEngine? ambience,
    bool career = true,
    String? intro,
    Future<void> Function(SessionController)? onEncore,
  }) =>
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
        isCareer: career,
        onRequestUpgrade: (_) async {},
        introText: intro,
        autoStart: intro == null,
        autoContinueOnFinish: onEncore != null,
        onRequestEncore: onEncore,
      );

  Future<void> pumpScreen(WidgetTester tester, SessionScreen s,
      {Size size = const Size(390, 850),
      Locale locale = const Locale('fr'),
      bool waitRunning = true}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: s,
    ));
    await settle(tester);
    for (var i = 0; waitRunning && i < 60 && !ctrlOf(tester).isRunning; i++) {
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
      'boutons : « UTILISE-MOI » sur sa ligne au-dessus, semi-transparent, '
      '« JE PEUX PAS » plein et tapable', (tester) async {
    await pumpScreen(tester, screen());
    ctrlOf(tester).debugAddPlayed(SessionController.useMeUnlockAfter);
    await settle(tester, 10);

    expect(useMeButton, findsOneWidget);
    final fail = tester.getRect(failButton);
    final useMe = tester.getRect(useMeButton);
    expect(useMe.bottom, lessThanOrEqualTo(fail.top));
    expect(useMe.right, closeTo(fail.right, 0.5));
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

  final instruction = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_CurrentInstruction');
  for (final lang in ['fr', 'en', 'de', 'es']) {
    for (final width in [320.0, 390.0, 700.0]) {
      testWidgets(
          '« UTILISE-MOI » apparaît : « JE PEUX PAS » et la consigne ne '
          'bougent pas ($lang, $width)', (tester) async {
        await pumpScreen(tester, screen(),
            size: Size(width, 850), locale: Locale(lang));
        final failBefore = tester.getRect(failButton);
        final instructionBefore = tester.getRect(instruction);
        expect(useMeButton, findsNothing);

        ctrlOf(tester).debugAddPlayed(SessionController.useMeUnlockAfter);
        await settle(tester, 10);

        expect(useMeButton, findsOneWidget);
        expect(tester.getRect(failButton), failBefore);
        expect(tester.getRect(instruction), instructionBefore);
        final useMe = tester.getRect(useMeButton);
        expect(useMe.bottom, lessThanOrEqualTo(failBefore.top));
        expect(useMe.right, closeTo(failBefore.right, 0.5));
        expect(useMe.top, greaterThanOrEqualTo(instructionBefore.bottom));
        expect(useMe.height, greaterThanOrEqualTo(48));
        expect(useMe.width, greaterThanOrEqualTo(48));
        expect(useMe.height, lessThan(failBefore.height + 1));
        expect(failBefore.height, greaterThanOrEqualTo(48));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final size in const [
    Size(568, 320),
    Size(667, 375),
    Size(844, 390),
    Size(320, 568),
    Size(390, 850),
  ]) {
    testWidgets(
        '« JE PEUX PAS » entier et tapable, immobile quand « UTILISE-MOI » '
        'apparaît (${size.width.toInt()}×${size.height.toInt()})',
        (tester) async {
      await pumpScreen(tester, screen(), size: size);
      final screenRect = Offset.zero & size;
      final failBefore = tester.getRect(failButton);
      final instructionBefore = tester.getRect(instruction);
      expect(screenRect.contains(failBefore.topLeft), isTrue,
          reason: 'coin haut-gauche de « JE PEUX PAS » hors écran');
      expect(failBefore.bottom, lessThanOrEqualTo(size.height),
          reason: '« JE PEUX PAS » rogné par le bas');

      ctrlOf(tester).debugAddPlayed(SessionController.useMeUnlockAfter);
      await settle(tester, 10);

      expect(useMeButton, findsOneWidget);
      expect(tester.getRect(failButton), failBefore);
      expect(tester.getRect(instruction), instructionBefore);
      final useMe = tester.getRect(useMeButton);
      expect(failBefore.overlaps(useMe), isFalse);
      expect(screenRect.contains(useMe.topLeft), isTrue);
      expect(useMe.bottom, lessThanOrEqualTo(size.height));
      expect(useMe.right, lessThanOrEqualTo(size.width));
      expect(useMe.top, greaterThanOrEqualTo(instructionBefore.bottom));

      await tester.tap(failButton);
      await settle(tester, 3);
      expect(ctrlOf(tester).isFailing, isTrue);
      await tester.runAsync(ctrlOf(tester).stop);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
    });
  }

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

  testWidgets(
      'réglages ouverts : « JE PEUX PAS » reste tapable et déclenche le FAIL',
      (tester) async {
    await pumpScreen(tester, screen());
    await tester.tap(settingsButton);
    await settle(tester, 3);
    expect(find.byType(Slider), findsWidgets);

    await tester.tap(failButton);
    await settle(tester, 3);
    expect(ctrlOf(tester).isFailing, isTrue);
    await tester.runAsync(ctrlOf(tester).stop);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });

  Future<NavigatorState> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Text('accueil')),
    ));
    return tester.state<NavigatorState>(find.byType(Navigator));
  }

  testWidgets(
      'séance enchaînée : l\'ancien écran ne rétablit pas la barre système '
      'sous la nouvelle séance', (tester) async {
    final nav = await pumpHome(tester);
    nav.push(MaterialPageRoute<void>(builder: (_) => screen(career: false)));
    await settle(tester);
    nav.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => screen(career: false)));
    await settle(tester, 8);

    expect(find.byType(SessionScreen), findsOneWidget);
    expect(uiModes.last, 'SystemUiMode.immersiveSticky');
    nav.pop();
    await settle(tester, 8);
    expect(uiModes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets(
      'enchaînement automatique avec les réglages ouverts : plus d\'ancien '
      'écran dans la pile', (tester) async {
    final nav = await pumpHome(tester);
    nav.push(MaterialPageRoute<void>(
      builder: (_) => screen(
        career: false,
        onEncore: (ctrl) => nav.pushReplacement(
            MaterialPageRoute<void>(builder: (_) => screen(career: false))),
      ),
    ));
    await settle(tester);

    await tester.tap(settingsButton);
    await settle(tester, 3);
    ctrlOf(tester).debugFinishSuccess();
    await tester.pump(const Duration(seconds: 5));
    await settle(tester, 8);

    expect(find.byType(SessionScreen, skipOffstage: false), findsOneWidget);
    nav.pop();
    await settle(tester, 8);
    expect(find.byType(SessionScreen), findsNothing);
    expect(find.text('accueil'), findsOneWidget);
  });

  bool veilOnly(WidgetTester tester) => tester
      .widget<SessionBackground>(find.byType(SessionBackground))
      .bottomVeilOnly;

  testWidgets('fond : voile uniforme à l\'intro', (tester) async {
    await pumpScreen(tester, screen(intro: 'Bonjour'), waitRunning: false);
    expect(find.byType(AppBar), findsOneWidget);
    expect(veilOnly(tester), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fond : dégradé bas seul en séance, voile uniforme à la fin',
      (tester) async {
    await pumpScreen(tester, screen(career: false));
    expect(veilOnly(tester), isTrue);

    await tester.runAsync(ctrlOf(tester).debugFinishSuccess);
    await settle(tester, 3);
    expect(ctrlOf(tester).isFinished, isTrue);
    expect(veilOnly(tester), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fond : le dégradé noircit le bas, le voile uniforme couvre tout',
      (tester) async {
    BackgroundsService.instance.current.value = const BackgroundEntry(
        id: 'v2-test',
        type: BackgroundMediaType.image,
        path: 'assets/inexistant.png');
    addTearDown(() => BackgroundsService.instance.current.value = null);

    Future<BoxDecoration> veil({required bool bottomOnly}) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox.expand(
            child: SessionBackground(bottomVeilOnly: bottomOnly)),
      ));
      await tester.pump(const Duration(seconds: 1));
      final boxes = find.descendant(
          of: find.byType(SessionBackground),
          matching: find.byType(DecoratedBox));
      return (boxes.evaluate().last.widget as DecoratedBox).decoration
          as BoxDecoration;
    }

    final gradient = await veil(bottomOnly: true);
    expect(gradient.color, isNull);
    final colors = (gradient.gradient as LinearGradient);
    expect(colors.begin, Alignment.topCenter);
    expect(colors.end, Alignment.bottomCenter);
    expect(colors.colors.first.a, 0);
    expect(colors.colors.last.a, greaterThan(0.8));

    final uniform = await veil(bottomOnly: false);
    expect(uniform.gradient, isNull);
    expect(uniform.color!.a, closeTo(0.45, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('retour d\'arrière-plan : le mode immersif est repris',
      (tester) async {
    await pumpScreen(tester, screen());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester, 2);
    uiModes.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester, 2);
    expect(uiModes, contains('SystemUiMode.immersiveSticky'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pastille du mode : semi-transparente', (tester) async {
    await pumpScreen(tester, screen());
    final opacity = tester.widget<Opacity>(find
        .descendant(
            of: find.byType(ModeBadgeRow), matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, inExclusiveRange(0.5, 1.0));
    await tester.pumpWidget(const SizedBox());
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
