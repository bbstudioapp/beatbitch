import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../models/session.dart';
import '../models/session_step.dart';
import '../services/beep_engine.dart';
import '../theme/app_theme.dart';

/// Visualisation animée du mouvement courant. Remplace le timer pendant
/// la séance pour donner un repère visuel du tempo et de la position
/// sans avoir à lire l'heure qui s'écoule.
///
/// L'axe vertical (tip en haut, full en bas) représente la **position le
/// long de la verge** — sémantique partagée par tous les modes :
/// - rhythm / hold / beg : position des lèvres (orbe pleine).
/// - lick                : position de la langue (pastille horizontale).
/// - hand                : position de la main (anneau, qui entoure la verge).
/// - biffle              : pas de position (gros pulse central, coups au visage).
/// - breath / freestyle  : pas de position (orbe respirante).
///
/// Cet axe partagé est volontaire : à terme, un step combo (hand+rhythm,
/// hand+lick) pourra superposer **plusieurs curseurs** sur la même
/// échelle pour montrer la coordination main/bouche d'un seul regard.
class MovementAnimation extends StatefulWidget {
  final SessionMode mode;
  final Position from;
  final Position? to;
  final int bpm;

  /// Hauteur réservée — calée sur la hauteur du `TimerDisplay` pour
  /// éviter tout décalage de mise en page lors du basculement debug.
  final double height;

  /// Source de vérité des battements pour les modes synced (rhythm/lick/
  /// hand/biffle). Si fournie, l'animation flip son orbe exactement à
  /// chaque beat émis par le BeepEngine — évite le drift visuel/audio
  /// causé par deux Timer parallèles non synchronisés.
  final BeepEngine? beepEngine;

  const MovementAnimation({
    super.key,
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
    this.height = 160,
    this.beepEngine,
  });

  @override
  State<MovementAnimation> createState() => _MovementAnimationState();
}

class _MovementAnimationState extends State<MovementAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Toggle d'alternance from/to pour rhythm/lick. Bascule à chaque
  /// fin de cycle du controller (= un battement). Garde aligné avec
  /// le BeepEngine qui alterne pareil sur ses bips.
  bool _flipped = false;

  /// Subscription au stream de beats du [BeepEngine] (si fourni). Quand
  /// présent, c'est *lui* qui pilote `_flipped` — on ignore le status
  /// listener interne du AnimationController pour les modes synced.
  StreamSubscription<BeatEvent>? _beatSub;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.mode, widget.bpm),
    );
    _startController();
    _maybeSubscribeBeats(widget.beepEngine);
  }

  @override
  void didUpdateWidget(covariant MovementAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modeChanged = oldWidget.mode != widget.mode;
    final tempoChanged = oldWidget.bpm != widget.bpm;
    final positionChanged =
        oldWidget.from != widget.from || oldWidget.to != widget.to;
    final engineChanged = oldWidget.beepEngine != widget.beepEngine;

    if (modeChanged) {
      _controller.removeStatusListener(_onStatus);
      _controller.stop();
      _controller.duration = _durationFor(widget.mode, widget.bpm);
      _flipped = false;
      _startController();
    } else if (tempoChanged) {
      _controller.duration = _durationFor(widget.mode, widget.bpm);
      if (_isBeatSynced(widget.mode) && !_isExternallyDriven) {
        _controller.forward(from: 0);
      }
    } else if (positionChanged && _isBeatSynced(widget.mode)) {
      // On repart au début du cycle pour que la prochaine alternance
      // s'aligne sur la nouvelle paire from/to. Le `TweenAnimationBuilder`
      // qui pilote la position de l'orbe lisse de toute façon le déplacement
      // depuis sa position visible courante vers la nouvelle cible.
      if (!_isExternallyDriven) {
        _flipped = false;
        _controller.forward(from: 0);
      }
    }

    if (engineChanged) {
      _beatSub?.cancel();
      _beatSub = null;
      _maybeSubscribeBeats(widget.beepEngine);
    }
  }

  @override
  void dispose() {
    _beatSub?.cancel();
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  bool get _isExternallyDriven => _beatSub != null;

  void _maybeSubscribeBeats(BeepEngine? engine) {
    if (engine == null) return;
    _beatSub = engine.beatStream.listen(_onBeatEvent);
  }

  void _onBeatEvent(BeatEvent event) {
    if (!mounted) return;
    // Quand on est piloté par le stream, on ignore le status listener
    // interne du AnimationController : on cale le flip exactement sur
    // l'instant du bip émis par le BeepEngine. Le AnimationController
    // continue de tourner pour fournir le `t` aux pulses (biffle, hold...).
    if (event.mode == SessionMode.rhythm ||
        event.mode == SessionMode.lick ||
        event.mode == SessionMode.hand) {
      // L'orbe glisse VERS la position qui vient de sonner : à l'instant du
      // bip `to`, on cale flipped pour viser `to` (= flipped ? from : to →
      // false ⇒ to). L'orbe atteint la cible à la fin du beat, juste avant
      // le bip suivant. Inversion par rapport à la version précédente qui
      // donnait l'impression d'un décalage d'un demi-beat.
      final flipped = event.position == widget.from;
      setState(() => _flipped = flipped);
      _controller.forward(from: 0);
    } else if (event.mode == SessionMode.biffle) {
      // Biffle : pas d'alternance, juste reset le pulse pour qu'il pulse
      // synchronisé avec chaque coup.
      _controller.forward(from: 0);
    }
  }

  void _startController() {
    if (_isBeatSynced(widget.mode)) {
      _controller.addStatusListener(_onStatus);
      _controller.forward(from: 0);
    } else {
      _controller.repeat(reverse: true);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Si un BeepEngine pilote l'animation, c'est lui qui fait avancer le
    // controller via `_onBeatEvent` — on ne flip pas ici (sinon on flip
    // deux fois et l'animation se dessynchronise).
    if (_isExternallyDriven) return;
    if (mounted) setState(() => _flipped = !_flipped);
    _controller.forward(from: 0);
  }

  static bool _isBeatSynced(SessionMode m) =>
      m == SessionMode.rhythm ||
      m == SessionMode.lick ||
      m == SessionMode.biffle ||
      m == SessionMode.hand;

  static Duration _durationFor(SessionMode mode, int bpm) {
    final clamped = bpm.clamp(20, 300);
    return switch (mode) {
      SessionMode.rhythm ||
      SessionMode.lick ||
      SessionMode.biffle ||
      SessionMode.hand =>
        Duration(milliseconds: (60000 / clamped).round()),
      SessionMode.hold || SessionMode.beg => const Duration(milliseconds: 1800),
      SessionMode.breath => const Duration(milliseconds: 3200),
      SessionMode.freestyle => const Duration(milliseconds: 2400),
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _buildForMode(_controller.value),
      ),
    );
  }

  Widget _buildForMode(double t) {
    final color = _modeColor(widget.mode);
    final cursorStyle = _cursorStyleFor(widget.mode);
    final beatDuration = _durationFor(widget.mode, widget.bpm);
    return switch (widget.mode) {
      SessionMode.rhythm ||
      SessionMode.lick ||
      SessionMode.hand =>
        _PositionLadder(
          from: widget.from,
          to: widget.to ?? widget.from,
          beatDuration: beatDuration,
          flipped: _flipped,
          color: color,
          cursorStyle: cursorStyle,
        ),
      SessionMode.biffle => _Pulse(t: t, color: color),
      SessionMode.hold || SessionMode.beg => _StaticPosition(
          position: widget.from,
          t: t,
          color: color,
          cursorStyle: cursorStyle,
        ),
      SessionMode.breath ||
      SessionMode.freestyle =>
        _Breath(t: t, color: color),
    };
  }

  static Color _modeColor(SessionMode m) => switch (m) {
        SessionMode.rhythm => AppTheme.accent,
        SessionMode.lick => const Color(0xFF4FC3F7),
        SessionMode.hold => const Color(0xFFFFD54F),
        SessionMode.biffle => const Color(0xFFEF5350),
        SessionMode.breath => const Color(0xFF81C784),
        SessionMode.beg => const Color(0xFFCE93D8),
        SessionMode.freestyle => const Color(0xFFB0BEC5),
        SessionMode.hand => const Color(0xFFFFAB91),
      };

  static _CursorStyle _cursorStyleFor(SessionMode m) => switch (m) {
        // lèvres / bouche → orbe pleine (le sample bip "remplit" la bouche)
        SessionMode.rhythm ||
        SessionMode.hold ||
        SessionMode.beg =>
          _CursorStyle.orb,
        // langue → pastille horizontale, lèche la position
        SessionMode.lick => _CursorStyle.tongue,
        // main → anneau ouvert (la main entoure la verge, ne la "remplit" pas)
        SessionMode.hand => _CursorStyle.ring,
        // modes sans position → fallback orbe (jamais consommé en pratique
        // car biffle/breath/freestyle utilisent des widgets dédiés)
        SessionMode.biffle ||
        SessionMode.breath ||
        SessionMode.freestyle =>
          _CursorStyle.orb,
      };
}

// ─── Sous-widgets ────────────────────────────────────────────────────────

/// Style visuel du curseur pour matérialiser l'organe au contact :
/// - [orb]    : disc plein (lèvres autour de la verge).
/// - [ring]   : anneau ouvert (main qui entoure la verge).
/// - [tongue] : pastille horizontale (langue qui lèche).
enum _CursorStyle { orb, ring, tongue }

/// Échelle verticale 5 positions (tip en haut, full en bas) avec un
/// curseur (orbe / anneau / langue) qui glisse entre `from` et `to` à
/// chaque battement. Quand `from == to`, le curseur pulse simplement
/// sur cette position.
///
/// Le curseur snap directement à la position cible à chaque beat (pas
/// de glissement interpolé) — pendant une transition de step (changement
/// de from/to), un slide donnerait l'impression que 2 bips sont avalés
/// le temps que le curseur rejoigne sa nouvelle position.
class _PositionLadder extends StatelessWidget {
  final Position from;
  final Position to;
  final Duration beatDuration;
  final bool flipped;
  final Color color;
  final _CursorStyle cursorStyle;

  const _PositionLadder({
    required this.from,
    required this.to,
    required this.beatDuration,
    required this.flipped,
    required this.color,
    required this.cursorStyle,
  });

  @override
  Widget build(BuildContext context) {
    // Cible courante du curseur : flipped=false → `to`, flipped=true → `from`.
    final target = flipped ? from : to;
    final targetAlignment = Alignment(_kCursorX, _toAlign(target.index));

    final activeIndices = {from.index, to.index};

    return Stack(
      alignment: Alignment.center,
      children: [
        // Silhouette discrète de la verge derrière les graduations.
        // Donne le contexte anatomique (la position ce n'est pas dans le vide,
        // c'est sur la verge) → utile pour tous les modes mais surtout pour
        // hand qui sinon évoque le même axe que la bouche sans repère.
        const _ShaftBackdrop(),
        // Lignes horizontales fines pour repérer les 5 positions.
        for (var i = 0; i < Position.values.length; i++)
          Align(
            alignment: Alignment(0, _toAlign(i)),
            child: FractionallySizedBox(
              widthFactor: 0.55,
              child: Container(
                height: 1,
                color: AppTheme.textMuted.withValues(alpha: 0.18),
              ),
            ),
          ),
        // Labels de position à droite. Mis en avant pour from / to.
        for (var i = 0; i < Position.values.length; i++)
          Align(
            alignment: Alignment(0.92, _toAlign(i)),
            child: Text(
              Position.values[i].localizedLabel(context),
              style: TextStyle(
                fontSize: 11,
                fontWeight: activeIndices.contains(i)
                    ? FontWeight.w700
                    : FontWeight.w400,
                letterSpacing: 1,
                color: activeIndices.contains(i)
                    ? color.withValues(alpha: 0.85)
                    : AppTheme.textMuted.withValues(alpha: 0.45),
              ),
            ),
          ),
        Align(
          alignment: targetAlignment,
          child: _Cursor(style: cursorStyle, color: color),
        ),
      ],
    );
  }

  /// Convertit un index de position (0..4) en y d'Alignment (-1..1).
  static double _toAlign(int index) => Position.values.length == 1
      ? 0
      : index / (Position.values.length - 1) * 2 - 1;
}

/// X (Alignment) où vivent le curseur et la silhouette de verge. Légèrement
/// décalé à gauche pour laisser respirer les labels à droite.
const double _kCursorX = -0.1;

/// Pulse central calé sur le BPM (utilisé par biffle). L'orbe pleine est
/// vive au début du battement (t≈0) puis décroît jusqu'au prochain.
class _Pulse extends StatelessWidget {
  final double t;
  final Color color;
  const _Pulse({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    final decay = Curves.easeOutQuad.transform(t);
    final scale = 1.0 - 0.45 * decay;
    final alpha = 1.0 - 0.6 * decay;
    return Center(
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: alpha),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.55 * alpha),
                blurRadius: 28,
                spreadRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Curseur statique sur une position donnée, avec un glow doux qui
/// respire lentement. Utilisé pour hold / beg : pas de tempo, juste
/// un ancrage. Style du curseur paramétrable (orb pour les lèvres,
/// éventuellement étendu plus tard).
class _StaticPosition extends StatelessWidget {
  final Position position;
  final double t;
  final Color color;
  final _CursorStyle cursorStyle;
  const _StaticPosition({
    required this.position,
    required this.t,
    required this.color,
    required this.cursorStyle,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = 0.85 + 0.15 * Curves.easeInOut.transform(t);
    return Stack(
      alignment: Alignment.center,
      children: [
        const _ShaftBackdrop(),
        // Repères des 5 positions, plus discrets que pour rhythm.
        for (var i = 0; i < Position.values.length; i++)
          Align(
            alignment: Alignment(0, _PositionLadder._toAlign(i)),
            child: FractionallySizedBox(
              widthFactor: 0.4,
              child: Container(
                height: 1,
                color: AppTheme.textMuted.withValues(alpha: 0.12),
              ),
            ),
          ),
        Align(
          alignment: Alignment(0.92, _PositionLadder._toAlign(position.index)),
          child: Text(
            position.localizedLabel(context),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ),
        Align(
          alignment:
              Alignment(_kCursorX, _PositionLadder._toAlign(position.index)),
          child: Transform.scale(
            scale: pulse,
            child: _Cursor(style: cursorStyle, color: color),
          ),
        ),
      ],
    );
  }
}

/// Orbe qui respire lentement pour le mode breath. Pas synchronisée au
/// BPM — vise juste à indiquer « phase de récupération ».
class _Breath extends StatelessWidget {
  final double t;
  final Color color;
  const _Breath({required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    // t va 0..1..0 grâce au repeat(reverse: true) appelant.
    final eased = Curves.easeInOut.transform(t);
    final scale = 0.6 + 0.4 * eased;
    final alpha = 0.55 + 0.35 * eased;
    return Center(
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: alpha * 0.85),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4 * alpha),
                blurRadius: 30,
                spreadRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Silhouette verticale de la verge en arrière-plan du ladder. Très
/// discrète (alpha bas, dégradé doux) pour ne pas distraire mais donner
/// le contexte anatomique de l'axe : tip en haut, base en bas.
class _ShaftBackdrop extends StatelessWidget {
  const _ShaftBackdrop();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(_kCursorX, 0),
      child: FractionallySizedBox(
        heightFactor: 0.96,
        child: SizedBox(
          width: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.textMuted.withValues(alpha: 0.06),
                  AppTheme.textMuted.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(
                color: AppTheme.textMuted.withValues(alpha: 0.10),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Curseur unique au look déterminé par [_CursorStyle]. Sert dans le ladder
/// (rhythm/lick/hand) et dans la position statique (hold/beg).
class _Cursor extends StatelessWidget {
  final _CursorStyle style;
  final Color color;

  const _Cursor({required this.style, required this.color});

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      _CursorStyle.orb => _OrbShape(color: color),
      _CursorStyle.ring => _RingShape(color: color),
      _CursorStyle.tongue => _TongueShape(color: color),
    };
  }
}

class _OrbShape extends StatelessWidget {
  static const double _size = 28;
  final Color color;
  const _OrbShape({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 18,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}

/// Anneau ouvert (la main entoure la verge sans la masquer). Bord coloré
/// épais, intérieur transparent → en combo on doit voir l'orbe/langue
/// derrière à la même position si elles coïncident.
class _RingShape extends StatelessWidget {
  static const double _size = 28;
  static const double _stroke = 4;
  final Color color;
  const _RingShape({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: color, width: _stroke),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Pastille horizontale, pour la langue qui lèche la position. Plus
/// large que haute → différencie clairement de l'orbe (cercle plein).
class _TongueShape extends StatelessWidget {
  static const double _w = 32;
  static const double _h = 16;
  final Color color;
  const _TongueShape({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_h / 2),
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}
