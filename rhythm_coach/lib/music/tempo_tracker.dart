import 'dart:math';

/// Résultat d'une estimation de tempo (cf. `specs/music_mode.md` PR2).
class TempoEstimate {
  /// Tempo estimé (battements/minute).
  final double bpm;

  /// Phase : temps (ms) d'un battement, modulo la période. Les battements
  /// tombent à `anchorMs + k × 60000/bpm`.
  final int anchorMs;

  /// Confiance ∈ [0, 1] : à quel point les onsets sont alignés sur cette
  /// période (1 = parfaitement réguliers).
  final double confidence;

  const TempoEstimate({
    required this.bpm,
    required this.anchorMs,
    required this.confidence,
  });
}

/// Estimateur de tempo (pur, testable). On lui pousse des **onsets**
/// (timestamps ms d'attaques détectées dans l'audio) ; il rend le BPM + la
/// phase + une confiance.
///
/// Méthode — **statistiques circulaires** : pour chaque période candidate `T`,
/// on projette chaque onset sur le cercle d'angle `2π·onset/T` et on mesure la
/// **longueur résultante** (1 = onsets parfaitement en phase à cette période,
/// ~0 = dispersés). La période la plus alignée gagne ; sa longueur résultante
/// sert de confiance et son angle moyen donne la phase. Octave : la plage BPM
/// bornée limite le repli moitié/double ; à égalité on garde le tempo le plus
/// lent (le débit d'onsets).
class TempoTracker {
  final double minBpm;
  final double maxBpm;
  final double stepBpm;

  /// Fenêtre glissante d'onsets considérés.
  final int windowMs;

  /// Minimum d'onsets pour tenter une estimation.
  final int minOnsets;

  final List<int> _onsets = [];

  TempoTracker({
    this.minBpm = 70,
    this.maxBpm = 160,
    this.stepBpm = 0.5,
    this.windowMs = 6000,
    this.minOnsets = 6,
  });

  void addOnset(int ms) {
    _onsets.add(ms);
    final cutoff = ms - windowMs;
    _onsets.removeWhere((t) => t < cutoff);
  }

  void clear() => _onsets.clear();

  int get onsetCount => _onsets.length;

  TempoEstimate? estimate() {
    if (_onsets.length < minOnsets) return null;
    var bestStrength = -1.0;
    var bestBpm = 0.0;
    var bestPhase = 0.0;
    for (var bpm = minBpm; bpm <= maxBpm; bpm += stepBpm) {
      final t = 60000.0 / bpm;
      var re = 0.0, im = 0.0;
      for (final o in _onsets) {
        final ph = 2 * pi * (o / t);
        re += cos(ph);
        im += sin(ph);
      }
      final strength = sqrt(re * re + im * im) / _onsets.length;
      if (strength > bestStrength) {
        bestStrength = strength;
        bestBpm = bpm;
        bestPhase = atan2(im, re); // -π..π
      }
    }
    final t = 60000.0 / bestBpm;
    var anchor = (bestPhase / (2 * pi)) * t;
    anchor %= t;
    if (anchor < 0) anchor += t;
    return TempoEstimate(
      bpm: bestBpm,
      anchorMs: anchor.round(),
      confidence: bestStrength,
    );
  }
}
