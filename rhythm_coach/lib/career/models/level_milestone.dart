import '../../models/session_step.dart';
import 'capability_requirement.dart';
import 'specialization.dart';
import 'unlock_key.dart';

/// Où placer la milestone dans la séance générée.
///
/// - `body` (default) : la séquence est insérée dans le corps de séance
///   (fenêtre `[insertAtMinSeconds, insertAtMaxSeconds]`). C'est une
///   parenthèse pédagogique entre la chauffe et le finish.
/// - `finalApotheose` : la séquence remplace la phase finish (boosts +
///   `_pickFinal`). Elle EST le final de la séance — la coach est
///   proche de l'apothéose, on attend l'orgasme avec elle. Ton plus
///   directif, pas pédagogique. Cf. milestones `intro_final_*`.
enum MilestonePlacement { body, finalApotheose }

/// Une milestone : séquence pédagogique imposée, qui débloque une ou
/// plusieurs `UnlockKey` une fois acquittée. Cf. E3 du plan.
///
/// **Sélection par humiliation + minLevel** : une milestone devient
/// candidate quand `playerMaxLevel ≥ minLevel` ET que le score
/// d'humiliation courant atteint `humilRequired - tolerance(obedience)`,
/// où `tolerance = 1 + obedience/50`. Le `minLevel` (champ `level` du
/// JSON) sert de garde-fou explicite : une milestone à humilRequired=0
/// ne doit pas tomber dès la première session si elle est pédagogiquement
/// « avancée » — l'auteur l'ancre à un niveau global minimum.
class LevelMilestone {
  /// Identifiant stable (ex: `"intro_hold_throat_short"`).
  final String id;

  /// Niveau global minimum pour que la milestone soit candidate. Lu
  /// depuis le champ `level` du JSON (rétro-compat avec l'ancien
  /// schéma). Default 1 → toujours candidate côté niveau, c'est
  /// l'humiliation qui filtre.
  final int minLevel;

  /// Humiliation maximale exigée par un step de la séquence. Calculée par
  /// le `MilestoneLoader` via `HumiliationScale.requiredFor` sur chaque
  /// step. Sert de seuil de candidature : la milestone n'est servie que
  /// quand `humilCurrent + 1 + obedience/50 ≥ humilRequired`.
  final double humilRequired;

  /// Libellé court affichable dans l'UI ("Première gorge tenue").
  final String displayLabel;

  /// Suite d'étapes imposées (avec `time` relatifs au début de la séquence).
  final List<SessionStep> sequence;

  /// Durée totale de la séquence en secondes (somme des durations).
  final int durationSeconds;

  /// Unlocks accordés à la complétion sans fail.
  final List<UnlockKey> unlocks;

  /// Si non vides, ces unlocks doivent avoir été acquittés au préalable
  /// pour que cette milestone soit candidate.
  final List<UnlockKey> requires;

  /// Seuils de télémétrie à franchir pour que la milestone soit candidate
  /// (gating capacité, 2ᵉ couche orthogonale à `humilRequired` et
  /// `minLevel`). Chaque entrée exige `best ≥ min` (ou `best ≤ min` pour
  /// les axes `minimize`) sur l'axe nommé. Liste vide = pas de gating
  /// télémétrie (mode hérité — seuls humil/level pilotent).
  ///
  /// Cf. doc local `~/beatbitch_career_unlocks_handoff.md` (passe 2).
  /// Quand `requiresCapability` est non vide, le `minLevel` devient un
  /// plancher mou de secours — la capacité prouvée pilote l'apparition.
  final List<CapabilityRequirement> requiresCapability;

  /// Plancher d'insertion : la milestone ne peut être insérée avant cette
  /// borne (en secondes depuis le début de la session). `null` → default 60.
  final int? insertAtMinSeconds;

  /// Plafond d'insertion : la milestone doit être insérée avant cette
  /// borne. `null` → default 0.4 × durée totale de la session générée.
  final int? insertAtMaxSeconds;

  /// Nombre maximum de retries autorisés sur fail dans la fenêtre milestone
  /// avant de tomber sur le flow fail standard.
  final int maxRetry;

  /// Si vrai, la session contenant cette milestone exige `includeHand=true`.
  /// Utilisé pour les milestones dont la séquence intègre du `hand` ou du
  /// `biffle` (ex: intro_basics, intro_biffle) — sans la main, les bips
  /// dédiés ne déclenchent pas et le scénario pédagogique perd son sens.
  /// Le toggle UI est forcé et grisé pour la séance concernée.
  final bool requiresHands;

  /// Branches de spécialisation associées à cette milestone. Sert au
  /// `MilestoneService.pendingFor(...)` pour prioriser les milestones
  /// dont au moins une branche correspond aux points investis par
  /// l'utilisatrice (cf. doc « Sélection milestone par spé + humil »).
  /// Liste vide = transverse (aucune branche dominante).
  ///
  /// Multi-branches : un milestone peut « parler » à plusieurs profils
  /// (ex: `endurance + resilience` pour un hold long sous pression). Le
  /// score de tri **somme** les points investis dans toutes les branches
  /// listées — une milestone qui couvre plusieurs spés choisies par la
  /// joueuse est donc strictement prioritaire sur une milestone mono-
  /// branche qui ne touche qu'une seule de ses spés.
  final List<SpecializationBranch> branches;

  /// Placement de la séquence dans la séance générée. Cf.
  /// [MilestonePlacement]. Default `body`.
  final MilestonePlacement placement;

  const LevelMilestone({
    required this.id,
    required this.humilRequired,
    required this.displayLabel,
    required this.sequence,
    required this.durationSeconds,
    required this.unlocks,
    this.minLevel = 1,
    this.requires = const [],
    this.requiresCapability = const [],
    this.insertAtMinSeconds,
    this.insertAtMaxSeconds,
    this.maxRetry = 1,
    this.requiresHands = false,
    this.branches = const [],
    this.placement = MilestonePlacement.body,
  });
}
