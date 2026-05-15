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

  /// Nombre de positions affichées sur l'axe vertical du ladder. Permet
  /// de masquer la 6ᵉ ligne (`Position.balls`) tant que la zone n'est
  /// pas révélée par la milestone d'unlock + le toggle `AnatomyProfile`.
  /// Par défaut : 5 lignes (`tip..full`, sans balls). Le SessionScreen
  /// passe la valeur calculée à partir du contexte joueuse.
  final int positionRowCount;

  const MovementAnimation({
    super.key,
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
    this.height = 160,
    this.beepEngine,
    this.positionRowCount = 5,
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

  /// Timestamp du dernier beat reçu (rhythm/lick/hand). Sert à extrapoler
  /// la fenêtre future de la trajectoire : à partir de cet instant, les
  /// beats suivants tombent à `_lastBeatAt + n × beatDuration` en alternant
  /// from↔to. Null tant qu'aucun beat n'a été reçu.
  DateTime? _lastBeatAt;

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
      _startController();
    } else if (tempoChanged) {
      _controller.duration = _durationFor(widget.mode, widget.bpm);
      if (_isBeatSynced(widget.mode) && !_isExternallyDriven) {
        _controller.forward(from: 0);
      }
    } else if (positionChanged && _isBeatSynced(widget.mode)) {
      // On repart au début du cycle pour que la prochaine alternance
      // s'aligne sur la nouvelle paire from/to.
      if (!_isExternallyDriven) {
        _controller.forward(from: 0);
      }
    }

    if (engineChanged) {
      _beatSub?.cancel();
      _beatSub = null;
      _maybeSubscribeBeats(widget.beepEngine);
    }

    // Au démarrage d'un nouveau step, le tout premier bip émis par le
    // BeepEngine tombe TOUJOURS sur `to` (`_alternateToggle = true` à chaque
    // `applyStep`). On remet donc `_flipped = false` pour que le curseur vise
    // `to` dès la bascule de step. Sans ce reset, en mode piloté par le stream
    // `_flipped` conserve la parité du dernier bip du step précédent (donc
    // ~aléatoire) : une fois sur deux le curseur part vers `from` alors que
    // l'audio annonce `to` — c'est le décalage « quasiment inversé » observé.
    // Il se recalait au bout d'un beat, mais à BPM bas ça reste très visible.
    //
    // On reset aussi l'ancrage de la courbe future (`_lastBeatAt`) : sinon
    // l'extrapolation continue avec un `_lastBeatAt` calé sur l'ancien step
    // mais les nouveaux from/to/BPM. `AnimatedOpacity` fait le fade-out, le
    // prochain `BeatEvent` recale et fade-in.
    if (modeChanged || tempoChanged || positionChanged) {
      _flipped = false;
      _lastBeatAt = null;
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
      // À l'instant du bip de `event.position`, le curseur EST visuellement à
      // cette position (l'AnimatedAlign du beat précédent vient juste de l'y
      // déposer). On programme immédiatement l'animation vers la PROCHAINE
      // position : durée = beatDuration, courbe d'anticipation easeInOutCubic
      // → le curseur arrivera pile sur la cible à l'instant du prochain bip.
      // L'audio reste maître : le bip déclenche le mouvement visuel, jamais
      // l'inverse.
      final nextIsFrom = event.position == widget.to;
      setState(() {
        _flipped = nextIsFrom;
        _lastBeatAt = DateTime.now();
      });
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
    final targetColor = _modeColor(widget.mode);
    return SizedBox(
      height: widget.height,
      // Couleur interpolée entre 2 modes pour adoucir les changements de step
      // (rhythm ambre → lick cyan → hand saumon, etc.). Durée volontairement
      // plus longue qu'un beat pour rester lisible même à BPM élevé.
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: targetColor),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        builder: (context, animatedColor, _) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) =>
              _buildForMode(_controller.value, animatedColor ?? targetColor),
        ),
      ),
    );
  }

  Widget _buildForMode(double t, Color color) {
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
          lastBeatAt: _lastBeatAt,
          rowCount: widget.positionRowCount,
        ),
      SessionMode.biffle => _Pulse(t: t, color: color),
      SessionMode.hold || SessionMode.beg => _StaticPosition(
          position: widget.from,
          t: t,
          color: color,
          cursorStyle: cursorStyle,
          rowCount: widget.positionRowCount,
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

/// Échelle verticale de positions (tip en haut, dernière en bas) avec
/// un curseur (orbe / anneau / langue) qui glisse entre `from` et `to`
/// à chaque battement. Le nombre de lignes est paramétré par [rowCount]
/// — par défaut 5 (`tip..full`), 6 quand `Position.balls` est révélée
/// (anatomie + milestone). Quand `from == to`, le curseur pulse
/// simplement sur cette position.
///
/// Le curseur **glisse** vers la prochaine cible avec une courbe d'easing
/// (`Curves.easeInOutCubic`) sur la durée d'un beat. Anticipation : départ
/// doux, accélération, arrivée freinée → l'utilisatrice voit où le curseur
/// va avant qu'il arrive, et à l'instant du prochain bip il est pile dessus.
///
/// L'audio reste maître : la cible de l'AnimatedAlign change à l'instant
/// même où le bip courant sonne (cf. `_onBeatEvent`), ce qui garantit que
/// le curseur visible *est* à `event.position` à ce moment précis (fin de
/// l'animation précédente) et que la suivante glissera pendant exactement
/// un beat. Pas de drift visuel/audio.
///
/// En cas de transition de step (from/to changent), `AnimatedAlign` glisse
/// naturellement de l'ancienne position visible vers la nouvelle cible
/// pendant un beat — pas de saut sec.
class _PositionLadder extends StatelessWidget {
  final Position from;
  final Position to;
  final Duration beatDuration;
  final bool flipped;
  final Color color;
  final _CursorStyle cursorStyle;
  final DateTime? lastBeatAt;

  /// Nombre de positions affichées (5 = sans balls, 6 = avec balls).
  /// Borne `_toAlign` pour que les positions visibles restent espacées
  /// uniformément dans la hauteur disponible quel que soit le rowCount.
  final int rowCount;

  const _PositionLadder({
    required this.from,
    required this.to,
    required this.beatDuration,
    required this.flipped,
    required this.color,
    required this.cursorStyle,
    required this.lastBeatAt,
    required this.rowCount,
  });

  /// Fenêtre de prévision de la trajectoire future. Volontairement plus longue
  /// que les 2 s perçues : les ~1 s supplémentaires servent de réserve dans
  /// laquelle les nouveaux beats *émergent en fondu* (cf. `_kFadeFraction`)
  /// au lieu d'apparaître brutalement à l'extrémité droite. À BPM bas (60-90)
  /// la marge est cruciale — un beat entier rentrerait sec sans elle.
  static const Duration _trajectoryWindow = Duration(milliseconds: 3000);

  /// Fraction de la zone visible à droite consacrée au fade-out (apparition
  /// douce des beats les plus lointains). 0.50 = la moitié droite de la zone
  /// utile s'atténue progressivement → le tracé "émerge" doucement de loin
  /// au lieu d'apparaître par bouts dès qu'un beat entre dans la fenêtre.
  static const double _kFadeFraction = 0.50;

  /// Fraction de la largeur réservée à droite (zone des labels de positions
  /// + marge). La courbe ne doit jamais pénétrer cette zone : sinon elle
  /// passe sous les libellés Bout/Gland/Milieu/Gorge/Tout et ressort à droite.
  /// 0.20 = la colonne des labels + sa droite jusqu'au bord d'écran sont
  /// complètement masquées. Cette même constante pilote la fin du fade dans
  /// le shader ET la zone utile du painter (cohérence garantie).
  static const double _kRightPaddingFraction = 0.20;

  @override
  Widget build(BuildContext context) {
    // Cible courante du curseur : flipped=false → `to`, flipped=true → `from`.
    final target = flipped ? from : to;
    final targetAlignment =
        Alignment(_kCursorX, _toAlign(target.index, rowCount));

    final activeIndices = {from.index, to.index};
    final beats = _computeFutureBeats();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Silhouette discrète de la verge derrière les graduations.
        // Donne le contexte anatomique (la position ce n'est pas dans le vide,
        // c'est sur la verge) → utile pour tous les modes mais surtout pour
        // hand qui sinon évoque le même axe que la bouche sans repère.
        const _ShaftBackdrop(),
        // Lignes horizontales fines pour repérer les positions visibles.
        for (var i = 0; i < rowCount; i++)
          Align(
            alignment: Alignment(0, _toAlign(i, rowCount)),
            child: FractionallySizedBox(
              widthFactor: 0.55,
              child: Container(
                height: 1,
                color: AppTheme.textMuted.withValues(alpha: 0.18),
              ),
            ),
          ),
        // Trajectoire future : courbe qui montre les `_trajectoryWindow` à
        // venir. Dessinée DERRIÈRE le curseur dans le Stack pour que l'orbe
        // masque proprement le t=0 de la courbe (sinon double-affichage).
        //
        // Deux mécaniques de douceur :
        // 1. ShaderMask horizontal → la moitié droite de la zone utile fade
        //    progressivement vers transparent, et la zone des labels (à
        //    partir de `1 - _kRightPaddingFraction`) est totalement masquée.
        //    La courbe ne peut donc jamais traverser les libellés Bout/
        //    Gland/Milieu/Gorge/Tout ni ressortir à leur droite.
        // 2. AnimatedOpacity → fade-in/out de la courbe entière quand elle
        //    apparaît ou disparaît (transition entre modes synced/non-synced,
        //    reset après mode change). Évite le blink.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: beats.length >= 2 ? 1.0 : 0.0,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  const cursorX = (_kCursorX + 1) / 2;
                  const rightEdge = 1.0 - _kRightPaddingFraction;
                  const usable = rightEdge - cursorX;
                  const fadeStart = rightEdge - usable * _kFadeFraction;
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                      Colors.transparent,
                    ],
                    stops: [0.0, fadeStart, rightEdge, 1.0],
                  ).createShader(rect);
                },
                child: CustomPaint(
                  painter: _TrajectoryPainter(
                    beats: beats.length >= 2 ? beats : const [],
                    color: color,
                    cursorXFraction: (_kCursorX + 1) / 2,
                    rightPaddingFraction: _kRightPaddingFraction,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Labels de position à droite. Mis en avant pour from / to.
        for (var i = 0; i < rowCount; i++)
          Align(
            alignment: Alignment(0.92, _toAlign(i, rowCount)),
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
        AnimatedAlign(
          alignment: targetAlignment,
          // En régime établi : glisse vers la prochaine cible sur exactement
          // un beat (anticipation easeInOutCubic, arrivée pile sur le bip).
          // Juste après une bascule de step (lastBeatAt == null, on attend le
          // 1er bip pendant le gap de transition silencieux du BeepEngine) :
          // on rejoint `to` plus vite (≈ le gap mini de 300 ms) pour être en
          // place quand ce 1er bip — toujours sur `to` — tombe. Le curseur
          // bouge quand même (pas de saut sec), il se cale juste plus tôt.
          duration: lastBeatAt == null
              ? const Duration(milliseconds: 260)
              : beatDuration,
          curve: Curves.easeInOutCubic,
          child: _Cursor(style: cursorStyle, color: color),
        ),
      ],
    );
  }

  /// Convertit un index de position en y d'Alignment (-1..1) sur un
  /// ladder de [rowCount] lignes. Avec [rowCount] = 5, l'index 4 (full)
  /// tombe en bas (y=1) ; avec [rowCount] = 6, l'index 5 (balls) tombe
  /// en bas et full remonte à 0.6.
  static double _toAlign(int index, int rowCount) =>
      rowCount <= 1 ? 0 : index / (rowCount - 1) * 2 - 1;

  /// Calcule les points de la trajectoire future :
  /// - point 0 : position visible courante du curseur (interpolée easeInOutCubic).
  /// - points suivants : prochains beats du step courant, en alternant from↔to.
  /// La fenêtre temporelle est `_trajectoryWindow`.
  ///
  /// Pas de prédiction au-delà du step courant (on n'a pas la timeline future
  /// dans ce widget — il faudrait remonter au SessionController). La courbe
  /// s'arrête naturellement à la fenêtre, et se recale au prochain beat émis
  /// dans le nouveau step le cas échéant.
  List<_BeatPoint> _computeFutureBeats() {
    final last = lastBeatAt;
    if (last == null) return const [];
    final beatMs = beatDuration.inMilliseconds.toDouble();
    if (beatMs <= 0) return const [];

    final now = DateTime.now();
    final windowMs = _trajectoryWindow.inMilliseconds.toDouble();
    final elapsed = now.difference(last).inMilliseconds.toDouble();

    // Avant le refactor : à l'instant `lastBeatAt`, le bip de
    // `flipped ? to : from` vient de sonner — donc la position visuelle au
    // moment du beat est cette position. Elle glisse ensuite vers la
    // prochaine cible (`flipped ? from : to`) sur beatDuration ms.
    final lastPosIdx = (flipped ? to : from).index.toDouble();
    final nextPosIdx = (flipped ? from : to).index.toDouble();

    final progress = (elapsed / beatMs).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(progress);
    final yNow = lastPosIdx + (nextPosIdx - lastPosIdx) * eased;

    final beats = <_BeatPoint>[
      _BeatPoint(t: 0, idx: yNow, isAnchor: true),
    ];

    // Prochains beats : à partir du premier qui tombe ≥ now, alterner from↔to.
    var nextTime = last.add(beatDuration);
    var nextPos = (flipped ? from : to);
    while (nextTime.isBefore(now)) {
      nextTime = nextTime.add(beatDuration);
      nextPos = (nextPos == from) ? to : from;
    }
    // On génère aussi UN beat hors-fenêtre (`_extraBeatsBeyondWindow`) : sa
    // pastille tombera à x > endX (masquée par le ShaderMask), mais le segment
    // cubique qui le relie à l'avant-dernier beat traverse la zone de fade et
    // arrive jusqu'au bord droit. Sans ce beat extra, la courbe s'arrêtait sec
    // au dernier point dans la fenêtre, laissant une portion vide à droite.
    var extraAdded = 0;
    while (true) {
      final dtMs = nextTime.difference(now).inMilliseconds.toDouble();
      if (dtMs > windowMs) {
        if (extraAdded >= _extraBeatsBeyondWindow) break;
        extraAdded++;
      }
      beats.add(_BeatPoint(
        t: dtMs / windowMs,
        idx: nextPos.index.toDouble(),
        isAnchor: false,
      ));
      nextTime = nextTime.add(beatDuration);
      nextPos = (nextPos == from) ? to : from;
    }
    return beats;
  }

  /// Nombre de beats à extrapoler au-delà de `_trajectoryWindow`. Un seul
  /// suffit : le segment cubique qui le relie au dernier beat dans la
  /// fenêtre couvre toute la zone de fade jusqu'au bord droit.
  static const int _extraBeatsBeyondWindow = 1;
}

/// Point sur la courbe future. `t` ∈ [0,1] = fraction de la fenêtre temporelle
/// (0 = présent, 1 = +window). `idx` ∈ [0,4] = position (tip→full).
/// `isAnchor=true` pour le point t=0 (curseur courant) — pas de pastille
/// dessinée dessus, c'est l'orbe qui occupe ce rôle.
class _BeatPoint {
  final double t;
  final double idx;
  final bool isAnchor;
  const _BeatPoint(
      {required this.t, required this.idx, required this.isAnchor});
}

/// Trace la trajectoire future dans la zone à droite du curseur.
///
/// La zone horizontale utile va de `cursorXFraction × width` (= position
/// du curseur) à `(1 - rightPaddingFraction) × width` (= avant les labels
/// de position à droite). La zone verticale = toute la hauteur du Stack,
/// avec `idx ∈ [0,4]` mappé linéairement.
///
/// La courbe est tracée comme une succession de cubics horizontales entre
/// chaque paire de beats consécutifs (control points à mi-chemin
/// horizontalement, alignés verticalement sur l'extrémité correspondante)
/// → forme d'onde lisse type sinusoïde, lisible d'un coup d'œil.
class _TrajectoryPainter extends CustomPainter {
  final List<_BeatPoint> beats;
  final Color color;
  final double cursorXFraction;
  final double rightPaddingFraction;

  _TrajectoryPainter({
    required this.beats,
    required this.color,
    required this.cursorXFraction,
    required this.rightPaddingFraction,
  });

  /// Marge verticale (en pixels) entre le tracé et les bords du canvas.
  /// Sans elle, à idx=0 (tip) ou idx=4 (full), le contour de la stroke
  /// (2.5 px) et la pastille (radius 3.5 px) dépassent le canvas, et il
  /// reste une fine ligne d'~1 px visible collée au bord supérieur ou
  /// inférieur (clip Flutter par défaut). 5 px = stroke + radius pastille.
  static const double _verticalInset = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (beats.length < 2) return;
    final h = size.height;
    final usableH = h - 2 * _verticalInset;
    if (usableH <= 0) return;
    final startX = cursorXFraction * size.width;
    final endX = (1 - rightPaddingFraction) * size.width;
    final span = endX - startX;
    if (span <= 0) return;

    Offset toOffset(_BeatPoint p) =>
        Offset(startX + p.t * span, _verticalInset + p.idx / 4 * usableH);

    // Path lissé (cubic bezier entre points consécutifs).
    final path = Path();
    final p0 = toOffset(beats.first);
    path.moveTo(p0.dx, p0.dy);
    for (var i = 1; i < beats.length; i++) {
      final prev = toOffset(beats[i - 1]);
      final cur = toOffset(beats[i]);
      final dx = cur.dx - prev.dx;
      // Control points à mi-chemin horizontal, alignés verticalement sur
      // l'extrémité correspondante → S-curve symétrique entre 2 beats,
      // évoque visuellement un easeInOut entre les 2 positions.
      final cp1 = Offset(prev.dx + dx * 0.5, prev.dy);
      final cp2 = Offset(cur.dx - dx * 0.5, cur.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, cur.dx, cur.dy);
    }

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);

    // Pastille sur chaque beat futur. Plus le beat est lointain, plus la
    // pastille est pâle → repère visuel d'horizon temporel. Skip les beats
    // hors fenêtre (`t > 1`) : ils existent uniquement pour que le segment
    // cubique qui les relie au dernier beat visible atteigne le bord droit.
    for (var i = 0; i < beats.length; i++) {
      final b = beats[i];
      if (b.isAnchor || b.t > 1.0) continue;
      final fade = (1.0 - b.t).clamp(0.0, 1.0);
      final dotPaint = Paint()
        ..color = color.withValues(alpha: 0.35 + 0.5 * fade);
      canvas.drawCircle(toOffset(b), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter old) {
    if (old.color != color ||
        old.beats.length != beats.length ||
        old.cursorXFraction != cursorXFraction ||
        old.rightPaddingFraction != rightPaddingFraction) {
      return true;
    }
    for (var i = 0; i < beats.length; i++) {
      if (beats[i].t != old.beats[i].t || beats[i].idx != old.beats[i].idx) {
        return true;
      }
    }
    return false;
  }
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

  /// Nombre de positions visibles sur le ladder (cf. `_PositionLadder`).
  final int rowCount;

  const _StaticPosition({
    required this.position,
    required this.t,
    required this.color,
    required this.cursorStyle,
    required this.rowCount,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = 0.85 + 0.15 * Curves.easeInOut.transform(t);
    return Stack(
      alignment: Alignment.center,
      children: [
        const _ShaftBackdrop(),
        // Repères des positions visibles, plus discrets que pour rhythm.
        for (var i = 0; i < rowCount; i++)
          Align(
            alignment: Alignment(0, _PositionLadder._toAlign(i, rowCount)),
            child: FractionallySizedBox(
              widthFactor: 0.4,
              child: Container(
                height: 1,
                color: AppTheme.textMuted.withValues(alpha: 0.12),
              ),
            ),
          ),
        Align(
          alignment: Alignment(
              0.92, _PositionLadder._toAlign(position.index, rowCount)),
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
          alignment: Alignment(
              _kCursorX, _PositionLadder._toAlign(position.index, rowCount)),
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
