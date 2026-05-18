// Library autonome — dispatch principal difficulté → step.
//
// [DifficultyDispatch.mapDifficultyToStep] est le cœur de la boucle
// main : à partir d'une difficulté `diff ∈ [0, 1]` tirée par
// `generate`, il construit le StepDraft concret du step suivant. Sa
// logique :
//   1. Sélection des candidats de mode via `ModeRules.difficultyRange` —
//      chaque rule expose sa propre fenêtre `[min, max)` éventuellement
//      gating-aware (unlocks, includeHand, état runtime). Le dispatcher
//      itère un ordre fixe `_mainLoopCandidateOrder` pour préserver le
//      tirage rng historique (cf. C.PR3).
//   2. Tirage pondéré du mode via [ModePicker.pickWeighted] (couleur spé
//      + dose coach + continuité par type).
//   3. Découpe simplex du budget de difficulté entre BPM / amplitude /
//      durée + bonus de spé par axe.
//   4. **Dispatch polymorphique** vers `ModeRules.build(DraftCtx)` du
//      mode tiré. Chaque rule porte ses propres ranges / samplers /
//      caps mode-specific.
//
// Sortie du `part of 'career_session_generator.dart'` historique en
// D.PR4 du plan de refacto. Devient une classe autonome paramétrée par
// le constructeur — le générateur instancie un `DifficultyDispatch`
// après que `_facade` et `_positionPickers` sont posés, puis l'invoque
// dans la boucle main.

import 'dart:math';

import '../../../models/session.dart';
import '../../models/specialization.dart';
import 'mode_picker.dart';
import 'mode_rules.dart';
import 'position_pickers.dart';
import 'rhythm_chain_tracker.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_draft.dart';

/// Ordre d'itération des candidats main loop. Préserve l'ordre historique
/// du dispatcher (`lick → rhythm → hold → biffle → hand → beg → suckle`)
/// — différent de l'ordre du registry (`rhythm, lick, hold, biffle, beg,
/// hand, breath, freestyle, suckle`). L'ordre est sémantiquement
/// important car [ModePicker.pickWeighted] consomme un seul tirage rng
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

/// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Classe
/// instanciée une fois par `generate()` après que le state du
/// générateur est posé. Mute `state` indirectement via les samplers
/// position consultés par `ModeRules.build` (`pickHoldPosition`,
/// `sampleFromTo`, etc.) — `mapDifficultyToStep` lui-même est pur
/// (ne consomme que la rng + les caps).
class DifficultyDispatch {
  DifficultyDispatch({
    required this.config,
    required this.state,
    required this.rng,
    required this.rules,
    required this.rhythmChain,
    required this.facade,
    required this.positionPickers,
  }) : _mainLoopFallback =
            _resolveRole(rules, ModeSemanticRole.mainLoopFallback);

  final SessionConfig config;
  final SessionRuntimeState state;
  final Random rng;
  final Map<SessionMode, ModeRules> rules;
  final RhythmChainTracker rhythmChain;
  final GenFacadeSurface facade;
  final PositionPickers positionPickers;

  /// Mode retenu comme fallback ultime quand toutes les candidates ont
  /// été exclues (cascade soft-mouth comprise). Résolu une fois à la
  /// construction pour éviter une itération du registre par appel.
  final SessionMode _mainLoopFallback;

  /// Résolution du rôle sémantique — itération du registre, retourne
  /// le 1er mode qui déclare le rôle. Itère dans l'ordre d'insertion du
  /// registry (déterministe). Dupliqué depuis `_resolveModeForRole` du
  /// générateur — le couplage est minimal (le dispatcher ne résout
  /// qu'un seul rôle).
  static SessionMode _resolveRole(
    Map<SessionMode, ModeRules> rules,
    ModeSemanticRole role,
  ) {
    for (final entry in rules.entries) {
      if (entry.value.roles.contains(role)) return entry.key;
    }
    throw StateError(
      'ModeSemanticRole.$role : aucun mode du registry ne le déclare',
    );
  }

  /// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Le budget
  /// est réparti aléatoirement entre les axes BPM, amplitude et durée —
  /// donc un step « hard » peut être lent profond endurant, ou rapide
  /// plus court, etc.
  StepDraft mapDifficultyToStep(double diff) {
    final ctx = DifficultyCtx(
      unlockedKeys: state.unlockedKeys,
      includeHand: config.includeHand,
      lastType: state.lastType,
      stepsOutsideBouche: state.stepsOutsideBouche,
      canChainRhythm: rhythmChain.canChain(),
    );
    final candidates = <SessionMode>[];
    for (final m in _mainLoopCandidateOrder) {
      final range = rules[m]!.difficultyRange(ctx);
      if (range == null) continue;
      if (diff >= range.min && diff < range.max) candidates.add(m);
    }
    // Exclusions Custom (dose `none`) : retirer les modes interdits avant
    // tirage. Si tout est exclu, cascade soft-mouth (le mode le plus doux
    // encore autorisé) ; si même la cascade ne donne rien, fallback
    // `mainLoopFallback` (rhythm) pour ne jamais crasher si une config
    // était corrompue.
    candidates.removeWhere(config.isModeForbidden);
    if (candidates.isEmpty) {
      for (final m in _softMouthCascade) {
        if (!config.isModeForbidden(m)) {
          candidates.add(m);
          break;
        }
      }
      if (candidates.isEmpty) {
        candidates.add(_mainLoopFallback);
      }
    }
    final mode = ModePicker.pickWeighted(
      ModePicker.filterRepeated(candidates, state.lastMode, rules: rules),
      spec: config.spec,
      coachWeights: config.coachModeWeights,
      continuity: state.continuitySnapshot(),
      rng: rng,
      rules: rules,
    );

    final (aBpm, aAmp, aDur) = positionPickers.sampleSimplex3();
    var bpmScore = (diff * 3 * aBpm).clamp(0.0, 1.0);
    var ampScore = (diff * 3 * aAmp).clamp(0.0, 1.0);
    var durScore = (diff * 3 * aDur).clamp(0.0, 1.0);
    // Bonus de spé sur les axes (capés 1.0). Coefs renforcés (+0.05 →
    // +0.08/pt) pour que la branche choisie pousse plus visiblement les
    // paramètres : 5 pts en profondeur = +0.40 ampScore, donc des
    // amplitudes mid→full / throat→full bien plus fréquentes.
    bpmScore = (bpmScore + 0.08 * config.pts(SpecializationBranch.rythmeBiffle))
        .clamp(0.0, 1.0);
    ampScore = (ampScore + 0.08 * config.pts(SpecializationBranch.profondeur))
        .clamp(0.0, 1.0);
    durScore = (durScore + 0.08 * config.pts(SpecializationBranch.endurance))
        .clamp(0.0, 1.0);

    // Dispatch polymorphique : chaque rule consomme les 3 scores via
    // `DraftCtx` et accède aux samplers / caps via `ctx.gen.*` (typé
    // `GenFacade`, surface restreinte du générateur). La logique
    // mode-specific (ranges BPM/amplitude/durée, sloppy boost pour lick,
    // obéissance boost pour beg, anatomy gate pour suckle…) est portée
    // par les `ModeRules.build` correspondants.
    return rules[mode]!.build(DraftCtx(
      bpmScore: bpmScore,
      ampScore: ampScore,
      durScore: durScore,
      gen: facade,
    ));
  }
}
