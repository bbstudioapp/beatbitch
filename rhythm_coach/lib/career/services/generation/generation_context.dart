// Library autonome — value object des paramètres immutables partagés
// entre `generate()` et ses helpers (chaîne main loop, finish phase,
// milestone scheduler, etc.).
//
// Sorti du `part of 'career_session_generator.dart'` historique en
// D.PR7 du plan de refacto (partie 1 — extraction du value object) pour
// préparer D.PR6 (MilestoneScheduler) qui le consomme par paramètre.
// Le restant de D.PR7 (cristallisation des compteurs courants `time`,
// `stamina`, `progress` dans le ctx) viendra plus tard quand les
// chaînes d'émission seront extraites.
//
// Construit une fois par `generate()` avec les 15 champs figés à
// l'ouverture de séance, passé par valeur à chaque helper qui en a
// besoin.

import '../../../models/session_step.dart';
import '../../models/career_level.dart';
import '../../models/level_milestone.dart';
import '../../models/phrase_bank.dart';

/// Paramètres immutables de la séance en cours de génération.
/// Construit par `CareerSessionGenerator.generate()` après que la
/// difficulté, la durée et le bundle de contenu (coach, milestones)
/// sont résolus. Threadé par valeur à tous les helpers — aucun champ
/// ne mute en cours de génération.
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

  const GenerationContext({
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
