import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';

/// Prérequis de candidature d'une milestone porté par un axe du profil de
/// capacités : la milestone n'est candidate que si la joueuse a `best`
/// franchi le seuil [min] sur l'axe [axis].
///
/// Sert de seconde couche de gating, orthogonale aux thermomètres humil /
/// obédiance et au `level` (le `level` reste comme plancher mou de
/// secours pour les milestones précoces et tutos qui n'ont pas de
/// télémétrie à consulter). Quand un `requiresCapability` est attaché à
/// une milestone, c'est la *capacité prouvée* qui pilote l'apparition —
/// pas le compteur de sessions. Cf. doc local
/// `~/beatbitch_career_unlocks_handoff.md`.
class CapabilityRequirement {
  final CapabilityAxis axis;
  final double min;

  const CapabilityRequirement({required this.axis, required this.min});

  /// Vrai si le profil porte un `best` qui satisfait le seuil.
  ///
  /// - Axe `maximize` / `accumulate` : `best >= min`.
  /// - Axe `minimize` (planchers BPM, dose minimale de breath) :
  ///   `best <= min` (la cible étant « plus lent » / « plus court »).
  /// - Pas de donnée (`best == null`) : non satisfait — la milestone n'est
  ///   pas candidate tant que l'axe n'a rien produit.
  bool isSatisfiedBy(CapabilityProfile profile) {
    final best = profile.bestOf(axis);
    if (best == null) return false;
    if (axis.recordKind == CapabilityRecordKind.minimize) {
      return best <= min;
    }
    return best >= min;
  }
}
