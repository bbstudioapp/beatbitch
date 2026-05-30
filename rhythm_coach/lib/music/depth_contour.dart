import 'dart:math';

import '../models/session_step.dart' show Position;

/// Contour de profondeur (axe depth, cf. `specs/music_mode.md` §5.2).
///
/// Assigne un `to` à chaque frappe d'une figure. Invariants garantis :
/// - chaque `to` est **strictement plus profond** que l'ancre `from` ;
/// - `to` ne dépasse jamais [maxDepth] (lui-même borné par `rhythmDepthMax`) ;
/// - deux frappes consécutives **diffèrent** (pas de bégaiement sur place,
///   cf. l'invariant `from > to` réinterprété par transition).
enum ContourFamily {
  /// Deux profondeurs en va-et-vient (A B A B).
  alternance,

  /// Montée/descente en escalier vers le plus profond (vague triangulaire).
  climb,

  /// Ancre basse + pics qui plongent de plus en plus profond
  /// (`mid throat mid full`…), exactement la famille « ancre-et-atteint ».
  reach,
}

class DepthContour {
  DepthContour._();

  static List<Position> generate({
    required int strikeCount,
    required Position anchor,
    required Position maxDepth,
    required ContourFamily family,
    required Random rng,
  }) {
    if (strikeCount <= 0) return const [];

    final lo = anchor.index + 1;
    final hi = min(maxDepth.index, Position.full.index);
    final choices = <Position>[
      for (var i = lo; i <= hi; i++) Position.values[i],
    ];
    if (choices.isEmpty) {
      // Cas dégénéré (ancre au plus profond autorisé) : un seul cran.
      final only = Position.values[max(lo, Position.mid.index).clamp(
        Position.head.index,
        Position.full.index,
      )];
      return List.filled(strikeCount, only);
    }

    return switch (family) {
      ContourFamily.alternance => _alternance(strikeCount, choices, rng),
      ContourFamily.climb => _climb(strikeCount, choices),
      ContourFamily.reach => _reach(strikeCount, choices),
    };
  }

  static List<Position> _alternance(int n, List<Position> choices, Random rng) {
    final a = choices.first;
    final b =
        choices.length == 1 ? a : choices[1 + rng.nextInt(choices.length - 1)];
    final lo = a.index <= b.index ? a : b;
    final hi = a.index <= b.index ? b : a;
    return [for (var i = 0; i < n; i++) (i.isEven ? lo : hi)];
  }

  static List<Position> _climb(int n, List<Position> choices) {
    final l = choices.length;
    if (l == 1) return List.filled(n, choices.first);
    final out = <Position>[];
    var i = 0, dir = 1;
    for (var k = 0; k < n; k++) {
      out.add(choices[i]);
      i += dir;
      if (i == l - 1) {
        dir = -1;
      } else if (i == 0) {
        dir = 1;
      }
    }
    return out;
  }

  static List<Position> _reach(int n, List<Position> choices) {
    final base = choices.first;
    if (choices.length == 1) return List.filled(n, base);
    final peaks = choices.sublist(1);
    final out = <Position>[];
    var p = 0;
    for (var k = 0; k < n; k++) {
      if (k.isEven) {
        out.add(base);
      } else {
        out.add(peaks[min(p, peaks.length - 1)]);
        p++;
      }
    }
    return out;
  }
}
