// Fichier part de `career_session_generator.dart` — value object
// `_SessionConfig` : inputs figés d'une séance.
//
// Le générateur expose une grosse surface de paramètres (`generate(...)`
// + `generatePunishment(...)`). Plutôt que de les répartir en ~16 fields
// d'instance mutables (chacun reset au début de chaque session par une
// assignation explicite), on les regroupe ici dans un value object
// immuable.
//
// Le generator garde un `late _SessionConfig _config` (re-posé en début
// de chaque `generate()` / `generatePunishment()`) et y accède via des
// getters d'instance `_level => _config.level` etc. — l'API interne du
// generator reste inchangée, mais l'invariant « ces 16 valeurs sont
// figées pour la séance » est désormais enforced par le langage.
//
// **Pas dans `_SessionConfig`** :
//   * `_unlockedKeys` — muté en cours de séance quand une milestone est
//     acquittée (un step scripté étend l'ensemble des unlocks pour les
//     steps suivants). C'est conceptuellement un state, pas un input.
//   * Tout l'état runtime (`_lastFoo`, `_stepsInLastType`, simulations
//     salive, etc.) qui mute à chaque step poussé.

part of 'career_session_generator.dart';

/// Snapshot immuable des inputs d'une séance, posé en début de
/// `generate()` / `generatePunishment()`. Lecture seule pour toute la
/// durée de l'opération.
///
/// Champs regroupés par catégorie :
///   * Bornes globales (`level`, `includeHand`, `maxDepthIndex`,
///     `deepProbability`).
///   * Profil joueuse (`spec`, `anatomy`, `coachModeWeights`).
///   * Bornes utilisateur Custom (`bpmRange`, `holdDurationRange`).
///   * Scores au moment t=0 (`humiliationCareer`, `humiliationSession`,
///     `obedience`).
///   * Profil capacités + surcharge déduite (`capProfile`, `capCeilings`,
///     `overloadAxis`, `overloadFactor`).
class _SessionConfig {
  const _SessionConfig({
    required this.level,
    required this.includeHand,
    required this.maxDepthIndex,
    required this.deepProbability,
    required this.spec,
    required this.anatomy,
    required this.coachModeWeights,
    required this.bpmRange,
    required this.holdDurationRange,
    required this.humiliationCareer,
    required this.humiliationSession,
    required this.obedience,
    required this.capProfile,
    required this.capCeilings,
    required this.overloadAxis,
    required this.overloadFactor,
  });

  // Bornes globales
  final int level;
  final bool includeHand;
  final int maxDepthIndex;
  final double deepProbability;

  // Profil joueuse
  final SpecializationAllocation spec;
  final AnatomyProfile anatomy;
  final Map<SessionMode, double> coachModeWeights;

  // Bornes utilisateur Custom (null hors Custom = pas de bornage)
  final (int, int)? bpmRange;
  final (int, int)? holdDurationRange;

  // Scores au moment t=0
  final double humiliationCareer;
  final double humiliationSession;
  final double obedience;

  // Profil capacités + surcharge déduite en début de séance
  final CapabilityProfile? capProfile;
  final Map<CapabilityAxis, double> capCeilings;
  final CapabilityAxis? overloadAxis;
  final double overloadFactor;
}
