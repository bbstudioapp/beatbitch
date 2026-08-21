import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../models/session.dart';
import '../models/session_step.dart';
import '../services/beep_engine.dart';
import '../theme/app_theme.dart';
import 'movement_trajectory_forecast.dart';

/// Visualisation animée du mouvement courant. Remplace le timer pendant
/// la séance pour donner un repère visuel du tempo et de la position
/// sans avoir à lire l'heure qui s'écoule.
///
/// L'axe vertical (tip en haut, full en bas) représente la **position le
/// long de la verge** — sémantique partagée par tous les modes :
/// - rhythm / hand : alterne from/to à chaque beat.
/// - lick          : comme rhythm (pastille horizontale).
/// - hold / beg / suckle : tenue sur `from` — courbe plate.
/// - biffle / breath / freestyle : pas de position — ligne plate en haut.
///
/// Un seul widget (`_PositionLadder`) reste monté pour tous les modes : la
/// courbe (silhouette, graduations, trajectoire) ne se démonte jamais d'une
/// consigne à l'autre, seule sa forme change (alternance, plateau tenu, ou
/// ligne du haut) — cf. `_MovementAnimationState._buildForMode`.
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

  /// Temps écoulé de la séance, corrélé à l'instant présent (précision ms).
  /// Sert d'ancrage pour situer les `upcomingSteps` (exprimés en secondes
  /// depuis le début de séance) sur l'horloge murale de la trajectoire.
  final Duration elapsed;

  /// Suite des steps de bip à venir, déjà résolus (mode/from/to/bpm hérités
  /// — cf. `resolveUpcomingMovementSteps`). Vide = comportement historique
  /// (extrapolation indéfinie de la consigne courante).
  final List<UpcomingMovementStep> upcomingSteps;

  const MovementAnimation({
    super.key,
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
    this.height = 160,
    this.beepEngine,
    this.positionRowCount = 5,
    this.elapsed = Duration.zero,
    this.upcomingSteps = const [],
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
  /// from↔to. Null tant qu'aucun beat n'a été reçu (ou juste après une
  /// transition de step, cf. `_frozenIdx`).
  DateTime? _lastBeatAt;

  /// Position visuelle gelée juste avant une transition de step (mode/tempo/
  /// position), point de départ du pont synthétique que dessine la courbe
  /// pendant le court intervalle sans beat réel (cf.
  /// `_PositionLadder._computeFutureBeats`) — sans lui la courbe entière
  /// disparaissait le temps que le 1er bip du nouveau step arrive.
  double? _frozenIdx;
  DateTime? _frozenAt;

  /// Ancrage horloge murale du `elapsed` de séance (rafraîchi au tick
  /// ~200 ms du `SessionController`, alors que ce widget se redessine à
  /// 60 fps). Sert à extrapoler un elapsed continu entre deux ticks au lieu
  /// d'utiliser la valeur figée telle quelle — sans ça, la position calculée
  /// d'une frontière de step à venir dérive en dents de scie (jusqu'à
  /// ~200 ms d'erreur, remise à zéro à chaque tick), visible comme une
  /// vibration horizontale de la courbe à l'approche du prochain step.
  DateTime? _elapsedAnchorAt;
  Duration? _elapsedAnchorValue;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.mode, widget.bpm),
    );
    _elapsedAnchorAt = DateTime.now();
    _elapsedAnchorValue = widget.elapsed;
    _frozenIdx = _ladderPositionsFor(widget.mode, widget.from, widget.to)
        .$2
        .index
        .toDouble();
    _frozenAt = DateTime.now();
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

    if (oldWidget.elapsed != widget.elapsed) {
      _elapsedAnchorAt = DateTime.now();
      _elapsedAnchorValue = widget.elapsed;
    }

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
    // On gèle la position visuelle courante (calculée avec les ANCIENS
    // from/to/mode/bpm/flipped) avant de réinitialiser `_lastBeatAt` : la
    // courbe s'en sert comme point de départ du pont synthétique vers `to`
    // pendant le court intervalle sans beat réel (cf.
    // `_PositionLadder._computeFutureBeats`). Sans ce gel, la courbe entière
    // disparaissait jusqu'au prochain `BeatEvent` (`beats.length < 2` →
    // `AnimatedOpacity` à 0).
    if (modeChanged || tempoChanged || positionChanged) {
      final (oldLadderFrom, oldLadderTo) =
          _ladderPositionsFor(oldWidget.mode, oldWidget.from, oldWidget.to);
      _frozenIdx = _visualIdxNow(
        from: oldLadderFrom,
        to: oldLadderTo,
        flipped: _flipped,
        lastBeatAt: _lastBeatAt,
        beatDuration: _durationFor(oldWidget.mode, oldWidget.bpm),
        now: DateTime.now(),
      );
      _frozenAt = DateTime.now();
      _flipped = false;
      _lastBeatAt = null;
    }
  }

  /// Position visuelle courante du curseur, même formule que
  /// `_PositionLadder._computeFutureBeats` — dupliquée en pure/statique ici
  /// pour geler un point de départ cohérent juste avant une transition
  /// (les anciens from/to/beatDuration ne sont plus disponibles une fois la
  /// transition appliquée).
  static double _visualIdxNow({
    required Position from,
    required Position to,
    required bool flipped,
    required DateTime? lastBeatAt,
    required Duration beatDuration,
    required DateTime now,
  }) {
    if (lastBeatAt == null) return (flipped ? from : to).index.toDouble();
    final beatMs = beatDuration.inMilliseconds.toDouble();
    if (beatMs <= 0) return (flipped ? from : to).index.toDouble();
    final sinceBeatMs = now.difference(lastBeatAt).inMilliseconds.toDouble();
    final lastPosIdx = (flipped ? to : from).index.toDouble();
    final nextPosIdx = (flipped ? from : to).index.toDouble();
    final progress = (sinceBeatMs / beatMs).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(progress);
    return lastPosIdx + (nextPosIdx - lastPosIdx) * eased;
  }

  /// Position affichée sur le ladder selon le mode : alternance réelle
  /// (rhythm/lick/hand), tenue plate sur `from` (hold/beg/suckle), ou
  /// ligne plate en haut pour les modes sans notion de position (Manu :
  /// « pour les respirations ou les biffles, on peut mettre une ligne
  /// droite en haut »). Utilisée pour ce qui est réellement affiché ET pour
  /// geler l'ancre de transition sur la même valeur (cf. `didUpdateWidget`) —
  /// sinon `_frozenIdx` capture une position brute jamais montrée à l'écran.
  static (Position, Position) _ladderPositionsFor(
    SessionMode mode,
    Position from,
    Position? to,
  ) =>
      switch (mode) {
        SessionMode.rhythm || SessionMode.lick || SessionMode.hand => (
            from,
            to ?? from
          ),
        SessionMode.hold || SessionMode.beg || SessionMode.suckle => (
            from,
            from
          ),
        SessionMode.biffle || SessionMode.breath || SessionMode.freestyle => (
            Position.tip,
            Position.tip
          ),
      };

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
      // Suckle : pulse régulier ~1.2s aligné sur le timer audio
      // (_sucklePulse dans BeepEngine). Pas de BPM, juste l'aspiration.
      SessionMode.suckle => const Duration(milliseconds: 1200),
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
    final (ladderFrom, ladderTo) =
        _ladderPositionsFor(widget.mode, widget.from, widget.to);
    final elapsedNow = _elapsedAnchorAt == null || _elapsedAnchorValue == null
        ? widget.elapsed
        : _elapsedAnchorValue! + DateTime.now().difference(_elapsedAnchorAt!);
    return _PositionLadder(
      mode: widget.mode,
      from: ladderFrom,
      to: ladderTo,
      beatDuration: beatDuration,
      flipped: _flipped,
      color: color,
      cursorStyle: cursorStyle,
      lastBeatAt: _lastBeatAt,
      frozenIdx: _frozenIdx,
      frozenAt: _frozenAt,
      rowCount: widget.positionRowCount,
      elapsed: elapsedNow,
      upcomingSteps: widget.upcomingSteps,
      pulseT: t,
    );
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
        // Suckle : rose vif (Material pink 400). Le turquoise précédent
        // collait trop au cyan de lick à l'œil — rose vif tranche
        // nettement avec tous les autres modes (mauve beg, saumon hand)
        // et garde un côté « bouche / lèvres » cohérent avec le geste.
        SessionMode.suckle => const Color(0xFFEC407A),
      };

  static _CursorStyle _cursorStyleFor(SessionMode m) => switch (m) {
        // lèvres / bouche → orbe pleine (le sample bip "remplit" la bouche)
        SessionMode.rhythm ||
        SessionMode.hold ||
        SessionMode.beg ||
        SessionMode.suckle =>
          _CursorStyle.orb,
        // langue → pastille horizontale, lèche la position
        SessionMode.lick => _CursorStyle.tongue,
        // main → anneau ouvert (la main entoure la verge, ne la "remplit" pas)
        SessionMode.hand => _CursorStyle.ring,
        // modes sans position → orbe, affiché en ligne plate en haut du
        // ladder (`_buildForMode` fixe from=to=tip) avec le pulse dédié de
        // `_CursorVisual`
        SessionMode.biffle ||
        SessionMode.breath ||
        SessionMode.freestyle =>
          _CursorStyle.orb,
      };

  /// Famille d'organe engagé — la trajectoire remonte à `tip` au
  /// franchissement d'une frontière de famille (cf. `_PositionLadder`).
  static _ModeFamily _familyOf(SessionMode m, Position p) => switch (m) {
        SessionMode.rhythm || SessionMode.hold => _ModeFamily.mouth,
        SessionMode.suckle =>
          p == Position.head ? _ModeFamily.mouth : _ModeFamily.other,
        SessionMode.beg ||
        SessionMode.lick ||
        SessionMode.hand ||
        SessionMode.biffle ||
        SessionMode.breath ||
        SessionMode.freestyle =>
          _ModeFamily.other,
      };
}

enum _ModeFamily { mouth, other }

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
/// Le curseur **est** le point d'ancrage `t=0` de `_computeFutureBeats`
/// (cf. `_BeatPoint.isAnchor`) : sa position vient de `_visualIdxNow`, la
/// même interpolation `Curves.easeInOutCubic` sur la durée d'un beat,
/// recalculée à chaque frame via `DateTime.now()` — la même formule qui
/// trace la trajectoire future. Une seule source pour les deux, ils ne
/// peuvent plus diverger.
///
/// L'audio reste maître : `lastBeatAt`/`flipped` ne changent qu'à la
/// réception d'un vrai `BeatEvent` (cf. `_onBeatEvent`), jamais par une
/// horloge murale libre.
///
/// En cas de transition de step (from/to changent), `_frozenIdx` gèle la
/// position visuelle d'avant-transition — point de départ du pont
/// synthétique tracé par `_computeFutureBeats` — pas de saut sec.
class _PositionLadder extends StatelessWidget {
  final SessionMode mode;
  final Position from;
  final Position to;
  final Duration beatDuration;
  final bool flipped;
  final Color color;
  final _CursorStyle cursorStyle;
  final DateTime? lastBeatAt;

  /// Position visuelle gelée juste avant la transition de step courante et
  /// instant de ce gel — point de départ et ancre temporelle du pont
  /// synthétique tracé par `_computeFutureBeats` tant qu'aucun beat réel
  /// n'est encore arrivé (`lastBeatAt == null`), cf.
  /// `_MovementAnimationState._frozenIdx`.
  final double? frozenIdx;
  final DateTime? frozenAt;

  /// Phase du `AnimationController` (0..1), consommée par `_CursorVisual`
  /// pour les pulses propres à biffle/breath/hold/beg/suckle.
  final double pulseT;

  /// Nombre de positions affichées (5 = sans balls, 6 = avec balls).
  /// Borne `_toAlign` pour que les positions visibles restent espacées
  /// uniformément dans la hauteur disponible quel que soit le rowCount.
  final int rowCount;

  /// Cf. `MovementAnimation.elapsed` / `.upcomingSteps`.
  final Duration elapsed;
  final List<UpcomingMovementStep> upcomingSteps;

  const _PositionLadder({
    required this.mode,
    required this.from,
    required this.to,
    required this.beatDuration,
    required this.flipped,
    required this.color,
    required this.cursorStyle,
    required this.lastBeatAt,
    required this.frozenIdx,
    required this.frozenAt,
    required this.pulseT,
    required this.rowCount,
    required this.elapsed,
    required this.upcomingSteps,
  });

  /// Fenêtre de prévision de la trajectoire future. Volontairement plus longue
  /// que les 2 s perçues : les ~1 s supplémentaires servent de réserve dans
  /// laquelle les nouveaux beats *émergent en fondu* (cf. `_kFadeFraction`)
  /// au lieu d'apparaître brutalement à l'extrémité droite. À BPM bas (60-90)
  /// la marge est cruciale — un beat entier rentrerait sec sans elle.
  static const Duration _trajectoryWindow = Duration(milliseconds: 3000);

  /// Durée du pont synthétique tracé entre la position gelée d'avant-
  /// transition (`frozenIdx`/`frozenAt`) et `to` tant qu'aucun beat réel
  /// n'est encore arrivé (`lastBeatAt == null`) — partagée avec la
  /// durée de l'`AnimatedAlign` du curseur dans `build()` pour que le
  /// tracé de la courbe et le glissement visuel du curseur s'accordent.
  static const int _bridgeMs = 260;

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
    final activeIndices = {from.index, to.index};
    final beats = _computeFutureBeats();
    // Le curseur EST le point d'ancrage t=0 de la trajectoire (cf. _BeatPoint
    // .isAnchor) — plus de moteur d'interpolation séparé : une seule source
    // pour la position affichée, curseur et courbe ne peuvent plus diverger.
    final cursorIdx = beats.isNotEmpty
        ? beats.first.idx
        : (flipped ? from : to).index.toDouble();
    final cursorAlignment = Alignment(_kCursorX, _toAlign(cursorIdx, rowCount));

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
                    rowCount: rowCount,
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
        Align(
          alignment: cursorAlignment,
          child: _CursorVisual(
            mode: mode,
            cursorStyle: cursorStyle,
            color: color,
            pulseT: pulseT,
          ),
        ),
      ],
    );
  }

  /// Convertit un index de position en y d'Alignment (-1..1) sur un
  /// ladder de [rowCount] lignes. Avec [rowCount] = 5, l'index 4 (full)
  /// tombe en bas (y=1) ; avec [rowCount] = 6, l'index 5 (balls) tombe
  /// en bas et full remonte à 0.6.
  static double _toAlign(num index, int rowCount) =>
      rowCount <= 1 ? 0 : index / (rowCount - 1) * 2 - 1;

  /// Calcule les points de la trajectoire future :
  /// - point 0 : position visible courante du curseur (interpolée easeInOutCubic).
  /// - points suivants : prochains beats, en alternant from↔to au sein du
  ///   step courant puis, à chaque frontière connue via `upcomingSteps`, du
  ///   step suivant — avec un point de passage par `tip` quand la frontière
  ///   franchit une famille de mode (`_MovementAnimationState._familyOf`),
  ///   décalé du gap de transition réel du moteur (`upcoming.transitionGap`).
  /// La fenêtre temporelle est `_trajectoryWindow`. `upcomingSteps` vide =
  /// comportement historique (extrapolation indéfinie du step courant).
  List<_BeatPoint> _computeFutureBeats() {
    final beatMs = beatDuration.inMilliseconds.toDouble();
    if (beatMs <= 0) return const [];
    final now = DateTime.now();
    final windowMs = _trajectoryWindow.inMilliseconds.toDouble();

    final DateTime last;
    final double yNow;
    final Position afterAnchorPos;
    if (lastBeatAt != null) {
      // À l'instant `lastBeatAt`, le bip de `flipped ? to : from` vient de
      // sonner — la position visuelle au moment du beat est cette position,
      // qui glisse ensuite vers la prochaine cible (`flipped ? from : to`).
      yNow = _MovementAnimationState._visualIdxNow(
        from: from,
        to: to,
        flipped: flipped,
        lastBeatAt: lastBeatAt,
        beatDuration: beatDuration,
        now: now,
      );
      last = lastBeatAt!;
      afterAnchorPos = flipped ? from : to;
    } else {
      // Pont synthétique : aucun beat réel n'est encore arrivé pour ce step
      // (juste après une transition). On glisse de la position gelée
      // (`frozenIdx`/`frozenAt`) vers `to` en `_bridgeMs`, puis on prétend
      // qu'un beat vient de sonner sur `to` à la fin du pont — c'est
      // toujours vrai pour le 1er bip réel d'un step (cf. `beep_engine.dart`,
      // jamais modifié ici) — pour rebrancher l'alternance normale derrière.
      final anchorAt = frozenAt ?? now;
      final anchorIdx = frozenIdx ?? to.index.toDouble();
      final targetIdx = to.index.toDouble();
      final sinceFrozenMs = now.difference(anchorAt).inMilliseconds.toDouble();
      final progress = (sinceFrozenMs / _bridgeMs).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(progress);
      yNow = anchorIdx + (targetIdx - anchorIdx) * eased;
      last = anchorAt.add(const Duration(milliseconds: _bridgeMs));
      afterAnchorPos = from;
    }

    final beats = <_BeatPoint>[
      _BeatPoint(t: 0, idx: yNow, isAnchor: true),
    ];

    // Ancrage horloge murale ↔ horloge de séance : `elapsed` est réputé
    // valable à `now` (rafraîchi à chaque tick du SessionController,
    // 200 ms — dérive bornée à cette fenêtre, cf. `MovementAnimation.elapsed`).
    final elapsedMs = elapsed.inMilliseconds;
    DateTime? boundaryAt(int index) {
      if (index >= upcomingSteps.length) return null;
      final offsetMs = upcomingSteps[index].startSecond * 1000 - elapsedMs;
      return now.add(Duration(milliseconds: offsetMs));
    }

    // On génère aussi UN point hors-fenêtre par segment (`_extraBeatsBeyondWindow`) :
    // sa pastille tombera à x > endX (masquée par le ShaderMask), mais le
    // segment cubique qui le relie au précédent traverse la zone de fade et
    // arrive jusqu'au bord droit. Sans lui, la courbe s'arrêtait sec au
    // dernier point dans la fenêtre, laissant une portion vide à droite.
    //
    // `prevIdx`/`lastIdx` gardent trace des 2 derniers points ajoutés — sert
    // à préserver l'alternance visuelle à une frontière de steps (plus bas).
    var extraAdded = 0;
    double? prevIdx;
    double? lastIdx;
    bool addPoint(DateTime at, double idx) {
      final dtMs = at.difference(now).inMilliseconds.toDouble();
      if (dtMs < 0) return true;
      if (dtMs > windowMs) {
        if (extraAdded >= _extraBeatsBeyondWindow) return false;
        extraAdded++;
      }
      beats.add(_BeatPoint(t: dtMs / windowMs, idx: idx, isAnchor: false));
      prevIdx = lastIdx;
      lastIdx = idx;
      return true;
    }

    var segFamily = _MovementAnimationState._familyOf(mode, from);
    var segFrom = from;
    var segTo = to;
    var segBeatMs = beatMs;
    var upcomingIdx = 0;
    var nextBoundary = boundaryAt(0);
    var nextTime = last.add(beatDuration);
    var nextPos = afterAnchorPos;

    while (true) {
      // Segment plat (hold/beg/suckle/biffle/breath/freestyle) tenu depuis
      // longtemps sans frontière à franchir : `nextTime` peut être resté
      // ancré loin dans le passé (aucun beat réel ne le rafraîchit hors
      // rhythm/lick/hand). Sans ce rattrapage, la boucle itérerait à petits
      // pas de `segBeatMs` depuis cette ancre jusqu'à `now` — des centaines
      // d'itérations à vide sur un hold/biffle long à BPM élevé.
      if (segFrom.index == segTo.index && nextTime.isBefore(now)) {
        nextTime = now;
      }
      if (nextBoundary != null && !nextBoundary.isAfter(nextTime)) {
        final boundary = nextBoundary;
        final upcoming = upcomingSteps[upcomingIdx];
        final newFamily =
            _MovementAnimationState._familyOf(upcoming.mode, upcoming.from);
        final (newFrom, newTo) = _MovementAnimationState._ladderPositionsFor(
            upcoming.mode, upcoming.from, upcoming.to);
        segBeatMs =
            _MovementAnimationState._durationFor(upcoming.mode, upcoming.bpm)
                .inMilliseconds
                .toDouble();
        // Le premier bip réel du step suivant n'arrive pas à `boundary`
        // (instant nominal du step) mais après le gap que
        // `BeepEngine.applyStep` insère avant de démarrer le nouveau mode.
        final resumeAt = boundary.add(upcoming.transitionGap);
        if (newFamily != segFamily) {
          if (!addPoint(resumeAt, Position.tip.index.toDouble())) break;
          nextTime = resumeAt.add(Duration(milliseconds: segBeatMs.round()));
          nextPos = newTo;
        } else {
          nextTime = resumeAt;
          // Point 6 de Manu : si viser `newTo` directement continuerait dans
          // le même sens que le dernier mouvement affiché, viser `newFrom`
          // d'abord pour préserver l'alternance visuelle (haut/bas/haut/
          // bas). Artefact de PRÉVISION seulement (dots pas encore réels) —
          // le vrai 1er beat du step reste toujours `to` (cf. beep_engine.dart,
          // jamais modifié ici).
          var target = newTo;
          if (prevIdx != null &&
              segFrom.index != segTo.index &&
              newFrom.index != newTo.index) {
            final lastDir = (lastIdx! - prevIdx!).sign;
            final candidateDir = (newTo.index - lastIdx!).sign;
            if (lastDir != 0 && candidateDir == lastDir) {
              target = newFrom;
            }
          }
          nextPos = target;
        }
        segFamily = newFamily;
        segFrom = newFrom;
        segTo = newTo;
        upcomingIdx++;
        nextBoundary = boundaryAt(upcomingIdx);
        continue;
      }
      if (!addPoint(nextTime, nextPos.index.toDouble())) break;
      nextTime = nextTime.add(Duration(milliseconds: segBeatMs.round()));
      nextPos = (nextPos == segFrom) ? segTo : segFrom;
    }
    return beats;
  }

  /// Nombre de beats à extrapoler au-delà de `_trajectoryWindow`. Un seul
  /// suffit : le segment cubique qui le relie au dernier beat dans la
  /// fenêtre couvre toute la zone de fade jusqu'au bord droit.
  static const int _extraBeatsBeyondWindow = 1;
}

/// Sonde de test pour `_PositionLadder._computeFutureBeats`. Passe par des
/// records (pas `_BeatPoint`, privé) pour rester compatible avec
/// `library_private_types_in_public_api`.
@visibleForTesting
List<({double t, double idx, bool isAnchor})> computeFutureBeatsForTest({
  required SessionMode mode,
  required Position from,
  required Position to,
  required Duration beatDuration,
  required bool flipped,
  DateTime? lastBeatAt,
  double? frozenIdx,
  DateTime? frozenAt,
  Duration elapsed = Duration.zero,
  List<UpcomingMovementStep> upcomingSteps = const [],
}) {
  final beats = _PositionLadder(
    mode: mode,
    from: from,
    to: to,
    beatDuration: beatDuration,
    flipped: flipped,
    color: const Color(0xFFFFFFFF),
    cursorStyle: _CursorStyle.orb,
    lastBeatAt: lastBeatAt,
    frozenIdx: frozenIdx,
    frozenAt: frozenAt,
    pulseT: 0,
    rowCount: 5,
    elapsed: elapsed,
    upcomingSteps: upcomingSteps,
  )._computeFutureBeats();
  return [for (final b in beats) (t: b.t, idx: b.idx, isAnchor: b.isAnchor)];
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

  /// Nombre de positions visibles sur le ladder (5 sans balls, 6 avec).
  /// Sert à mapper `p.idx` → y absolu de la même façon que
  /// `_PositionLadder._toAlign` mappe l'index → coordonnée d'`Alignment`.
  /// Sans ce param, le painter divisait par 4 (hardcodé pour 5 lignes),
  /// ce qui décalait toutes les pastilles dès qu'on passait à 6 lignes
  /// (et balls tombait carrément sous le canvas).
  final int rowCount;

  _TrajectoryPainter({
    required this.beats,
    required this.color,
    required this.cursorXFraction,
    required this.rightPaddingFraction,
    required this.rowCount,
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

    final maxIdx = (rowCount - 1).clamp(1, 99);
    Offset toOffset(_BeatPoint p) =>
        Offset(startX + p.t * span, _verticalInset + p.idx / maxIdx * usableH);

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
        old.rightPaddingFraction != rightPaddingFraction ||
        old.rowCount != rowCount) {
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

/// Curseur du ladder avec le pulse propre à chaque mode — remplace les
/// anciens `_Pulse`/`_Breath`/pulse inline de `_StaticPosition`, tous
/// centrés plein écran (90-110 px) et pensés pour un widget démonté à
/// chaque changement de mode. Ici le ladder reste monté en permanence
/// (cf. doc de classe de `MovementAnimation`) : la taille de base reste
/// celle de `_OrbShape`/`_RingShape`/`_TongueShape` (28-32 px) pour tenir
/// dans une ligne, seuls l'échelle et l'alpha du curseur varient.
class _CursorVisual extends StatelessWidget {
  final SessionMode mode;
  final _CursorStyle cursorStyle;
  final Color color;
  final double pulseT;

  const _CursorVisual({
    required this.mode,
    required this.cursorStyle,
    required this.color,
    required this.pulseT,
  });

  @override
  Widget build(BuildContext context) {
    final cursor = _Cursor(style: cursorStyle, color: color);
    switch (mode) {
      case SessionMode.biffle:
        final decay = Curves.easeOutQuad.transform(pulseT);
        return Opacity(
          opacity: 1.0 - 0.5 * decay,
          child: Transform.scale(scale: 1.0 - 0.35 * decay, child: cursor),
        );
      case SessionMode.breath:
      case SessionMode.freestyle:
        final eased = Curves.easeInOut.transform(pulseT);
        return Opacity(
          opacity: 0.65 + 0.35 * eased,
          child: Transform.scale(scale: 0.75 + 0.25 * eased, child: cursor),
        );
      case SessionMode.hold:
      case SessionMode.beg:
      case SessionMode.suckle:
        final pulse = 0.85 + 0.15 * Curves.easeInOut.transform(pulseT);
        return Transform.scale(scale: pulse, child: cursor);
      case SessionMode.rhythm:
      case SessionMode.lick:
      case SessionMode.hand:
        return cursor;
    }
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
