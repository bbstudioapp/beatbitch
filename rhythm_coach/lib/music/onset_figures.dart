import 'beat_pattern.dart';

/// Banque **curée** de figures rythmiques (axe onset, cf. `specs/music_mode.md`
/// §8). Chaque figure ne porte que la *nature* des slots — la profondeur des
/// frappes est assignée ensuite par le contour (cf. `depth_contour.dart`).
///
/// Notation d'une mesure (8 slots / croches) :
///   `o` frappe · `.` release (remonte) · `_` hold (tient) · `-`/espace ignoré.
class OnsetFigure {
  final String id;

  /// Niveau de difficulté (densité / syncope) — sert au gating par phrase.
  final int level;

  final List<SlotOnset> onsets;

  const OnsetFigure(this.id, this.level, this.onsets);
}

List<SlotOnset> _parse(String s) {
  final out = <SlotOnset>[];
  for (final ch in s.split('')) {
    switch (ch) {
      case 'o':
        out.add(SlotOnset.strike);
      case '.':
      case '·': // ·
        out.add(SlotOnset.release);
      case '_':
        out.add(SlotOnset.hold);
      case '-':
      case ' ':
        break; // séparateur ignoré
      default:
        throw ArgumentError('Caractère de figure inconnu : "$ch" dans "$s"');
    }
  }
  if (!out.contains(SlotOnset.strike)) {
    throw ArgumentError('Figure sans frappe : "$s"');
  }
  return out;
}

OnsetFigure _fig(String id, int level, String slots) =>
    OnsetFigure(id, level, _parse(slots));

/// Banque de départ (PR1). Volontairement petite et lisible — on l'étoffe au
/// fil des retours d'usage.
final List<OnsetFigure> onsetFigureBank = [
  // Niveau 1 — régulier, sur le temps, doux.
  _fig('quarter', 1, 'o.o.o.o.'),
  _fig('breath_gap', 1, 'o.o...o.'),
  _fig('hold_soft', 1, 'o_o.o_o.'),
  // Niveau 2 — plus dense, un trou.
  _fig('gallop', 2, 'o.oo.oo.'),
  _fig('anchor_gap', 2, 'o.o.o...'),
  _fig('eighths', 2, 'oo.o.oo.'),
  // Niveau 3 — syncope / montée.
  _fig('clave', 3, 'o.oo.o.o'),
  _fig('build', 3, 'o_o_oo.o'),
  _fig('syncope', 3, '.oo.o.oo'),
];
