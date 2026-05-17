// Fichier part de `career_session_generator.dart` — règles du mode
// `hold`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`. Partage le helper
// `_clampHeldDuration` avec `_BegRules` (cap durée sur position tenue).

part of 'career_session_generator.dart';

/// Règles `hold` : coût pur lié à la profondeur tenue (`to`). Convention
/// uniforme hold/beg : la position tenue est dans `to`.
class _HoldRules extends _ModeRules {
  const _HoldRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final depth = _StaminaModel.positionDepth(draft.to, draft.to);
    return -depth * dur / 2.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.holdBalls;
    }
    // Convention : hold/beg portent leur position dans `to`. Les holds
    // tip/head sont du socle de base (pas de clé) ; mid+ sont gatés.
    final to = draft.to;
    if (to == null || to == Position.tip || to == Position.head) return null;
    if (to == Position.mid) return UnlockKey.holdMidShort;
    final dur = draft.duration ?? 0;
    if (to == Position.throat) {
      return dur > 10 ? UnlockKey.throatHoldLong : UnlockKey.throatHoldShort;
    }
    if (to == Position.full) {
      return dur > 10 ? UnlockKey.fullHoldLong : UnlockKey.fullHoldShort;
    }
    return null;
  }

  @override
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) =>
      _clampHeldDuration(draft, c);

  @override
  _StepDraft? tryDegrade(_StepDraft draft) {
    // (1) Hold throat/full long → raccourcir d'abord (la durée pèse
    // beaucoup sur l'humiliation requise, la position reste contractuelle).
    if ((draft.to == Position.throat || draft.to == Position.full) &&
        (draft.duration ?? 0) > 5) {
      return _StepDraft(
        mode: draft.mode,
        bpm: draft.bpm,
        from: draft.from,
        to: draft.to,
        duration: max(2, (draft.duration ?? 0) ~/ 2),
      );
    }
    // (2) Descendre `to` d'un cran (la position tenue). Note : hold
    // descend jusqu'à `tip`, contrairement aux modes rythmiques qui
    // s'arrêtent à `head`.
    if (draft.to != null && draft.to!.index > Position.tip.index) {
      return _StepDraft(
        mode: draft.mode,
        bpm: draft.bpm,
        from: draft.from,
        to: Position.values[draft.to!.index - 1],
        duration: draft.duration,
      );
    }
    return null;
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Convention uniforme hold/beg : la position tenue est dans `to`
    // (matche BeepEngine et le format SessionStep des JSON).
    final to = ctx.gen._pickHoldPosition(ctx.ampScore);
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(8.0, 30.0, max(ctx.durScore, ctx.bpmScore)),
      enduranceFactor: 0.08,
    );
    return _StepDraft(
      mode: SessionMode.hold,
      bpm: null,
      from: null,
      to: to,
      duration: dur,
    );
  }
}
