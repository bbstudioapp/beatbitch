// Library autonome — `GenFacade`, implémentation unique de
// `GenFacadeSurface` (interface dans `mode_rules.dart`).
//
// Surface du générateur exposée aux `ModeRules`. C'est strictement tout
// ce qu'une rule a le droit de consommer — ajouter une méthode ou un
// getter ici est un acte explicite (« j'élargis l'API que les modes
// peuvent voir »).
//
// Composition explicite : la facade ne détient pas de référence au
// générateur. Elle reçoit en constructeur les collaborateurs dont les
// rules ont besoin — state stable (`config`, `state`, `rng`,
// `rhythmChain`) et sous-systèmes (`PositionPickers`). Les méthodes
// `BpmPacing` consommées passent par le `config` field. Le générateur
// recrée la facade à chaque `generate()` / `generatePunishment()`,
// après que ses sous-systèmes sont posés.
//
// Sortie du `part of 'career_session_generator.dart'` historique
// (aboutissement de la phase A, A.PR7 du plan de refacto). Le
// constructeur a perdu son `_` privé : la classe vit désormais dans sa
// propre library, donc « privé à la library » suffit à préserver
// l'intention (les rules n'importent pas `gen_facade.dart`, elles
// reçoivent un `ctx.gen` typé via `GenFacadeSurface`).
//
// `career_session_generator.dart` re-exporte `GenFacade` pour préserver
// la rétrocompat des call sites externes (tests, scénarios JSON, etc.).

import 'dart:math';

import '../../../models/session_step.dart';
import 'bpm_pacing.dart';
import 'mode_rules.dart';
import 'position_pickers.dart';
import 'rhythm_chain_tracker.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_draft.dart';

/// Implémentation unique de [GenFacadeSurface] (cf. `mode_rules.dart`) :
/// les rules reçoivent un `ctx.gen` typé via l'interface — `GenFacade`
/// reste la seule implémentation concrète, mais aucune rule ne référence
/// cette classe directement.
class GenFacade implements GenFacadeSurface {
  GenFacade({
    required this.config,
    required this.state,
    required this.rng,
    required this.rhythmChain,
    required PositionPickers positionPickers,
  }) : _positionPickers = positionPickers;

  // ─── State stable lu par les rules ───────────────────────────────────────
  @override
  final SessionConfig config;
  @override
  final SessionRuntimeState state;
  @override
  final Random rng;
  @override
  final RhythmChainTracker rhythmChain;

  // ─── Sous-systèmes wrappés (privés — accès via les méthodes ci-dessous) ──
  final PositionPickers _positionPickers;

  // ─── Plafonds milestone (délégués à `_positionPickers`) ──────────────────
  @override
  int milestoneHoldCeilingIdx() => _positionPickers.milestoneHoldCeilingIdx();
  @override
  int milestoneRhythmCeilingIdx() =>
      _positionPickers.milestoneRhythmCeilingIdx();

  // ─── Samplers position (délégués à `_positionPickers`) ───────────────────
  @override
  (Position, Position) sampleFromTo(double ampScore,
          {bool capByDepth = true}) =>
      _positionPickers.sampleFromTo(ampScore, capByDepth: capByDepth);
  @override
  (Position, Position) sampleFromToForHand(double ampScore) =>
      _positionPickers.sampleFromToForHand(ampScore);
  @override
  (Position, Position) sampleFromToForLick(double ampScore) =>
      _positionPickers.sampleFromToForLick(ampScore);
  @override
  Position pickHoldPosition(double ampScore) =>
      _positionPickers.pickHoldPosition(ampScore);
  @override
  Position? pickBegPosition(double ampScore) =>
      _positionPickers.pickBegPosition(ampScore);
  @override
  StepDraft? maybePickBegWithChain({
    required Position? to,
    required int obPts,
  }) =>
      _positionPickers.maybePickBegWithChain(to: to, obPts: obPts);

  // ─── Caps pacing (délégué à `BpmPacing` avec injection de `config`) ─────
  @override
  int capRhythmDurationByPulses(int dur, int bpm, Position? to) =>
      BpmPacing.capRhythmDurationByPulses(dur, bpm, to, config: config);
}
