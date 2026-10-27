import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  group('AmbienceEngine.startFinishMusic', () {
    test('démarre le fichier au point qui place le sommet dans untilPeak',
        () async {
      final engine = _OffsetRecordingEngine();
      await engine.startFinishMusic(
          const Duration(seconds: 25), AmbienceEngine.commonFinishTrack);
      expect(engine.offsets.single,
          AmbienceEngine.commonFinishTrack.peak - const Duration(seconds: 25));
      expect(engine.isFinishMusicPlaying, isTrue);
    });

    test('montée plus longue que le sommet : départ au début du fichier',
        () async {
      final engine = _OffsetRecordingEngine();
      await engine.startFinishMusic(
          AmbienceEngine.commonFinishTrack.peak + const Duration(seconds: 30),
          AmbienceEngine.commonFinishTrack);
      expect(engine.offsets.single, Duration.zero);
    });

    test('un fondu demandé pendant le démarrage empêche la musique de jouer',
        () async {
      final engine = _SlowStartEngine();
      final starting = engine.startFinishMusic(
          const Duration(seconds: 25), AmbienceEngine.commonFinishTrack);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.inFlight, isTrue,
          reason: 'le fondu doit tomber pendant le démarrage');
      await engine.fadeOutFinishMusic(
          duration: const Duration(milliseconds: 60));
      await starting;
      expect(engine.inFlight, isFalse);
      expect(engine.isFinishMusicPlaying, isFalse,
          reason: 'un FAIL tombé pendant le démarrage laissait la musique '
              'jouer pendant la punition');
    });
  });

  group('musique de fin par coach', () {
    const linaTrack = (
      asset: 'audio/music/finish_coach_01_lina.mp3',
      peak: Duration(seconds: 61)
    );
    const tracks = {'lina': linaTrack};
    Future<bool> bundled(String key) async =>
        key == 'assets/${linaTrack.asset}';
    Future<bool> nothingBundled(String key) async => false;

    test('une coach avec morceau joue son fichier calé sur son sommet',
        () async {
      final engine = _OffsetRecordingEngine(
          finishTracksByCoach: tracks, isAssetBundled: bundled);
      final track = await engine.finishTrackFor('lina');
      await engine.startFinishMusic(const Duration(seconds: 25), track);
      expect(engine.assets.single, linaTrack.asset);
      expect(engine.offsets.single, const Duration(seconds: 36));
    });

    test('un morceau de coach absent du bundle retombe sur le commun',
        () async {
      final engine = _OffsetRecordingEngine(
          finishTracksByCoach: tracks, isAssetBundled: nothingBundled);
      final track = await engine.finishTrackFor('lina');
      await engine.startFinishMusic(const Duration(seconds: 25), track);
      expect(engine.assets.single, 'audio/music/finish_music.mp3');
      expect(engine.offsets.single, const Duration(seconds: 67));
    });

    test('une coach sans morceau et une séance sans coach jouent le commun',
        () async {
      final engine = _OffsetRecordingEngine(
          finishTracksByCoach: tracks, isAssetBundled: bundled);
      expect(await engine.finishTrackFor('helene'),
          AmbienceEngine.commonFinishTrack);
      expect(
          await engine.finishTrackFor(null), AmbienceEngine.commonFinishTrack);
      expect(AmbienceEngine.commonFinishTrack, (
        asset: 'audio/music/finish_music.mp3',
        peak: const Duration(seconds: 92)
      ));
    });

    test(
        'la séance démarre le morceau de sa coach sur son sommet, et une '
        'séance de plus avec la même coach rejoue le même', () async {
      // Sommet de 2 s : départ au final (8 s) au lieu du début de montée
      // (4 s) que donnerait le sommet commun.
      const shortPeak = (
        asset: 'audio/music/finish_coach_01_lina.mp3',
        peak: Duration(seconds: 2)
      );
      final ambience = _FinishRecordingAmbience(
          finishTracksByCoach: {'lina': shortPeak},
          isAssetBundled: (key) async => key == 'assets/${shortPeak.asset}');
      late SessionController ctrl;
      ambience.onEvent = (e) => ambience.events.add((e, ctrl.elapsedSeconds));

      for (var i = 0; i < 2; i++) {
        ambience.events.clear();
        ctrl = _buildController(ambience, coachTag: 'lina');
        await ctrl.start();
        await _waitUntil(() => ambience.events.isNotEmpty);
        await ctrl.stop();
        ctrl.dispose();
        expect(ambience.events.single, ('start 0s', 8),
            reason: 'séance ${i + 1} : départ calé sur le sommet de 2 s');
      }
      expect(ambience.tracks, [shortPeak, shortPeak]);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('une séance sans coach démarre le commun au début de la montée',
        () async {
      final ambience = _FinishRecordingAmbience(
          finishTracksByCoach: tracks, isAssetBundled: bundled);
      late SessionController ctrl;
      ambience.onEvent = (e) => ambience.events.add((e, ctrl.elapsedSeconds));
      ctrl = _buildController(ambience);
      await ctrl.start();
      await _waitUntil(() => ambience.events.isNotEmpty);
      await ctrl.stop();
      ctrl.dispose();
      expect(ambience.events.single, ('start 4s', 4));
      expect(ambience.tracks.single, AmbienceEngine.commonFinishTrack);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  test('un fondu demandé pendant un autre fondu le laisse aller à son terme',
      () async {
    final engine = _OffsetRecordingEngine();
    await engine.startFinishMusic(
        const Duration(seconds: 25), AmbienceEngine.commonFinishTrack);

    final clock = Stopwatch()..start();
    final first =
        engine.fadeOutFinishMusic(duration: const Duration(milliseconds: 600));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await engine.fadeOutFinishMusic(
        duration: const Duration(milliseconds: 600));
    await first;

    expect(clock.elapsedMilliseconds, greaterThan(500),
        reason: 'le second fondu a interrompu le premier à mi-volume : la '
            'musique reste audible');
  });

  test(
      'la musique démarre au début de la montée, calée sur le final, et '
      "s'éteint au post-final", () async {
    final ambience = _FinishRecordingAmbience();
    late SessionController ctrl;
    ambience.onEvent = (e) => ambience.events.add((e, ctrl.elapsedSeconds));
    ctrl = _buildController(ambience);
    await ctrl.start();
    await _waitUntil(() => ctrl.isFinished);

    final starts = ambience.events.where((e) => e.$1.startsWith('start'));
    expect(starts.map((e) => e.$1), ['start 4s'],
        reason: 'un seul départ, sommet dans 4 s (final à 8, montée à 4)');
    expect(starts.single.$2, 4);
    final fades = ambience.events.where((e) => e.$1 == 'fade');
    expect(fades, isNotEmpty);
    expect(fades.first.$2, 11, reason: 'premier step du post-final');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('un FAIL pendant la montée relance la musique à la reprise', () async {
    final starts = await _startsAroundPunishment((ctrl) => ctrl.triggerFail());
    expect(starts, ['start 16s', 'start 12s'],
        reason: 'le fondu du FAIL éteint la musique ; le step de 8 s qui suit '
            'la punition doit la relancer, calée sur le final');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('une mini-punition pendant la montée relance la musique à la reprise',
      () async {
    final starts = await _startsAroundPunishment(
        (ctrl) => ctrl.debugRunMiniPunishment(_shortPunishment));
    expect(starts, ['start 16s', 'start 12s'],
        reason: 'le fondu de la mini-punition éteint la musique ; le step de '
            '8 s qui suit doit la relancer, calée sur le final');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
      'sans le fichier de la musique de finish, la montée et le final se '
      "jouent jusqu'au bout", () async {
    final ambience = _MissingFinishAssetAmbience();
    final beep = _RecordingBeepEngine();
    final ctrl = _buildController(ambience, beep: beep);
    await ctrl.start();
    await _waitUntil(() => ctrl.isFinished);

    expect(ambience.attempts, 1,
        reason: 'la musique est bien demandée, et son absence est absorbée');
    expect(ambience.isFinishMusicPlaying, isFalse);
    expect(beep.appliedTimes, containsAllInOrder([4, 8, 11]),
        reason: 'montée (4), final (8) et post-final (11) appliqués');
    ctrl.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Démarrages de la musique de finish autour de [punish], lancé dès le
/// premier démarrage (step de 4 s).
Future<List<String>> _startsAroundPunishment(
    Future<void> Function(SessionController ctrl) punish) async {
  final ambience = _FinishRecordingAmbience();
  ambience.onEvent = (e) => ambience.events.add((e, 0));
  final ctrl = SessionController(
    session: const Session(
      id: 'finish-fail',
      name: 'finish-fail',
      description: '',
      durationSeconds: 40,
      defaultMode: SessionMode.rhythm,
      silentFinishStartTime: 4,
      finalStepTime: 20,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40),
        SessionStep(time: 4, mode: SessionMode.rhythm, bpm: 60),
        SessionStep(time: 8, mode: SessionMode.rhythm, bpm: 90),
        SessionStep(time: 20, mode: SessionMode.hold, to: Position.full),
        SessionStep(time: 24, mode: SessionMode.breath, duration: 2),
      ],
    ),
    tts: TtsService(),
    beep: _SilentBeepEngine(),
    ambience: ambience,
    // Endurance haute : respiration d'avant-punition courte.
    staminaProfile: List<double>.filled(120, 100),
    punishmentBundle: const PunishmentBundle(
        failPhrases: ['raté'], punishments: [_shortPunishment]),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
  );
  await ctrl.start();
  await _waitUntil(() => ambience.events.isNotEmpty);
  await punish(ctrl);
  await _waitUntil(() => ctrl.elapsedSeconds >= 9);
  await ctrl.stop();
  ctrl.dispose();
  return [
    for (final (e, _) in ambience.events)
      if (e.startsWith('start')) e,
  ];
}

const _shortPunishment = Punishment(
  id: 'courte',
  name: 'courte',
  durationSeconds: 1,
  steps: [SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 60)],
);

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition non atteinte en ${timeout.inSeconds} s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

SessionController _buildController(AmbienceEngine ambience,
    {BeepEngine? beep, String? coachTag}) {
  return SessionController(
    session: const Session(
      id: 'finish',
      name: 'finish',
      description: '',
      durationSeconds: 13,
      defaultMode: SessionMode.rhythm,
      silentFinishStartTime: 4,
      finalStepTime: 8,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
        SessionStep(time: 2, mode: SessionMode.rhythm, bpm: 60, duration: 2),
        SessionStep(time: 4, mode: SessionMode.rhythm, bpm: 90, duration: 4),
        SessionStep(time: 8, mode: SessionMode.hold, to: Position.full),
        SessionStep(time: 11, mode: SessionMode.breath, duration: 2),
      ],
    ),
    tts: TtsService(),
    beep: beep ?? _SilentBeepEngine(),
    ambience: ambience,
    punishmentBundle: const PunishmentBundle(failPhrases: [], punishments: []),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
    coachTag: coachTag,
  );
}

class _OffsetRecordingEngine extends AmbienceEngine {
  _OffsetRecordingEngine({
    super.finishTracksByCoach,
    super.isAssetBundled,
  });

  final List<Duration> offsets = [];
  final List<String> assets = [];

  @override
  Future<void> startFinishPlayback(String asset, Duration offset) async {
    assets.add(asset);
    offsets.add(offset);
  }
}

/// Démarrage du lecteur qui prend 300 ms, comme `setSource + seek + resume`
/// sur un appareil lent.
class _SlowStartEngine extends AmbienceEngine {
  bool inFlight = false;

  @override
  Future<void> startFinishPlayback(String asset, Duration offset) async {
    inFlight = true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    inFlight = false;
  }
}

/// Le lecteur lève comme sur un asset absent du bundle.
class _MissingFinishAssetAmbience extends AmbienceEngine {
  int attempts = 0;

  @override
  Future<void> startFinishPlayback(String asset, Duration offset) async {
    attempts++;
    throw PlatformException(code: 'AudioPlayers Exception', message: 'asset');
  }

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
}

class _RecordingBeepEngine extends _SilentBeepEngine {
  final List<int> appliedTimes = [];

  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async =>
      appliedTimes.add(step.time);
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

class _FinishRecordingAmbience extends AmbienceEngine {
  _FinishRecordingAmbience({
    super.finishTracksByCoach,
    super.isAssetBundled,
  });

  final List<(String, int)> events = [];
  final List<FinishTrack> tracks = [];
  void Function(String) onEvent = (_) {};

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
  @override
  Future<void> startFinishMusic(Duration untilPeak, FinishTrack track) async {
    tracks.add(track);
    onEvent('start ${untilPeak.inSeconds}s');
  }

  @override
  Future<void> fadeOutFinishMusic(
          {Duration duration = const Duration(seconds: 3)}) async =>
      onEvent('fade');
  @override
  Future<void> stopFinishMusic() async {}
}
