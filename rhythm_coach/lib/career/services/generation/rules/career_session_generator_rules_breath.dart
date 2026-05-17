// Library autonome — règles du mode
// `breath`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `breath` : toujours regen. Vitesse 2.8 stamina/s — règle de
/// design : un breath doit être plus court que les steps d'action qu'il
/// sépare, sinon la dramaturgie ressemble à « action / longue pause /
/// action / longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui
/// couvre un step rythme moyen (~20 de coût) et permet d'enchaîner.
class BreathRules extends ModeRules {
  const BreathRules();

  @override
  StepType classify(Position? to) => StepType.transit;

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final regen = StaminaModel.lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    return dur * 2.8 * regen;
  }

  @override
  StepDraft build(DraftCtx ctx) {
    final dur = StaminaModel.lerp(6.0, 15.0, ctx.durScore).round();
    return StepDraft(
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
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) => [
        PostFinalVariant(
          req: 0.0,
          blocked: false,
          draft: StepDraft(
            mode: SessionMode.breath,
            bpm: null,
            from: null,
            to: null,
            duration: ctx.duration,
          ),
        ),
      ];
}
