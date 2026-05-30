import '../models/session_step.dart' show Position;

/// Mode Music — grammaire de base d'une figure de mesure.
///
/// Cf. `specs/music_mode.md` §5. Le beat de la musique tombe sur le `to`
/// (impact profond) ; le `from`/ancre est la remontée hors-temps.

/// Nature d'un slot sur la grille de battements (§5.1).
enum SlotOnset {
  /// Plonge sur `to` pile sur le beat (impact).
  strike,

  /// Remonte vers l'ancre `from` (relâche / souffle).
  release,

  /// Reste sur le `to` de la frappe précédente (tient en profondeur).
  hold,
}

/// Un slot de la grille : sa nature, et pour une frappe, sa profondeur cible.
class BeatSlot {
  final SlotOnset onset;

  /// Profondeur d'impact. Non-null **uniquement** pour [SlotOnset.strike].
  final Position? to;

  const BeatSlot.strike(Position this.to) : onset = SlotOnset.strike;
  const BeatSlot.release()
      : onset = SlotOnset.release,
        to = null;
  const BeatSlot.hold()
      : onset = SlotOnset.hold,
        to = null;
}

/// Figure jouable d'une mesure : la séquence de slots, l'ancre de remontée,
/// et le tempo des slots (déjà mappé sous les plafonds de capacités).
class BeatPattern {
  final List<BeatSlot> slots;

  /// Ancre `from` : profondeur de remontée sur un [SlotOnset.release].
  final Position anchor;

  /// Tempo des slots en battements/minute (déjà borné par les plafonds).
  final int bpm;

  const BeatPattern({
    required this.slots,
    required this.anchor,
    required this.bpm,
  });
}
