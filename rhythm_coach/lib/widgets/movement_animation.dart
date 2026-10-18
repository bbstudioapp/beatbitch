import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../models/hold_move.dart';
import '../models/session.dart';
import '../models/session_step.dart';
import '../services/beep_engine.dart';
import '../theme/app_theme.dart';
import 'movement_trajectory_forecast.dart';

class MovementAnimation extends StatefulWidget {
  final SessionMode mode;
  final Position from;
  final Position? to;
  final int bpm;

  /// Calée sur la hauteur du `TimerDisplay` : pas de saut de mise en page
  /// quand l'un remplace l'autre.
  final double height;

  /// Si fourni, ses bips pilotent l'alternance : un second timer côté
  /// visuel dériverait de l'audio.
  final BeepEngine? beepEngine;

  final int positionRowCount;

  /// Temps de séance, pas horloge murale : ancre les `upcomingSteps`.
  final Duration elapsed;

  /// Seul signal qui distingue deux steps consécutifs de configuration
  /// identique, alors que le moteur se tait pendant le gap de l'un.

  final int stepSerial;

  /// Vide = extrapolation indéfinie de la consigne courante.
  final List<UpcomingMovementStep> upcomingSteps;

  final bool showTrajectoryDots;

  final List<HoldMove> moves;

  final bool paused;

  const MovementAnimation({
    super.key,
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
    this.height = 160,
    this.beepEngine,
    this.positionRowCount = 5,
    this.stepSerial = 0,
    this.elapsed = Duration.zero,
    this.upcomingSteps = const [],
    this.showTrajectoryDots = false,
    this.moves = const [],
    this.paused = false,
  });

  @override
  State<MovementAnimation> createState() => _MovementAnimationState();
}

class _MovementAnimationState extends State<MovementAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  bool _flipped = false;

  StreamSubscription<BeatEvent>? _beatSub;

  DateTime? _lastBeatAt;

  /// BPM interpolé sous rampe : `widget.bpm` reste celui du départ.
  double? _lastBeatBpm;

  double? _frozenIdx;
  DateTime? _frozenAt;

  /// Le gel part de la position affichée, pas d'un recalcul : le step
  /// s'applique jusqu'à un tick après l'instant annoncé par la courbe.
  double? _renderedIdx;

  Duration? _bridgeGap;
  bool _bridgeViaTip = false;

  /// En temps de séance, comme le moteur : il ne court pas pendant une pause.
  Duration? _movesOrigin;

  /// `elapsed` n'est rafraîchi qu'au tick de 200 ms du contrôleur : sans
  /// extrapolation entre deux ticks, les frontières à venir vibrent.
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
    _movesOrigin = widget.elapsed;
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
      if (!_isExternallyDriven) {
        _controller.forward(from: 0);
      }
    }

    if (engineChanged) {
      _beatSub?.cancel();
      _beatSub = null;
      _maybeSubscribeBeats(widget.beepEngine);
    }

    // Le gel se calcule avec l'ancien widget, avant la remise à zéro de
    // `_lastBeatAt`. `_flipped = false` : `applyStep` réarme l'alternance, le
    // 1er bip d'un step tombe toujours sur `to`.
    final stepReapplied = oldWidget.stepSerial != widget.stepSerial;
    if (modeChanged || tempoChanged || positionChanged || stepReapplied) {
      final (oldLadderFrom, oldLadderTo) =
          _ladderPositionsFor(oldWidget.mode, oldWidget.from, oldWidget.to);
      _frozenIdx = _renderedIdx ??
          _visualIdxNow(
            from: oldLadderFrom,
            to: oldLadderTo,
            flipped: _flipped,
            lastBeatAt: _lastBeatAt,
            beatDuration: _durationFor(oldWidget.mode, oldWidget.bpm),
            now: DateTime.now(),
          );
      _frozenAt = DateTime.now();
      _bridgeGap = BeepEngine.transitionGap(
        incoming: widget.mode,
        previous: oldWidget.mode,
        incomingTo: widget.to,
      );
      _bridgeViaTip = _familyOf(widget.mode, widget.from) !=
          _familyOf(oldWidget.mode, oldWidget.from);
      _movesOrigin = widget.elapsed + _bridgeGap!;
      _flipped = false;
      _lastBeatAt = null;
      _lastBeatBpm = null;
    }
  }

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

  /// Sert aussi au gel de transition : sinon `_frozenIdx` capture une
  /// position brute jamais montrée à l'écran.
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
    if (event.mode == SessionMode.rhythm ||
        event.mode == SessionMode.lick ||
        event.mode == SessionMode.hand) {
      // `nextInterval`, pas `60000/bpm` : sous ancrage l'intervalle alterne.
      final nextIsFrom = event.position == widget.to;
      _controller.duration = event.nextInterval;
      setState(() {
        _flipped = nextIsFrom;
        _lastBeatAt = DateTime.now();
        _lastBeatBpm = event.bpm;
      });
      _controller.forward(from: 0);
    } else if (event.mode == SessionMode.biffle) {
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
      // Aligné sur `BeepEngine._sucklePulse`.
      SessionMode.suckle => const Duration(milliseconds: 1200),
    };
  }

  @override
  Widget build(BuildContext context) {
    final targetColor = _modeColor(widget.mode);
    return SizedBox(
      height: widget.height,
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
    final beatDuration =
        _controller.duration ?? _durationFor(widget.mode, widget.bpm);
    final (ladderFrom, ladderTo) =
        _ladderPositionsFor(widget.mode, widget.from, widget.to);
    final elapsedNow = widget.paused
        ? widget.elapsed
        : extrapolatedElapsed(
            anchorValue: _elapsedAnchorValue,
            anchorAt: _elapsedAnchorAt,
            fallback: widget.elapsed,
            now: DateTime.now(),
          );
    return _PositionLadder(
      mode: widget.mode,
      from: ladderFrom,
      to: ladderTo,
      beatDuration: beatDuration,
      bpm: (_lastBeatBpm ?? widget.bpm.toDouble()).round(),
      flipped: _flipped,
      color: color,
      cursorStyle: cursorStyle,
      lastBeatAt: _lastBeatAt,
      frozenIdx: _frozenIdx,
      frozenAt: _frozenAt,
      onCursorIdx: (idx) => _renderedIdx = idx,
      bridgeGap: _bridgeGap,
      bridgeViaTip: _bridgeViaTip,
      rowCount: widget.positionRowCount,
      elapsed: elapsedNow,
      upcomingSteps: widget.upcomingSteps,
      showTrajectoryDots: widget.showTrajectoryDots,
      moves: widget.mode == SessionMode.hold ? widget.moves : const [],
      movesOrigin: _movesOrigin,
      pulseT: t,
      paused: widget.paused,
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
        SessionMode.suckle => const Color(0xFFEC407A),
      };

  static _CursorStyle _cursorStyleFor(SessionMode m) => switch (m) {
        SessionMode.rhythm ||
        SessionMode.hold ||
        SessionMode.beg ||
        SessionMode.suckle =>
          _CursorStyle.orb,
        SessionMode.lick => _CursorStyle.tongue,
        SessionMode.hand => _CursorStyle.ring,
        SessionMode.biffle ||
        SessionMode.breath ||
        SessionMode.freestyle =>
          _CursorStyle.orb,
      };

  /// Au franchissement d'une frontière de famille, la trajectoire remonte à
  /// `tip`.
  static _ModeFamily _familyOf(SessionMode m, Position p) => switch (m) {
        SessionMode.rhythm ||
        SessionMode.hold ||
        SessionMode.beg =>
          _ModeFamily.mouth,
        SessionMode.suckle =>
          p == Position.head ? _ModeFamily.mouth : _ModeFamily.other,
        SessionMode.lick ||
        SessionMode.hand ||
        SessionMode.biffle ||
        SessionMode.breath ||
        SessionMode.freestyle =>
          _ModeFamily.other,
      };
}

enum _ModeFamily { mouth, other }

enum _CursorStyle { orb, ring, tongue }

/// Inverse de la soustraction de `BeepEngine._intervalAfter` : ce widget ne
/// reçoit ni `anchor` ni `ratio`.
@visibleForTesting
int complementaryBeatIntervalMs({
  required int lastIntervalMs,
  required int bpm,
}) =>
    (120000 / bpm).round() - lastIntervalMs;

/// Le curseur est le point `t=0` de la trajectoire : une seule source pour
/// les deux. `lastBeatAt`/`flipped` ne changent qu'à la réception d'un vrai
/// `BeatEvent`, jamais sur une horloge murale libre.
const _kLevelLabelShadows = [
  Shadow(color: Color(0xB3000000), blurRadius: 3),
  Shadow(color: Color(0x80000000), blurRadius: 1, offset: Offset(0, 1)),
];

class _PositionLadder extends StatefulWidget {
  final SessionMode mode;
  final Position from;
  final Position to;
  final Duration beatDuration;

  final int bpm;

  final bool flipped;
  final Color color;
  final _CursorStyle cursorStyle;
  final DateTime? lastBeatAt;

  final double? frozenIdx;
  final DateTime? frozenAt;

  final void Function(double idx)? onCursorIdx;

  final Duration? bridgeGap;
  final bool bridgeViaTip;

  final double pulseT;

  final int rowCount;

  final Duration elapsed;
  final List<UpcomingMovementStep> upcomingSteps;
  final bool showTrajectoryDots;
  final List<HoldMove> moves;
  final Duration? movesOrigin;
  final bool paused;

  const _PositionLadder({
    required this.mode,
    required this.from,
    required this.to,
    required this.beatDuration,
    required this.bpm,
    required this.flipped,
    required this.color,
    required this.cursorStyle,
    required this.lastBeatAt,
    required this.frozenIdx,
    required this.frozenAt,
    this.onCursorIdx,
    this.bridgeGap,
    this.bridgeViaTip = false,
    required this.pulseT,
    required this.rowCount,
    required this.elapsed,
    required this.upcomingSteps,
    this.showTrajectoryDots = false,
    this.moves = const [],
    this.movesOrigin,
    this.paused = false,
  });

  @override
  State<_PositionLadder> createState() => _PositionLadderState();

  /// Plus longue que les 2 s perçues : la réserve laisse les beats lointains
  /// émerger en fondu au lieu d'entrer sec à droite, surtout à BPM bas.
  static const Duration _trajectoryWindow = Duration(milliseconds: 3000);

  /// Durée du pont quand le gap du moteur est inconnu (aucune transition avant).
  static const int _bridgeMs = 260;

  static const double _kFadeFraction = 0.50;

  /// Pilote à la fois la fin du fondu du shader et la zone utile du painter :
  /// la courbe ne passe jamais sous les libellés de position.
  static const double _kRightPaddingFraction = 0.20;

  static double _toAlign(num index, int rowCount) =>
      rowCount <= 1 ? 0 : index / (rowCount - 1) * 2 - 1;

  /// [pins] : une frontière déjà placée ne recule jamais vers le futur ;
  /// quand l'horloge de séance cale (step reporté pendant la voix), un
  /// recalcul la replacerait derrière la géométrie déjà défilée.
  List<_BeatPoint> _computeFutureBeats([Map<int, DateTime>? pins]) {
    final beatMs = beatDuration.inMilliseconds.toDouble();
    if (beatMs <= 0) return const [];
    final now = DateTime.now();
    final windowMs = _trajectoryWindow.inMilliseconds.toDouble();

    final DateTime last;
    double yNow;
    final Position afterAnchorPos;
    double? bridgeTargetIdx;
    DateTime? bridgeViaAt;
    DateTime? originAt;
    double? originIdx;
    if (lastBeatAt != null) {
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
      originAt = lastBeatAt;
      originIdx = (flipped ? to : from).index.toDouble();
    } else {
      final anchorAt = frozenAt ?? now;
      final anchorIdx = frozenIdx ?? to.index.toDouble();
      final bridgeMs = (bridgeGap?.inMilliseconds ?? _bridgeMs).toDouble();
      // Le passage par `tip` tient dans le gap : le 1er bip réel tombe sur
      // `to` à sa fin.
      last = anchorAt.add(Duration(milliseconds: bridgeMs.round()));
      final viaAt = bridgeViaTip
          ? anchorAt.add(Duration(milliseconds: (bridgeMs / 2).round()))
          : null;
      double leg(DateTime start, DateTime end, double fromIdx, double toIdx) {
        final spanMs = end.difference(start).inMilliseconds.toDouble();
        if (spanMs <= 0) return toIdx;
        final p = (now.difference(start).inMilliseconds.toDouble() / spanMs)
            .clamp(0.0, 1.0);
        return fromIdx + (toIdx - fromIdx) * Curves.easeInOutCubic.transform(p);
      }

      // Hors rhythm/lick/hand, aucun `BeatEvent` ne relève `lastBeatAt` : le
      // pont doit enchaîner lui-même sur un bip synthétique à `last`.
      final tipIdx = Position.tip.index.toDouble();
      final toIdx = to.index.toDouble();
      if (now.isAfter(last) || now.isAtSameMomentAs(last)) {
        yNow = _MovementAnimationState._visualIdxNow(
          from: to,
          to: from,
          flipped: false,
          lastBeatAt: last,
          beatDuration: beatDuration,
          now: now,
        );
        originAt = last;
        originIdx = toIdx;
      } else if (viaAt != null && now.isBefore(viaAt)) {
        yNow = leg(anchorAt, viaAt, anchorIdx, tipIdx);
        originAt = anchorAt;
        originIdx = anchorIdx;
      } else {
        yNow = leg(
            viaAt ?? anchorAt, last, viaAt == null ? anchorIdx : tipIdx, toIdx);
        originAt = viaAt ?? anchorAt;
        originIdx = viaAt == null ? anchorIdx : tipIdx;
      }
      afterAnchorPos = from;
      bridgeTargetIdx = toIdx;
      bridgeViaAt = viaAt;
    }

    final elapsedMs0 = elapsed.inMilliseconds;
    List<List<(DateTime, double)>> groupsAt(
            Position hold, List<HoldMove> moves, DateTime origin) =>
        [
          for (final g in holdMoveGroups(hold, moves))
            [for (final k in g) (origin.add(k.at), k.idx)],
        ];
    var segGroups = movesOrigin == null || moves.isEmpty
        ? const <List<(DateTime, double)>>[]
        : groupsAt(
            from,
            moves,
            now.add(Duration(
                milliseconds: movesOrigin!.inMilliseconds - elapsedMs0)));
    var segKf = [for (final g in segGroups) ...g];
    groups:
    for (final g in segGroups) {
      for (var j = 0; j + 1 < g.length; j++) {
        final (aAt, aIdx) = g[j];
        final (bAt, bIdx) = g[j + 1];
        if (now.isBefore(aAt) || !now.isBefore(bAt)) continue;
        final spanMs = bAt.difference(aAt).inMilliseconds.toDouble();
        final p = now.difference(aAt).inMilliseconds.toDouble() / spanMs;
        yNow = aIdx + (bIdx - aIdx) * Curves.easeInOutCubic.transform(p);
        originAt = aAt;
        originIdx = aIdx;
        break groups;
      }
    }

    final anchorOrigin = originAt;
    final beats = <_BeatPoint>[
      _BeatPoint(
        t: 0,
        idx: yNow,
        isAnchor: true,
        originT: anchorOrigin == null
            ? null
            : anchorOrigin.difference(now).inMilliseconds.toDouble() / windowMs,
        originIdx: originIdx,
      ),
    ];

    // Dernier repère passé : origine du curseur. Sans lui, sur un plateau,
    // `originAt` a l'âge du plateau entier et le curseur suit une corde.
    DateTime? pastAt;
    double? pastIdx;

    // Sans l'arrivée du pont dans la géométrie, le défilement glisse sur une
    // droite que le recalcul suivant corrige par un saut.
    if (bridgeTargetIdx != null) {
      void addBridgePoint(DateTime at, double idx) {
        final dtMs = at.difference(now).inMilliseconds.toDouble();
        if (dtMs > 0) {
          beats.add(_BeatPoint(t: dtMs / windowMs, idx: idx, isAnchor: false));
        } else {
          pastAt = at;
          pastIdx = idx;
        }
      }

      if (bridgeViaAt != null) {
        addBridgePoint(bridgeViaAt, Position.tip.index.toDouble());
      }
      addBridgePoint(last, bridgeTargetIdx);
    }

    final elapsedMs = elapsed.inMilliseconds;
    DateTime? boundaryAt(int index) {
      if (index >= upcomingSteps.length) return null;
      final start = upcomingSteps[index].startSecond;
      var at = now.add(Duration(milliseconds: start * 1000 - elapsedMs));
      final pinned = pins?[start];
      if (pinned != null && pinned.isBefore(at)) at = pinned;
      pins?[start] = at;
      return at;
    }

    var extraAdded = 0;
    var lastPointAt = last;
    var lastPointIdx = lastBeatAt != null
        ? (flipped ? to : from).index.toDouble()
        : (bridgeTargetIdx ?? to.index.toDouble());
    bool addPoint(DateTime at, double idx) {
      final dtMs = at.difference(now).inMilliseconds.toDouble();
      lastPointAt = at;
      lastPointIdx = idx;
      if (dtMs < 0) {
        pastAt = at;
        pastIdx = idx;
        return true;
      }
      if (dtMs > windowMs) {
        if (extraAdded >= _extraBeatsBeyondWindow) return false;
        extraAdded++;
      }
      beats.add(_BeatPoint(t: dtMs / windowMs, idx: idx, isAnchor: false));
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

    // Sous ancrage l'intervalle alterne. Segment courant seulement :
    // `UpcomingMovementStep` ne porte ni `anchor` ni `ratio`.
    final alternates = _MovementAnimationState._isBeatSynced(mode) &&
        from.index != to.index &&
        beatMs > 0;
    final otherMs = alternates
        ? complementaryBeatIntervalMs(
                lastIntervalMs: beatDuration.inMilliseconds, bpm: bpm)
            .toDouble()
        : beatMs;
    var useOther = true;
    double advanceMs() {
      if (upcomingIdx > 0 || !alternates) return segBeatMs;
      final ms = useOther ? otherMs : beatMs;
      useOther = !useOther;
      return ms;
    }

    var kfI = 0;
    bool insideMove(DateTime t) {
      for (final g in segGroups) {
        if (t.isAfter(g.first.$1) && t.isBefore(g.last.$1)) return true;
      }
      return false;
    }

    while (true) {
      if (segFrom.index == segTo.index && nextTime.isBefore(now)) {
        // Multiples entiers du battement, pas `now` : deux recalculs doivent
        // poser leurs points aux mêmes instants.
        final lateMs = now.difference(nextTime).inMilliseconds.toDouble();
        final steps = (lateMs / segBeatMs).ceil();
        nextTime = nextTime.add(
          Duration(milliseconds: (steps * segBeatMs).round()),
        );
      }
      final kfLimit = nextBoundary != null && nextBoundary.isBefore(nextTime)
          ? nextBoundary
          : nextTime;
      var stopped = false;
      while (kfI < segKf.length && !segKf[kfI].$1.isAfter(kfLimit)) {
        if (!addPoint(segKf[kfI].$1, segKf[kfI].$2)) {
          stopped = true;
          break;
        }
        kfI++;
      }
      if (stopped) break;
      if (nextBoundary != null && !nextBoundary.isAfter(nextTime)) {
        final boundary = nextBoundary;
        // Sans la position atteinte à la frontière, la courbe rejoint le step
        // suivant trop tôt et le gel ramène le curseur en arrière.
        final legMs =
            nextTime.difference(lastPointAt).inMilliseconds.toDouble();
        final atBoundaryIdx = legMs <= 0
            ? lastPointIdx
            : lastPointIdx +
                (nextPos.index.toDouble() - lastPointIdx) *
                    Curves.easeInOutCubic.transform(
                      (boundary
                                  .difference(lastPointAt)
                                  .inMilliseconds
                                  .toDouble() /
                              legMs)
                          .clamp(0.0, 1.0),
                    );
        if (!addPoint(boundary, atBoundaryIdx)) break;
        final upcoming = upcomingSteps[upcomingIdx];
        final newFamily =
            _MovementAnimationState._familyOf(upcoming.mode, upcoming.from);
        final (newFrom, newTo) = _MovementAnimationState._ladderPositionsFor(
            upcoming.mode, upcoming.from, upcoming.to);
        segBeatMs =
            _MovementAnimationState._durationFor(upcoming.mode, upcoming.bpm)
                .inMilliseconds
                .toDouble();
        final resumeAt = boundary.add(upcoming.transitionGap);
        if (newFamily != segFamily) {
          final viaAt = boundary.add(Duration(
              milliseconds: upcoming.transitionGap.inMilliseconds ~/ 2));
          if (!addPoint(viaAt, Position.tip.index.toDouble())) break;
          nextTime = resumeAt;
          nextPos = newTo;
        } else {
          nextTime = resumeAt;
          // `applyStep` réarme l'alternance : le 1er bip d'un step tombe
          // toujours sur `to`.
          nextPos = newTo;
        }
        segFamily = newFamily;
        segFrom = newFrom;
        segTo = newTo;
        segGroups =
            upcoming.mode == SessionMode.hold && upcoming.moves.isNotEmpty
                ? groupsAt(newFrom, upcoming.moves, resumeAt)
                : const <List<(DateTime, double)>>[];
        segKf = [for (final g in segGroups) ...g];
        kfI = 0;
        upcomingIdx++;
        nextBoundary = boundaryAt(upcomingIdx);
        continue;
      }
      if (!insideMove(nextTime) &&
          !addPoint(nextTime, nextPos.index.toDouble())) {
        break;
      }
      nextTime = nextTime.add(Duration(milliseconds: advanceMs().round()));
      nextPos = (nextPos == segFrom) ? segTo : segFrom;
    }

    final freshAt = pastAt;
    final freshIdx = pastIdx;
    if (freshAt != null &&
        freshIdx != null &&
        (anchorOrigin == null || freshAt.isAfter(anchorOrigin))) {
      beats[0] = _BeatPoint(
        t: 0,
        idx: beats[0].idx,
        isAnchor: true,
        originT: freshAt.difference(now).inMilliseconds.toDouble() / windowMs,
        originIdx: freshIdx,
      );
    }
    return beats;
  }

  /// Un seul suffit : son segment cubique couvre le fondu jusqu'au bord droit.
  static const int _extraBeatsBeyondWindow = 1;
}

class _PositionLadderState extends State<_PositionLadder> {
  List<_BeatPoint>? _rawBeats;
  DateTime? _computedAt;

  /// Sans lui, la garde de remplissage recalculerait à chaque frame une
  /// fenêtre qu'aucun recalcul ne peut compléter (fin de séance).
  bool _windowUnfillable = false;

  DateTime? _pausedAt;

  /// Aucune image n'est construite en arrière-plan : la première qui montre
  /// la pause arrive au retour dans l'appli. La pause date de l'instant où le
  /// temps de séance s'est arrêté, pas de cette image.
  DateTime? _lastFrameAt;
  Duration? _lastFrameElapsed;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant _PositionLadder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused && !oldWidget.paused) {
      _pausedAt = _lastFrameAt!.add(widget.elapsed - _lastFrameElapsed!);
    }
    if (!widget.paused) _resumeClock();
    if (!_sameGeometry(oldWidget, widget)) {
      _recompute();
    }
  }

  final Map<int, DateTime> _boundaryPins = {};

  void _resumeClock() {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    final pause = DateTime.now().difference(pausedAt);
    _computedAt = _computedAt!.add(pause);
    _boundaryPins.updateAll((_, at) => at.add(pause));
    _pausedAt = null;
  }

  void _recompute() {
    // Le moteur reprend (et émet un bip) avant que l'écran ne lève la pause.
    _resumeClock();
    // Une épingle ne vaut que pour une frontière encore annoncée : revenue
    // après un trou dans la liste, elle serait dans le passé.
    _boundaryPins.removeWhere(
        (start, _) => !widget.upcomingSteps.any((s) => s.startSecond == start));
    _rawBeats = widget._computeFutureBeats(_boundaryPins);
    _computedAt = DateTime.now();
    _windowUnfillable = _rawBeats!.isEmpty || _rawBeats!.last.t < 1.0;
  }

  /// Une image en pause ne relance pas l'horloge : seul le moteur le fait.
  void _refill() {
    final frozen = _pausedAt != null;
    _recompute();
    if (frozen) _pausedAt = _computedAt;
  }

  static const Color _tongueColor = Color(0xFF4FC3F7);

  (List<_BeatPoint>, double?) _tongue() {
    final origin = widget.movesOrigin;
    if (origin == null ||
        widget.moves.isEmpty ||
        widget.rowCount <= Position.balls.index) {
      return (const [], null);
    }
    final nowMs = (widget.elapsed - origin).inMilliseconds;
    final windowMs = _PositionLadder._trajectoryWindow.inMilliseconds;
    final full = Position.full.index.toDouble();
    final balls = Position.balls.index.toDouble();
    for (final g in holdMoveGroups(widget.from, widget.moves)) {
      if (!g.first.tongue) continue;
      final startMs = g.first.at.inMilliseconds;
      final endMs = g.last.at.inMilliseconds;
      if (endMs <= nowMs || startMs >= nowMs + windowMs) continue;
      final keys = <(int, double)>[(startMs, full)];
      for (final f in g.skip(1)) {
        final ms = f.at.inMilliseconds;
        if (f.beep == null) {
          keys.add((ms, full));
          continue;
        }
        final mid = (keys.last.$1 + ms) ~/ 2;
        if (mid > keys.last.$1) keys.add((mid, full));
        keys.add((ms, balls));
      }
      double? idxNow;
      for (var i = 0; i + 1 < keys.length; i++) {
        final (aMs, aIdx) = keys[i];
        final (bMs, bIdx) = keys[i + 1];
        if (nowMs < aMs || nowMs >= bMs) continue;
        final p = (nowMs - aMs) / (bMs - aMs);
        idxNow = aIdx + (bIdx - aIdx) * Curves.easeInOutCubic.transform(p);
      }
      return (
        [
          if (idxNow != null) _BeatPoint(t: 0, idx: idxNow, isAnchor: true),
          for (final (ms, idx) in keys)
            if (ms > nowMs)
              _BeatPoint(t: (ms - nowMs) / windowMs, idx: idx, isAnchor: false),
        ],
        idxNow,
      );
    }
    return (const [], null);
  }

  @override
  Widget build(BuildContext context) {
    _lastFrameAt = DateTime.now();
    _lastFrameElapsed = widget.elapsed;
    final windowMs =
        _PositionLadder._trajectoryWindow.inMilliseconds.toDouble();
    final deltaT =
        (_pausedAt ?? DateTime.now()).difference(_computedAt!).inMilliseconds /
            windowMs;
    var beats = _scrollBeats(_rawBeats!, deltaT);
    // Le défilement ne fabrique aucun point : sans recalcul, la fenêtre se
    // viderait par la droite.
    if (beats != null &&
        !_windowUnfillable &&
        (beats.isEmpty || beats.last.t < 1.0)) {
      _refill();
      beats = _scrollBeats(_rawBeats!, 0.0);
    }
    if (beats == null) {
      _recompute();
      beats = _scrollBeats(_rawBeats!, 0.0) ?? const [];
    }

    final activeIndices = {widget.from.index, widget.to.index};
    final cursorIdx = beats.isNotEmpty
        ? beats.first.idx
        : (widget.flipped ? widget.from : widget.to).index.toDouble();
    widget.onCursorIdx?.call(cursorIdx);
    final cursorAlignment =
        Alignment(_kCursorX, _PositionLadder._toAlign(cursorIdx, _kLevelSlots));
    final (tongueBeats, tongueIdx) = _tongue();

    return Stack(
      alignment: Alignment.center,
      children: [
        const _Shaft(),
        for (var i = 0; i < widget.rowCount; i++)
          Align(
            alignment: Alignment(0, _PositionLadder._toAlign(i, _kLevelSlots)),
            child: SizedBox(
              height: _kLevelBox,
              child: FractionallySizedBox(
                widthFactor: 0.55,
                child: Center(
                  child: Container(
                    height: 1,
                    color: AppTheme.textMuted.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: beats.length >= 2 ? 1.0 : 0.0,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  const cursorX = (_kCursorX + 1) / 2;
                  const rightEdge =
                      1.0 - _PositionLadder._kRightPaddingFraction;
                  const usable = rightEdge - cursorX;
                  const fadeStart =
                      rightEdge - usable * _PositionLadder._kFadeFraction;
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
                    color: widget.color,
                    cursorXFraction: (_kCursorX + 1) / 2,
                    rightPaddingFraction:
                        _PositionLadder._kRightPaddingFraction,
                    showDots: widget.showTrajectoryDots,
                  ),
                ),
              ),
            ),
          ),
        ),
        for (var i = 0; i < widget.rowCount; i++)
          Align(
            alignment:
                Alignment(0.92, _PositionLadder._toAlign(i, _kLevelSlots)),
            child: SizedBox(
              height: _kLevelBox,
              child: Align(
                widthFactor: 1,
                child: Text(
                  Position.values[i].localizedLabel(context),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: activeIndices.contains(i)
                        ? FontWeight.w800
                        : FontWeight.w600,
                    letterSpacing: 1,
                    color: activeIndices.contains(i)
                        ? widget.color
                        : Colors.white.withValues(alpha: 0.9),
                    shadows: _kLevelLabelShadows,
                  ),
                ),
              ),
            ),
          ),
        if (tongueBeats.length >= 2)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('tongue-curve'),
                painter: _TrajectoryPainter(
                  beats: tongueBeats,
                  color: _tongueColor,
                  cursorXFraction: (_kCursorX + 1) / 2,
                  rightPaddingFraction: _PositionLadder._kRightPaddingFraction,
                  showDots: false,
                ),
              ),
            ),
          ),
        if (tongueIdx != null)
          Align(
            key: const ValueKey('cursor-tongue'),
            alignment: Alignment(
                _kCursorX, _PositionLadder._toAlign(tongueIdx, _kLevelSlots)),
            child: const SizedBox(
              height: _kLevelBox,
              child: Align(
                widthFactor: 1,
                child: _Cursor(style: _CursorStyle.tongue, color: _tongueColor),
              ),
            ),
          ),
        Align(
          alignment: cursorAlignment,
          child: SizedBox(
            height: _kLevelBox,
            child: Align(
              widthFactor: 1,
              child: _CursorVisual(
                mode: widget.mode,
                cursorStyle: widget.cursorStyle,
                color: widget.color,
                pulseT: widget.pulseT,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sans `elapsed` : il avance en continu, le défilement en tient déjà compte.
bool _sameGeometry(_PositionLadder a, _PositionLadder b) {
  return a.mode == b.mode &&
      a.from == b.from &&
      a.to == b.to &&
      a.beatDuration == b.beatDuration &&
      a.flipped == b.flipped &&
      a.lastBeatAt == b.lastBeatAt &&
      a.frozenIdx == b.frozenIdx &&
      a.frozenAt == b.frozenAt &&
      a.rowCount == b.rowCount &&
      a.movesOrigin == b.movesOrigin &&
      listEquals(a.moves, b.moves) &&
      _sameUpcomingSteps(a.upcomingSteps, b.upcomingSteps);
}

bool _sameUpcomingSteps(
    List<UpcomingMovementStep> a, List<UpcomingMovementStep> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final sa = a[i];
    final sb = b[i];
    if (sa.mode != sb.mode ||
        sa.from != sb.from ||
        sa.to != sb.to ||
        sa.bpm != sb.bpm ||
        sa.startSecond != sb.startSecond ||
        sa.transitionGap != sb.transitionGap ||
        !listEquals(sa.moves, sb.moves)) {
      return false;
    }
  }
  return true;
}

/// `null` : plus aucun point au-delà de `t = 0`, il faut recalculer.
List<_BeatPoint>? _scrollBeats(List<_BeatPoint> raw, double deltaT) {
  if (raw.isEmpty) return const [];
  _BeatPoint? prev;
  final future = <_BeatPoint>[];
  for (final b in raw) {
    final t = b.t - deltaT;
    if (t <= 0) {
      prev = _BeatPoint(
        t: t,
        idx: b.idx,
        isAnchor: false,
        originT: b.originT,
        originIdx: b.originIdx,
      );
    } else {
      future.add(_BeatPoint(t: t, idx: b.idx, isAnchor: false));
    }
  }
  if (future.isEmpty) return null;
  final next = future.first;
  final double anchorIdx;
  if (prev == null) {
    anchorIdx = next.idx;
  } else {
    final prevT = prev.originT == null ? prev.t : prev.originT! - deltaT;
    final prevIdx = prev.originIdx ?? prev.idx;
    final span = next.t - prevT;
    final frac = span <= 0 ? 1.0 : ((0 - prevT) / span).clamp(0.0, 1.0);
    // Amortir seulement aux changements de sens : sinon le curseur s'arrête
    // entre deux points alignés.
    final after = future.length > 1 ? future[1] : null;
    final incoming = (next.idx - prevIdx).sign;
    final outgoing = after == null ? incoming : (after.idx - next.idx).sign;
    final turns = incoming != 0 && outgoing != incoming;
    final eased = turns ? Curves.easeInOutCubic.transform(frac) : frac;
    anchorIdx = prevIdx + (next.idx - prevIdx) * eased;
  }
  return [
    _BeatPoint(t: 0, idx: anchorIdx, isAnchor: true),
    ...future,
  ];
}

/// Records plutôt que `_BeatPoint` : un type privé n'est pas exposable.
@visibleForTesting
List<({double t, double idx, bool isAnchor})>? scrollBeatsForTest({
  required List<({double t, double idx, bool isAnchor})> raw,
  required double deltaT,
}) {
  final beats = _scrollBeats(
    [for (final b in raw) _BeatPoint(t: b.t, idx: b.idx, isAnchor: b.isAnchor)],
    deltaT,
  );
  if (beats == null) return null;
  return [for (final b in beats) (t: b.t, idx: b.idx, isAnchor: b.isAnchor)];
}

int _bpmOfRegularInterval(Duration beatDuration) {
  final ms = beatDuration.inMilliseconds;
  return ms <= 0 ? 60 : (60000 / ms).round();
}

typedef GeometryKeyForTest = ({
  SessionMode mode,
  Position from,
  Position to,
  Duration beatDuration,
  bool flipped,
  DateTime? lastBeatAt,
  double? frozenIdx,
  DateTime? frozenAt,
  int rowCount,
  List<UpcomingMovementStep> upcomingSteps,
});

@visibleForTesting
bool sameGeometryForTest(GeometryKeyForTest a, GeometryKeyForTest b) {
  _PositionLadder build(GeometryKeyForTest k) => _PositionLadder(
        mode: k.mode,
        from: k.from,
        to: k.to,
        beatDuration: k.beatDuration,
        bpm: _bpmOfRegularInterval(k.beatDuration),
        flipped: k.flipped,
        color: const Color(0xFFFFFFFF),
        cursorStyle: _CursorStyle.orb,
        lastBeatAt: k.lastBeatAt,
        frozenIdx: k.frozenIdx,
        frozenAt: k.frozenAt,
        pulseT: 0,
        rowCount: k.rowCount,
        elapsed: Duration.zero,
        upcomingSteps: k.upcomingSteps,
      );
  return _sameGeometry(build(a), build(b));
}

@visibleForTesting
List<({double t, double idx, bool isAnchor})> computeFutureBeatsForTest({
  required SessionMode mode,
  required Position from,
  required Position to,
  required Duration beatDuration,
  required bool flipped,
  int? bpm,
  DateTime? lastBeatAt,
  double? frozenIdx,
  DateTime? frozenAt,
  Duration? bridgeGap,
  bool bridgeViaTip = false,
  Duration elapsed = Duration.zero,
  List<UpcomingMovementStep> upcomingSteps = const [],
}) {
  final beats = _PositionLadder(
    mode: mode,
    from: from,
    to: to,
    beatDuration: beatDuration,
    bpm: bpm ?? _bpmOfRegularInterval(beatDuration),
    flipped: flipped,
    color: const Color(0xFFFFFFFF),
    cursorStyle: _CursorStyle.orb,
    lastBeatAt: lastBeatAt,
    frozenIdx: frozenIdx,
    frozenAt: frozenAt,
    bridgeGap: bridgeGap,
    bridgeViaTip: bridgeViaTip,
    pulseT: 0,
    rowCount: 5,
    elapsed: elapsed,
    upcomingSteps: upcomingSteps,
  )._computeFutureBeats();
  return [for (final b in beats) (t: b.t, idx: b.idx, isAnchor: b.isAnchor)];
}

@visibleForTesting
double? anchorAfterScrollForTest({
  required SessionMode mode,
  required Position from,
  required Position to,
  required Duration beatDuration,
  required bool flipped,
  int? bpm,
  required Duration elapsedSinceCompute,
  DateTime? lastBeatAt,
  double? frozenIdx,
  DateTime? frozenAt,
  Duration? bridgeGap,
  bool bridgeViaTip = false,
  Duration elapsed = Duration.zero,
  List<UpcomingMovementStep> upcomingSteps = const [],
}) {
  final raw = _PositionLadder(
    mode: mode,
    from: from,
    to: to,
    beatDuration: beatDuration,
    bpm: bpm ?? _bpmOfRegularInterval(beatDuration),
    flipped: flipped,
    color: const Color(0xFFFFFFFF),
    cursorStyle: _CursorStyle.orb,
    lastBeatAt: lastBeatAt,
    frozenIdx: frozenIdx,
    frozenAt: frozenAt,
    bridgeGap: bridgeGap,
    bridgeViaTip: bridgeViaTip,
    pulseT: 0,
    rowCount: 5,
    elapsed: elapsed,
    upcomingSteps: upcomingSteps,
  )._computeFutureBeats();
  final windowMs = _PositionLadder._trajectoryWindow.inMilliseconds.toDouble();
  final scrolled = _scrollBeats(
      raw, elapsedSinceCompute.inMilliseconds.toDouble() / windowMs);
  return scrolled?.first.idx;
}

/// Un tick du contrôleur (200 ms) plus une marge : `elapsed` se fige pendant
/// un défi, l'ancre n'est alors plus réarmée.
const Duration _kElapsedExtrapolationCap = Duration(milliseconds: 250);

@visibleForTesting
Duration extrapolatedElapsed({
  required Duration? anchorValue,
  required DateTime? anchorAt,
  required Duration fallback,
  required DateTime now,
}) {
  if (anchorValue == null || anchorAt == null) return fallback;
  final since = now.difference(anchorAt);
  return anchorValue +
      (since > _kElapsedExtrapolationCap ? _kElapsedExtrapolationCap : since);
}

/// `t` : fraction de `_trajectoryWindow` (0 = présent).
class _BeatPoint {
  final double t;
  final double idx;
  final bool isAnchor;

  /// Début du segment en cours (`t` négatif) : sans lui, chaque recalcul
  /// redémarre l'easing au milieu du mouvement.
  final double? originT;
  final double? originIdx;
  const _BeatPoint({
    required this.t,
    required this.idx,
    required this.isAnchor,
    this.originT,
    this.originIdx,
  });
}

class _TrajectoryPainter extends CustomPainter {
  final List<_BeatPoint> beats;
  final Color color;
  final double cursorXFraction;
  final double rightPaddingFraction;

  final bool showDots;

  _TrajectoryPainter({
    required this.beats,
    required this.color,
    required this.cursorXFraction,
    required this.rightPaddingFraction,
    required this.showDots,
  });

  /// Le tracé passe par le centre des boîtes de niveau, donc par le curseur.
  static const double _verticalInset = _kLevelBox / 2;

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

    final maxIdx = _kLevelSlots - 1;
    Offset toOffset(_BeatPoint p) =>
        Offset(startX + p.t * span, _verticalInset + p.idx / maxIdx * usableH);

    final path = Path();
    final p0 = toOffset(beats.first);
    path.moveTo(p0.dx, p0.dy);
    for (var i = 1; i < beats.length; i++) {
      final prev = toOffset(beats[i - 1]);
      final cur = toOffset(beats[i]);
      final dx = cur.dx - prev.dx;
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

    if (!showDots) return;

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
        old.showDots != showDots ||
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

const double _kCursorX = -0.1;

/// Un `Align` ne centre ses enfants sur la même ordonnée que s'ils ont la
/// même hauteur. Égale au plus grand curseur.
const double _kLevelBox = 28;

/// Le niveau `balls` garde toujours sa place, affiché ou non : la piste en
/// image descend jusqu'aux bourses.
final int _kLevelSlots = Position.values.length;

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

/// Asset externalisé sur R2 : absent d'un build local ou de la CI.
class _Shaft extends StatelessWidget {
  const _Shaft();

  static const String asset = 'assets/courbe/piste_penis.png';
  static const double _assetW = 58;
  static const double _assetH = 201;
  static const double _assetTipY = 3;
  static const double _assetFullY = 149;
  static const double _opacity = 0.85;

  static final _probes = Expando<_ShaftProbe>();

  @override
  Widget build(BuildContext context) {
    final bundle = DefaultAssetBundle.of(context);
    final probe = _probes[bundle] ??= _ShaftProbe(bundle);
    return FutureBuilder<bool>(
      future: probe.available,
      initialData: probe.known,
      builder: (context, snapshot) => switch (snapshot.data) {
        true => _image(),
        false => const _ShaftBackdrop(),
        null => const SizedBox.shrink(),
      },
    );
  }

  Widget _image() {
    return LayoutBuilder(builder: (context, box) {
      final usable = box.maxHeight - _kLevelBox;
      double levelY(Position p) =>
          _kLevelBox / 2 + p.index / (_kLevelSlots - 1) * usable;
      final scale = (levelY(Position.full) - levelY(Position.tip)) /
          (_assetFullY - _assetTipY);
      final width = _assetW * scale;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (_kCursorX + 1) / 2 * box.maxWidth - width / 2,
            top: levelY(Position.tip) - _assetTipY * scale,
            width: width,
            height: _assetH * scale,
            child: Opacity(
              opacity: _opacity,
              child: Image.asset(
                asset,
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _ShaftProbe {
  bool? known;
  late final Future<bool> available;

  _ShaftProbe(AssetBundle bundle) {
    // flutter_test sans asset : `load` lève avant de rendre un Future.
    available = Future.sync(() => bundle.load(_Shaft.asset))
        .then((_) => known = true, onError: (_) => known = false);
  }
}

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
