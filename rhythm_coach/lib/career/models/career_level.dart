import 'dart:math';

/// Configuration de difficulté d'un niveau de carrière. Calculée
/// analytiquement à partir du numéro de niveau (pas de table figée).
class CareerLevel {
  /// Numéro du niveau (1 = débutant).
  final int level;

  /// Borne haute absolue de la fenêtre de tirage (`diff ∈ [0, 1]`).
  /// Plus le niveau monte, plus le dé peut atteindre des valeurs élevées.
  final double maxDifficultyCap;

  /// Multiplicateur de régénération en fin de séance (à `t = duration`).
  /// Augmente avec le niveau : plus on est avancé, plus la récup s'accélère
  /// vers la fin → moins de temps réel passé en récup, plus d'effort enchaîné.
  final double regenEndMultiplier;

  /// Durée nominale d'une séance à ce niveau, en secondes. Couple
  /// difficulté/endurance avec durée — niveau 1 court, niveau 15+ long.
  final int durationSeconds;

  /// Nombre de boosts émis pendant la phase finish. Scale avec le niveau
  /// pour allonger et durcir l'apothéose des paliers élevés. Le mode
  /// encore ajoute `encoreChainIndex * 2` par-dessus côté générateur.
  final int boostsCount;

  const CareerLevel({
    required this.level,
    required this.maxDifficultyCap,
    required this.regenEndMultiplier,
    required this.durationSeconds,
    required this.boostsCount,
  });

  /// Déduit la config d'un niveau N. Niveau 1 = doux et permissif ;
  /// chaque niveau ajoute ~5 points de plafond et accélère la récup en fin
  /// de séance. Plafonné à 1.0 / 3.0.
  factory CareerLevel.forLevel(int n) {
    final level = max(1, n);
    final cap = min(0.20 + 0.05 * level, 1.0);
    final regenEnd = min(1.2 + 0.15 * level, 3.0);
    return CareerLevel(
      level: level,
      maxDifficultyCap: cap,
      regenEndMultiplier: regenEnd,
      durationSeconds: _durationForLevel(level),
      boostsCount: _boostsCountForLevel(level),
    );
  }

  /// Mapping niveau → durée. Couple progression et endurance : un niveau
  /// 1 ne dure pas 30 min, un niveau 15 demande de tenir longtemps.
  static int _durationForLevel(int level) {
    if (level <= 2) return 5 * 60;
    if (level <= 4) return 8 * 60;
    if (level <= 7) return 12 * 60;
    if (level <= 10) return 18 * 60;
    if (level <= 14) return 25 * 60;
    if (level <= 17) return 35 * 60;
    return 45 * 60;
  }

  /// Nombre de boosts émis dans la phase finish. Plus on monte en niveau,
  /// plus la phase d'apothéose s'allonge — la séance niveau 1 reste tendue
  /// mais courte, la séance niveau 15+ enchaîne 5 boosts.
  static int _boostsCountForLevel(int level) {
    if (level <= 3) return 2;
    if (level <= 7) return 3;
    if (level <= 12) return 4;
    return 5;
  }
}
