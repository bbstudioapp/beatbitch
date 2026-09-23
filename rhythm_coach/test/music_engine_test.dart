import 'dart:async';

import 'package:beat_bitch/models/session_music.dart';
import 'package:beat_bitch/services/music_clock.dart';
import 'package:beat_bitch/services/music_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = SessionMusic(
  asset: 'audio/music/montee_en_puissance.mp3',
  bpm: 121.96,
  firstBeatSeconds: 16.934,
);

/// Lecteur factice fidèle à `audioplayers` : rien n'est rapporté avant que le
/// son ne sorte réellement (latence de démarrage), puis une position à chaque
/// frame ; l'horloge audio peut tourner un peu plus vite que l'horloge murale.
class _FakePort implements MusicPlayerPort {
  _FakePort(this.async,
      {this.startupLatency = Duration.zero,
      this.audioRate = 1.0,
      this.hangOnTransport = false});

  final FakeAsync async;
  final Duration startupLatency;
  final double audioRate;
  final bool hangOnTransport;
  final _controller = StreamController<Duration>.broadcast();
  Timer? _ticker;
  Duration _audio = Duration.zero;
  Duration? _lastTick;
  bool _running = false;
  int loads = 0;
  int plays = 0;
  int pauses = 0;
  int stops = 0;
  bool failLoad = false;
  bool silent = false;

  Duration get audioPosition => _audio;

  @override
  Stream<Duration> get positions => _controller.stream;

  @override
  Future<void> load(String asset, {required double volume}) async {
    loads++;
    if (failLoad) throw StateError('asset introuvable');
  }

  void _advance() {
    final last = _lastTick;
    if (!_running || last == null || async.elapsed < last) return;
    _audio += (async.elapsed - last) * audioRate;
    _lastTick = async.elapsed;
  }

  @override
  Future<void> play() async {
    plays++;
    if (hangOnTransport && plays > 1) return Completer<void>().future;
    _running = true;
    _lastTick = async.elapsed + startupLatency;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _advance();
      final started = _lastTick != null && async.elapsed >= _lastTick!;
      if (_running && started && !silent) _controller.add(_audio);
    });
  }

  @override
  Future<void> pause() async {
    pauses++;
    if (hangOnTransport) return Completer<void>().future;
    _advance();
    _running = false;
    _lastTick = null;
  }

  @override
  Future<void> stop() async {
    stops++;
    _advance();
    _running = false;
    _lastTick = null;
  }

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
  }
}

void main() {
  test(
      'un lecteur qui démarre en retard : la position est celle du morceau, '
      'pas le temps écoulé depuis la demande', () {
    fakeAsync((async) {
      final port =
          _FakePort(async, startupLatency: const Duration(milliseconds: 1300));
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      bool? started;
      engine.start(_track).then((v) => started = v);

      async.elapse(const Duration(milliseconds: 1000));
      expect(started, isNull, reason: 'le morceau ne joue pas encore');
      expect(engine.position, Duration.zero);

      async.elapse(const Duration(milliseconds: 400));
      expect(started, isTrue);
      expect(engine.position.inMilliseconds, lessThan(150),
          reason: 'le morceau vient de démarrer, il n\'est pas à 1,3 s');

      async.elapse(const Duration(seconds: 10));
      expect((engine.position - port.audioPosition).abs().inMilliseconds,
          lessThan(20));
    });
  });

  test(
      'sans aucun rapport du lecteur : repli sur l\'horloge murale, sans '
      'planter', () {
    fakeAsync((async) {
      final port = _FakePort(async)..silent = true;
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      bool? started;
      engine.start(_track).then((v) => started = v);

      async.elapse(const Duration(seconds: 4));
      expect(started, isFalse);
      expect(engine.isSynced, isFalse);
      expect(port.stops, greaterThanOrEqualTo(1),
          reason: 'le lecteur muet est coupé');

      final before = engine.position;
      async.elapse(const Duration(seconds: 2));
      expect(engine.position - before, const Duration(seconds: 2));
    });
  });

  test('un asset qui ne charge pas : la séance continue sans musique', () {
    fakeAsync((async) {
      final port = _FakePort(async)..failLoad = true;
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      bool? started;
      engine.start(_track).then((v) => started = v);
      async.flushMicrotasks();

      expect(started, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(engine.position, const Duration(seconds: 1));
    });
  });

  test('la pause fige la position, la reprise repart de celle du morceau', () {
    fakeAsync((async) {
      final port = _FakePort(async);
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      engine.start(_track);
      async.elapse(const Duration(seconds: 5));

      engine.pause();
      async.flushMicrotasks();
      final frozen = engine.position;
      expect(port.pauses, 1);
      async.elapse(const Duration(seconds: 7));
      expect(engine.position, frozen);

      engine.resume();
      async.elapse(const Duration(seconds: 3));
      expect((engine.position - frozen).inMilliseconds, closeTo(3000, 40),
          reason: 'le morceau a repris là où il s\'était arrêté');
      expect((engine.position - port.audioPosition).abs().inMilliseconds,
          lessThan(40));
    });
  });

  test('un lecteur qui ne répond plus à pause ne retarde pas la séance', () {
    fakeAsync((async) {
      final port = _FakePort(async, hangOnTransport: true);
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      engine.start(_track);
      async.elapse(const Duration(seconds: 2));

      var returned = false;
      engine.pause().then((_) => returned = true);
      async.elapse(const Duration(milliseconds: 400));
      expect(returned, isTrue, reason: 'borné à 300 ms');
    });
  });

  test(
      'pas de dérive cumulée : l\'horloge audio va 0,1 % plus vite que '
      'l\'horloge murale', () {
    fakeAsync((async) {
      final port = _FakePort(async, audioRate: 1.001);
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      engine.start(_track);
      async.elapse(const Duration(milliseconds: 100));

      var worst = Duration.zero;
      for (var i = 0; i < 17900; i++) {
        async.elapse(const Duration(milliseconds: 10));
        final error = (engine.position - port.audioPosition).abs();
        if (error > worst) worst = error;
      }
      expect(port.audioPosition.inSeconds, greaterThan(178));
      expect(worst.inMilliseconds, lessThan(20),
          reason: 'sans ré-ancrage, 178 s de dérive à 0,1 % font 178 ms');
    });
  });

  test('stop puis nouveau start : repart de zéro', () {
    fakeAsync((async) {
      final port = _FakePort(async);
      final engine =
          MusicEngine(port: port, clock: MusicClock(now: () => async.elapsed));
      engine.start(_track);
      async.elapse(const Duration(seconds: 3));
      engine.stop();
      async.flushMicrotasks();
      final endedAt = engine.position;
      expect(endedAt.inMilliseconds, closeTo(3000, 40));

      port._audio = Duration.zero;
      engine.start(_track);
      async.elapse(const Duration(milliseconds: 100));
      expect(engine.position.inMilliseconds, lessThan(200));
    });
  });
}
