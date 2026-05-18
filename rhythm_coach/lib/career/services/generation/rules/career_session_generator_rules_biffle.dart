// Library autonome — règles du mode
// `biffle`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

import 'dart:math';

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `biffle` : effort soutenu (la fille encaisse), conso entre
/// rythme et hold, modulée par la profondeur.
class BiffleRules extends ModeRules {
  const BiffleRules();

  @override
  StepType classify(Position? to) => StepType.libreMain;

  @override
  bool get isRhythmic => true;

  /// Biffle candidat dès `diff ≥ 0.40`, gaté par `includeHand` (le
  /// biffle implique un coup de queue, pas joué quand l'utilisateur
  /// désactive le toggle hand) et par l'unlock `biffleBasic`. Pré-filtre
  /// au tirage : sinon une cascade systématique biffle → lick se
  /// déclenchait au moindre tirage hors palier. Convention héritée
  /// (`unlockedKeys.isEmpty` = pas de gating) préservée.
  @override
  ({double min, double max})? difficultyRange(DifficultyCtx ctx) {
    if (!ctx.includeHand) return null;
    final canBiffle = ctx.unlockedKeys.isEmpty ||
        ctx.unlockedKeys.contains(UnlockKey.biffleBasic);
    if (!canBiffle) return null;
    return (min: 0.40, max: double.infinity);
  }

  @override
  double baseWeight(SpecializationAllocation spec) =>
      1.0 +
      0.60 * spec.pointsIn(SpecializationBranch.rythmeBiffle) +
      0.25 * spec.pointsIn(SpecializationBranch.sloppy);

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 3.5;
  }

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) =>
      (draft.bpm ?? 0) > 100 ? UnlockKey.biffleFast : UnlockKey.biffleBasic;

  @override
  StepDraft clampToCapability(StepDraft draft, CapabilityClampSurface c) {
    var bpm = draft.bpm;
    var dur = draft.duration;
    final durCap = c.capabilityCapFor(CapabilityAxis.biffleStreak);
    if (durCap != null && dur != null && dur > durCap) {
      dur = max(2, durCap.floor());
    }
    final bpmCap = c.capabilityCapFor(CapabilityAxis.biffleBpmMax);
    if (bpmCap != null && bpm != null && bpm > bpmCap) {
      bpm = bpmCap.round();
    }
    if (bpm == draft.bpm && dur == draft.duration) return draft;
    return StepDraft(
      mode: draft.mode,
      bpm: bpm,
      bpmEnd: draft.bpmEnd,
      from: draft.from,
      to: draft.to,
      duration: dur,
      chainNext: draft.chainNext,
    );
  }

  @override
  StepDraft? tryDegrade(StepDraft draft) {
    // Biffle n'a pas de from/to (coups de queue sur le visage). Cascade :
    // cap BPM à 80, sinon repli sur lick tip→head qui devient une vraie
    // récup en bouche.
    if ((draft.bpm ?? 0) > 80) {
      return StepDraft(
        mode: draft.mode,
        bpm: 80,
        from: draft.from,
        to: draft.to,
        duration: draft.duration,
      );
    }
    return StepDraft(
      mode: SessionMode.lick,
      bpm: draft.bpm ?? 60,
      from: draft.from ?? Position.tip,
      to: draft.to ?? Position.head,
      duration: draft.duration,
    );
  }

  @override
  StepDraft build(DraftCtx ctx) {
    // Biffle = coups de queue sur le visage : pas de notion de position.
    // from/to restent null.
    final bpm = StaminaModel.lerp(80.0, 140.0, ctx.bpmScore).round();
    final dur = ctx.gen.config.scaleDuration(
      StaminaModel.lerp(15.0, 40.0, ctx.durScore),
      enduranceFactor: 0.05,
    );
    return StepDraft(
      mode: SessionMode.biffle,
      bpm: bpm,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Biffle entre dans la palette de récup uniquement si le toggle Hand
  /// est actif (le mode est mécaniquement « main libre ») ET si la
  /// milestone d'introduction (`biffle_basic`) est acquittée. En mode
  /// hérité (sessions hors-carrière) le gating est court-circuité.
  @override
  bool isRecoveryCandidate(RecoveryAvailability a) =>
      a.includeHand &&
      (a.heritage || a.unlockedKeys.contains(UnlockKey.biffleBasic));

  @override
  StepDraft buildRecovery(RecoveryCtx ctx) {
    final (from, to) = ctx.gen.sampleFromTo(0.3);
    return StepDraft(
      mode: SessionMode.biffle,
      bpm: ctx.bpm,
      from: from,
      to: to,
      duration: ctx.duration,
    );
  }

  /// Biffle final = coups lents (BPM 40-60) + sauce sur le visage.
  /// Émis uniquement si le toggle Hand est actif (`ctx.biffleBpm != null`).
  /// Gate : `finalBiffle` (niveau 5, requires `biffle_basic`).
  @override
  List<FinalVariant> finalVariants(FinalCtx ctx) {
    if (ctx.biffleBpm == null) return const [];
    return [
      FinalVariant(
        req: 13.0,
        gate: UnlockKey.finalBiffle,
        draft: StepDraft(
          mode: SessionMode.biffle,
          bpm: ctx.biffleBpm,
          from: null,
          to: null,
          duration: ctx.fastDur,
        ),
      ),
    ];
  }
}
