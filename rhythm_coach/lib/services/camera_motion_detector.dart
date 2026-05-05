import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/session_step.dart';

/// Axe principal détecté pour le mouvement.
///
/// `vertical` : la tête monte/descend dans le frame (cas typique vue 3/4 ou
/// profil avec mouvement de hochement).
///
/// `horizontal` : le visage va et vient horizontalement (cas typique profil
/// pur, le sujet avance/recule en gardant la tête droite).
enum MotionAxis { vertical, horizontal }

/// Cycle de vie du détecteur.
enum MotionDetectorState { idle, initializing, calibrating, detecting, error }

/// Snapshot du rythme courant.
@immutable
class MotionRhythm {
  /// Battements par minute estimés à partir des extrema détectés.
  /// 0 si pas encore assez de données.
  final double bpm;

  /// True si BPM ≥ [CameraMotionDetector.fastBpmThreshold].
  final bool fast;

  /// Période moyenne pic-à-pic (Duration.zero si non disponible).
  final Duration period;

  /// Confiance [0..1] : proportion d'extrema utilisables sur la fenêtre.
  final double confidence;

  const MotionRhythm({
    required this.bpm,
    required this.fast,
    required this.period,
    required this.confidence,
  });

  static const empty = MotionRhythm(
    bpm: 0,
    fast: false,
    period: Duration.zero,
    confidence: 0,
  );
}

/// Résultat d'une calibration.
@immutable
class CalibrationResult {
  final MotionAxis axis;
  final double signalMin;
  final double signalMax;
  final int samplesCount;
  final bool acceptable;

  const CalibrationResult({
    required this.axis,
    required this.signalMin,
    required this.signalMax,
    required this.samplesCount,
    required this.acceptable,
  });

  double get range => signalMax - signalMin;
}

/// Détecteur de mouvement de tête par caméra + accéléromètre.
///
/// Pipeline :
/// 1. `camera` capture un flux image (basse résolution, format YUV ou NV21).
/// 2. `google_mlkit_face_detection` extrait la position de la tête à chaque frame.
///    On préfère la `noseBase` quand elle est dispo (plus stable), sinon le
///    centroïde du bounding box.
/// 3. Un signal 1D est extrait selon l'axe dominant (Y ou X normalisé).
/// 4. EMA → détection d'extrema avec hystérésis amplitude → période → BPM.
/// 5. Mapping signal → Position via 5 buckets calibrés.
/// 6. Accéléromètre lu en parallèle pour détecter la stabilité du téléphone
///    (variance) et fusionner un fallback rythmique si le visage est perdu.
///
/// Hypothèses :
/// - Téléphone posé sur le côté, vue de profil ou 3/4 du sujet.
/// - Pas de marquage physique : on s'appuie uniquement sur la tête.
/// - Android only (cf. CLAUDE.md). Conversion `CameraImage → InputImage`
///   simplifiée pour ce cas.
class CameraMotionDetector {
  // ─────────────── Tuning constants ───────────────

  /// Seuil BPM au-delà duquel on classe le mouvement comme "rapide".
  /// Repère typique : un mouvement lent profond tourne ~50–70 BPM,
  /// un mouvement rapide superficiel ~120–180 BPM.
  static const double fastBpmThreshold = 100;

  /// Coefficient de lissage EMA appliqué au signal 1D.
  /// Plus bas = plus lisse mais plus laggy.
  static const double _emaAlpha = 0.35;

  /// Hystérésis (en fraction du range calibré) à franchir avant de valider
  /// un changement de direction. Évite de compter 10 micro-extrema pour 1 cycle.
  static const double _directionHysteresis = 0.12;

  /// Fenêtre glissante des dernières périodes pic-à-pic prises en compte
  /// pour le BPM moyen.
  static const int _bpmWindow = 5;

  /// Durée par défaut d'une calibration.
  static const Duration defaultCalibrationDuration = Duration(seconds: 10);

  /// Throttling : si une frame est encore en cours d'analyse, on droppe.
  /// Cible ~15–20 fps de détection effective.
  static const Duration _minFrameInterval = Duration(milliseconds: 50);

  /// Range minimum (en unités normalisées 0–1) pour considérer une calibration
  /// valide. En dessous, le signal est trop plat pour distinguer 5 niveaux.
  static const double _minAcceptableRange = 0.05;

  // ─────────────── Dependencies ───────────────

  CameraController? _camera;
  late final FaceDetector _faceDetector;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // ─────────────── State ───────────────

  MotionDetectorState _state = MotionDetectorState.idle;
  MotionAxis _axis = MotionAxis.vertical;

  // Flag global d'activation. Indépendant de _state pour permettre une mise
  // en veille rapide sans toucher à la caméra ni perdre la calibration.
  bool _enabled = true;

  // Calibration : on accumule X et Y normalisés en parallèle puis on choisit
  // l'axe dominant à la fin.
  bool _calibrating = false;
  Completer<CalibrationResult>? _calibrationCompleter;
  Timer? _calibrationTimer;
  final List<double> _calibX = [];
  final List<double> _calibY = [];

  // Signal courant.
  double? _signalMin;
  double? _signalMax;
  double? _smoothed; // Valeur EMA courante.
  bool _goingUp = true;
  double? _lastExtremumValue; // Dernier extremum confirmé.
  DateTime? _lastPeakAt; // Timestamp du dernier maximum (pour BPM pic-à-pic).
  final List<Duration> _recentPeriods = [];

  Position? _currentDepth;
  MotionRhythm _currentRhythm = MotionRhythm.empty;

  // Throttling.
  bool _frameBusy = false;
  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Accéléromètre : variance courte fenêtre pour détecter perturbations.
  final List<double> _accelMagWindow = [];
  double _accelVariance = 0;

  // ─────────────── Public streams & callbacks ───────────────

  final _depthCtrl = StreamController<Position>.broadcast();
  final _rhythmCtrl = StreamController<MotionRhythm>.broadcast();
  final _stateCtrl = StreamController<MotionDetectorState>.broadcast();

  /// Émet à chaque changement de bucket de profondeur.
  Stream<Position> get depthStream => _depthCtrl.stream;

  /// Émet une mise à jour du rythme à chaque nouveau pic détecté.
  Stream<MotionRhythm> get rhythmStream => _rhythmCtrl.stream;

  /// Émet à chaque changement d'état du cycle de vie.
  Stream<MotionDetectorState> get stateStream => _stateCtrl.stream;

  /// Callback alternatif au stream `depthStream`.
  void Function(Position depth)? onDepthChanged;

  /// Callback alternatif au stream `rhythmStream`.
  void Function(MotionRhythm rhythm)? onRhythmDetected;

  // ─────────────── Public getters ───────────────

  MotionDetectorState get state => _state;
  MotionAxis get detectedAxis => _axis;
  Position? get currentDepth => _currentDepth;
  MotionRhythm get currentRhythm => _currentRhythm;
  bool get isCalibrated => _signalMin != null && _signalMax != null;
  CameraController? get cameraController => _camera;

  /// Bornes courantes du signal calibré, ou null si pas encore calibré.
  /// Exposées pour permettre la persistance entre sessions.
  double? get calibrationMin => _signalMin;
  double? get calibrationMax => _signalMax;

  /// Flag global d'activation. À `false`, toutes les frames caméra et events
  /// accéléromètre sont droppés en amont du pipeline (la caméra reste
  /// allumée pour éviter le coût d'une réinit). La calibration et l'état
  /// sont préservés ; au passage à `true`, l'état signal est resetté pour
  /// repartir d'une base propre (évite un BPM faussé par une période
  /// inter-désactivation).
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      _resetSignalState();
    }
  }

  // ─────────────── Construction ───────────────

  CameraMotionDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true, // On exploite noseBase.
        enableClassification: false,
        enableTracking: true, // Stabilise l'ID du visage entre frames.
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );
  }

  // ─────────────── Lifecycle ───────────────

  /// Initialise la caméra (front si dispo, sinon back) et abonne l'accéléromètre.
  /// Doit être appelé avant `startCalibration` ou `startDetection`.
  ///
  /// `lensDirection` permet de forcer l'orientation. En vue de profil sur un
  /// téléphone posé latéralement, la front-cam est en général le bon choix.
  Future<void> initialize({
    CameraLensDirection lensDirection = CameraLensDirection.front,
  }) async {
    _setState(MotionDetectorState.initializing);
    try {
      final cameras = await availableCameras();
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == lensDirection,
        orElse: () => cameras.first,
      );

      _camera = CameraController(
        selected,
        // Basse résolution = plus de FPS pour ML Kit, suffisant pour suivre
        // un visage. On n'a pas besoin de 1080p pour tracker une coordonnée.
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await _camera!.initialize();
      await _camera!.startImageStream(_onCameraImage);

      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onAccel, onError: (_) {});

      _setState(MotionDetectorState.idle);
    } catch (e, st) {
      debugPrint('CameraMotionDetector init failed: $e\n$st');
      _setState(MotionDetectorState.error);
      rethrow;
    }
  }

  /// Lance une phase de calibration.
  ///
  /// L'utilisateur doit faire ~3-4 mouvements lents et profonds pendant
  /// `duration`. À la fin :
  /// - On choisit l'axe dominant (variance la plus forte).
  /// - On enregistre min/max sur cet axe → bornes des 5 buckets.
  ///
  /// Renvoie un [CalibrationResult] indiquant si la calibration est utilisable.
  /// Si `acceptable == false`, le caller devrait demander à l'utilisateur de
  /// recommencer avec des mouvements plus amples.
  Future<CalibrationResult> startCalibration({
    Duration duration = defaultCalibrationDuration,
  }) async {
    if (_calibrating) {
      throw StateError('Calibration déjà en cours');
    }
    if (_camera == null || !_camera!.value.isInitialized) {
      throw StateError('Détecteur non initialisé');
    }

    _calibX.clear();
    _calibY.clear();
    _calibrating = true;
    _calibrationCompleter = Completer<CalibrationResult>();

    _setState(MotionDetectorState.calibrating);

    _calibrationTimer = Timer(duration, _finalizeCalibration);
    return _calibrationCompleter!.future;
  }

  /// Annule une calibration en cours sans fixer les bornes.
  void cancelCalibration() {
    if (!_calibrating) return;
    _calibrationTimer?.cancel();
    _calibrating = false;
    _calibX.clear();
    _calibY.clear();
    _calibrationCompleter?.completeError(
      StateError('Calibration annulée'),
    );
    _calibrationCompleter = null;
    _setState(MotionDetectorState.idle);
  }

  /// Démarre la détection en temps réel. La calibration doit avoir réussi
  /// au préalable, sinon `StateError`.
  void startDetection() {
    if (!isCalibrated) {
      throw StateError('Calibration manquante — appelez startCalibration() d\'abord');
    }
    _resetSignalState();
    _setState(MotionDetectorState.detecting);
  }

  /// Met en pause la détection. La calibration reste mémorisée.
  void stopDetection() {
    if (_state != MotionDetectorState.detecting) return;
    _setState(MotionDetectorState.idle);
  }

  /// Permet d'injecter manuellement une calibration (tests, persistance entre
  /// sessions). `axis` détermine quel signal sera traqué ensuite.
  void presetCalibration({
    required MotionAxis axis,
    required double signalMin,
    required double signalMax,
  }) {
    if (signalMax - signalMin < _minAcceptableRange) {
      throw ArgumentError('Range trop faible : ${signalMax - signalMin}');
    }
    _axis = axis;
    _signalMin = signalMin;
    _signalMax = signalMax;
  }

  /// Libère caméra, détecteur ML Kit, accéléromètre et streams.
  Future<void> dispose() async {
    _calibrationTimer?.cancel();
    _calibrating = false;
    await _accelSub?.cancel();
    try {
      if (_camera?.value.isStreamingImages ?? false) {
        await _camera!.stopImageStream();
      }
    } catch (_) {}
    await _camera?.dispose();
    await _faceDetector.close();
    await _depthCtrl.close();
    await _rhythmCtrl.close();
    await _stateCtrl.close();
  }

  // ─────────────── Camera frame pipeline ───────────────

  void _onCameraImage(CameraImage image) {
    if (!_enabled) return;
    if (_frameBusy) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessedAt) < _minFrameInterval) return;
    if (_state != MotionDetectorState.calibrating &&
        _state != MotionDetectorState.detecting) {
      return;
    }
    _frameBusy = true;
    _lastProcessedAt = now;

    _processFrame(image, now).whenComplete(() => _frameBusy = false);
  }

  Future<void> _processFrame(CameraImage image, DateTime ts) async {
    final input = _toInputImage(image);
    if (input == null) return;

    List<Face> faces;
    try {
      faces = await _faceDetector.processImage(input);
    } catch (e) {
      debugPrint('FaceDetector error: $e');
      return;
    }
    if (faces.isEmpty) return;

    // En multi-visage, on prend le plus gros — le sujet le plus proche.
    final face = faces.reduce(
      (a, b) => a.boundingBox.longestSide >= b.boundingBox.longestSide ? a : b,
    );

    // Préfère le repère noseBase (plus stable que le centroïde du bbox vis-à-vis
    // d'une variation de cadrage). Fallback sur le centre du bbox.
    final nose = face.landmarks[FaceLandmarkType.noseBase];
    final px = (nose?.position.x ?? face.boundingBox.center.dx).toDouble();
    final py = (nose?.position.y ?? face.boundingBox.center.dy).toDouble();

    // Normalisation [0..1] pour neutraliser la résolution.
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final nx = (px / w).clamp(0.0, 1.0);
    final ny = (py / h).clamp(0.0, 1.0);

    if (_calibrating) {
      _calibX.add(nx);
      _calibY.add(ny);
      return;
    }

    if (_state == MotionDetectorState.detecting && isCalibrated) {
      final raw = _axis == MotionAxis.vertical ? ny : nx;
      _onSignalSample(raw, ts);
    }
  }

  // ─────────────── Calibration finalization ───────────────

  void _finalizeCalibration() {
    if (!_calibrating) return;
    _calibrating = false;

    final result = _computeCalibration();
    if (result.acceptable) {
      _axis = result.axis;
      _signalMin = result.signalMin;
      _signalMax = result.signalMax;
    }

    _setState(MotionDetectorState.idle);

    final completer = _calibrationCompleter;
    _calibrationCompleter = null;
    completer?.complete(result);
  }

  CalibrationResult _computeCalibration() {
    if (_calibX.length < 10 || _calibY.length < 10) {
      return CalibrationResult(
        axis: _axis,
        signalMin: 0,
        signalMax: 0,
        samplesCount: _calibX.length,
        acceptable: false,
      );
    }

    final rangeX = _percentileRange(_calibX, low: 0.05, high: 0.95);
    final rangeY = _percentileRange(_calibY, low: 0.05, high: 0.95);

    // L'axe avec le plus grand range (5e–95e percentile) gagne.
    // Percentiles plutôt que min/max bruts pour ignorer les outliers
    // (frames où le visage sort partiellement du cadre).
    final axis = rangeY.span >= rangeX.span
        ? MotionAxis.vertical
        : MotionAxis.horizontal;
    final picked = axis == MotionAxis.vertical ? rangeY : rangeX;

    final acceptable = picked.span >= _minAcceptableRange;

    return CalibrationResult(
      axis: axis,
      signalMin: picked.lo,
      signalMax: picked.hi,
      samplesCount: _calibX.length,
      acceptable: acceptable,
    );
  }

  ({double lo, double hi, double span}) _percentileRange(
    List<double> values, {
    required double low,
    required double high,
  }) {
    final sorted = List<double>.from(values)..sort();
    final lo = sorted[(sorted.length * low).floor().clamp(0, sorted.length - 1)];
    final hi = sorted[(sorted.length * high).floor().clamp(0, sorted.length - 1)];
    return (lo: lo, hi: hi, span: hi - lo);
  }

  // ─────────────── Signal processing ───────────────

  void _resetSignalState() {
    _smoothed = null;
    _goingUp = true;
    _lastExtremumValue = null;
    _lastPeakAt = null;
    _recentPeriods.clear();
    _currentDepth = null;
    _currentRhythm = MotionRhythm.empty;
  }

  void _onSignalSample(double raw, DateTime ts) {
    // 1. Lissage EMA.
    final prev = _smoothed;
    final smoothed = prev == null ? raw : prev + _emaAlpha * (raw - prev);
    _smoothed = smoothed;

    // 2. Mapping → bucket de profondeur.
    final newDepth = _depthFor(smoothed);
    if (newDepth != null && newDepth != _currentDepth) {
      _currentDepth = newDepth;
      _depthCtrl.add(newDepth);
      onDepthChanged?.call(newDepth);
    }

    // 3. Détection d'extrema avec hystérésis amplitude.
    if (prev == null) return;
    final range = (_signalMax! - _signalMin!).abs();
    final hyst = range * _directionHysteresis;

    // Direction implicite par le signe Δ. Mais on confirme un retournement
    // uniquement si le swing depuis le dernier extremum dépasse l'hystérésis.
    final lastExt = _lastExtremumValue ?? smoothed;
    final swing = (smoothed - lastExt).abs();

    if (_goingUp) {
      if (smoothed < prev && swing >= hyst) {
        // On vient de franchir un maximum local. `prev` ≈ pic.
        _registerPeak(prev, ts);
        _goingUp = false;
        _lastExtremumValue = prev;
      } else if (smoothed > (_lastExtremumValue ?? smoothed)) {
        // Toujours en montée, rien à faire.
      }
    } else {
      if (smoothed > prev && swing >= hyst) {
        // Minimum local. On ne pousse pas de période ici (pic-à-pic suffit),
        // mais on met à jour la direction.
        _goingUp = true;
        _lastExtremumValue = prev;
      }
    }
  }

  void _registerPeak(double value, DateTime now) {
    if (_lastPeakAt != null) {
      final period = now.difference(_lastPeakAt!);
      // Filtre des périodes aberrantes : <0.2s = >300 BPM, >2.5s = <24 BPM.
      // Hors plage humaine plausible → on ignore.
      if (period.inMilliseconds >= 200 && period.inMilliseconds <= 2500) {
        _recentPeriods.add(period);
        if (_recentPeriods.length > _bpmWindow) {
          _recentPeriods.removeAt(0);
        }
        _emitRhythm();
      }
    }
    _lastPeakAt = now;
  }

  void _emitRhythm() {
    if (_recentPeriods.isEmpty) return;
    final avgMs = _recentPeriods
            .map((p) => p.inMicroseconds)
            .reduce((a, b) => a + b) /
        _recentPeriods.length /
        1000.0;
    final bpm = 60000.0 / avgMs;
    final fast = bpm >= fastBpmThreshold;
    final confidence = _recentPeriods.length / _bpmWindow;

    final rhythm = MotionRhythm(
      bpm: bpm,
      fast: fast,
      period: Duration(milliseconds: avgMs.round()),
      confidence: confidence,
    );
    _currentRhythm = rhythm;
    _rhythmCtrl.add(rhythm);
    onRhythmDetected?.call(rhythm);
  }

  /// Maps un signal lissé sur la plage calibrée → 1 des 5 niveaux.
  ///
  /// Convention : pour `vertical`, le signal **augmente** quand la tête
  /// descend (Y caméra croissant). On veut `tip` (haut/peu profond) au signal
  /// minimal et `full` (bas/profond) au signal maximal — donc bucket index
  /// croissant avec le signal.
  ///
  /// Pour `horizontal`, l'utilisateur décide *de fait* lors de la calibration
  /// (le min correspond au visage le plus loin du dildo, donc `tip`). Si la
  /// convention est inversée, le caller peut le détecter en regardant si la
  /// première Position émise correspond à la position attendue, et appeler
  /// [invertAxisPolarity].
  Position? _depthFor(double smoothed) {
    final lo = _signalMin!;
    final hi = _signalMax!;
    final range = hi - lo;
    if (range <= 0) return null;
    final t = ((smoothed - lo) / range).clamp(0.0, 1.0);
    // 5 buckets uniformes. On pourrait pondérer (ex. throat/full plus larges)
    // mais ça contredirait l'intention "5 niveaux égaux" de la calibration.
    final idx = (t * 5).floor().clamp(0, 4);
    return Position.values[idx];
  }

  /// Inverse la polarité : utile si la calibration a été faite "à l'envers"
  /// (utilisateur en mouvement inverse). Échange min/max.
  void invertAxisPolarity() {
    if (!isCalibrated) return;
    final tmp = _signalMin!;
    _signalMin = _signalMax;
    _signalMax = tmp;
  }

  // ─────────────── Accelerometer ───────────────

  void _onAccel(AccelerometerEvent e) {
    if (!_enabled) return;
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _accelMagWindow.add(mag);
    if (_accelMagWindow.length > 30) _accelMagWindow.removeAt(0);
    if (_accelMagWindow.length >= 10) {
      final mean = _accelMagWindow.reduce((a, b) => a + b) / _accelMagWindow.length;
      double s = 0;
      for (final v in _accelMagWindow) {
        s += (v - mean) * (v - mean);
      }
      _accelVariance = s / _accelMagWindow.length;
    }
  }

  /// Variance courante de la magnitude accéléromètre. Une variance élevée
  /// (> ~0.5) pendant la détection signifie probablement que le téléphone
  /// bouge — la lecture caméra est moins fiable. Le caller peut décider
  /// d'ignorer les transitions de profondeur dans ce cas.
  double get accelerometerVariance => _accelVariance;

  /// Heuristique : true si le téléphone semble stable (variance faible).
  bool get phoneStable => _accelVariance < 0.5;

  // ─────────────── Image conversion ───────────────

  /// Convertit un `CameraImage` en `InputImage` pour ML Kit. Implémentation
  /// Android-only (NV21) — c'est la cible de l'app (cf. CLAUDE.md).
  InputImage? _toInputImage(CameraImage image) {
    if (_camera == null) return null;
    final desc = _camera!.description;

    // Concaténation des plans en un seul buffer NV21.
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final Uint8List bytes = allBytes.done().buffer.asUint8List();

    final rotation = InputImageRotationValue.fromRawValue(desc.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  // ─────────────── State plumbing ───────────────

  void _setState(MotionDetectorState s) {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
  }
}
