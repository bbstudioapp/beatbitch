import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/screens/career_screen.dart';
import 'package:beat_bitch/career/services/coach_loader.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/main.dart' show coachService;
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/coach_phrases_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VoiceTts extends TtsService {
  final ops = <String>[];

  @override
  Future<void> restoreDefaultVoicePreset() async => ops.add('défaut');

  @override
  Future<void> applyCoachVoicePreset({
    String? coachId,
    String? voiceName,
    String? voiceLocale,
    double? rate,
    double? pitch,
    bool skipPreferredVoices = false,
  }) async {
    ops.add('$coachId');
  }
}

class _SilentBeep extends BeepEngine {
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

class _SilentAmbience extends AmbienceEngine {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  final audioEventChannels = [
    const EventChannel('xyz.luan/audioplayers.global/events'),
    const EventChannel('xyz.luan/audioplayers/events/ambience_loop'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final unlocked = [
    for (final c in CoachCatalog.defaults)
      if (c.isPrincipal && c.tier <= 3) c.id
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'coach.unlocked_ids': unlocked,
      'coach.selected_id': unlocked.first,
      'career.completed_sessions': 20,
      'stats.obedience_level': 90.0,
    });
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
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
  });

  tearDown(() {
    BackgroundsService.instance.debugResetForTest();
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null);
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

  testWidgets(
      'carrière, deux séances de plus : la coach garde son palier et sa voix, '
      'la voix par défaut revient en quittant la chaîne', (tester) async {
    await tester.runAsync(() async {
      await CoachPhrasesService.instance.ensureLoaded();
      await coachService.load();
      coachService.attachPhrases(await CoachLoader().load());
    });
    final svc = BackgroundsService.instance
      ..setBundle(BackgroundsBundle(entries: [
        for (final n in const [
          'lina-v3-a1-play-01_play_lina',
          'lina-v3-a3-play-01_play_lina_nu2',
        ])
          BackgroundsLoader.parseEntry('assets/backgrounds/$n.webp')!,
      ]));
    final tts = _VoiceTts();
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CareerScreen(
        tts: tts,
        beep: _SilentBeep(),
        ambience: _SilentAmbience(),
        userProfile: UserProfileService(),
      ),
    ));
    await _until(tester, () => find.text('DÉMARRER').evaluate().isNotEmpty);
    await tester.tap(find.text('DÉMARRER'));

    final screens = find.byType(SessionScreen, skipOffstage: false);
    await _until(tester, () => screens.evaluate().isNotEmpty);
    final first = tester.widget<SessionScreen>(screens);
    expect(first.keepsBackgroundTier, isFalse);
    expect(first.onRequestEncore, isNotNull, reason: 'porte encore ouverte');
    final ctrl = Provider.of<SessionController>(
        tester.element(find
            .descendant(
                of: screens,
                matching: find.byType(Scaffold, skipOffstage: false))
            .first),
        listen: false);

    svc.pickForContext(const BackgroundContext(
        mode: 'hold', position: 'throat', coach: 'lina', tier: 'nu2'));
    expect(svc.current.value?.id, 'lina-v3-a3-play-01', reason: 'témoin');

    first.onRequestEncore!(ctrl);
    await _until(
        tester,
        () =>
            screens.evaluate().length == 1 &&
            !identical(tester.widget<SessionScreen>(screens), first));
    final second = tester.widget<SessionScreen>(screens);
    final ctrl2 = Provider.of<SessionController>(
        tester.element(find
            .descendant(
                of: screens,
                matching: find.byType(Scaffold, skipOffstage: false))
            .first),
        listen: false);
    await _until(tester, () => ctrl2.isRunning);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    svc.pickForContext(const BackgroundContext(
        mode: 'hold', position: 'throat', coach: 'lina'));
    expect(svc.current.value?.id, 'lina-v3-a3-play-01',
        reason: "l'encore carrière garde le palier");

    final opsAvantQuitter = List<String>.of(tts.ops);
    expect(opsAvantQuitter.where((o) => o == 'défaut'), isEmpty,
        reason: "pas de voix par défaut tant qu'on est dans la chaîne");
    expect(second.keepsBackgroundTier, isTrue);

    expect(second.onRequestEncore, isNotNull, reason: 'porte encore ouverte');
    second.onRequestEncore!(ctrl2);
    await _until(tester, () {
      final w = screens.evaluate().length == 1
          ? tester.widget<SessionScreen>(screens)
          : null;
      return w != null && !identical(w, second);
    });
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    expect(tts.ops.where((o) => o == 'défaut'), isEmpty,
        reason: 'chaîne de 3 : toujours pas de voix par défaut');
    svc.pickForContext(const BackgroundContext(
        mode: 'hold', position: 'throat', coach: 'lina'));
    expect(svc.current.value?.id, 'lina-v3-a3-play-01',
        reason: 'la 2ᵉ séance de plus garde le palier aussi');

    Navigator.of(tester.element(screens)).pop();
    await _until(tester, () => screens.evaluate().isEmpty);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    expect(tts.ops.last, 'défaut', reason: 'quitter rétablit la voix');
    expect(svc.current.value, isNull, reason: 'dernier écran libère le fond');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition non atteinte');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
