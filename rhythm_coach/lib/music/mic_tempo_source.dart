import 'dart:async';

import 'beat_clock.dart';
import 'beat_grid.dart';
import 'onset_detector.dart';
import 'tempo_tracker.dart';

/// Source de tempo « micro » (PR2) — détecte le tempo de la musique ambiante
/// (cf. `specs/music_mode.md`). **Hors ligne** : tout se passe sur l'appareil.
///
/// Le cœur est [feedPcm] (pur, testable) : PCM → onsets → tempo → battements.
/// La capture micro réelle (`record`) n'est qu'une fine couche qui appelle
/// [feedPcm] (cf. `MicCapture`). L'horloge maître est l'horloge **échantillons**
/// (`OnsetDetector.elapsedMs`), donc tout est piloté par l'arrivée du PCM — pas
/// de `Timer`, et c'est déterministe en test.
///
/// Cycle : **intro/calibration** (écoute sans émettre tant que le tempo n'est
/// pas verrouillé avec assez de confiance) → **lecture** (émet les battements,
/// re-cale doucement la dérive). Gating : [gate] ignore les onsets pendant une
/// fenêtre (appelé par le contrôleur quand l'app joue un bip).
class MicTempoSource implements BeatClock {
  final OnsetDetector _detector;
  final TempoTracker _tracker;

  /// Confiance minimale pour verrouiller / re-caler le tempo.
  final double lockConfidence;

  final StreamController<BeatTick> _ctrl =
      StreamController<BeatTick>.broadcast();
  BeatScheduler? _scheduler;
  int _lastElapsed = 0;
  int _gateUntil = 0;
  double? _bpm;

  MicTempoSource({
    OnsetDetector? detector,
    TempoTracker? tracker,
    this.lockConfidence = 0.85,
  })  : _detector = detector ?? OnsetDetector(),
        _tracker = tracker ?? TempoTracker();

  /// Vrai tant que le tempo n'est pas verrouillé (phase d'intro).
  bool get isCalibrating => _scheduler == null;

  @override
  Stream<BeatTick> get ticks => _ctrl.stream;

  @override
  double? get bpm => _bpm;

  @override
  bool get isRunning => _scheduler != null;

  /// Ignore les onsets pendant [windowMs] à partir de maintenant (gating des
  /// bips de l'app).
  void gate(int windowMs) {
    final until = _lastElapsed + windowMs;
    if (until > _gateUntil) _gateUntil = until;
  }

  /// Cœur : pousse des samples PCM mono (−1..1).
  void feedPcm(List<double> samples) {
    final onsets = _detector.process(samples);
    _lastElapsed = _detector.elapsedMs;
    for (final o in onsets) {
      if (o >= _gateUntil) _tracker.addOnset(o);
    }

    final est = _tracker.estimate();
    if (est != null && est.confidence >= lockConfidence) {
      final grid = BeatGrid(bpm: est.bpm, anchorMs: est.anchorMs);
      if (_scheduler == null) {
        _scheduler = BeatScheduler(grid); // verrou initial : fin de l'intro
      } else {
        _scheduler!.retune(grid, _lastElapsed); // re-cale la dérive
      }
      _bpm = est.bpm;
    }

    final s = _scheduler;
    if (s != null) {
      for (final t in s.poll(_lastElapsed)) {
        _ctrl.add(t);
      }
    }
  }

  // L'émission est pilotée par le flux PCM ; start/stop sont des no-op côté
  // horloge (la capture micro est gérée par la couche `MicCapture`).
  @override
  void start() {}

  @override
  void stop() {}

  @override
  void dispose() => _ctrl.close();
}
