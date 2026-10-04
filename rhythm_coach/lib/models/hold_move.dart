import 'session_step.dart';

/// Mouvement ponctuel demandé pendant une tenue.
enum HoldMoveKind {
  /// Aller-retour rapide vers [HoldMove.to], plus haut ou plus profond, puis
  /// retour immédiat sur la position tenue.
  excursion,
  micro,
  lickBalls;

  static HoldMoveKind? fromString(String? raw) => switch (raw) {
        'excursion' => HoldMoveKind.excursion,
        'micro' => HoldMoveKind.micro,
        'lick_balls' => HoldMoveKind.lickBalls,
        _ => null,
      };

  String get serialized => switch (this) {
        HoldMoveKind.excursion => 'excursion',
        HoldMoveKind.micro => 'micro',
        HoldMoveKind.lickBalls => 'lick_balls',
      };
}

class HoldMove {
  final HoldMoveKind kind;

  /// Départ du mouvement, en secondes depuis le début réel de la tenue (son
  /// premier bip, après le gap de transition).
  final double at;

  final Position? to;
  final double? duration;

  const HoldMove({
    required this.kind,
    required this.at,
    this.to,
    this.duration,
  });

  /// Un mouvement mal formé est ignoré plutôt que de casser la séance.
  static HoldMove? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = HoldMoveKind.fromString(raw['type'] as String?);
    final at = raw['at'];
    if (kind == null || at is! num || at < 0) return null;
    final to = Position.fromString(raw['to'] as String?);
    if (kind == HoldMoveKind.excursion && to == null) return null;
    final duration = raw['duration'];
    return HoldMove(
      kind: kind,
      at: at.toDouble(),
      to: to,
      duration: duration is num ? duration.toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': kind.serialized,
        'at': at,
        if (to != null) 'to': to!.serialized,
        if (duration != null) 'duration': duration,
      };

  @override
  bool operator ==(Object other) =>
      other is HoldMove &&
      other.kind == kind &&
      other.at == at &&
      other.to == to &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(kind, at, to, duration);
}

/// Instant clé d'un mouvement de tenue, compté depuis le début réel de la
/// tenue. [idx] : position sur l'échelle (fractionnaire pour un
/// micro-mouvement). [beep] : le moteur joue le bip de cette position à cet
/// instant, au volume relatif [volume]. [tongue] : instant d'un léchage.
class HoldKeyframe {
  final Duration at;
  final double idx;
  final Position? beep;
  final double volume;
  final bool tongue;

  const HoldKeyframe(this.at, this.idx,
      {this.beep, this.volume = 1.0, this.tongue = false});
}

/// Durée d'un trajet d'aller-retour : assez court pour rester un à-coup,
/// assez long pour qu'un trajet jusqu'au bout reste faisable.
Duration excursionLeg(Position from, Position to) =>
    Duration(milliseconds: 200 + 120 * (from.index - to.index).abs());

/// Demi-période d'un micro-mouvement (~3 va-et-vient par seconde) et son
/// amplitude, en crans.
const Duration microHalfPeriod = Duration(milliseconds: 170);
const double microAmplitude = 0.4;
const double microTickVolume = 0.35;

/// Intervalle entre deux coups de langue d'un lick balls, et leur volume.
const Duration lickBallsPeriod = Duration(milliseconds: 450);
const double lickBallsVolume = 0.5;

/// Instants clés de chaque mouvement d'une tenue sur [hold], un groupe par
/// mouvement, triés. Un mouvement qui chevaucherait le précédent est ignoré.
List<List<HoldKeyframe>> holdMoveGroups(Position hold, List<HoldMove> moves) {
  final out = <List<HoldKeyframe>>[];
  final h = hold.index.toDouble();
  var busyUntil = Duration.zero;
  final sorted = [...moves]..sort((a, b) => a.at.compareTo(b.at));
  for (final m in sorted) {
    final start = Duration(microseconds: (m.at * 1e6).round());
    if (start < busyUntil) continue;
    switch (m.kind) {
      case HoldMoveKind.excursion:
        final leg = excursionLeg(hold, m.to!);
        out.add([
          HoldKeyframe(start, h),
          HoldKeyframe(start + leg, m.to!.index.toDouble(), beep: m.to),
          HoldKeyframe(start + leg * 2, h, beep: hold),
        ]);
        busyUntil = start + leg * 2;
      case HoldMoveKind.micro:
        final duration =
            Duration(microseconds: ((m.duration ?? 4) * 1e6).round());
        final peak =
            hold == Position.tip ? h + microAmplitude : h - microAmplitude;
        final frames = <HoldKeyframe>[HoldKeyframe(start, h)];
        var t = start;
        var up = true;
        while (t + microHalfPeriod <= start + duration || !up) {
          t += microHalfPeriod;
          frames.add(up
              ? HoldKeyframe(t, peak, beep: hold, volume: microTickVolume)
              : HoldKeyframe(t, h));
          up = !up;
        }
        out.add(frames);
        busyUntil = t;
      case HoldMoveKind.lickBalls:
        final end =
            start + Duration(microseconds: ((m.duration ?? 4) * 1e6).round());
        final frames = <HoldKeyframe>[HoldKeyframe(start, h, tongue: true)];
        for (var t = start + lickBallsPeriod; t <= end; t += lickBallsPeriod) {
          frames.add(HoldKeyframe(t, h,
              beep: Position.balls, volume: lickBallsVolume, tongue: true));
        }
        if (frames.last.at < end) {
          frames.add(HoldKeyframe(end, h, tongue: true));
        }
        out.add(frames);
        busyUntil = end;
    }
  }
  return out;
}

/// Tous les instants clés d'une tenue, à plat.
List<HoldKeyframe> holdKeyframes(Position hold, List<HoldMove> moves) =>
    [for (final g in holdMoveGroups(hold, moves)) ...g];
