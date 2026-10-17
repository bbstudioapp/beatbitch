import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_music.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/music_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Horloge réelle : le ticker est un `Timer.periodic`, et les `await` de
// `start()` ne se tiennent qu'avec des portes que le test ouvre à la main.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockToggle =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
      '.toggle';
  const wakelockIsEnabled =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
      '.isEnabled';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Wakelock wakelock;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    wakelock = _Wakelock();
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, (call) async => null);
    }
    // Le message pigeon de `toggle` est `[ToggleMessage]` ; son codec est privé
    // au paquet, l'octet final porte `enable` (1 = vrai, 2 = faux).
    messenger.setMockMessageHandler(wakelockToggle, (message) async {
      await wakelock
          .onToggle(message!.getUint8(message.lengthInBytes - 1) == 1);
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
    messenger.setMockMessageHandler(
      wakelockIsEnabled,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, null);
    }
    messenger.setMockMessageHandler(wakelockToggle, null);
    messenger.setMockMessageHandler(wakelockIsEnabled, null);
  });

  Future<Set<String>> profileKeys() async =>
      (await SharedPreferences.getInstance()).getKeys();

  /// Rejoue le geste : `start()` bloqué sur [gate], le joueur quitte, la porte
  /// s'ouvre, puis on laisse [settle] au contrôleur pour faire (ou non) du bruit.
  Future<List<Object>> leaveDuringStart(
    _Bench b,
    _Gate gate,
    void Function() leave, {
    Duration settle = const Duration(milliseconds: 500),
  }) {
    gate.hold();
    return _guarded((errors) async {
      final started = b.ctrl.start().catchError((Object e) {
        errors.add(e);
      });
      await gate.reached;
      leave();
      gate.open();
      await started;
      await Future<void>.delayed(settle);
    });
  }

  void expectNoPhantomSession(_Bench b, List<Object> errors) {
    expect(b.beep.applied.length, 0,
        reason: 'applyStep sur le BeepEngine partagé après dispose()');
    expect(b.ctrl.state, SessionState.idle,
        reason: 'le contrôleur libéré ne doit pas passer en running');
    expect(b.ctrl.elapsed, Duration.zero,
        reason: "l'horloge de séance ne doit pas avoir démarré");
    expect(errors, isEmpty,
        reason: 'exceptions levées par le contrôleur libéré (assert debug)');
  }

  group('retour arrière pendant start()', () {
    test('pendant _tts.init : rien de ce qui suit ne démarre', () async {
      final b = _Bench();
      final errors = await leaveDuringStart(b, b.tts.gate, b.ctrl.dispose);

      expectNoPhantomSession(b, errors);
      expect(b.beep.initCalls, 0, reason: '_beep.init() après dispose()');
      expect(wakelock.enables, 0, reason: 'wakelock enclenché après dispose()');
    });

    test(
        'pendant _beep.init : pas de wakelock, pas de ticker, aucune écriture '
        'de profil', () async {
      final b = _Bench();
      final errors = await leaveDuringStart(
        b,
        b.beep.gate,
        b.ctrl.dispose,
        settle: const Duration(milliseconds: 2500),
      );

      expect(await profileKeys(), isEmpty,
          reason: 'une séance jamais jouée a écrit dans le profil');
      expectNoPhantomSession(b, errors);
      expect(wakelock.enables, 0, reason: 'wakelock enclenché après dispose()');
    });

    test('pendant le wakelock : relâché, séance non démarrée', () async {
      final b = _Bench();
      final errors = await leaveDuringStart(b, wakelock.gate, b.ctrl.dispose);

      expectNoPhantomSession(b, errors);
      expect(wakelock.on, isFalse,
          reason: "l'écran reste maintenu allumé après dispose()");
    });

    test('detachAudio pendant _beep.init : même arrêt propre', () async {
      final b = _Bench();
      final errors = await leaveDuringStart(
        b,
        b.beep.gate,
        () => unawaited(b.ctrl.detachAudio()),
        settle: const Duration(milliseconds: 2500),
      );

      expect(await profileKeys(), isEmpty,
          reason: 'une séance détachée a écrit dans le profil');
      expectNoPhantomSession(b, errors);
      expect(wakelock.enables, 0,
          reason: 'wakelock enclenché après detachAudio()');
      b.ctrl.dispose();
    });

    test('séance à morceau, pendant music.start : grille non attachée',
        () async {
      final b = _Bench(music: true);
      final errors = await leaveDuringStart(b, b.port.gate, b.ctrl.dispose);

      expectNoPhantomSession(b, errors);
      expect(b.beep.attachedTrack, isNull,
          reason: 'grille du morceau laissée sur le BeepEngine partagé');
      expect(b.port.playing, isFalse,
          reason: 'morceau laissé en lecture après dispose()');
      expect(wakelock.enables, 0, reason: 'wakelock enclenché après dispose()');
    });

    test(
        'séance à morceau, pendant la lecture du réglage d’avance : aucun '
        'lecteur lancé', () async {
      final prefs = _GatedPrefsStore();
      SharedPreferencesStorePlatform.instance = prefs;
      prefs.gate.hold();
      final b = _Bench(music: true);
      final errors = await _guarded((errors) async {
        final started = b.ctrl.start().catchError((Object e) {
          errors.add(e);
        });
        await b.beep.gate.reached;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        b.ctrl.dispose();
        prefs.gate.open();
        await started;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });

      expectNoPhantomSession(b, errors);
      expect(b.port.playing, isFalse,
          reason: 'morceau laissé en lecture sans propriétaire');
      expect(b.port.created, isFalse,
          reason: 'lecteur natif non libéré après dispose()');
      expect(b.port.loads, 0,
          reason: 'morceau chargé pour un contrôleur libéré');
      expect(wakelock.enables, 0, reason: 'wakelock enclenché après dispose()');
    });
  });

  group('témoins', () {
    test(
        'dispose() après la fin de start() : plus aucun applyStep, horloge '
        'figée', () async {
      final b = _Bench();
      await b.ctrl.start();
      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.applied, isNotEmpty);

      b.ctrl.dispose();
      final applied = b.beep.applied.length;
      final elapsed = b.ctrl.elapsed;
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(b.beep.applied.length, applied);
      expect(b.ctrl.elapsed, elapsed);
    });

    test('séance à morceau menée jusqu’au bout : grille attachée', () async {
      final b = _Bench(music: true);
      await b.ctrl.start();

      expect(b.ctrl.state, SessionState.running);
      expect(b.beep.attachedTrack, _track);
      expect(wakelock.on, isTrue);
      b.ctrl.dispose();
    });
  });

  group('_finish', () {
    test('ne part pas d’un contrôleur libéré', () async {
      final b = _Bench();
      await b.ctrl.start();
      b.ctrl.dispose();
      final before = await profileKeys();

      await _guarded((_) => b.ctrl.debugFinishSuccess());

      expect(await profileKeys(), before,
          reason: 'la clôture a écrit dans le profil après dispose()');
    });
  });
}

const _track = SessionMusic(
  asset: 'audio/music/montee_en_puissance.mp3',
  bpm: 121.96,
  firstBeatSeconds: 16.934,
);

/// Exécute [body] dans une zone qui collecte aussi les erreurs de timers, et
/// rend toujours la main — une assertion levée dans la zone aurait suspendu le
/// test.
Future<List<Object>> _guarded(
  Future<void> Function(List<Object> errors) body,
) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body(errors);
    } catch (e) {
      errors.add(e);
    } finally {
      done.complete();
    }
  }, (e, _) => errors.add(e));
  await done.future;
  return errors;
}

/// Point d'arrêt d'un `await` de `start()`. Ouverte tant que le test ne l'a pas
/// posée avec [hold] : [reached] dit que `start()` y est arrivé, [open] le
/// laisse repartir.
class _Gate {
  final _reached = Completer<void>();
  final _open = Completer<void>();
  bool _held = false;

  Future<void> get reached => _reached.future;

  void hold() => _held = true;

  Future<void> pass() {
    if (!_reached.isCompleted) _reached.complete();
    return _held ? _open.future : Future<void>.value();
  }

  void open() {
    if (!_open.isCompleted) _open.complete();
  }
}

class _Wakelock {
  final gate = _Gate();
  int enables = 0;
  bool on = false;

  /// `on` suit l'ordre de **résolution** des appels : un `enable` lent qui
  /// aboutit après le `disable` du `dispose()` laisse l'écran allumé.
  Future<void> onToggle(bool enable) async {
    if (enable) {
      enables++;
      await gate.pass();
    }
    on = enable;
  }
}

class _Bench {
  _Bench({bool music = false}) {
    ctrl = SessionController(
      session: Session(
        id: 'fantome',
        name: 'fantome',
        description: '',
        durationSeconds: 1,
        defaultMode: SessionMode.rhythm,
        steps: const [
          SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 1),
        ],
        music: music ? _track : null,
      ),
      tts: tts,
      beep: beep,
      ambience: _SilentAmbienceEngine(),
      punishmentBundle:
          const PunishmentBundle(failPhrases: [], punishments: []),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      music: music
          ? MusicEngine(
              port: port, syncTimeout: const Duration(milliseconds: 200))
          : null,
    );
  }

  final tts = _GatedTts();
  final beep = _GatedBeep();
  final port = _GatedPort();
  late final SessionController ctrl;
}

class _GatedTts extends TtsService {
  final gate = _Gate();

  @override
  Future<void> init() async {
    await gate.pass();
    await super.init();
  }
}

class _GatedBeep extends BeepEngine {
  final gate = _Gate();
  int initCalls = 0;
  final List<SessionStep> applied = [];
  SessionMusic? attachedTrack;

  @override
  Future<void> init() async {
    initCalls++;
    await gate.pass();
  }

  @override
  void attachMusic(SessionMusic music, Duration Function() position) {
    attachedTrack = music;
    super.attachMusic(music, position);
  }

  @override
  void detachMusic() {
    attachedTrack = null;
    super.detachMusic();
  }

  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    applied.add(step);
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

/// Création paresseuse, comme `MusicEngine._createdPort` : un `dispose()` qui
/// précède la première demande de `positions` n'a rien à libérer.
class _GatedPort implements MusicPlayerPort {
  final gate = _Gate();
  final _positions = StreamController<Duration>.broadcast();
  bool created = false;
  bool playing = false;
  int loads = 0;

  @override
  Stream<Duration> get positions {
    created = true;
    return _positions.stream;
  }

  @override
  Stream<void> get completions => const Stream<void>.empty();

  @override
  Future<void> load(String asset, {required double volume}) async {
    loads++;
  }

  @override
  Future<void> play() async {
    await gate.pass();
    if (created) playing = true;
    _positions.add(Duration.zero);
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> dispose() async {
    created = false;
    playing = false;
  }
}

/// `getInstance()` met la première lecture en cache : seul moyen de tenir
/// `getMusicBeepAdvanceMs()`.
class _GatedPrefsStore extends InMemorySharedPreferencesStore {
  _GatedPrefsStore() : super.empty();

  final gate = _Gate();

  @override
  Future<Map<String, Object>> getAll() async {
    await gate.pass();
    return super.getAll();
  }
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
