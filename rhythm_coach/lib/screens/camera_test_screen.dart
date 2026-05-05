import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/session.dart';
import '../models/session_step.dart';
import '../services/ambience_engine.dart';
import '../services/beep_engine.dart';
import '../l10n/app_localizations.dart';
import '../services/camera_motion_detector.dart';
import '../services/camera_motion_service.dart';
import '../services/coach_phrases_loader.dart';
import '../services/hold_verifier.dart';
import '../services/punishment_loader.dart';
import '../services/random_comments_loader.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'session_screen.dart';

/// Écran de test isolé pour le tracking caméra des holds.
///
/// Pipeline :
/// 1. Demande la permission caméra.
/// 2. Initialise [CameraMotionDetector].
/// 3. L'utilisateur calibre (10 s de mouvements amples).
/// 4. L'utilisateur lance la session de test (5 holds successifs).
/// 5. Pendant la session, [HoldVerifier] vérifie chaque hold et le coach
///    rappelle vocalement quand la position dérive trop longtemps.
///
/// Ne touche pas au flow scénario/carrière : tout est créé localement et
/// libéré au pop de l'écran.
class CameraTestScreen extends StatefulWidget {
  final TtsService tts;
  final BeepEngine beep;
  final AmbienceEngine ambience;

  const CameraTestScreen({
    super.key,
    required this.tts,
    required this.beep,
    required this.ambience,
  });

  @override
  State<CameraTestScreen> createState() => _CameraTestScreenState();
}

enum _Step { permission, ready, calibrating, calibrated, error }

class _CameraTestScreenState extends State<CameraTestScreen> {
  final CameraMotionService _service = CameraMotionService();
  CameraMotionDetector? _detector;
  _Step _step = _Step.permission;
  String? _errorMessage;

  // Live preview du tracking : utile pour vérifier visuellement que la
  // calibration et la détection se comportent comme attendu avant de
  // lancer la session.
  Position? _liveDepth;
  CalibrationResult? _calibration;

  // Bundles requis par SessionScreen — chargés à l'init.
  Future<({Session session, PunishmentBundle punishments, RandomCommentsBundle randoms})>?
      _testBundleFuture;

  @override
  void initState() {
    super.initState();
    _testBundleFuture = _loadTestBundle();
    _bootstrap();
  }

  @override
  void dispose() {
    // On ne dispose pas le détecteur : il appartient au singleton et reste
    // disponible pour les sessions scénario/carrière. Juste détacher le
    // callback live pour ne pas pousser de setState sur un widget unmounted.
    _detector?.onDepthChanged = null;
    super.dispose();
  }

  // ── Bootstrap ────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    final ok = await _service.ensureInitialized();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _step = _Step.error;
        _errorMessage =
            AppLocalizations.of(context).cameraPermissionDenied;
      });
      return;
    }
    final detector = _service.detector!;
    detector.onDepthChanged = (p) {
      if (!mounted) return;
      setState(() => _liveDepth = p);
    };
    setState(() {
      _detector = detector;
      // Si une calibration persistée a été rechargée par le service, on
      // saute directement à l'état "calibré" pour permettre de relancer
      // une session sans recalibrer.
      _step = detector.isCalibrated ? _Step.calibrated : _Step.ready;
    });
  }

  Future<({Session session, PunishmentBundle punishments, RandomCommentsBundle randoms})>
      _loadTestBundle() async {
    final raw = await rootBundle
        .loadString('assets/sessions/session_camera_test.json');
    final session = Session.fromJson(json.decode(raw) as Map<String, dynamic>);
    final punishments = await PunishmentLoader().load();
    final randoms = await RandomCommentsLoader().load();
    return (session: session, punishments: punishments, randoms: randoms);
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _calibrate() async {
    final detector = _detector;
    if (detector == null) return;
    setState(() {
      _step = _Step.calibrating;
      _calibration = null;
    });
    try {
      final result = await detector.startCalibration();
      if (result.acceptable) {
        await _service.persistCurrentCalibration();
      }
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      setState(() {
        _calibration = result;
        _step = result.acceptable ? _Step.calibrated : _Step.ready;
        if (!result.acceptable) {
          _errorMessage = t.cameraCalibrationFailedRange(
            result.range.toStringAsFixed(3),
          );
        } else {
          _errorMessage = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.ready;
        _errorMessage =
            AppLocalizations.of(context).cameraCalibrationFailed(e.toString());
      });
    }
  }

  Future<void> _launchSession() async {
    final detector = _detector;
    final bundleFuture = _testBundleFuture;
    if (detector == null || bundleFuture == null) return;
    final bundle = await bundleFuture;
    if (!mounted) return;

    final verifier = HoldVerifier(
      detector: detector,
      tts: widget.tts,
      phrases: CoachPhrasesService.instance.current,
    );
    detector.startDetection();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          session: bundle.session,
          tts: widget.tts,
          beep: widget.beep,
          ambience: widget.ambience,
          punishmentBundle: bundle.punishments,
          randomComments: bundle.randoms,
          introText: bundle.session.intro,
          holdVerifier: verifier,
          endButtonLabel: AppLocalizations.of(context).cameraReturnButton,
        ),
      ),
    );

    // Au retour de la session : on coupe la détection mais on garde la
    // caméra active pour permettre un second test sans recalibrer.
    detector.stopDetection();
    if (!mounted) return;
    setState(() => _liveDepth = null);
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.cameraTestAppBarTitle)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final t = AppLocalizations.of(context);
    switch (_step) {
      case _Step.permission:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(t.cameraInitializing),
            ],
          ),
        );
      case _Step.error:
        return Center(
          child: Text(
            _errorMessage ?? t.cameraUnknownError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        );
      case _Step.ready:
      case _Step.calibrating:
      case _Step.calibrated:
        return _buildMain();
    }
  }

  Widget _buildMain() {
    final detector = _detector;
    final preview = detector?.cameraController;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null && preview.value.isInitialized)
          AspectRatio(
            aspectRatio: preview.value.aspectRatio,
            child: CameraPreview(preview),
          )
        else
          Container(
            height: 200,
            color: Colors.black26,
            alignment: Alignment.center,
            child: Text(AppLocalizations.of(context).cameraPreviewUnavailable),
          ),
        const SizedBox(height: 16),
        _buildStatusChip(),
        const SizedBox(height: 24),
        if (_step == _Step.ready) _buildCalibrateInstructions(),
        if (_step == _Step.calibrating) _buildCalibratingIndicator(),
        if (_step == _Step.calibrated) _buildCalibratedSummary(),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _step == _Step.calibrating ? null : _calibrate,
                icon: const Icon(Icons.fitness_center),
                label: Text(_step == _Step.calibrated
                    ? AppLocalizations.of(context).cameraRecalibrate
                    : AppLocalizations.of(context).cameraCalibrate),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _step == _Step.calibrated ? _launchSession : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(AppLocalizations.of(context).cameraStartSession),
              ),
            ),
          ],
        ),
        if (_errorMessage != null && _step != _Step.error)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildStatusChip() {
    final t = AppLocalizations.of(context);
    final axis = _detector?.detectedAxis;
    final live = _liveDepth;
    final axisLabel = axis == MotionAxis.horizontal
        ? t.cameraAxisHorizontal
        : t.cameraAxisVertical;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Chip(label: Text(t.cameraAxisLabel(axisLabel))),
        Chip(label: Text(t.cameraLivePositionLabel(live?.name ?? '—'))),
      ],
    );
  }

  Widget _buildCalibrateInstructions() {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.cameraCalibrationTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              t.cameraCalibrationInstructions,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalibratingIndicator() {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                t.cameraCalibratingMessage,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalibratedSummary() {
    final calib = _calibration;
    if (calib == null) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.cameraCalibratedTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              t.cameraCalibrationSummary(
                calib.axis.name,
                calib.range.toStringAsFixed(3),
                calib.samplesCount,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              t.cameraCalibratedHint,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
