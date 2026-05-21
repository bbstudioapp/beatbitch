import '../models/career_level.dart';

/// Point d'extraction unique des paramètres de difficulté de carrière dérivés
/// d'un niveau. Aujourd'hui purement wrapper sur [CareerLevel.forLevel]
/// (Phase 19.1, no-op fonctionnel). Sera rebranché en Phase 19.6 sur
/// `(CapabilityProfile, sessionsCompleted, totalSeconds, SessionLengthChoice)`
/// pour retirer la dépendance au `level`.
class CareerDifficultyResolver {
  const CareerDifficultyResolver._();

  /// Résout la config de difficulté pour un niveau donné. Délègue strictement
  /// à [CareerLevel.forLevel] — les call sites passent par cet accessor pour
  /// que la bascule de Phase 19.6 reste locale.
  static CareerLevel resolve(int level) => CareerLevel.forLevel(level);
}
