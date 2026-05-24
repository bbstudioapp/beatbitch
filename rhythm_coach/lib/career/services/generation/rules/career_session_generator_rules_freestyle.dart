// Library autonome — règles du mode
// `freestyle`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `freestyle` : phase libre, neutre côté endurance (ni effort
/// ni vraie regen). Toujours gaté par `freestyle` (palier d'intro
/// `intro_freestyle` au niveau 7).
class FreestyleRules extends ModeRules {
  const FreestyleRules();

  @override
  StepType classify(Position? to) => StepType.transit;

  /// Freestyle = vraie pause libre, sans bip ni guidage. Seul mode
  /// tiré uniquement par `_buildRecoveryStep`, donc son poids doit
  /// rester marginal pour ne pas dominer toutes les récup une fois
  /// débloqué (sinon ~25 % des récup partaient en freestyle parce
  /// que son multiplicateur de continuité est neutre — `transit` —
  /// alors que les autres candidats prennent la friction de quitter
  /// bouche). Un poids bas le garde comme option ponctuelle.
  @override
  double baseWeight(SpecializationAllocation spec) => 0.25;

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) => 0.0;

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) => UnlockKey.freestyle;

  @override
  StepDraft build(DraftCtx ctx) {
    final dur = StaminaModel.lerp(8.0, 18.0, ctx.durScore).round();
    return StepDraft(
      mode: SessionMode.freestyle,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Freestyle n'entre dans la palette de récup qu'après acquittement
  /// de sa milestone (`intro_freestyle`, niveau 7) — sa phase libre
  /// neutre est introduite explicitement, pas un fallback de récup
  /// permanent.
  @override
  bool isRecoveryCandidate(RecoveryAvailability a) =>
      a.heritage || a.unlockedKeys.contains(UnlockKey.freestyle);

  @override
  StepDraft buildRecovery(RecoveryCtx ctx) {
    final freeDur = 8 + ctx.gen.rng.nextInt(8);
    return StepDraft(
      mode: SessionMode.freestyle,
      bpm: null,
      from: null,
      to: null,
      duration: freeDur,
    );
  }
}
