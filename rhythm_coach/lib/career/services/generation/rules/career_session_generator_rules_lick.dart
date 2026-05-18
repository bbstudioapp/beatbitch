// Library autonome — règles du mode
// `lick`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

import 'dart:math';

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `lick` : BPM ≤ 60 = vraie récup vocale (regen), au-delà = effort
/// léger (consommation modérée, plus de regen).
class LickRules extends ModeRules {
  const LickRules();

  @override
  Set<ModeSemanticRole> get roles => const {ModeSemanticRole.burstFallback};

  /// Lick est la baseline « bouche douce » : seul mode candidat sous
  /// `diff < 0.30`. Bornage strict sur la haute (`< 0.30`) pour
  /// préserver l'isomorphie avec le test historique `diff < 0.30`.
  @override
  ({double min, double max})? difficultyRange(DifficultyCtx ctx) =>
      (min: 0.0, max: 0.30);

  @override
  StepType classify(Position? to) => StepType.langue;

  @override
  bool get isRhythmic => true;

  @override
  bool get isFlow => true;

  /// Base abaissée (retour utilisateur « moins de lèche ») : sans
  /// point sloppy, le lick pèse ~0.6 contre ~1.0 pour un mode neutre.
  /// Le boost sloppy (+0.70/pt) reste pleinement effectif → une
  /// joueuse spé sloppy en voit toujours beaucoup (×4.1 à 5 pts).
  @override
  double baseWeight(SpecializationAllocation spec) =>
      0.6 + 0.70 * spec.pointsIn(SpecializationBranch.sloppy);

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = draft.bpm ?? 60;
    if (bpm <= 60) {
      final regen = StaminaModel.lerp(
        cfg.regenStartMultiplier,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.2 * regen;
    }
    final depth = StaminaModel.positionDepth(draft.from, draft.to);
    return -depth * dur / 8.0;
  }

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.lickBalls;
    }
    // Lick X→full nécessite la milestone `intro_lick_full`. Sinon, lick
    // from=tip (toutes amplitudes ≤ throat) est du socle de base.
    if (draft.to == Position.full) return UnlockKey.lickFull;
    return null;
  }

  @override
  StepDraft? tryDegrade(StepDraft draft) =>
      tryDescendToWithGuard(draft) ?? tryDescendFrom(draft);

  @override
  StepDraft build(DraftCtx ctx) {
    // Sloppy : monte le BPM minimum (≥ 65 = lick humide / saliveux).
    final sloppyPts = ctx.gen.config.pts(SpecializationBranch.sloppy);
    final lickBpmScore = sloppyPts > 0 ? max(ctx.bpmScore, 0.3) : ctx.bpmScore;
    final bpm = StaminaModel.lerp(55.0, 80.0, lickBpmScore).round();
    // Tirage spécifique lick : tip→head forcé tant qu'humiliation < 2,
    // toutes amplitudes (incluant tip → throat/full) à partir de 2.
    final (from, to) = ctx.gen.sampleFromToForLick(ctx.ampScore);
    final dur = ctx.gen.config.scaleDuration(
      StaminaModel.lerp(10.0, 25.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    return StepDraft(
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
  bool isRecoveryCandidate(RecoveryAvailability a) => true;

  @override
  StepDraft buildRecovery(RecoveryCtx ctx) {
    final (from, to) = ctx.gen.sampleFromTo(0.3);
    return StepDraft(
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
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) => [
        PostFinalVariant(
          req: 35.0,
          blocked: ctx.finalMode == SessionMode.lick ||
              ctx.isModeForbidden(SessionMode.lick),
          draft: StepDraft(
            mode: SessionMode.lick,
            bpm: ctx.bpm,
            from: Position.tip,
            to: Position.head,
            duration: ctx.duration,
          ),
        ),
      ];

  /// 2 variantes finales :
  ///  * `tip→head 60 BPM dur 16` (req 8, gate `finalLickTipHead`) —
  ///    palier intermédiaire de la palette principale.
  ///  * `full→balls 55 BPM dur 16` (req 17, gate `lickBalls`) — variante
  ///    « sloppy descente » introduite par la milestone
  ///    `intro_balls_lick`. Pas de gate-final dédiée : on réutilise
  ///    l'unlock du composant. Filtre anatomy assuré par `_isUnlocked`
  ///    côté picker, donc on émet la variante systématiquement quand
  ///    `anatomy.hasBalls`.
  @override
  List<FinalVariant> finalVariants(FinalCtx ctx) {
    final out = <FinalVariant>[
      const FinalVariant(
        req: 8.0,
        gate: UnlockKey.finalLickTipHead,
        draft: StepDraft(
          mode: SessionMode.lick,
          bpm: 60,
          from: Position.tip,
          to: Position.head,
          duration: 16,
        ),
      ),
    ];
    if (ctx.anatomy.hasBalls) {
      out.add(const FinalVariant(
        req: 17.0,
        gate: UnlockKey.lickBalls,
        draft: StepDraft(
          mode: SessionMode.lick,
          bpm: 55,
          from: Position.full,
          to: Position.balls,
          duration: 16,
        ),
      ));
    }
    return out;
  }

  /// Lick : profondeur d'amplitude max = `full` (4). Pas de tension de
  /// profondeur côté gating — la diversification peut décaler `to` au
  /// plus haut sans contrainte milestone (cf. `LickRules.unlockKeyFor`
  /// qui gate seulement `to == full` et `balls`).
  @override
  int? amplitudeDiversifyCeiling(GenFacadeSurface gen) => Position.full.index;

  /// Lick post-final = consigne d'aftercare humiliant (« lèche pour
  /// nettoyer »). Pool dédié `pickPostFinalLick` avec fallback cascade
  /// vers le pool générique côté caller.
  @override
  String? pickPostFinalText(PhraseBank bank, Random rng) =>
      bank.pickPostFinalLick(rng);

  /// Rang 2 (2ᵉ fallback) dans la chaîne d'intro intense/quickie : la
  /// langue prend le relais quand rhythm ET hand sont exclus.
  @override
  int? get introPriority => 2;

  /// Intro langue : consomme les 4 params du ctx straight.
  @override
  StepDraft buildIntroStep(IntroCtx ctx) => StepDraft(
        mode: SessionMode.lick,
        bpm: ctx.bpm,
        from: ctx.from,
        to: ctx.to,
        duration: ctx.duration,
      );

  /// Palette d'intro standard lick : une seule variante d'amorce douce,
  /// `tip→head 60 BPM 20s`, toujours dispo (lick n'a pas de gating
  /// milestone côté socle de base).
  @override
  List<StepDraft> firstStepVariants(IntroStandardCtx ctx) => const [
        StepDraft(
          mode: SessionMode.lick,
          bpm: 60,
          from: Position.tip,
          to: Position.head,
          duration: 20,
        ),
      ];
}
