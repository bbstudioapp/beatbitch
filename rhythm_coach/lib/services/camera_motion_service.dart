import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../career/services/debug_settings_service.dart';
import 'camera_motion_detector.dart';
import 'coach_phrases_loader.dart';
import 'hold_verifier.dart';
import 'platform_capabilities.dart';
import 'tts_service.dart';

/// Singleton qui détient un [CameraMotionDetector] partagé et persiste la
/// calibration entre lancements (shared_preferences). Centralise toute la
/// logique d'activation conditionnelle de la vérif caméra :
///
/// - Le toggle utilisateur est lu via [DebugSettingsService.getCameraHoldCheck].
/// - La calibration min/max/axis est sauvée en prefs et rechargée au démarrage.
/// - [buildVerifierIfEnabled] retourne un [HoldVerifier] prêt à câbler dans
///   un `SessionController`, ou null si le toggle est OFF / la perm est
///   refusée / la calibration n'a jamais été faite.
class CameraMotionService {
  static final CameraMotionService _instance = CameraMotionService._();
  factory CameraMotionService() => _instance;
  CameraMotionService._();

  static const String _kAxis = 'cam_motion.axis';
  static const String _kMin = 'cam_motion.min';
  static const String _kMax = 'cam_motion.max';

  final DebugSettingsService _debug = DebugSettingsService();

  CameraMotionDetector? _detector;
  bool _initializing = false;
  bool _calibrationLoaded = false;

  CameraMotionDetector? get detector => _detector;
  bool get isReady => _detector != null && _detector!.isCalibrated;

  // ── Init ─────────────────────────────────────────────────────────────

  /// Garantit que le détecteur est initialisé (caméra allumée + accéléromètre
  /// abonné) et que la calibration persistée a été rechargée. Idempotent —
  /// les appels concurrents partagent la même initialisation en cours.
  ///
  /// Renvoie `false` si la permission caméra a été refusée ou si l'init
  /// caméra a échoué. Dans ce cas le détecteur reste null.
  Future<bool> ensureInitialized() async {
    if (!PlatformCapabilities.supportsCameraHoldCheck) return false;
    if (_detector != null) return true;
    if (_initializing) {
      // Attente passive le temps que l'init concurrente se termine.
      while (_initializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _detector != null;
    }

    _initializing = true;
    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) return false;

      final detector = CameraMotionDetector();
      await detector.initialize();
      _detector = detector;
      await _loadPersistedCalibration();
      return true;
    } catch (_) {
      return false;
    } finally {
      _initializing = false;
    }
  }

  /// Libère la caméra et réinitialise l'état interne. La calibration
  /// persistée est conservée en prefs.
  Future<void> release() async {
    final d = _detector;
    _detector = null;
    _calibrationLoaded = false;
    await d?.dispose();
  }

  // ── Calibration persistance ──────────────────────────────────────────

  Future<void> _loadPersistedCalibration() async {
    if (_calibrationLoaded) return;
    final detector = _detector;
    if (detector == null) return;
    final prefs = await SharedPreferences.getInstance();
    final axisRaw = prefs.getString(_kAxis);
    final min = prefs.getDouble(_kMin);
    final max = prefs.getDouble(_kMax);
    if (axisRaw == null || min == null || max == null) {
      _calibrationLoaded = true;
      return;
    }
    final axis = MotionAxis.values.firstWhere(
      (a) => a.name == axisRaw,
      orElse: () => MotionAxis.vertical,
    );
    try {
      detector.presetCalibration(axis: axis, signalMin: min, signalMax: max);
    } catch (_) {
      // Range corrompu/trop faible — ignore, recalibration manuelle requise.
    }
    _calibrationLoaded = true;
  }

  /// Persiste la calibration courante du détecteur. Appelé après une
  /// calibration utilisateur réussie depuis [CameraTestScreen].
  Future<void> persistCurrentCalibration() async {
    final detector = _detector;
    if (detector == null || !detector.isCalibrated) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAxis, detector.detectedAxis.name);
    await prefs.setDouble(_kMin, detector.calibrationMin!);
    await prefs.setDouble(_kMax, detector.calibrationMax!);
  }

  /// Efface la calibration persistée.
  Future<void> clearPersistedCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAxis);
    await prefs.remove(_kMin);
    await prefs.remove(_kMax);
  }

  // ── Wiring conditionnel pour les écrans de session ───────────────────

  /// Renvoie un [HoldVerifier] câblé sur le détecteur partagé, ou null si :
  /// - le toggle utilisateur est OFF, ou
  /// - le détecteur n'a pas pu être initialisé (perm refusée, etc.), ou
  /// - aucune calibration valide n'est disponible.
  ///
  /// Quand non-null, le détecteur est en mode `detecting` et reste actif
  /// pendant toute la durée de la session. À la fin, le caller (ou la
  /// session via le verifier) doit appeler [stopSessionDetection].
  Future<HoldVerifier?> buildVerifierIfEnabled(
    TtsService tts, {
    CoachPhrases? phrases,
  }) async {
    if (!PlatformCapabilities.supportsCameraHoldCheck) return null;
    final effectivePhrases = phrases ?? CoachPhrasesService.instance.current;
    final enabled = await _debug.getCameraHoldCheck();
    if (!enabled) return null;
    final ok = await ensureInitialized();
    if (!ok) return null;
    final detector = _detector!;
    if (!detector.isCalibrated) return null;
    detector.startDetection();
    return HoldVerifier(
      detector: detector,
      tts: tts,
      phrases: effectivePhrases,
    );
  }

  /// À appeler quand une session pilotée par un verifier se termine, pour
  /// remettre le détecteur en idle (la caméra reste allumée, prête pour
  /// la session suivante).
  void stopSessionDetection() {
    _detector?.stopDetection();
  }
}
