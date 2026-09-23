import 'dart:async';

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
        clock: MusicClock(now: () => Duration.zero),
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

  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> playForMode(SessionMode mode) async {
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
