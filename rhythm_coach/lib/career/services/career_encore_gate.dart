import '../models/unlock_key.dart';
import 'milestone_service.dart';

/// Évalue si le bouton « J'en veux encore » doit être proposé sur l'écran
/// de fin de session.
///
/// Conditions cumulatives :
/// - **niveau ≥ 5** (cap absolu — pas d'encore aux premiers paliers)
/// - ET (a) milestone `intro_encore` acquittée ET
///   (humil ≥ 30 OU obed ≥ 50) pour la voie pédagogique normale,
/// - OU (b) `obed ≥ 80` pour la voie alternative — la salope a démontré
///   sa docilité, on lui ouvre l'encore sans milestone.
///
/// Centralisé pour pouvoir être consommé depuis :
/// - `_CareerScreenState._start` (session normale)
/// - `_CareerScreenState._handleEncore` (chaînage encore)
/// - `SurpriseRouter` (session surprise déclenchée par notif)
class CareerEncoreGate {
  CareerEncoreGate._();

  static bool canEncore({
    required int level,
    required double humiliationScore,
    required double obedienceScore,
    required MilestoneService milestoneService,
  }) {
    if (level < 5) return false;
    if (obedienceScore >= 80.0) return true;
    final hasMilestone =
        milestoneService.acquiredUnlockKeys().contains(UnlockKey.encore);
    if (!hasMilestone) return false;
    return humiliationScore >= 30.0 || obedienceScore >= 50.0;
  }
}
