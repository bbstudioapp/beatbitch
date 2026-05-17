// Fichier part de `career_session_generator.dart` — règles du mode
// `hand`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of 'career_session_generator.dart';

/// Règles `hand` : effort modéré côté endurance (la bouche se repose, mais
/// la main travaille). On consomme moins que rhythm équivalent.
class _HandRules extends _ModeRules {
  const _HandRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 6.0;
  }

  @override
  _StepDraft? tryDegrade(_StepDraft draft) =>
      _tryDescendToWithGuard(draft) ?? _tryDescendFrom(draft);

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Hand sert d'outil d'excitation/endurance pure : sa fréquence peut
    // grimper sans coût d'humiliation. Plage très large pour permettre
    // récup lente (60 BPM) jusqu'à burst frénétique (180 BPM).
    final bpm = _StaminaModel.lerp(60.0, 180.0, ctx.bpmScore).round();
    // Tirage spécifique hand : la main tient la base de la queue, donc
    // l'amplitude reste dans le haut (jamais plus profond que throat).
    // En revanche tip→head et head→head sont autorisés (le tirage
    // commun les exclut pour les autres modes).
    final (from, to) = ctx.gen._sampleFromToForHand(ctx.ampScore);
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(15.0, 30.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    return _StepDraft(
      mode: SessionMode.hand,
      bpm: bpm,
      from: from,
      to: to,
      duration: dur,
    );
  }
}
