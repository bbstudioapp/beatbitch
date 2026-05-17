// Library autonome — value object `SessionConfig` : inputs figés d'une
// séance.
//
// Extrait de `career_session_generator.dart` : sa sortie en library
// autonome est préalable à l'extraction de `gen_facade.dart` (la
// facade expose `SessionConfig` comme field, donc elle ne peut pas
// rester `part of` du générateur sinon le `gen_facade.dart` autonome
// ne pourrait pas le référencer).
//
// **Pas dans `SessionConfig`** :
//   * `unlockedKeys` — muté en cours de séance quand une milestone est
//     acquittée (un step scripté étend l'ensemble des unlocks pour les
//     steps suivants). C'est conceptuellement un state, pas un input.
//   * Tout l'état runtime (`_lastFoo`, `_stepsInLastType`, simulations
//     salive, etc.) qui mute à chaque step poussé.

import '../../../models/anatomy_profile.dart';
import '../../../models/session.dart';
import '../../../services/capability_axis.dart';
import '../../../services/capability_service.dart';
import '../../../services/humiliation_engine.dart';
import '../../models/specialization.dart';

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
class SessionConfig {
  const SessionConfig({
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

  // ─── Méthodes dérivées (pures, lisent uniquement les fields ci-dessus) ───

  /// True si le mode est exclu par le caller via `coachModeWeights[m] == 0`.
  /// Un coach normal ne pose jamais 0 (cf. CoachMeta) → toujours false hors
  /// Custom. En Custom, c'est le dosage `none` de `CustomSessionConfig` qui
  /// pose le 0 et qui doit être honoré partout (palette finale, mini-vagues,
  /// pré-finisher, intro, recovery…), pas seulement dans `_pickWeightedMode`.
  bool isModeForbidden(SessionMode m) {
    final w = coachModeWeights[m];
    return w != null && w <= 0;
  }

  /// Points investis dans la branche [b] (lecture courte de `spec`).
  int pts(SpecializationBranch b) => spec.pointsIn(b);

  /// Applique aux durées les multiplicateurs de spé, capés. `enduranceFactor`
  /// = bonus par point Endurance ; `extraFactor` = bonus brut additionnel.
  int scaleDuration(
    double base, {
    double enduranceFactor = 0.0,
    double extraFactor = 0.0,
  }) {
    final mul = 1.0 +
        enduranceFactor * pts(SpecializationBranch.endurance) +
        extraFactor;
    final capped = mul.clamp(1.0, 1.6);
    return (base * capped).round();
  }

  /// Cap effectif d'humiliation projeté au temps `seconds` depuis le
  /// début de la session générée. Modèle 2 thermomètres :
  ///
  ///   `cap(t) = career + min(session + tickRate × t/60, sessionCap)`
  ///
  /// avec `tickRate = 1 × accel(obed)` (cf. `HumiliationEngine.onTickSecond`).
  /// La projection ne tient pas compte des bumps évènementiels (punition
  /// complétée, hold profond complété…) — c'est volontairement conservateur,
  /// le runtime peut accepter des actions un poil plus dures que ce que la
  /// rampe seule prédit.
  double humilCapAt(int seconds) {
    final accel = (1.0 + obedience / 100.0).clamp(1.0, 3.0);
    final tickRate = HumiliationEngine.bumpPerInterval * accel; // par minute
    final added = tickRate * seconds / 60.0;
    final session =
        (humiliationSession + added).clamp(0.0, HumiliationEngine.sessionCap);
    return humiliationCareer + session;
  }
}
