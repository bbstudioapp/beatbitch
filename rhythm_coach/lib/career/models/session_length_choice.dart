/// Palier de durée d'une séance carrière. Sélecteur UX qui remplacera le
/// picker de niveau (cf. Phase 19.4) — pour l'instant (Phase 19.3) c'est
/// un paramètre additif optionnel du générateur, le picker UI reste
/// pilote du level.
///
/// Quatre paliers fungibles avec milestones/défis (cf. roadmap Phase 19) :
///
/// | Palier  | Durée   | Events totaux | Body milestones max |
/// |---------|---------|---------------|---------------------|
/// | bachee  | ~6 min  | 1             | 1                   |
/// | courte  | ~12 min | 2             | 1                   |
/// | moyenne | ~25 min | 3             | 2                   |
/// | longue  | ~45 min | 4             | 2                   |
///
/// La bâclée garde son nom et reste portée par le flag `quickie` pour
/// l'intensityFloor (0.65) ; la durée 6 min est l'alignement de ce
/// palier sur le mécanisme existant. La fusion sémantique
/// `bachee ⇔ quickie` est tranchée en Phase 19.4.
enum SessionLengthChoice {
  bachee(360),
  courte(720),
  moyenne(1500),
  longue(2700);

  const SessionLengthChoice(this.durationSeconds);

  /// Durée nominale du palier en secondes. Passée telle quelle au
  /// générateur — peut être surchargée explicitement via le paramètre
  /// `durationSeconds` (priorité plus haute, cas debug / surprise).
  final int durationSeconds;
}
