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
  Set<ModeSemanticRole> get roles => const {
        ModeSemanticRole.breath,
        ModeSemanticRole.postWaveBreath,
        ModeSemanticRole.recoveryFallback,
      };

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

  /// Breath de récup : cible le déficit projeté + un petit buffer 22.0
  /// pour reconstruire 2-3 steps derrière. Durée bornée [4, 12] s — au
  /// delà, le breath devient plus long que l'action qu'il sépare et
  /// brise la cadence (cf. règle de design dans `delta`). Si la dette
  /// reste après 12 s, c'est au moteur d'insérer un nouveau breath plus
  /// tard, pas à un breath unique d'absorber un trou massif.
  @override
  StepDraft? buildBreathRecovery(BreathRecoveryCtx ctx) {
    final regen = StaminaModel.lerp(
      ctx.cfg.regenStartMultiplier,
      ctx.cfg.regenEndMultiplier,
      ctx.progress,
    );
    // Cohérent avec `delta` ci-dessus : `dur * 2.8 * regen`.
    final regenPerSec = 2.8 * regen;
    const targetBuffer = 22.0;
    final raw =
        (ctx.deficit + targetBuffer) / (regenPerSec <= 0 ? 1.0 : regenPerSec);
    final dur = raw.ceil().clamp(4, 12);
    return StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Pause longue post-vague : vise stamina ~95, bornée [12, 20] s et
  /// capée par le temps restant avant le pré-finisher / boosts pour ne
  /// pas marcher sur la dramaturgie de fin de session. Retourne `null`
  /// si moins de 12 s sont disponibles.
  @override
  StepDraft? buildPostWaveBreath(PostWaveBreathCtx ctx) {
    if (ctx.remainingSeconds < 12) return null;
    final regen = StaminaModel.lerp(
      ctx.cfg.regenStartMultiplier,
      ctx.cfg.regenEndMultiplier,
      ctx.progress,
    );
    final regenPerSec = 2.8 * regen;
    const target = 95.0;
    final deficit = (target - ctx.stamina).clamp(0.0, target);
    final raw = regenPerSec <= 0 ? 12.0 : deficit / regenPerSec;
    final upperBound = ctx.remainingSeconds < 20 ? ctx.remainingSeconds : 20;
    final dur = raw.ceil().clamp(12, upperBound);
    return StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Faux-breath : 2-3 s, juste assez pour entendre un soupir, trop peu
  /// pour vraiment récupérer (à 2.8 stamina/s = 5-8 stamina rendus,
  /// peanuts face au coût d'un step intense ~25-40).
  @override
  StepDraft? buildFakeBreath(FakeBreathCtx ctx) {
    final dur = 2 + ctx.rng.nextInt(2);
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
