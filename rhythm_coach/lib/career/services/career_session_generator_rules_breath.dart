// Fichier part de `career_session_generator.dart` — règles du mode
// `breath`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of 'career_session_generator.dart';

/// Règles `breath` : toujours regen. Vitesse 2.8 stamina/s — règle de
/// design : un breath doit être plus court que les steps d'action qu'il
/// sépare, sinon la dramaturgie ressemble à « action / longue pause /
/// action / longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui
/// couvre un step rythme moyen (~20 de coût) et permet d'enchaîner.
class _BreathRules extends _ModeRules {
  const _BreathRules();

  @override
  _StepType classify(Position? to) => _StepType.transit;

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final regen = _StaminaModel.lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    return dur * 2.8 * regen;
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    final dur = _StaminaModel.lerp(6.0, 15.0, ctx.durScore).round();
    return _StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Breath post-final = req 0 (toujours accessible), jamais blocked
  /// (breath n'est pas dosable Custom, cf. `CustomSessionConfig.
  /// dosableModes`). Sert de fallback safe quand humilCap est trop bas
  /// pour les autres variantes.
  @override
  List<_PostFinalVariant> postFinalVariants(_PostFinalCtx ctx) => [
        _PostFinalVariant(
          req: 0.0,
          blocked: false,
          draft: _StepDraft(
            mode: SessionMode.breath,
            bpm: null,
            from: null,
            to: null,
            duration: ctx.duration,
          ),
        ),
      ];
}
