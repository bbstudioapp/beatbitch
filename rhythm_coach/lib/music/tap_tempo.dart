import 'dart:async';

import 'beat_clock.dart';
import 'beat_grid.dart';

/// Estimateur de tempo par tap (pur, testable). On lui passe des timestamps
/// (ms, monotones) ; il rend un BPM robuste (médiane des intervalles) et
/// l'ancre de phase (1er tap). Cf. `specs/music_mode.md` §4.1.
class TapTempoEstimator {
  final int maxTaps;
  final int resetGapMs;
  final double minBpm;
  final double maxBpm;

  final List<int> _taps = [];

  TapTempoEstimator({
    this.maxTaps = 8,
    this.resetGapMs = 2500,
    this.minBpm = 40,
    this.maxBpm = 240,
  });

  void tap(int nowMs) {
    if (_taps.isNotEmpty && nowMs - _taps.last > resetGapMs) _taps.clear();
    _taps.add(nowMs);
    if (_taps.length > maxTaps) _taps.removeAt(0);
  }

  void clear() => _taps.clear();

  int get tapCount => _taps.length;

  /// Au moins 1 intervalle → un tempo grossier est disponible.
  bool get hasTempo => _taps.length >= 2;

  /// ≥ 3 intervalles → tempo considéré stable (UI : 4 taps recommandés).
  bool get isStable => _taps.length >= 4;

  /// Temps du battement de référence (1er tap), ou `null`.
  int? get anchorMs => _taps.isEmpty ? null : _taps.first;

  List<int> get _intervals =>
      [for (var i = 1; i < _taps.length; i++) _taps[i] - _taps[i - 1]];

  double? get bpm {
    final iv = _intervals;
    if (iv.isEmpty) return null;
    final sorted = [...iv]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    if (median <= 0) return null;
    return (60000.0 / median).clamp(minBpm, maxBpm);
  }
}

/// Source de tempo « tap » (PR1). La joueuse tape le rythme ; on free-run
/// ensuite. Un unique [Stopwatch] sert de base de temps partagée entre les
/// taps et l'horloge — pas de dérive entre les deux.
class TapTempoSource implements BeatClock {
  final TapTempoEstimator _est;
  final Stopwatch _sw = Stopwatch();
  final StreamController<BeatTick> _ctrl =
      StreamController<BeatTick>.broadcast();

  /// Période de poll de l'horloge. ~16 ms = bien plus fin qu'un battement,
  /// donc aucun battement n'est manqué.
  final Duration tickPeriod;

  /// Horloge injectable (ms) — pour les tests. `null` = `Stopwatch` interne.
  final int Function()? _nowFn;

  BeatScheduler? _scheduler;
  Timer? _timer;

  TapTempoSource(
      {TapTempoEstimator? estimator,
      int Function()? nowMs,
      this.tickPeriod = const Duration(milliseconds: 16)})
      : _est = estimator ?? TapTempoEstimator(),
        _nowFn = nowMs;

  int get _now => _nowFn?.call() ?? _sw.elapsedMilliseconds;

  /// Enregistre un tap (au moment présent) et met à jour le tempo.
  void tap() {
    if (_nowFn == null && !_sw.isRunning) _sw.start();
    _est.tap(_now);
    _rebuildGrid();
  }

  /// Vrai dès qu'un tempo grossier est dispo.
  bool get hasTempo => _est.hasTempo;
  bool get isStable => _est.isStable;
  int get tapCount => _est.tapCount;

  void _rebuildGrid() {
    final bpm = _est.bpm;
    final anchor = _est.anchorMs;
    if (bpm == null || anchor == null) return;
    final grid = BeatGrid(bpm: bpm, anchorMs: anchor);
    if (_scheduler == null) {
      _scheduler = BeatScheduler(grid);
    } else {
      _scheduler!.retune(grid, _now);
    }
  }

  @override
  double? get bpm => _est.bpm;

  @override
  bool get isRunning => _timer != null;

  @override
  Stream<BeatTick> get ticks => _ctrl.stream;

  @override
  void start() {
    if (_scheduler == null || _timer != null) return;
    _timer = Timer.periodic(tickPeriod, (_) {
      final s = _scheduler;
      if (s == null) return;
      for (final t in s.poll(_now)) {
        _ctrl.add(t);
      }
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    _ctrl.close();
    _sw.stop();
  }
}
