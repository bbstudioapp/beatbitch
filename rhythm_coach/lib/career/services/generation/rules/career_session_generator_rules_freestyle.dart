// Fichier part de `career_session_generator.dart` — règles du mode
// `freestyle`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of '../career_session_generator.dart';

/// Règles `freestyle` : phase libre, neutre côté endurance (ni effort
/// ni vraie regen). Toujours gaté par `freestyle` (palier d'intro
/// `intro_freestyle` au niveau 7).
class _FreestyleRules extends _ModeRules {
  const _FreestyleRules();

  @override
  _StepType classify(Position? to) => _StepType.transit;

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) => 0.0;

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) => UnlockKey.freestyle;

  @override
  _StepDraft build(_DraftCtx ctx) {
    final dur = _StaminaModel.lerp(8.0, 18.0, ctx.durScore).round();
    return _StepDraft(
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
  bool isRecoveryCandidate(_RecoveryAvailability a) =>
      a.heritage || a.unlockedKeys.contains(UnlockKey.freestyle);

  @override
  _StepDraft buildRecovery(_RecoveryCtx ctx) {
    final freeDur = 8 + ctx.gen._rng.nextInt(8);
    return _StepDraft(
      mode: SessionMode.freestyle,
      bpm: null,
      from: null,
      to: null,
      duration: freeDur,
    );
  }
}
