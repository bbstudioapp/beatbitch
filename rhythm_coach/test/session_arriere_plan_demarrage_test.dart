import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/coach_phrases_loader.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appli en arrière-plan pendant le décompte de mise en place ou pendant les
/// `await` de `start()` : la séance n'est ni lancée ni inscrite au profil, et
/// le retour dans l'appli ne fait jamais repartir le son seul.
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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
    await CoachPhrasesService.instance.ensureLoaded(locale: const Locale('en'));
  });

  tearDown(() {
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

  Future<_Bench> mount(
    WidgetTester tester, {
    String? introText,
    bool autoStart = false,
    bool holdBeepInit = false,
  }) async {
    final b = _Bench();
    if (holdBeepInit) b.beep.gate = Completer<void>();
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
        session: const Session(
          id: 'arriere-plan',
          name: 'arriere-plan',
          description: '',
          durationSeconds: 3,
          defaultMode: SessionMode.rhythm,
          steps: [
            SessionStep(
                time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 3),
          ],
        ),
        tts: b.tts,
        beep: b.beep,
        ambience: _SilentAmbienceEngine(),
        punishmentBundle:
            const PunishmentBundle(failPhrases: [], punishments: []),
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
        introText: introText,
        autoStart: autoStart,
      ),
    ));
    b.ctrl = Provider.of<SessionController>(
        tester.element(find.byType(Scaffold).first),
        listen: false);
    return b;
  }

  Future<void> elapse(WidgetTester tester, Duration d) async {
    for (var ms = 0; ms < d.inMilliseconds; ms += 100) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void lifecycle(WidgetTester tester, AppLifecycleState s) =>
      tester.binding.handleAppLifecycleStateChanged(s);

  Future<Set<String>> statsKeys() async =>
      (await SharedPreferences.getInstance())
          .getKeys()
          .where((k) => k.startsWith('stats.'))
          .toSet();

  group('décompte de mise en place', () {
    testWidgets(
        'arrière-plan pendant le décompte : ni start(), ni bip, ni voix, '
        'rien au profil', (tester) async {
      final b = await mount(tester, introText: 'Mets-toi en place.');
      await tester.tap(find.byType(FilledButton));
      await elapse(tester, const Duration(seconds: 2));
      final speaks = b.tts.speaks.length;
      final stops = b.tts.stops;

      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.paused);
      await elapse(tester, const Duration(seconds: 12));

      expect(b.ctrl.state, SessionState.idle,
          reason: 'la séance a quitté idle alors que la joueuse est partie');
      expect(b.beep.initCalls, 0,
          reason: 'start() a été appelé en arrière-plan');
      expect(b.beep.applied, isEmpty, reason: 'applyStep en arrière-plan');
      expect(b.tts.speaks.length, speaks,
          reason: 'le coach parle en arrière-plan');
      expect(b.tts.stops, greaterThan(stops),
          reason: 'la voix du décompte n’est pas coupée');
      expect(await statsKeys(), isEmpty,
          reason: 'une séance jamais jouée a écrit dans le profil');
    });

    testWidgets('retour dans l’appli : le décompte reprend depuis le début',
        (tester) async {
      final b = await mount(tester, introText: 'Mets-toi en place.');
      await tester.tap(find.byType(FilledButton));
      await elapse(tester, const Duration(seconds: 3));
      lifecycle(tester, AppLifecycleState.paused);
      await elapse(tester, const Duration(seconds: 10));
      expect(b.ctrl.state, SessionState.idle,
          reason: 'la séance a démarré pendant l’absence');

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('7'), findsOneWidget,
          reason: 'le décompte ne repart pas de 7 au retour');
      await elapse(tester, const Duration(seconds: 5));
      expect(b.ctrl.state, SessionState.idle,
          reason: 'la séance démarre avant la fin du décompte repris');

      await elapse(tester, const Duration(seconds: 4));
      expect(b.ctrl.state, SessionState.running,
          reason: 'le décompte repris n’aboutit pas');
      expect(b.beep.applied.length, 1);
    });
  });

  group('start() en vol', () {
    testWidgets(
        'arrière-plan pendant les await : la séance arrive en pause, rien ne '
        'tourne, rien au profil', (tester) async {
      final b = await mount(tester, autoStart: true, holdBeepInit: true);
      await elapse(tester, const Duration(milliseconds: 300));
      expect(b.beep.initCalls, 1, reason: 'le banc n’a pas tenu start()');

      lifecycle(tester, AppLifecycleState.paused);
      b.beep.gate!.complete();
      await elapse(tester, const Duration(seconds: 6));

      expect(b.ctrl.state, SessionState.paused,
          reason: 'la séance n’arrive pas en pause');
      expect(b.beep.applied, isEmpty, reason: 'applyStep en arrière-plan');
      expect(b.ctrl.elapsed, Duration.zero, reason: 'l’horloge a démarré');
      expect(await statsKeys(), isEmpty,
          reason: 'une séance jamais jouée a écrit dans le profil');
    });

    testWidgets(
        'start() appelé alors que l’appli est déjà en arrière-plan : en pause',
        (tester) async {
      final b = await mount(tester);
      lifecycle(tester, AppLifecycleState.paused);

      unawaited(b.ctrl.start());
      await elapse(tester, const Duration(seconds: 2));

      expect(b.ctrl.state, SessionState.paused);
      expect(b.beep.applied, isEmpty);
    });

    testWidgets(
        'retour avant la fin de start() : la séance arrive quand même en '
        'pause', (tester) async {
      final b = await mount(tester, autoStart: true, holdBeepInit: true);
      await elapse(tester, const Duration(milliseconds: 300));

      lifecycle(tester, AppLifecycleState.paused);
      lifecycle(tester, AppLifecycleState.resumed);
      b.beep.gate!.complete();
      await elapse(tester, const Duration(seconds: 2));

      expect(b.ctrl.state, SessionState.paused);
      expect(b.beep.applied, isEmpty);
    });

    testWidgets(
        'reprise par le bouton : le premier step est posé, aucun rythme '
        'par défaut avant lui', (tester) async {
      final b = await mount(tester, autoStart: true, holdBeepInit: true);
      await elapse(tester, const Duration(milliseconds: 300));
      lifecycle(tester, AppLifecycleState.paused);
      b.beep.gate!.complete();
      await elapse(tester, const Duration(seconds: 2));
      lifecycle(tester, AppLifecycleState.resumed);
      await elapse(tester, const Duration(seconds: 2));
      expect(b.ctrl.state, SessionState.paused,
          reason: 'le retour dans l’appli a relancé la séance seul');

      await tester.tap(find.byIcon(Icons.play_arrow).last);
      await elapse(tester, const Duration(seconds: 1));

      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.resumes, 0,
          reason: 'le moteur a repris sa config par défaut avant le step 0');
      expect(b.beep.applied.length, 1);
    });
  });

  testWidgets('témoin : arrière-plan pendant une séance running → pause',
      (tester) async {
    final b = await mount(tester, autoStart: true);
    await elapse(tester, const Duration(seconds: 1));
    expect(b.ctrl.state, SessionState.running);

    lifecycle(tester, AppLifecycleState.paused);
    await elapse(tester, const Duration(seconds: 1));
    expect(b.ctrl.state, SessionState.paused);
    final applied = b.beep.applied.length;

    lifecycle(tester, AppLifecycleState.resumed);
    await elapse(tester, const Duration(seconds: 2));
    expect(b.ctrl.state, SessionState.paused,
        reason: 'le retour dans l’appli a relancé la séance seul');
    expect(b.beep.applied.length, applied);
  });
}

class _Bench {
  final tts = _RecordingTts();
  final beep = _RecordingBeep();
  late final SessionController ctrl;
}

class _RecordingTts extends TtsService {
  final List<String> speaks = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text) async => speaks.add(text);
  int stops = 0;
  @override
  Future<void> stop() async => stops++;
}

class _RecordingBeep extends BeepEngine {
  /// Posée par le test pour tenir l'`await _beep.init()` de `start()`.
  Completer<void>? gate;
  int initCalls = 0;
  int resumes = 0;
  final List<SessionStep> applied = [];

  @override
  Future<void> init() async {
    initCalls++;
    await gate?.future;
  }

  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    applied.add(step);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {
    resumes++;
  }

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
