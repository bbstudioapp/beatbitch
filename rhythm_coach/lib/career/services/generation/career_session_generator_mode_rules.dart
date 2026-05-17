// Fichier part de `career_session_generator.dart`. Depuis A.PR2, ne porte
// plus que `GenFacade` — implémentation unique de `GenFacadeSurface`
// (interface dans `mode_rules.dart`, library autonome). Tout le reste
// (contrat `ModeRules`, value objects de contexte, helpers, default
// registry) a déménagé.

part of 'career_session_generator.dart';

/// Surface du générateur exposée aux `ModeRules`. C'est strictement tout
/// ce qu'une rule a le droit de consommer — ajouter une méthode ou un
/// getter ici est un acte explicite (« j'élargis l'API que les modes
/// peuvent voir »).
///
/// Composition explicite : la facade ne détient pas de référence au
/// générateur. Elle reçoit en constructeur les collaborateurs dont les
/// rules ont besoin — state stable (`config`, `state`, `rng`,
/// `rhythmChain`) et sous-systèmes (`_PositionPickers`). Les méthodes
/// `BpmPacing` consommées passent par le `config` field. Le générateur
/// recrée la facade à chaque `generate()` / `generatePunishment()`,
/// après que ses sous-systèmes sont posés.
///
/// `implements GenFacadeSurface` (cf. `mode_rules.dart`) : les rules
/// reçoivent un `ctx.gen` typé via l'interface — `GenFacade` reste la
/// seule implémentation concrète, mais aucune rule ne référence cette
/// classe directement.
class GenFacade implements GenFacadeSurface {
  GenFacade._({
    required this.config,
    required this.state,
    required this.rng,
    required this.rhythmChain,
    required _PositionPickers positionPickers,
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
  final _PositionPickers _positionPickers;

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
