// Fichier part de `career_session_generator.dart` — règles du mode
// `biffle`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of 'career_session_generator.dart';

/// Règles `biffle` : effort soutenu (la fille encaisse), conso entre
/// rythme et hold, modulée par la profondeur.
class _BiffleRules extends _ModeRules {
  const _BiffleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 3.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) =>
      (draft.bpm ?? 0) > 100 ? UnlockKey.biffleFast : UnlockKey.biffleBasic;

  @override
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) {
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
    return _StepDraft(
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
  _StepDraft? tryDegrade(_StepDraft draft) {
    // Biffle n'a pas de from/to (coups de queue sur le visage). Cascade :
    // cap BPM à 80, sinon repli sur lick tip→head qui devient une vraie
    // récup en bouche.
    if ((draft.bpm ?? 0) > 80) {
      return _StepDraft(
        mode: draft.mode,
        bpm: 80,
        from: draft.from,
        to: draft.to,
        duration: draft.duration,
      );
    }
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: draft.bpm ?? 60,
      from: draft.from ?? Position.tip,
      to: draft.to ?? Position.head,
      duration: draft.duration,
    );
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Biffle = coups de queue sur le visage : pas de notion de position.
    // from/to restent null.
    final bpm = _StaminaModel.lerp(80.0, 140.0, ctx.bpmScore).round();
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(15.0, 40.0, ctx.durScore),
      enduranceFactor: 0.05,
    );
    return _StepDraft(
      mode: SessionMode.biffle,
      bpm: bpm,
      from: null,
      to: null,
      duration: dur,
    );
  }
}
