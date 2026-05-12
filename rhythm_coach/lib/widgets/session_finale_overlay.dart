import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Overlay de finale : un halo blanc crémeux qui « gicle » par à-coups
/// irréguliers sur le step final d'une séance (carrière + custom). Chaque
/// giclée laisse ensuite un **résidu** qui ne disparaît pas (les giclées
/// s'accumulent sur l'écran), plus une brume diffuse qui se tasse sans
/// s'effacer. Quelques pulses de vibration accompagnent les giclées.
///
/// `active` flippe à `true` pile quand le `finale_chime` retentit et que la
/// séance tourne encore (`SessionController.finaleChimeStarted && isRunning`).
/// Le widget démarre alors sa séquence ; il la mène à terme tout seul, même si
/// `active` repasse à `false` ensuite (séance terminée) — les résidus restent
/// affichés jusqu'à ce que la route soit dépilée. `IgnorePointer` : ne capture
/// aucun tap.
class SessionFinaleOverlay extends StatefulWidget {
  final bool active;
  const SessionFinaleOverlay({super.key, required this.active});

  @override
  State<SessionFinaleOverlay> createState() => _SessionFinaleOverlayState();
}

class _SessionFinaleOverlayState extends State<SessionFinaleOverlay>
    with SingleTickerProviderStateMixin {
  /// Durée pendant laquelle le controller tourne. Les giclées s'étalent
  /// (écarts de 1 à 3 s entre chacune) ; passé la dernière, c'est juste la
  /// brume qui se tasse et les résidus qui se figent. Une fois le controller
  /// terminé, le painter reste sur sa dernière frame (résidus visibles)
  /// jusqu'au dispose de la route.
  static const double _totalSeconds = 16.0;

  late final AnimationController _ctrl;
  final Random _rng = Random();

  bool _started = false;
  List<_Spurt> _spurts = const [];
  int _firedHaptics = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_totalSeconds * 1000).round()),
    )..addListener(_onTick);
    if (widget.active) _begin();
  }

  @override
  void didUpdateWidget(SessionFinaleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // On ne réagit qu'à la première activation : une fois lancée, la
    // séquence va jusqu'au bout indépendamment de `active`.
    if (!oldWidget.active && widget.active && !_started) _begin();
  }

  void _begin() {
    _started = true;
    // Quelques giclées (3 à 5) : la première avec le chime, les suivantes
    // espacées de 1 à 3 s chacune (tiré au hasard → rythme « pas forcément
    // régulier »).
    final n = 3 + _rng.nextInt(3);
    final spurts = <_Spurt>[];
    var t = 0.05;
    for (var i = 0; i < n; i++) {
      if (i > 0) t += 1.0 + _rng.nextDouble() * 2.0; // 1,0-3,0 s
      spurts.add(_Spurt(
        startSeconds: t,
        // Décalages autour du centre (en fraction de l'écran).
        dx: (_rng.nextDouble() - 0.5) * 0.22,
        dy: (_rng.nextDouble() - 0.5) * 0.22 - 0.02,
        radiusFraction: 0.28 + _rng.nextDouble() * 0.24,
        // La première giclée est la plus franche.
        intensity: i == 0 ? 1.0 : 0.55 + _rng.nextDouble() * 0.45,
      ));
    }
    _spurts = spurts;
    _ctrl.forward(from: 0);
  }

  void _onTick() {
    final t = _ctrl.value * _totalSeconds;
    while (_firedHaptics < _spurts.length &&
        t >= _spurts[_firedHaptics].startSeconds) {
      // heavyImpact : franc sur Android, no-op silencieux ailleurs.
      HapticFeedback.heavyImpact();
      _firedHaptics++;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _FinalePainter(
            elapsedSeconds: _ctrl.value * _totalSeconds,
            totalSeconds: _totalSeconds,
            spurts: _spurts,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Spurt {
  final double startSeconds;
  final double dx;
  final double dy;
  final double radiusFraction;
  final double intensity;
  const _Spurt({
    required this.startSeconds,
    required this.dx,
    required this.dy,
    required this.radiusFraction,
    required this.intensity,
  });
}

class _FinalePainter extends CustomPainter {
  final double elapsedSeconds;
  final double totalSeconds;
  final List<_Spurt> spurts;

  _FinalePainter({
    required this.elapsedSeconds,
    required this.totalSeconds,
    required this.spurts,
  });

  /// Blanc crémeux (légèrement chaud).
  static const Color _cream = Color(0xFFFFF7E6);

  /// Le pic d'une giclée retombe à cette fraction de son intensité (résidu
  /// qui reste à l'écran), au lieu de zéro.
  static const double _spurtResidual = 0.30;

  /// La brume diffuse retombe à cette fraction de son pic.
  static const double _hazeResidual = 0.40;

  @override
  void paint(Canvas canvas, Size size) {
    final t = elapsedSeconds;
    final shortest = min(size.width, size.height);
    // Centre du halo ≈ là où trône l'orbe d'animation (un poil au-dessus du
    // milieu pour les écrans hauts).
    final center = Offset(size.width * 0.5, size.height * 0.43);

    // ── Brume diffuse ──────────────────────────────────────────────────
    // Montée (0 → 1 sur 0,5 s), plateau, puis tassement vers un résidu (pas
    // zéro) atteint vers la fin de la séquence.
    final double hazeEnv;
    if (t < 0.5) {
      hazeEnv = (t / 0.5).clamp(0.0, 1.0);
    } else if (t < 3.0) {
      hazeEnv = 1.0;
    } else {
      final d = ((t - 3.0) / (totalSeconds - 3.0)).clamp(0.0, 1.0);
      hazeEnv = 1.0 - (1.0 - _hazeResidual) * d;
    }
    final hazeAlpha = (0.24 * hazeEnv).clamp(0.0, 1.0);
    if (hazeAlpha > 0.003) {
      final hazeRadius = shortest * 0.88;
      final rect = Rect.fromCircle(center: center, radius: hazeRadius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            _cream.withValues(alpha: hazeAlpha),
            _cream.withValues(alpha: hazeAlpha * 0.45),
            _cream.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect);
      canvas.drawRect(Offset.zero & size, paint);
    }

    // ── Giclées + résidus ──────────────────────────────────────────────
    for (final s in spurts) {
      final dt = t - s.startSeconds;
      if (dt < 0) continue;

      // Enveloppe d'intensité : attaque franche (0 → 1 sur ~90 ms),
      // décroissance ease-out vers le palier résidu sur ~0,7 s, puis on
      // reste sur le résidu (la giclée laisse une trace).
      final double env;
      if (dt < 0.09) {
        env = dt / 0.09;
      } else if (dt < 0.79) {
        final d = (dt - 0.09) / 0.70;
        env = _spurtResidual + (1.0 - _spurtResidual) * (1.0 - d) * (1.0 - d);
      } else {
        env = _spurtResidual;
      }

      // Le rayon s'épanouit (la giclée s'étale) sur ~0,5 s puis reste à sa
      // taille pleine — un résidu étalé, pas un point.
      final spread = (dt / 0.5).clamp(0.0, 1.0);
      final radius = s.radiusFraction * shortest * (0.55 + 0.45 * spread);

      final blobCenter = center + Offset(s.dx * size.width, s.dy * size.height);
      final alpha = ((0.40 + 0.5 * s.intensity) * env).clamp(0.0, 0.88);
      if (alpha <= 0.003) continue;
      final rect = Rect.fromCircle(center: blobCenter, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            _cream.withValues(alpha: alpha * 0.72),
            _cream.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(rect);
      canvas.drawCircle(blobCenter, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_FinalePainter old) =>
      old.elapsedSeconds != elapsedSeconds || !identical(old.spurts, spurts);
}
