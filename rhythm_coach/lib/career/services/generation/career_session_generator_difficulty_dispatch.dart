// Fichier part de `career_session_generator.dart` — dispatch principal
// difficulté → step.
//
// `_mapDifficultyToStep` est le cœur de la boucle main : à partir d'une
// difficulté `diff ∈ [0, 1]` tirée par `generate`, il construit le
// StepDraft concret du step suivant. Sa logique :
//   1. Sélection des candidats de mode via `ModeRules.difficultyRange` —
//      chaque rule expose sa propre fenêtre `[min, max)` éventuellement
//      gating-aware (unlocks, includeHand, état runtime). Le dispatcher
//      itère un ordre fixe `_mainLoopCandidateOrder` pour préserver le
//      tirage rng historique (cf. C.PR3).
//   2. Tirage pondéré du mode via `_ModePicker.pickWeighted` (couleur spé
//      + dose coach + continuité par type).
//   3. Découpe simplex du budget de difficulté entre BPM / amplitude /
//      durée + bonus de spé par axe.
//   4. **Dispatch polymorphique** vers `ModeRules.build(DraftCtx)` du
//      mode tiré (cf. `career_session_generator_mode_rules.dart`). Chaque
//      rule porte ses propres ranges / samplers / caps mode-specific.
//
// Le file reste posé comme **extension** sur `CareerSessionGenerator`
// (library-private, call site `_mapDifficultyToStep(diff)` inchangé)
// pour l'accès à `this` côté orchestration (candidats, picker, _config.pts).
// Le sous-cas par mode du switch a migré vers le registry `_modeRules`.

part of 'career_session_generator.dart';

/// Ordre d'itération des candidats main loop. Préserve l'ordre historique
/// du dispatcher (`lick → rhythm → hold → biffle → hand → beg → suckle`)
/// — différent de l'ordre du registry (`rhythm, lick, hold, biffle, beg,
/// hand, breath, freestyle, suckle`). L'ordre est sémantiquement
/// important car `_ModePicker.pickWeighted` consomme un seul tirage rng
/// et itère les candidats : un changement d'ordre rebattrait les
/// sessions reproductibles à seed égal. Les modes non listés (breath /
/// freestyle) retournent `null` à `difficultyRange` et ne sont pas
/// candidats. Cf. C.PR3.
const List<SessionMode> _mainLoopCandidateOrder = [
  SessionMode.lick,
  SessionMode.rhythm,
  SessionMode.hold,
  SessionMode.biffle,
  SessionMode.hand,
  SessionMode.beg,
  SessionMode.suckle,
];

/// Cascade soft-mouth pour le cas Custom où **toutes** les candidates
/// main loop ont été retirées par `_config.isModeForbidden` (doses
/// `none`). On privilégie le mode le plus doux encore autorisé : lick
/// (langue) → hold (statique) → rhythm (rythme bouche). Si même rhythm
/// est forbidden, le fallback `mainLoopFallback` ci-dessous prend le
/// relais et force rhythm pour ne jamais crasher.
const List<SessionMode> _softMouthCascade = [
  SessionMode.lick,
  SessionMode.hold,
  SessionMode.rhythm,
];

extension _DifficultyDispatch on CareerSessionGenerator {
  /// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Le budget est
  /// réparti aléatoirement entre les axes BPM, amplitude et durée — donc un
  /// step "hard" peut être lent profond endurant, ou rapide plus court, etc.
  StepDraft _mapDifficultyToStep(double diff) {
    final ctx = DifficultyCtx(
      unlockedKeys: _state.unlockedKeys,
      includeHand: _config.includeHand,
      lastType: _state.lastType,
      stepsOutsideBouche: _state.stepsOutsideBouche,
      canChainRhythm: _rhythmChain.canChain(),
    );
    final candidates = <SessionMode>[];
    for (final m in _mainLoopCandidateOrder) {
      final range = _rules[m]!.difficultyRange(ctx);
      if (range == null) continue;
      if (diff >= range.min && diff < range.max) candidates.add(m);
    }
    // Exclusions Custom (dose `none`) : retirer les modes interdits avant
    // tirage. Si tout est exclu, cascade soft-mouth (le mode le plus doux
    // encore autorisé) ; si même la cascade ne donne rien, fallback
    // `mainLoopFallback` (rhythm) pour ne jamais crasher si une config
    // était corrompue.
    candidates.removeWhere(_config.isModeForbidden);
    if (candidates.isEmpty) {
      for (final m in _softMouthCascade) {
        if (!_config.isModeForbidden(m)) {
          candidates.add(m);
          break;
        }
      }
      if (candidates.isEmpty) {
        candidates.add(_resolveModeForRole(ModeSemanticRole.mainLoopFallback));
      }
    }
    final mode = _pickWeightedMode(_filterRepeated(candidates));

    final (aBpm, aAmp, aDur) = _sampleSimplex3();
    var bpmScore = (diff * 3 * aBpm).clamp(0.0, 1.0);
    var ampScore = (diff * 3 * aAmp).clamp(0.0, 1.0);
    var durScore = (diff * 3 * aDur).clamp(0.0, 1.0);
    // Bonus de spé sur les axes (capés 1.0). Coefs renforcés (+0.05 →
    // +0.08/pt) pour que la branche choisie pousse plus visiblement les
    // paramètres : 5 pts en profondeur = +0.40 ampScore, donc des
    // amplitudes mid→full / throat→full bien plus fréquentes.
    bpmScore =
        (bpmScore + 0.08 * _config.pts(SpecializationBranch.rythmeBiffle))
            .clamp(0.0, 1.0);
    ampScore = (ampScore + 0.08 * _config.pts(SpecializationBranch.profondeur))
        .clamp(0.0, 1.0);
    durScore = (durScore + 0.08 * _config.pts(SpecializationBranch.endurance))
        .clamp(0.0, 1.0);

    // Dispatch polymorphique : chaque rule consomme les 3 scores via
    // `DraftCtx` et accède aux samplers / caps via `ctx.gen.*` (typé
    // `GenFacade`, surface restreinte du générateur). La logique
    // mode-specific (ranges BPM/amplitude/durée, sloppy boost pour lick,
    // obéissance boost pour beg, anatomy gate pour suckle…) est portée
    // par les `ModeRules.build` correspondants.
    return _rules[mode]!.build(DraftCtx(
      bpmScore: bpmScore,
      ampScore: ampScore,
      durScore: durScore,
      gen: _facade,
    ));
  }
}
