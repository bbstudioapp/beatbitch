import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/punishment.dart';
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

/// Appli en arrière-plan pendant le décompte de mise en place, pendant les
/// `await` de `start()`, pendant un fail / une punition, ou écran monté déjà en
/// arrière-plan : la séance n'est ni lancée ni relancée, rien n'est inscrit au
/// profil, et le retour dans l'appli ne fait jamais repartir le son seul.
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
    Session session = _shortSession,
    PunishmentBundle punishments =
        const PunishmentBundle(failPhrases: [], punishments: []),
    List<double>? staminaProfile,
  }) async {
    final b = _Bench();
    if (holdBeepInit) b.beep.gate = Completer<void>();
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SessionScreen(
        session: session,
        tts: b.tts,
        beep: b.beep,
        ambience: b.ambience,
        punishmentBundle: punishments,
        staminaProfile: staminaProfile,
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

  Future<Map<String, Object?>> statsMap() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final k in prefs.getKeys().where((k) => k.startsWith('stats.')))
        k: prefs.get(k),
    };
  }

  Future<_Mark> markOf(_Bench b) async => _Mark(
        applied: b.beep.applied.length,
        elapsed: b.ctrl.elapsed,
        stats: await statsMap(),
        beepPauses: b.beep.pauses,
        ambiencePauses: b.ambience.pauses,
        ttsStops: b.tts.stops,
      );

  /// Ce qui a bougé depuis [since] alors que la séance devait attendre le
  /// bouton de reprise ; vide = elle attend.
  Future<List<String>> leaks(_Bench b, _Mark since) async {
    final out = <String>[];
    if (b.ctrl.state != SessionState.paused) {
      out.add('état ${b.ctrl.state.name} au lieu de paused');
    }
    final steps = b.beep.applied.length - since.applied;
    if (steps != 0) out.add('applyStep ×$steps');
    if (b.ctrl.elapsed != since.elapsed) {
      out.add('horloge ${since.elapsed} → ${b.ctrl.elapsed}');
    }
    final stats = await statsMap();
    final written = stats.entries
        .where((e) => since.stats[e.key] != e.value)
        .map((e) => e.key)
        .toList();
    if (written.isNotEmpty) out.add('profil écrit : $written');
    return out;
  }

  /// Ce que la sortie d'un fail en pause devait couper et n'a pas coupé.
  List<String> notCut(_Bench b, _Mark since) => [
        if (b.tts.stops == since.ttsStops) 'voix non coupée',
        if (b.ambience.pauses == since.ambiencePauses) 'ambiance non coupée',
        if (b.beep.pauses == since.beepPauses) 'bips non coupés',
      ];

  /// Temps réel, au rythme des timers simulés : le `Stopwatch` du contrôleur
  /// et les attentes des flows de fail ne sont pas simulés.
  Future<void> realElapse(WidgetTester tester, Duration d) async {
    for (var ms = 0; ms < d.inMilliseconds; ms += 100) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() condition,
    String what, {
    Duration limit = const Duration(seconds: 15),
  }) async {
    for (var ms = 0; ms < limit.inMilliseconds && !condition(); ms += 100) {
      await realElapse(tester, const Duration(milliseconds: 100));
    }
    expect(condition(), isTrue, reason: 'jamais atteint : $what');
  }

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
  group('fail / punition pendant l’absence', () {
    Future<_Bench> inMiniPunishment(
      WidgetTester tester, {
      bool background = true,
    }) async {
      final b = await mount(tester, autoStart: true, punishments: _punishments);
      await realElapse(tester, const Duration(seconds: 1));
      expect(b.ctrl.state, SessionState.running,
          reason: 'le banc n’a pas lancé la séance');
      unawaited(b.ctrl.debugRunMiniPunishment(_punishment));
      await until(
          tester, () => b.ctrl.failPhase == FailPhase.punishment, 'punition');
      if (background) lifecycle(tester, AppLifecycleState.paused);
      return b;
    }

    testWidgets(
        'mini-punition : à la sortie la séance arrive en pause, ni horloge, ni '
        'step, ni profil, voix et ambiance coupées', (tester) async {
      final b = await inMiniPunishment(tester);
      final since = await markOf(b);

      await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
      await realElapse(tester, const Duration(seconds: 3));

      expect([...await leaks(b, since), ...notCut(b, since)], isEmpty,
          reason: 'la séance a quitté l’attente alors que la joueuse est '
              'partie');
    });

    testWidgets(
        'mini-punition : le retour dans l’appli ne relance rien, le bouton '
        'rejoue la boucle d’avant la punition', (tester) async {
      final b = await inMiniPunishment(tester);
      final since = await markOf(b);
      await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');

      lifecycle(tester, AppLifecycleState.resumed);
      await realElapse(tester, const Duration(seconds: 2));
      expect(b.ctrl.state, SessionState.paused,
          reason: 'le retour dans l’appli a relancé la séance seul');
      expect(b.beep.applied.length, since.applied);

      await tester.tap(find.byIcon(Icons.play_arrow).last);
      await realElapse(tester, const Duration(milliseconds: 500));

      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.applied.skip(since.applied), [same(_step0)],
          reason: 'la boucle d’avant la punition n’est pas rejouée');
      expect(b.beep.resumes, 0,
          reason: 'le moteur a repris le dernier mode de la punition');
      expect(b.ctrl.elapsed, greaterThan(since.elapsed),
          reason: 'l’horloge ne repart pas');
    });

    testWidgets('témoin : mini-punition au premier plan → la séance repart',
        (tester) async {
      final b = await inMiniPunishment(tester, background: false);
      final since = await markOf(b);

      await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
      await realElapse(tester, const Duration(milliseconds: 500));

      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.applied.skip(since.applied), [same(_step0)]);
      expect(b.ctrl.elapsed, greaterThan(since.elapsed));
    });

    testWidgets(
        'fail complet (phrase, respiration, punition) : le saut de section est '
        'différé, la séance arrive en pause', (tester) async {
      final b = await mount(tester,
          autoStart: true,
          session: _jumpSession,
          punishments: _punishments,
          staminaProfile: List<double>.filled(120, 100));
      await realElapse(tester, const Duration(milliseconds: 500));
      expect(b.ctrl.state, SessionState.running,
          reason: 'le banc n’a pas lancé la séance');

      unawaited(b.ctrl.triggerFail());
      await until(
          tester, () => b.ctrl.failPhase == FailPhase.breath, 'respiration');
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.paused);
      await until(
          tester, () => b.ctrl.failPhase == FailPhase.punishment, 'punition');
      final since = await markOf(b);

      await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
      await realElapse(tester, const Duration(seconds: 2));

      expect([...await leaks(b, since), ...notCut(b, since)], isEmpty,
          reason: 'la séance a quitté l’attente alors que la joueuse est '
              'partie');

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow).last);
      await realElapse(tester, const Duration(milliseconds: 500));

      expect(b.ctrl.state, SessionState.running);
      expect(b.ctrl.elapsed, greaterThanOrEqualTo(const Duration(seconds: 6)),
          reason: 'le saut de section différé n’est pas rejoué à la reprise');
      expect(b.beep.applied.skip(since.applied), [same(_sectionStep)]);
    }, timeout: const Timeout(Duration(seconds: 40)));

    testWidgets(
        'témoin : fail complet au premier plan → saut de section, la séance '
        'repart', (tester) async {
      final b = await mount(tester,
          autoStart: true,
          session: _jumpSession,
          punishments: _punishments,
          staminaProfile: List<double>.filled(120, 100));
      await realElapse(tester, const Duration(milliseconds: 500));

      unawaited(b.ctrl.triggerFail());
      await until(
          tester, () => b.ctrl.failPhase == FailPhase.punishment, 'punition');
      final since = await markOf(b);
      await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
      await realElapse(tester, const Duration(milliseconds: 300));

      expect(b.ctrl.state, SessionState.running);
      expect(b.ctrl.elapsed, greaterThanOrEqualTo(const Duration(seconds: 6)));
      expect(b.beep.applied.skip(since.applied), [same(_sectionStep)]);
    }, timeout: const Timeout(Duration(seconds: 40)));

    testWidgets(
        'départ pendant la restauration de la boucle : la séance arrive en '
        'pause', (tester) async {
      final b = await mount(tester, autoStart: true, punishments: _punishments);
      await realElapse(tester, const Duration(seconds: 1));
      final beforeFlow = b.beep.applied.length;
      b.beep
        ..holdApplyOf = _step0
        ..applyGate = Completer<void>();

      unawaited(b.ctrl.debugRunMiniPunishment(_punishment));
      await until(tester, () => b.beep.applied.length == beforeFlow + 2,
          'restauration de la boucle en vol');
      lifecycle(tester, AppLifecycleState.paused);
      final since = await markOf(b);
      b.beep.applyGate!.complete();
      await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
      await realElapse(tester, const Duration(seconds: 3));

      expect([...await leaks(b, since), ...notCut(b, since)], isEmpty,
          reason: 'l’événement d’arrière-plan reçu pendant la restauration '
              'a été perdu');

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow).last);
      await realElapse(tester, const Duration(milliseconds: 500));
      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.resumes, 1,
          reason: 'la boucle déjà restaurée se reprend, elle ne se rejoue pas');
      expect(b.beep.applied.length, since.applied);
    });

    group('rejeu de la sortie différée', () {
      /// Sortie différée, retour dans l'appli, bouton de reprise : la
      /// restauration de la boucle est en vol, tenue par `applyGate`.
      Future<_Bench> inReplayWindow(WidgetTester tester) async {
        final b = await inMiniPunishment(tester);
        await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
        lifecycle(tester, AppLifecycleState.resumed);
        await tester.pump();
        expect(b.ctrl.state, SessionState.paused,
            reason: 'le banc n’a pas amené la séance en pause');
        b.beep
          ..holdApplyOf = _step0
          ..applyGate = Completer<void>();
        final before = b.beep.applied.length;
        await tester.tap(find.byIcon(Icons.play_arrow).last);
        await until(tester, () => b.beep.applied.length == before + 1,
            'restauration de la boucle en vol');
        return b;
      }

      testWidgets('un nouveau fail est refusé, comme au premier plan',
          (tester) async {
        final b = await inReplayWindow(tester);

        unawaited(b.ctrl.triggerFail());
        await realElapse(tester, const Duration(milliseconds: 500));
        expect(b.ctrl.failPhase, isNull,
            reason: 'un fail a démarré pendant le rejeu de la sortie différée');
        expect(b.ctrl.isFailFlowActive, isTrue,
            reason: 'le rejeu n’est pas gardé comme une sortie de fail');

        b.beep.applyGate!.complete();
        await until(tester, () => !b.ctrl.isFailFlowActive, 'fin du rejeu');
        await realElapse(tester, const Duration(milliseconds: 500));
        expect(b.ctrl.state, SessionState.running);
        expect(b.ctrl.failPhase, isNull);
      });

      testWidgets('pause() est refusée, comme au premier plan', (tester) async {
        final b = await inReplayWindow(tester);

        await b.ctrl.pause();
        expect(b.ctrl.state, SessionState.running,
            reason: 'une pause a été acceptée pendant le rejeu');

        b.beep.applyGate!.complete();
        await until(tester, () => !b.ctrl.isFailFlowActive, 'fin du rejeu');
        await realElapse(tester, const Duration(milliseconds: 300));
        final at = b.ctrl.elapsed;
        await realElapse(tester, const Duration(milliseconds: 500));
        expect(b.ctrl.state, SessionState.running);
        expect(b.ctrl.elapsed, greaterThan(at));
      });

      testWidgets('stop() pendant le rejeu : la séance reste arrêtée',
          (tester) async {
        final b = await inReplayWindow(tester);

        await b.ctrl.stop();
        expect(b.ctrl.state, SessionState.idle);

        b.beep.applyGate!.complete();
        await realElapse(tester, const Duration(milliseconds: 500));
        expect(b.ctrl.state, SessionState.idle,
            reason: 'la fin du rejeu a relancé une séance arrêtée');
        expect(b.ctrl.elapsed, Duration.zero);
      });
    });

    group('sortie différée périmée', () {
      Future<void> restartAndPauseResume(WidgetTester tester, _Bench b) async {
        lifecycle(tester, AppLifecycleState.resumed);
        await b.ctrl.start();
        expect(b.ctrl.state, SessionState.running,
            reason: 'le banc n’a pas relancé la séance');
        final applied = b.beep.applied.length;
        final resumes = b.beep.resumes;
        await b.ctrl.pause();
        await b.ctrl.resume();
        expect(b.beep.resumes, resumes + 1,
            reason: 'une pause ordinaire doit reprendre le moteur');
        expect(b.beep.applied.length, applied,
            reason: 'la sortie de fail d’une séance précédente a été '
                'rejouée à la reprise');
      }

      testWidgets('stop() l’abandonne', (tester) async {
        final b = await inMiniPunishment(tester);
        await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
        expect(b.ctrl.state, SessionState.paused,
            reason: 'le banc n’a pas amené la séance en pause');

        unawaited(b.ctrl.stop());
        await realElapse(tester, const Duration(milliseconds: 500));
        expect(b.ctrl.state, SessionState.idle);
        await restartAndPauseResume(tester, b);
      });

      testWidgets('un nouveau départ après la fin l’abandonne', (tester) async {
        final b = await inMiniPunishment(tester);
        await until(tester, () => !b.ctrl.isFailFlowActive, 'sortie du flow');
        expect(b.ctrl.state, SessionState.paused,
            reason: 'le banc n’a pas amené la séance en pause');

        unawaited(b.ctrl.debugFinishSuccess());
        await realElapse(tester, const Duration(seconds: 1));
        expect(b.ctrl.state, SessionState.finished);
        await restartAndPauseResume(tester, b);
      });
    });
  });

  group('écran monté appli déjà en arrière-plan', () {
    testWidgets('autoStart : la séance ne démarre pas seule, rien au profil',
        (tester) async {
      lifecycle(tester, AppLifecycleState.paused);
      final b = await mount(tester, autoStart: true);
      await realElapse(tester, const Duration(seconds: 4));

      expect(await leaks(b, _Mark.zero), isEmpty,
          reason: 'l’écran poussé pendant l’absence a lancé la séance');

      lifecycle(tester, AppLifecycleState.resumed);
      await realElapse(tester, const Duration(seconds: 2));
      expect(b.ctrl.state, SessionState.paused,
          reason: 'le retour dans l’appli a relancé la séance seul');

      await tester.tap(find.byIcon(Icons.play_arrow).last);
      await realElapse(tester, const Duration(seconds: 1));
      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.resumes, 0,
          reason: 'le moteur a repris sa config par défaut avant le step 0');
      expect(b.beep.applied, [same(_step0)]);
    });

    testWidgets('témoin : monté après le retour dans l’appli → démarre',
        (tester) async {
      lifecycle(tester, AppLifecycleState.paused);
      lifecycle(tester, AppLifecycleState.resumed);
      final b = await mount(tester, autoStart: true);
      await realElapse(tester, const Duration(seconds: 1));

      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.applied, [same(_step0)]);
    });
  });
}

const _step0 =
    SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 3);

const _shortSession = Session(
  id: 'arriere-plan',
  name: 'arriere-plan',
  description: '',
  durationSeconds: 3,
  defaultMode: SessionMode.rhythm,
  steps: [_step0],
);

/// Un step de section à t=6 : la sortie d'un fail y saute au lieu de rejouer la
/// boucle d'avant.
const _sectionStep =
    SessionStep(time: 6, mode: SessionMode.rhythm, bpm: 60, duration: 1);

const _jumpSession = Session(
  id: 'arriere-plan-saut',
  name: 'arriere-plan-saut',
  description: '',
  durationSeconds: 8,
  defaultMode: SessionMode.rhythm,
  steps: [_step0, _sectionStep],
);

const _punishment = Punishment(
  id: 'p',
  name: 'p',
  durationSeconds: 1,
  steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
);

const _punishments =
    PunishmentBundle(failPhrases: ['tu craques'], punishments: [_punishment]);

class _Mark {
  final int applied;
  final Duration elapsed;
  final Map<String, Object?> stats;
  final int beepPauses;
  final int ambiencePauses;
  final int ttsStops;

  const _Mark({
    required this.applied,
    required this.elapsed,
    required this.stats,
    required this.beepPauses,
    required this.ambiencePauses,
    required this.ttsStops,
  });

  static const zero = _Mark(
    applied: 0,
    elapsed: Duration.zero,
    stats: {},
    beepPauses: 0,
    ambiencePauses: 0,
    ttsStops: 0,
  );
}

class _Bench {
  final tts = _RecordingTts();
  final beep = _RecordingBeep();
  final ambience = _SilentAmbienceEngine();
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
  int pauses = 0;
  final List<SessionStep> applied = [];

  /// Tient l'`applyStep` de ce step précis (identité) jusqu'à la complétion de
  /// [applyGate] : la restauration de la boucle à la sortie d'un fail.
  SessionStep? holdApplyOf;
  Completer<void>? applyGate;

  @override
  Future<void> init() async {
    initCalls++;
    await gate?.future;
  }

  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    applied.add(step);
    if (identical(step, holdApplyOf)) await applyGate?.future;
  }

  @override
  Future<void> pause() async => pauses++;
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
  int pauses = 0;

  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> playForMode(SessionMode mode, {Position? depth}) async {}
  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
