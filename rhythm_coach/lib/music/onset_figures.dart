import 'beat_pattern.dart';

/// Banque **curée** de figures rythmiques (axe onset, cf. `specs/music_mode.md`
/// §8).
///
/// Modèle du mouvement : on alterne **ancre** (remontée, 1 battement) et
/// **plongée** — « une ancre 1 fois sur 2 ». Une plongée fait `d` battements en
/// bas (1ᵉʳ = la **frappe**, les suivants = des **holds**). `d` est **impair** :
/// - `1` = simple frappe (ancre avant, ancre après),
/// - `3, 5, 7…` = la plongée « saute » 1, 2, 3 ancres (chaque saut ajoute 2
///   battements de hold). Une longueur paire casserait l'alternance ancre/frappe.
class OnsetFigure {
  final String id;

  /// Niveau de difficulté (densité / longueur des holds) — gating par phrase.
  final int level;

  /// Longueurs des plongées successives (battements en bas), chacune **impaire**.
  final List<int> plunges;

  const OnsetFigure(this.id, this.level, this.plunges);

  /// Déploie en slots : pour chaque plongée `d`, la **frappe** d'abord puis
  /// `d-1` holds puis l'**ancre** (release). Le 1ᵉʳ temps est donc une frappe
  /// (pas une ancre) ; la dernière ancre précède cycliquement la 1ʳᵉ frappe.
  /// `d-1` est pair → l'alternance ancre/frappe est préservée.
  List<SlotOnset> expand() => [
        for (final d in plunges) ...[
          SlotOnset.strike,
          for (var i = 1; i < d; i++) SlotOnset.hold,
          SlotOnset.release,
        ],
      ];
}

/// Banque de départ (PR1). Petite et lisible — on l'étoffe au fil des retours.
/// Toutes les plongées sont impaires (cf. [OnsetFigure]).
const List<OnsetFigure> onsetFigureBank = [
  // Niveau 1 — pompe régulière, peu ou pas de holds.
  OnsetFigure('steady', 1, [1, 1, 1, 1]),
  OnsetFigure('steady_long', 1, [1, 1, 1, 1, 1, 1]),
  OnsetFigure('one_hold', 1, [1, 1, 3, 1]),
  // Niveau 2 — des holds courts (saut d'une ancre).
  OnsetFigure('holds', 2, [3, 1, 3, 1]),
  OnsetFigure('mixed', 2, [1, 3, 1, 1, 3]),
  OnsetFigure('hold5', 2, [5, 1, 1]),
  // Niveau 3 — holds longs (sauts multiples).
  OnsetFigure('long_hold', 3, [1, 7, 1]),
  OnsetFigure('deep', 3, [5, 1, 5, 1]),
  OnsetFigure('climb', 3, [1, 3, 5, 1]),
];
