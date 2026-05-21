import 'dart:math';

import '../../models/session_step.dart';

/// Gates et seuils level-based de la génération de séance.
///
/// Phase 19.2 — extracts purs, sortie identique aux expressions inline
/// d'origine. Les noms reflètent l'**intention métier** pour guider le
/// rewire Phase 19.6 (où ces helpers consommeront `(CapabilityProfile,
/// sessionsCompleted, SessionLengthChoice)` au lieu de `level`).
///
/// Aucun helper ici ne touche au RNG ni à l'état — pure dérivation.
class CareerLevelGates {
  const CareerLevelGates._();

  /// Vrai pour les sessions « débutante » (level 1-2) hors bâclée / intense.
  /// Influe sur la pré-finition (raccourcie) et le pacing global.
  static bool isLowLevelIntro({
    required int level,
    required bool quickie,
    required bool intense,
  }) =>
      level <= 2 && !quickie && !intense;

  /// Vrai au-dessus du seuil d'éligibilité aux mini-vagues mid-session
  /// (cf. `_shouldEmitMiniWave`). En dessous, la diagonale d'intensité
  /// reste monotone du début au finish.
  static bool isMiniWaveEligible(int level) => level >= 5;

  /// Vrai quand la palette finale peut basculer sur la coloration spé
  /// (sloppy / obéissance) — au-delà, la dramaturgie tient.
  static bool canColorFinalBySpec(int level) => level >= 7;

  /// Vrai pour les premiers niveaux où le finish hand a une baseline BPM
  /// dédiée (40-60 BPM, sample-friendly pour une débutante).
  static bool usesShortHandFinalBaseline(int level) => level < 4;

  /// Coefficient « preferHandBase » du burst pré-finish : élevé en bas
  /// niveau peu humiliant (favorise hand neutre), réduit ensuite.
  static double burstHandPreference({
    required int level,
    required double humiliationCareer,
  }) =>
      humiliationCareer < 5 && level <= 3 ? 0.70 : 0.25;

  /// Bonus de BPM cap appliqué aux boosts finish, scale par niveau +
  /// chaîne d'encore (capé pour éviter les pics absurdes — le profil de
  /// capacités borne en pratique via `clampToCapability`).
  static int finishBpmBoostBpm({
    required int level,
    required int encoreChainIndex,
  }) =>
      ((level - 1) * 4 + max(0, encoreChainIndex) * 8).clamp(0, 70);

  /// Plafond de profondeur (index dans `Position.values`) par défaut pour
  /// une `SessionConfig`. Aujourd'hui constant (full ouvert) — sera
  /// rebranché en Phase 19.7 sur `rhythm.depth_max.comfort` du
  /// `CapabilityProfile`.
  static int defaultMaxDepthIndex() => Position.full.index;
}
