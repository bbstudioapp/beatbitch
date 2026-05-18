// Library autonome — contexte partagé entre `generate()` et ses
// helpers (chaîne main loop, finish phase, milestone scheduler, etc.).
//
// Sorti du `part of 'career_session_generator.dart'` historique en
// D.PR7 du plan de refacto (partie 1 — extraction du value object) ;
// enrichi en D.PR7-2 avec les **compteurs courants** [time] /
// [stamina] / [progress] qui muent à chaque step émis. Les helpers
// d'émission consomment et mutent directement ces champs au lieu de
// les threader via paramètres + tuples de retour
// `({int time, double stamina})`.
//
// Construit une fois par `generate()` après que la difficulté, la
// durée et le bundle de contenu (coach, milestones) sont résolus.

import '../../../models/session_step.dart';
import '../../models/career_level.dart';
import '../../models/level_milestone.dart';
import '../../models/phrase_bank.dart';

/// Contexte mutable de la séance en cours de génération. Porte les
/// **paramètres figés** à l'ouverture (durée, configuration, bundles)
/// + le **curseur courant** ([time], [stamina]) muté par chaque step
/// émis.
///
/// Distinguer immutable vs mutable :
/// - `final` (params figés) : `effectiveDuration`, `genUntil`, `cfg`,
///   `bank`, etc. — ne changent jamais en cours de génération.
/// - mutables : [time], [stamina], et les listes [steps] / [profile]
///   (référence stable, contenu accumulé).
class GenerationContext {
  /// Steps déjà émis (mutable). La même liste est passée à tous les
  /// helpers ; les méthodes `_emitStep` / `_pushMilestoneSequence` /
  /// etc. y appendent leurs steps.
  final List<SessionStep> steps;

  /// Profil stamina pré-rempli (taille `effectiveDuration + 60`),
  /// muté par `StaminaModel.fillProfile` à chaque emission.
  final List<double> profile;

  final int encoreChainIndex;
  final int effectiveDuration;
  final int boostsCount;
  final int genUntil;
  final double intensityFloor;
  final bool quickie;
  final bool noStats;
  final CareerLevel cfg;
  final PhraseBank bank;
  final String? sessionName;
  final String? sessionNameQuickie;
  final String? Function(String milestoneId, int stepTime)?
      milestoneTextResolver;
  final List<LevelMilestone> insertedBodies;

  /// Curseur temporel courant (secondes depuis le début de séance).
  /// Démarre à 0, incrémenté par chaque step émis. Lu par tous les
  /// helpers pour décider de la fenêtre courante (mini-vague, swallow,
  /// recovery, boosts, etc.).
  int time = 0;

  /// Endurance courante de la joueuse (0..100, peut descendre négatif
  /// = dette d'endurance signalant un sas breath). Démarre à
  /// `StaminaModel.cap` (= 100), mutée par chaque step émis via
  /// `StaminaModel.apply`.
  double stamina = 100.0;

  /// Progression normalisée de la séance ∈ [0, 1] dérivée du curseur
  /// temporel. Consommée par les rules pour moduler regen/cost
  /// stamina, par le main loop pour resserrer la fenêtre de
  /// difficulté, etc. Recalculée à la volée (pas de cache, le coût
  /// est négligeable).
  double get progress => time / effectiveDuration;

  GenerationContext({
    required this.steps,
    required this.profile,
    required this.encoreChainIndex,
    required this.effectiveDuration,
    required this.boostsCount,
    required this.genUntil,
    required this.intensityFloor,
    required this.quickie,
    required this.noStats,
    required this.cfg,
    required this.bank,
    required this.sessionName,
    required this.sessionNameQuickie,
    required this.milestoneTextResolver,
    required this.insertedBodies,
  });
}
