import 'dart:math';

import '../../models/session_step.dart';
import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';

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
  /// une `SessionConfig` quand aucun profil de capacités n'est fourni
  /// (Custom mode, debug, surprise router). Full ouvert — la difficulté
  /// effective est gated en aval par `_clampToCapability` quand un
  /// profil est dispo.
  static int defaultMaxDepthIndex() => Position.full.index;

  /// Plafond de profondeur dérivé du `CapabilityProfile` (Phase 19.7).
  /// Lit `rhythm.depth_max.comfort` (en cran, double), l'arrondit et le
  /// borne dans `[head, full]`.
  ///
  /// Plancher à `head` (= idx 1) : `tip` n'est jamais une borne haute
  /// utile (une joueuse sans profil démarre déjà avec des actions
  /// `tip`/`head` débloquées par les milestones d'intro). Plafond à
  /// `full` (= idx 4) : on n'autorise pas `balls` via ce mécanisme —
  /// l'anatomie balls a son propre gating.
  ///
  /// Quand le profil ne porte pas encore de donnée pour cet axe
  /// (joueuse neuve, axe jamais sollicité), on retombe sur
  /// [defaultMaxDepthIndex] (= full ouvert) — `_clampToCapability` côté
  /// générateur évite que le tirage déborde, le profil se remplira sur
  /// les premières séances.
  static int maxDepthIndexForProfile(CapabilityProfile? profile) {
    if (profile == null) return defaultMaxDepthIndex();
    final comfort = profile.comfortOf(CapabilityAxis.rhythmDepthMax);
    if (comfort == null) return defaultMaxDepthIndex();
    final rounded = comfort.round();
    return rounded.clamp(Position.head.index, Position.full.index);
  }
}
