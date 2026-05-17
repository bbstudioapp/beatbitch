// Fichier part de `career_session_generator.dart` — règles du mode
// `suckle`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of '../career_session_generator.dart';

/// Règles `suckle` : aspiration / téter. La bouche bosse sans aller-retour.
/// Coût par seconde modéré, plus marqué sur head (zone sensible → pompage
/// actif) que sur balls (sloppy soumis mais peu intense musculairement).
/// On modélise sur `_holdCostPerSec` de StaminaEngine en l'ajustant :
/// head ≈ 60 % d'un hold mid, balls ≈ 30 % (moins d'effort de la bouche,
/// plus de l'humil).
class _SuckleRules extends ModeRules {
  const _SuckleRules();

  /// Aspiration : bouche au contact (head ou balls). Classé `bouche` pour
  /// bénéficier de la même friction de continuité que hold / beg-tenu —
  /// éviter d'enchaîner deux modes bouche sans pause.
  @override
  StepType classify(Position? to) => StepType.bouche;

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final pos = draft.to ?? draft.from;
    if (pos == Position.head) return -0.30 * dur;
    if (pos == Position.balls) return -0.15 * dur;
    return 0.0;
  }

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) {
    // Suckle hors balls (filtré ailleurs) → forcément head. Gating
    // dédié, indépendant de la profondeur générique (suckle head n'est
    // pas une généralisation de hold head — c'est un geste explicite à
    // introduire pédagogiquement par sa propre milestone).
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.suckleBalls;
    }
    return UnlockKey.suckleHead;
  }

  @override
  StepDraft build(DraftCtx ctx) {
    // Aspiration : pas de BPM (pulse fixe ~1.2s côté audio), position
    // tenue dans `to`. Cibles valides = head ou balls (cf. `_isUnlocked`).
    // - En carrière : unlock `suckleHead` au level 4-5, `suckleBalls`
    //   plus tard ; le filtre `_isUnlocked` rejette ce qui n'est pas
    //   encore acquis et la cascade dégrade.
    // - En mode hérité (Custom) : balls n'est candidat que si l'anatomy
    //   l'inclut et que la profondeur max le permet (`_config.maxDepthIndex >=
    //   Position.balls.index`). On biaise vers head (zone classique) avec
    //   ~30 % de chances de tirer balls quand dispo, pour rester audible
    //   mais marginal.
    final dur = ctx.gen.config.scaleDuration(
      _StaminaModel.lerp(8.0, 18.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    final ballsAllowed = ctx.gen.config.anatomy.hasBalls &&
        ctx.gen.config.maxDepthIndex >= Position.balls.index &&
        (ctx.gen.state.unlockedKeys.isEmpty ||
            ctx.gen.state.unlockedKeys.contains(UnlockKey.suckleBalls));
    final to = (ballsAllowed && ctx.gen.rng.nextDouble() < 0.30)
        ? Position.balls
        : Position.head;
    return StepDraft(
      mode: SessionMode.suckle,
      bpm: null,
      from: null,
      to: to,
      duration: dur,
    );
  }
}
