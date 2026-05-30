import '../models/session_step.dart' show Position;

/// Action de slot produite par le `MusicSessionEngine` et consommée par le
/// binding audio (`BeepEngine`, bloc 4) et l'UI (courbe de profondeur).
/// Cf. `specs/music_mode.md` §5.1.
enum SlotActionKind {
  /// Plonge sur [depth] (impact sur le battement).
  strike,

  /// Remonte vers l'ancre ([depth] = `from`).
  release,

  /// Tient [depth] (profondeur de la dernière frappe).
  hold,
}

class SlotAction {
  final SlotActionKind kind;

  /// Profondeur concernée : la cible pour `strike`, la profondeur tenue pour
  /// `hold`, l'ancre `from` pour `release`. Toujours renseignée.
  final Position depth;

  /// Battement de l'horloge qui a déclenché l'action.
  final int beatIndex;

  /// Tempo courant (battements/minute).
  final double bpm;

  /// Pour une frappe : vraie si elle **amorce un hold** (suivie de holds) — le
  /// son doit alors être celui d'un hold, pas d'une plongée.
  final bool sustained;

  const SlotAction({
    required this.kind,
    required this.depth,
    required this.beatIndex,
    required this.bpm,
    this.sustained = false,
  });
}
