/// Catégorie du final d'une séance, utilisée pour piocher la bonne variante
/// de `finale_chime` (cf. `assets/audio/finale_chimes.json`).
///
/// Mapping (cf. `_pickFinal` dans `CareerSessionGenerator`) :
/// - `easy`    : hand 60/70, hold tip
/// - `medium`  : hold head, hold mid, biffle 80
/// - `hard`    : hold throat
/// - `extreme` : hold full
enum FinalCategory {
  easy,
  medium,
  hard,
  extreme;

  String get serialized => name;

  static FinalCategory? fromString(String? raw) {
    if (raw == null) return null;
    for (final c in FinalCategory.values) {
      if (c.serialized == raw) return c;
    }
    return null;
  }
}
