import 'dart:async';
import 'dart:io';

import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/final_category.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_music.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/music_clock.dart';
import 'package:beat_bitch/services/music_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/step_resolution.dart';
import 'package:beat_bitch/services/stats_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Séance à morceau pilotée par un faux lecteur : la position de lecture est
/// posée par le test, jamais par le temps réel. Aucun son.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();
  final spoken = <String>[];

  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  void installFakeTtsEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      switch (call.method) {
        case 'speak':
          spoken.add('${call.arguments}');
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
  }

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    spoken.clear();
    installFakeTtsEngine();
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
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  const track = SessionMusic(
    asset: 'audio/music/montee_en_puissance.mp3',
    bpm: 121.96,
    firstBeatSeconds: 16.934,
  );

  const steps = [
    SessionStep(
        time: 0, text: 'ouverture', mode: SessionMode.breath, duration: 1),
    SessionStep(
        time: 1,
        text: 'debut',
        mode: SessionMode.rhythm,
        from: Position.tip,
        to: Position.head,
        bpm: 61),
    SessionStep(
        time: 30,
        text: 'monte',
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.mid,
        bpm: 122),
    SessionStep(
        time: 45,
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
        bpm: 122),
    SessionStep(
        time: 60,
        text: 'tiens',
        mode: SessionMode.hold,
        to: Position.mid,
        duration: 20),
    SessionStep(
        time: 80,
        text: 'retombee',
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.mid,
        bpm: 122),
    SessionStep(time: 90, text: 'mot final'),
  ];

  const musical = Session(
    id: 'musique-test',
    name: 'musique-test',
    description: '',
    durationSeconds: 100,
    defaultMode: SessionMode.rhythm,
    steps: steps,
    music: track,
  );

  const longMusical = Session(
    id: 'musique-test-longue',
    name: 'musique-test-longue',
    description: '',
    durationSeconds: 300,
    defaultMode: SessionMode.rhythm,
    steps: steps,
    music: track,
  );

  const fullHoldMusical = Session(
    id: 'musique-test-tenue-full',
    name: 'musique-test-tenue-full',
    description: '',
    durationSeconds: 100,
    defaultMode: SessionMode.rhythm,
    steps: [
      SessionStep(
          time: 0, text: 'ouverture', mode: SessionMode.breath, duration: 1),
      SessionStep(
          time: 10,
          text: 'au fond',
          mode: SessionMode.hold,
          to: Position.full,
          duration: 20),
      SessionStep(
          time: 30,
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.mid,
          bpm: 122),
    ],
    music: track,
  );

  const plain = Session(
    id: 'plain-test',
    name: 'plain-test',
    description: '',
    durationSeconds: 100,
    defaultMode: SessionMode.rhythm,
    steps: steps,
  );

  const punishments = PunishmentBundle(
    failPhrases: ['tu craques'],
    punishments: [
      Punishment(
        id: 'p',
        name: 'p',
        durationSeconds: 1,
        steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
      ),
    ],
  );

  ({SessionController ctrl, _Port port, _Beep beep, _SilentAmbienceEngine amb})
      build({
    Session session = musical,
    Duration startupLatency = Duration.zero,
    _Beep? sharedBeep,
    RandomCommentsBundle? randomComments,
    PhraseBank? phraseBank,
    double miniPunishmentRate = 0.0,
    Duration Function()? wall,
  }) {
    final port = _Port()..startupLatency = startupLatency;
    final beep = sharedBeep ?? _Beep();
    final amb = _SilentAmbienceEngine();
    final ctrl = SessionController(
      phraseBank: phraseBank,
      miniPunishmentRate: miniPunishmentRate,
      staminaProfile: List<double>.filled(120, 100),
      session: session,
      tts: TtsService(),
      beep: beep,
      ambience: amb,
      punishmentBundle: punishments,
      randomComments: randomComments ??
          const RandomCommentsBundle(
            comments: [],
            minIntervalSeconds: 999,
            maxIntervalSeconds: 999,
            scriptedCooldownSeconds: 4,
          ),
      music: MusicEngine(
        port: port,
        clock: MusicClock(now: wall ?? () => Duration.zero),
      ),
    );
    return (ctrl: ctrl, port: port, beep: beep, amb: amb);
  }

  Future<void> at(_Port port, SessionController ctrl, double seconds) async {
    port.seek(Duration(microseconds: (seconds * 1e6).round()));
    await Future<void>.delayed(Duration.zero);
    ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  Duration secondsAfterBreath(double fromSeconds) =>
      track.beatPeriod * 16 +
      Duration(milliseconds: (fromSeconds * 1000).round());

  test(
      'séance musicale avec un final : la musique de finish ne joue pas '
      'par-dessus le morceau', () async {
    final t = build(
      session: const Session(
        id: 'musique-finale',
        name: 'musique-finale',
        description: '',
        durationSeconds: 100,
        defaultMode: SessionMode.rhythm,
        steps: steps,
        music: track,
        silentFinishStartTime: 30,
        finalStepTime: 80,
      ),
    );
    await t.ctrl.start();
    for (final s in [31.0, 46.0, 61.0]) {
      await at(t.port, t.ctrl, s);
    }
    expect(t.beep.appliedSteps.map((s) => s.bpm), contains(122),
        reason: 'les steps de la montée doivent être passés');
    expect(t.amb.finishStarts, isEmpty);
    await t.ctrl.stop();
  });

  test(
      'les steps partent sur la position du morceau, pas sur le chronomètre : '
      'un lecteur qui tarde ne fait avancer aucune consigne', () async {
    final t = build(startupLatency: const Duration(milliseconds: 500));

    final starting = t.ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(t.ctrl.state, SessionState.idle,
        reason: 'la séance attend que le morceau joue réellement');
    expect(t.beep.appliedSteps, isEmpty);
    await starting;
    expect(t.ctrl.state, SessionState.running);
    expect(t.beep.appliedSteps.map((s) => s.mode), [SessionMode.breath]);

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    t.ctrl.debugTick();
    expect(t.ctrl.elapsedSeconds, 0,
        reason: 'la position du morceau n\'a pas bougé');
    expect(t.ctrl.playedSeconds, greaterThanOrEqualTo(1),
        reason: 'le chronomètre, lui, a couru');
    expect(t.beep.appliedSteps, hasLength(1),
        reason: 'le step de t=1 attend la position 1 s du morceau');

    await at(t.port, t.ctrl, 1.2);
    expect(t.beep.appliedSteps.last.bpm, 61);
    expect(spoken, contains('debut'));

    await at(t.port, t.ctrl, 31);
    expect(t.beep.appliedSteps.last.bpm, 122);
    expect(t.ctrl.elapsedSeconds, 31);
    expect(t.amb.playForModeCalls, 0,
        reason: 'pas d\'ambiance sous le morceau');

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
      'les bips sont calés sur la grille du morceau, hors du BeepEngine de la '
      'séance ordinaire', () async {
    final t = build();
    await t.ctrl.start();
    expect(t.beep.attachedTrack, track);
    expect(t.beep.attachedPosition!(), Duration.zero);
    t.port.seek(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);
    expect(t.beep.attachedPosition!(), const Duration(seconds: 42),
        reason: 'la grille lit la position de lecture du morceau');

    await t.ctrl.stop();
    expect(t.beep.attachedTrack, isNull);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'avance des bips : lue des préférences, appliquée à la grille et à '
      'l\'horloge de séance, bornée et mémorisée', () async {
    SharedPreferences.setMockInitialValues(
        {'debug.music_beep_advance_ms': 120});
    final t = build();
    await t.ctrl.start();
    expect(t.beep.musicBeepAdvance, const Duration(milliseconds: 120));
    t.port.seek(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);
    expect(t.beep.attachedPosition!(), const Duration(seconds: 42),
        reason: 'le morceau ne bouge pas');
    expect(t.ctrl.elapsed, const Duration(milliseconds: 42120),
        reason: 'le curseur suit les bips');

    await t.ctrl.setMusicBeepAdvanceMs(999);
    expect(t.ctrl.musicBeepAdvanceMs, 400);
    expect(t.beep.musicBeepAdvance, const Duration(milliseconds: 400));
    expect(
        (await SharedPreferences.getInstance())
            .getInt('debug.music_beep_advance_ms'),
        400);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('avance réglée à 0 : l\'horloge de séance est la position du morceau',
      () async {
    SharedPreferences.setMockInitialValues({'debug.music_beep_advance_ms': 0});
    final t = build();
    await t.ctrl.start();
    t.port.seek(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);
    expect(t.beep.musicBeepAdvance, Duration.zero);
    expect(t.ctrl.elapsed, const Duration(seconds: 42));

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'sans valeur mémorisée, une séance musicale applique 150 ms d\'avance '
      '(aucune dépendance à kDebugMode dans ce chemin)', () async {
    final t = build();
    await t.ctrl.start();
    t.port.seek(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);
    expect(t.beep.musicBeepAdvance, const Duration(milliseconds: 150));
    expect(t.ctrl.musicBeepAdvanceMs, 150);
    expect(t.ctrl.elapsed, const Duration(milliseconds: 42150));

    await t.ctrl.stop();

    // `flutter test` tourne en debug : `kDebugMode` ne se bascule pas ici. Ce
    // qui prouve l'indépendance, c'est qu'aucun `kDebugMode` ne touche le code
    // de l'avance (lecture de la préférence, contrôleur, grille).
    for (final path in [
      'lib/controllers/session_controller.dart',
      'lib/services/beep_engine.dart',
      'lib/career/services/debug_settings_service.dart',
    ]) {
      final lines = File(path).readAsLinesSync();
      var advanceLines = 0;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('eepAdvance')) advanceLines++;
        if (!lines[i].contains('kDebugMode')) continue;
        final near = lines.sublist(
            i < 4 ? 0 : i - 4, i + 5 > lines.length ? lines.length : i + 5);
        expect(near.where((l) => l.contains('eepAdvance')), isEmpty,
            reason: '$path:${i + 1} : kDebugMode près du code de l\'avance');
      }
      expect(advanceLines, greaterThan(0),
          reason: '$path : garde-fou anti-vide');
    }
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('une valeur mémorisée à 0 reste respectée malgré le défaut à 150',
      () async {
    SharedPreferences.setMockInitialValues({'debug.music_beep_advance_ms': 0});
    final t = build();
    await t.ctrl.start();
    expect(t.ctrl.musicBeepAdvanceMs, 0);
    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'JE PEUX PAS : la musique ne s\'arrête pas, ni punition ni phrase, les '
      'consignes du souffle sont perdues et la séance reprend sur le step '
      'atteint', () async {
    final t = build();
    final states = <SessionState>[];
    t.ctrl.addListener(() {
      if (states.isEmpty || states.last != t.ctrl.state) {
        states.add(t.ctrl.state);
      }
    });
    await t.ctrl.start();
    final stopsAtStart = t.port.stops;
    await at(t.port, t.ctrl, 75);
    spoken.clear();
    final applied = t.beep.appliedSteps.length;
    expect(t.ctrl.canTriggerFail, isTrue);

    var lastPosition = t.ctrl.elapsed;
    await t.ctrl.triggerFail();
    expect(t.ctrl.state, SessionState.running,
        reason: 'la séance ne passe jamais en failing');
    expect(t.ctrl.isMusicBreathing, isTrue);
    expect(t.ctrl.failPhase, FailPhase.breath);
    expect(t.ctrl.canTriggerFail, isFalse,
        reason: 'pas de second appui pendant le souffle');
    expect(t.ctrl.hadFailThisSession, isTrue);
    expect(t.beep.appliedSteps.skip(applied).map((s) => s.mode),
        [SessionMode.breath],
        reason: 'le souffle passe par le BeepEngine');
    expect(t.beep.appliedSteps.last.duration, 8);
    expect(spoken, isEmpty, reason: 'aucune phrase de fail');

    await at(t.port, t.ctrl, 80.5);
    expect(t.ctrl.isMusicBreathing, isTrue);
    expect(t.beep.appliedSteps.last.mode, SessionMode.breath,
        reason: 'le step de t=80 tombe dans le souffle : perdu');
    expect(t.ctrl.elapsed, greaterThan(lastPosition));
    lastPosition = t.ctrl.elapsed;

    await at(t.port, t.ctrl, 83);
    expect(t.ctrl.isMusicBreathing, isFalse);
    expect(t.ctrl.failPhase, isNull);
    final resumed = t.beep.appliedSteps.last;
    expect(resumed.mode, SessionMode.rhythm);
    expect(resumed.bpm, 122);
    expect(resumed.from, Position.head);
    expect(resumed.to, Position.mid);
    expect(resumed.text, isEmpty);
    expect(spoken, isEmpty,
        reason: 'la consigne de t=80 est perdue, pas dite en retard');
    expect(t.ctrl.elapsed, greaterThan(lastPosition));

    await at(t.port, t.ctrl, 90.4);
    expect(spoken, ['mot final'],
        reason: 'après le souffle les consignes reprennent');

    expect(states, everyElement(SessionState.running));
    expect(t.port.pauses, 0, reason: 'la musique n\'est jamais mise en pause');
    expect(t.port.stops, stopsAtStart);
    expect(t.beep.pauseCalls, 0);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('JE PEUX PAS pendant une tenue : elle reprend pour sa durée restante',
      () async {
    final t = build();
    await t.ctrl.start();
    await at(t.port, t.ctrl, 62);
    expect(t.beep.appliedSteps.last.mode, SessionMode.hold);

    await t.ctrl.triggerFail();
    await at(t.port, t.ctrl, 70);
    expect(t.ctrl.isMusicBreathing, isFalse);
    final resumed = t.beep.appliedSteps.last;
    expect(resumed.mode, SessionMode.hold);
    expect(resumed.to, Position.mid);
    expect(resumed.duration, 10, reason: '60 + 20 − 70');
    expect(resumed.text, isEmpty);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('le souffle dure 16 temps du morceau', () async {
    final t = build();
    await t.ctrl.start();
    await at(t.port, t.ctrl, 40);
    await t.ctrl.triggerFail();

    final end = 40 + secondsAfterBreath(0).inMicroseconds / 1e6;
    await at(t.port, t.ctrl, end - 0.05);
    expect(t.ctrl.isMusicBreathing, isTrue);
    await at(t.port, t.ctrl, end + 0.05);
    expect(t.ctrl.isMusicBreathing, isFalse);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'pause et reprise : la position se fige avec le morceau, aucune '
      'consigne ne part pendant la pause', () async {
    final t = build();
    await t.ctrl.start();
    await at(t.port, t.ctrl, 40);

    await t.ctrl.pause();
    expect(t.port.pauses, 1);
    t.port.seek(const Duration(seconds: 65));
    await Future<void>.delayed(Duration.zero);
    expect(t.ctrl.elapsedSeconds, 40, reason: 'la position est figée');

    await t.ctrl.resume();
    expect(t.port.plays, 2);
    expect(t.beep.attachedTrack, track,
        reason: 'la pause ne détache pas le morceau des bips');
    await at(t.port, t.ctrl, 41);
    expect(t.ctrl.elapsedSeconds, 41);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('fin de séance : pas de finale_chime, morceau libéré, bips détachés',
      () async {
    final t = build();
    await t.ctrl.start();
    await at(t.port, t.ctrl, 99);
    await at(t.port, t.ctrl, 100.2);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(t.ctrl.state, SessionState.finished);
    expect(t.beep.finaleChimes, 0);
    expect(t.beep.attachedTrack, isNull);
    expect(t.port.stops, greaterThanOrEqualTo(1));
    expect(t.ctrl.elapsedSeconds, greaterThanOrEqualTo(100),
        reason: 'l\'écran de fin relit la position figée');

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'fin du morceau : le lecteur retombe à 0, la séance court sur l\'horloge '
      'murale jusqu\'à sa durée puis se termine', () async {
    var wall = Duration.zero;
    final t = build(wall: () => wall);
    await t.ctrl.start();
    await at(t.port, t.ctrl, 99.8);

    t.port.finish();
    await Future<void>.delayed(Duration.zero);
    wall += const Duration(milliseconds: 100);
    t.ctrl.debugTick();
    expect(t.ctrl.state, SessionState.running);
    expect(t.ctrl.elapsed, greaterThanOrEqualTo(const Duration(seconds: 99)),
        reason: 'la position du lecteur retombée à 0 ne fait pas reculer la '
            'séance');

    wall += const Duration(milliseconds: 300);
    t.ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(t.ctrl.state, SessionState.finished);
    expect(t.beep.attachedTrack, isNull);
    expect(t.ctrl.elapsedSeconds, greaterThanOrEqualTo(100));

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'fin de séance à 150 ms d\'avance : le morceau (99,848 s pour 100 s de '
      'séance, comme 178,848 s pour 179 s) finit avant la séance, l\'événement '
      'de fin reste le juge', () async {
    var wall = Duration.zero;
    final t = build(wall: () => wall);
    await t.ctrl.start();
    expect(t.ctrl.musicBeepAdvanceMs, 150);
    await at(t.port, t.ctrl, 99.848);
    expect(t.ctrl.state, SessionState.running,
        reason: 'à 150 ms la séance n\'est pas finie avant la fin du morceau');

    t.port.finish();
    await Future<void>.delayed(Duration.zero);
    wall += const Duration(milliseconds: 10);
    t.ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(t.ctrl.state, SessionState.finished);
    expect(t.beep.attachedTrack, isNull);
    expect(t.beep.finaleChimes, 0);

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'fin de séance à 400 ms d\'avance (maximum) : la séance se termine '
      'proprement, 248 ms avant la fin du morceau, sans attendre son '
      'événement de fin', () async {
    SharedPreferences.setMockInitialValues(
        {'debug.music_beep_advance_ms': 400});
    final t = build();
    await t.ctrl.start();
    await at(t.port, t.ctrl, 99.6);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(t.ctrl.state, SessionState.finished);
    expect(t.beep.attachedTrack, isNull);
    expect(t.beep.finaleChimes, 0);
    expect(t.port.stops, greaterThanOrEqualTo(1));

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'séance ordinaire : aucune avance, ni sur le moteur de bips ni sur '
      'l\'horloge, et rien n\'est écrit dans les préférences', () async {
    final shared = _Beep();
    final t = build(session: plain, sharedBeep: shared);
    await t.ctrl.start();
    expect(t.ctrl.isMusical, isFalse);
    expect(t.ctrl.musicBeepAdvanceMs, 0);
    expect(shared.musicBeepAdvance, Duration.zero);
    expect(t.ctrl.elapsed, lessThan(const Duration(milliseconds: 150)),
        reason: 'l\'horloge est le chronomètre, sans les 150 ms du morceau');

    await t.ctrl.setMusicBeepAdvanceMs(300);
    expect(t.ctrl.musicBeepAdvanceMs, 0);
    expect(shared.musicBeepAdvance, Duration.zero);
    expect(
        (await SharedPreferences.getInstance())
            .containsKey('debug.music_beep_advance_ms'),
        isFalse);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'fin du morceau : le rapport à 0 arrivé avant l\'événement de fin ne '
      'fait pas reculer la séance', () async {
    var wall = Duration.zero;
    final t = build(wall: () => wall);
    await t.ctrl.start();
    await at(t.port, t.ctrl, 99.8);

    t.port.finish(zeroFirst: true);
    await Future<void>.delayed(Duration.zero);
    wall += const Duration(milliseconds: 100);
    t.ctrl.debugTick();
    expect(t.ctrl.elapsed, greaterThanOrEqualTo(const Duration(seconds: 99)));

    wall += const Duration(milliseconds: 300);
    t.ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(t.ctrl.state, SessionState.finished);

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'JE PEUX PAS dont le souffle déborde la fin du morceau : la séance se '
      'termine à sa durée, souffle coupé', () async {
    var wall = Duration.zero;
    final t = build(wall: () => wall);
    await t.ctrl.start();
    await at(t.port, t.ctrl, 92);
    await t.ctrl.triggerFail();
    expect(t.ctrl.isMusicBreathing, isTrue);

    await at(t.port, t.ctrl, 99.8);
    t.port.finish();
    await Future<void>.delayed(Duration.zero);
    wall += const Duration(milliseconds: 100);
    t.ctrl.debugTick();
    expect(t.ctrl.state, SessionState.running);
    expect(t.ctrl.elapsed, greaterThanOrEqualTo(const Duration(seconds: 99)));

    wall += const Duration(milliseconds: 300);
    t.ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(t.ctrl.state, SessionState.finished);
    expect(t.ctrl.isMusicBreathing, isFalse);
    expect(t.ctrl.hadFailThisSession, isTrue);

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'stop pendant la queue qui suit la fin du morceau : séance à l\'arrêt, '
      'jamais terminée, morceau libéré', () async {
    var wall = Duration.zero;
    final t = build(wall: () => wall);
    final states = <SessionState>[];
    t.ctrl.addListener(() {
      if (states.isEmpty || states.last != t.ctrl.state) {
        states.add(t.ctrl.state);
      }
    });
    await t.ctrl.start();
    await at(t.port, t.ctrl, 99.6);
    t.port.finish();
    await Future<void>.delayed(Duration.zero);
    wall += const Duration(milliseconds: 100);
    t.ctrl.debugTick();
    expect(t.ctrl.elapsed, greaterThanOrEqualTo(const Duration(seconds: 99)));
    final stops = t.port.stops;

    await t.ctrl.stop();
    expect(t.ctrl.state, SessionState.idle);
    expect(t.port.stops, greaterThan(stops));
    expect(t.beep.attachedTrack, isNull);

    wall += const Duration(seconds: 5);
    t.ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(states, isNot(contains(SessionState.finished)));
    expect(t.ctrl.state, SessionState.idle);

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'pause puis reprise dans la queue qui suit la fin du morceau : le '
      'lecteur n\'est pas relancé', () async {
    var wall = Duration.zero;
    final t = build(wall: () => wall);
    await t.ctrl.start();
    await at(t.port, t.ctrl, 99.8);
    t.port.finish();
    await Future<void>.delayed(Duration.zero);
    final plays = t.port.plays;

    await t.ctrl.pause();
    await t.ctrl.resume();
    expect(t.port.plays, plays,
        reason: 'un lecteur terminé qu\'on reprend repartirait du début');

    wall += const Duration(milliseconds: 400);
    t.ctrl.debugTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(t.ctrl.state, SessionState.finished);

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'JE PEUX PAS pendant une tenue full : le record Iron Lungs ne compte que '
      'la tenue reprise après le souffle', () async {
    final t = build(session: fullHoldMusical);
    await t.ctrl.start();
    for (final second in [10, 11, 12, 13]) {
      await at(t.port, t.ctrl, second + 0.2);
    }
    expect(t.beep.currentMode, SessionMode.hold);
    expect(t.beep.currentFrom, Position.full);

    await t.ctrl.triggerFail();
    expect(t.beep.currentMode, SessionMode.breath);

    for (var second = 22; second <= 29; second++) {
      await at(t.port, t.ctrl, second + 0.2);
    }
    expect(t.beep.currentMode, SessionMode.hold,
        reason: 'la tenue reprend après le souffle');
    await at(t.port, t.ctrl, 30.2);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await StatsService().snapshot()).maxHoldFullAtomic, 8,
        reason: 'les 4 s d\'avant le FAIL et les 8 s d\'après ne font pas une '
            'tenue de 12 s');

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('detachAudio et dispose libèrent le morceau et détachent les bips',
      () async {
    final a = build();
    await a.ctrl.start();
    final stopsA = a.port.stops;
    await a.ctrl.detachAudio();
    expect(a.beep.attachedTrack, isNull);
    expect(a.port.stops, greaterThan(stopsA));
    a.ctrl.dispose();

    final b = build();
    await b.ctrl.start();
    final stopsB = b.port.stops;
    b.ctrl.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(b.beep.attachedTrack, isNull);
    expect(b.port.stops, greaterThan(stopsB));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'une séance ordinaire qui démarre détache le morceau resté sur le '
      'BeepEngine partagé', () async {
    final shared = _Beep();
    shared.attachMusic(track, () => Duration.zero);
    expect(shared.attachedTrack, isNotNull);

    final t = build(session: plain, sharedBeep: shared);
    await t.ctrl.start();
    expect(shared.attachedTrack, isNull);
    expect(t.ctrl.isMusical, isFalse);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('pas de mini-punition sur une séance à morceau', () async {
    final t = build(session: longMusical, miniPunishmentRate: 1.0);
    await t.ctrl.start();
    for (var second = 1; second <= 62; second++) {
      await at(t.port, t.ctrl, second.toDouble());
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(t.ctrl.state, SessionState.running);
    expect(t.beep.pauseCalls, 0,
        reason: 'une mini-punition couperait les bips le temps de la punition');

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('pas de commentaire aléatoire sur une séance à morceau', () async {
    final t = build(
      randomComments: const RandomCommentsBundle(
        comments: [RandomComment(text: 'au hasard')],
        minIntervalSeconds: 1,
        maxIntervalSeconds: 1,
        scriptedCooldownSeconds: 0,
      ),
    );
    await t.ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(spoken.where((s) => s == 'au hasard'), isEmpty);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(
      'le coach ne parle que par les consignes du morceau : ni palier de '
      'progression, ni phrase de transition', () async {
    const bank = PhraseBank(
      byMode: {},
      congrats: [],
      intros: [],
      progress: {
        25: [PhraseEntry(text: 'palier')],
      },
      transitions: {
        TransitionKind.depthUp: [PhraseEntry(text: 'plus profond')],
      },
    );
    final t = build(phraseBank: bank);
    await t.ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await at(t.port, t.ctrl, 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await at(t.port, t.ctrl, 26);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await at(t.port, t.ctrl, 31);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await at(t.port, t.ctrl, 46);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(t.beep.appliedSteps.last.to, Position.throat,
        reason: 'le step sans texte de t=45 a bien été appliqué');
    expect(spoken, ['ouverture', 'debut', 'monte']);

    await t.ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
      'un JE PEUX PAS musical ne coûte pas d\'humiliation de carrière en fin '
      'de séance', () async {
    SharedPreferences.setMockInitialValues({'stats.humiliation_level': 10.0});
    final t = build();
    await t.ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await at(t.port, t.ctrl, 20);
    await t.ctrl.triggerFail();
    await at(t.port, t.ctrl, 99);
    await at(t.port, t.ctrl, 100.2);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(t.ctrl.state, SessionState.finished);

    expect(await StatsService().getHumiliationLevel(), greaterThanOrEqualTo(10),
        reason: 'un fail ordinaire retirerait 1 point de carrière');

    t.ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));
}

class _Port implements MusicPlayerPort {
  final _controller = StreamController<Duration>.broadcast();
  Duration startupLatency = Duration.zero;
  Duration _audio = Duration.zero;
  int plays = 0;
  int pauses = 0;
  int stops = 0;

  void seek(Duration to) {
    _audio = to;
    _controller.add(to);
  }

  final _completed = StreamController<void>.broadcast();

  @override
  Stream<void> get completions => _completed.stream;

  /// Fin de lecture des plugins audioplayers : l'événement de fin, puis la
  /// position remise à 0 ; [zeroFirst] inverse cet ordre.
  void finish({bool zeroFirst = false}) {
    _audio = Duration.zero;
    if (zeroFirst) {
      _controller.add(Duration.zero);
      _completed.add(null);
    } else {
      _completed.add(null);
      _controller.add(Duration.zero);
    }
  }

  @override
  Stream<Duration> get positions => _controller.stream;
  @override
  Future<void> load(String asset, {required double volume}) async {}
  @override
  Future<void> play() async {
    plays++;
    Timer(startupLatency, () => _controller.add(_audio));
  }

  @override
  Future<void> pause() async => pauses++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}

class _Beep extends BeepEngine {
  int pauseCalls = 0;
  int finaleChimes = 0;
  final List<SessionStep> appliedSteps = [];
  SessionMusic? attachedTrack;
  Duration Function()? attachedPosition;
  SessionMode _mode = SessionMode.rhythm;
  Position _from = Position.head;
  Position? _to;
  int _bpm = 60;

  @override
  SessionMode get currentMode => _mode;
  @override
  Position get currentFrom => _from;
  @override
  Position? get currentTo => _to;
  @override
  int get currentBpm => _bpm;

  @override
  void attachMusic(SessionMusic music, Duration Function() position) {
    attachedTrack = music;
    attachedPosition = position;
    super.attachMusic(music, position);
  }

  @override
  void detachMusic() {
    attachedTrack = null;
    attachedPosition = null;
    super.detachMusic();
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    appliedSteps.add(step);
    if (step.isTextOnly) return;
    final resolved = resolveStepConfig(
      step: step,
      defaultMode: sessionMode,
      currentFrom: _from,
      currentBpm: _bpm,
    );
    _mode = resolved.mode;
    _bpm = resolved.bpm;
    _from = resolved.from;
    _to = resolved.to;
  }

  @override
  Future<void> playFinaleChime(
      {FinalCategory? category, double volume = 1.0}) async {
    finaleChimes++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _SilentAmbienceEngine extends AmbienceEngine {
  int playForModeCalls = 0;
  final List<Duration> finishStarts = [];

  @override
  Future<void> startFinishMusic(Duration untilPeak) async =>
      finishStarts.add(untilPeak);

  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> playForMode(SessionMode mode, {Position? depth}) async {
    playForModeCalls++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
