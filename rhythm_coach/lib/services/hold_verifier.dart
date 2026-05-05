import 'dart:async';
import 'dart:math';

import '../models/session_step.dart';
import 'camera_motion_detector.dart';
import 'coach_phrases_loader.dart';
import 'tts_service.dart';

/// Rapport de fin d'un hold vérifié par la caméra.
///
/// `accuracy` ∈ [0..1] = ratio temps_sur_cible / temps_total.
/// `maxDriftMs` = plus longue dérive consécutive observée hors-cible.
/// `nudges` = nombre de rappels TTS déclenchés.
class HoldReport {
  final Duration total;
  final Duration onTarget;
  final Duration maxDrift;
  final int nudges;
  final bool armedWithDetection;

  const HoldReport({
    required this.total,
    required this.onTarget,
    required this.maxDrift,
    required this.nudges,
    required this.armedWithDetection,
  });

  double get accuracy {
    final tot = total.inMilliseconds;
    if (tot <= 0) return 0;
    return (onTarget.inMilliseconds / tot).clamp(0.0, 1.0);
  }

  static const empty = HoldReport(
    total: Duration.zero,
    onTarget: Duration.zero,
    maxDrift: Duration.zero,
    nudges: 0,
    armedWithDetection: false,
  );
}

/// Vérifie en temps réel qu'un hold est tenu sur la position attendue, et
/// déclenche un rappel TTS court si l'utilisateur dérive trop longtemps.
///
/// Architecture :
/// - `arm(expected, duration)` démarre une fenêtre. Un Timer.periodic 200 ms
///   compare `_detector.currentDepth` à `expected`.
/// - On accumule `_onTargetMs`, on suit la dérive consécutive (`_driftStartedAt`).
/// - Au-delà de [driftThreshold] consécutifs hors-cible, on lance un rappel
///   TTS — direction-aware (descends/remonte). Cooldown [nudgeCooldown] entre
///   deux rappels pour ne pas spammer.
/// - `disarm()` arrête le timer et renvoie un [HoldReport].
///
/// Si `detector == null`, le verifier est un no-op silencieux : `arm/disarm`
/// fonctionnent mais aucune mesure n'est faite. Permet de garder un seul
/// chemin de code dans le SessionController qu'il y ait caméra ou non.
class HoldVerifier {
  static const Duration _tickInterval = Duration(milliseconds: 200);

  /// Dérive consécutive minimale avant déclenchement d'un rappel vocal.
  static const Duration driftThreshold = Duration(milliseconds: 1500);

  /// Délai minimum entre deux rappels vocaux pendant un même hold.
  static const Duration nudgeCooldown = Duration(seconds: 4);

  /// Délai d'amorçage : au début d'un hold on laisse l'utilisateur se mettre
  /// en place sans déclencher de rappel immédiat.
  static const Duration warmup = Duration(milliseconds: 800);

  final CameraMotionDetector? _detector;
  final TtsService _tts;
  final Random _random;
  CoachPhrases _phrases;

  /// Désactivable à chaud (toggle debug). À false → pareil que `detector == null`.
  bool enabled;

  HoldVerifier({
    required CameraMotionDetector? detector,
    required TtsService tts,
    required CoachPhrases phrases,
    Random? random,
    this.enabled = true,
  })  : _detector = detector,
        _tts = tts,
        _phrases = phrases,
        _random = random ?? Random();

  /// Permet de remplacer la banque de phrases (utile si la locale change
  /// au cours de la vie du verifier).
  void setPhrases(CoachPhrases phrases) {
    _phrases = phrases;
  }

  // ── État interne courant ─────────────────────────────────────────────

  Timer? _ticker;
  Position? _expected;
  DateTime? _armedAt;
  DateTime? _lastTickAt;
  DateTime? _driftStartedAt;
  Duration _onTargetMs = Duration.zero;
  Duration _maxDrift = Duration.zero;
  Duration _totalMs = Duration.zero;
  int _nudges = 0;
  DateTime _lastNudgeAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isArmed => _ticker != null;

  /// Démarre la vérification pour la position `expected`. Si déjà armé, le
  /// hold précédent est désarmé en silence (pas de report émis).
  void arm(Position expected) {
    if (!enabled || _detector == null) {
      // No-op : on garde quand même `_expected` non-null pour que `isArmed`
      // soit cohérent côté caller. Pas de timer = pas de coût CPU.
      _expected = expected;
      _armedAt = DateTime.now();
      return;
    }
    _resetCounters();
    _expected = expected;
    final now = DateTime.now();
    _armedAt = now;
    _lastTickAt = now;
    _ticker = Timer.periodic(_tickInterval, (_) => _onTick());
  }

  /// Arrête la vérification et renvoie le rapport.
  HoldReport disarm() {
    _ticker?.cancel();
    _ticker = null;

    final report = HoldReport(
      total: _totalMs,
      onTarget: _onTargetMs,
      maxDrift: _maxDrift,
      nudges: _nudges,
      armedWithDetection: _detector != null && enabled && _armedAt != null,
    );
    _expected = null;
    _armedAt = null;
    return report;
  }

  void _resetCounters() {
    _lastTickAt = null;
    _driftStartedAt = null;
    _onTargetMs = Duration.zero;
    _maxDrift = Duration.zero;
    _totalMs = Duration.zero;
    _nudges = 0;
    _lastNudgeAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _onTick() {
    final detector = _detector;
    final expected = _expected;
    if (detector == null || expected == null) return;

    final now = DateTime.now();
    final lastTick = _lastTickAt ?? now;
    final dt = now.difference(lastTick);
    _lastTickAt = now;
    _totalMs += dt;

    // Pas encore sorti du warmup → on accumule du temps mais on n'évalue
    // pas encore la cible (l'utilisateur est en train de se mettre en place).
    final since = now.difference(_armedAt!);
    if (since < warmup) return;

    final current = detector.currentDepth;
    final onTarget = current == expected;

    if (onTarget) {
      _onTargetMs += dt;
      // Reset du suivi de dérive : prochain rappel vocal repart d'un délai
      // plein.
      _driftStartedAt = null;
      return;
    }

    // Hors-cible. On démarre/poursuit le suivi de dérive consécutive.
    _driftStartedAt ??= now;
    final drift = now.difference(_driftStartedAt!);
    if (drift > _maxDrift) _maxDrift = drift;

    if (drift < driftThreshold) return;
    if (now.difference(_lastNudgeAt) < nudgeCooldown) return;
    if (_tts.isSpeaking) return; // ne pas couper une phrase scriptée en cours.

    _lastNudgeAt = now;
    _nudges++;
    _tts.speak(_pickNudgePhrase(expected: expected, current: current));
  }

  /// Choisit une phrase courte selon la direction de l'écart.
  ///
  /// `expected.index` plus grand = position plus profonde (full=4 > tip=0).
  /// - current null → on perd la tête : "où es-tu ?", "remets-toi en place".
  /// - current.index < expected.index → utilisateur trop en surface → descendre.
  /// - current.index > expected.index → utilisateur trop profond → remonter.
  String _pickNudgePhrase({
    required Position expected,
    required Position? current,
  }) {
    if (current == null) {
      return _pick(_phrases.lost);
    }
    if (current.index < expected.index) {
      return _pick(_phrases.goDeeper);
    }
    return _pick(_phrases.goUp);
  }

  String _pick(List<String> phrases) =>
      phrases[_random.nextInt(phrases.length)];
}
