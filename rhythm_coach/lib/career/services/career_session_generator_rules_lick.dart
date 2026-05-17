// Fichier part de `career_session_generator.dart` — règles du mode
// `lick`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of 'career_session_generator.dart';

/// Règles `lick` : BPM ≤ 60 = vraie récup vocale (regen), au-delà = effort
/// léger (consommation modérée, plus de regen).
class _LickRules extends _ModeRules {
  const _LickRules();

  @override
  _StepType classify(Position? to) => _StepType.langue;

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = draft.bpm ?? 60;
    if (bpm <= 60) {
      final regen = _StaminaModel.lerp(
        cfg.regenStartMultiplier,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.2 * regen;
    }
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -depth * dur / 8.0;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.lickBalls;
    }
    // Lick X→full nécessite la milestone `intro_lick_full`. Sinon, lick
    // from=tip (toutes amplitudes ≤ throat) est du socle de base.
    if (draft.to == Position.full) return UnlockKey.lickFull;
    return null;
  }

  @override
  _StepDraft? tryDegrade(_StepDraft draft) =>
      _tryDescendToWithGuard(draft) ?? _tryDescendFrom(draft);

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Sloppy : monte le BPM minimum (≥ 65 = lick humide / saliveux).
    final sloppyPts = ctx.gen._pts(SpecializationBranch.sloppy);
    final lickBpmScore = sloppyPts > 0 ? max(ctx.bpmScore, 0.3) : ctx.bpmScore;
    final bpm = _StaminaModel.lerp(55.0, 80.0, lickBpmScore).round();
    // Tirage spécifique lick : tip→head forcé tant qu'humiliation < 2,
    // toutes amplitudes (incluant tip → throat/full) à partir de 2.
    final (from, to) = ctx.gen._sampleFromToForLick(ctx.ampScore);
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(10.0, 25.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: bpm,
      from: from,
      to: to,
      duration: dur,
    );
  }

  /// Lick est toujours candidat en récup — c'est la baseline « langue »
  /// (variante douce, vraie regen d'endurance à BPM bas).
  @override
  bool isRecoveryCandidate(_RecoveryAvailability a) => true;

  @override
  _StepDraft buildRecovery(_RecoveryCtx ctx) {
    final (from, to) = ctx.gen._sampleFromTo(0.3);
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: ctx.bpm,
      from: from,
      to: to,
      duration: ctx.duration,
    );
  }

  /// Lick post-final = lèche douce tip→head. Blocked si lick vient juste
  /// d'être joué en final (alternance) ou si la dose Custom lick est 0.
  /// Cible privilégiée par le biais spé sloppy ≥ 2 pts (« lèche pour
  /// nettoyer »).
  @override
  List<_PostFinalVariant> postFinalVariants(_PostFinalCtx ctx) => [
        _PostFinalVariant(
          req: 35.0,
          blocked: ctx.finalMode == SessionMode.lick ||
              ctx.isModeForbidden(SessionMode.lick),
          draft: _StepDraft(
            mode: SessionMode.lick,
            bpm: ctx.bpm,
            from: Position.tip,
            to: Position.head,
            duration: ctx.duration,
          ),
        ),
      ];
}
