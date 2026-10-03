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
/// tenue. [beep] : le moteur joue le bip de [position] à cet instant, quand
/// le curseur y arrive.
class HoldKeyframe {
  final Duration at;
  final Position position;
  final bool beep;

  const HoldKeyframe(this.at, this.position, {this.beep = false});
}

/// Durée d'un trajet d'aller-retour : assez court pour rester un à-coup,
/// assez long pour qu'un trajet jusqu'au bout reste faisable.
Duration excursionLeg(Position from, Position to) =>
    Duration(milliseconds: 200 + 120 * (from.index - to.index).abs());

/// Instants clés de tous les mouvements d'une tenue sur [hold], triés. Les
/// mouvements qui se chevaucheraient sont ignorés (le premier gagne).
List<HoldKeyframe> holdKeyframes(Position hold, List<HoldMove> moves) {
  final out = <HoldKeyframe>[];
  var busyUntil = Duration.zero;
  final sorted = [...moves]..sort((a, b) => a.at.compareTo(b.at));
  for (final m in sorted) {
    final start = Duration(microseconds: (m.at * 1e6).round());
    if (start < busyUntil) continue;
    switch (m.kind) {
      case HoldMoveKind.excursion:
        final leg = excursionLeg(hold, m.to!);
        out
          ..add(HoldKeyframe(start, hold))
          ..add(HoldKeyframe(start + leg, m.to!, beep: true))
          ..add(HoldKeyframe(start + leg * 2, hold, beep: true));
        busyUntil = start + leg * 2;
      case HoldMoveKind.micro:
      case HoldMoveKind.lickBalls:
        break;
    }
  }
  return out;
}
