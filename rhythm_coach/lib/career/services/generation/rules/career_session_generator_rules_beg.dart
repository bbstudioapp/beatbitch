// Library autonome — règles du mode
// `beg`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`. Partage le helper
// `clampHeldDuration` avec `HoldRules` (cap durée sur position tenue).

import 'dart:math';

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `beg` : convention uniforme hold/beg, la position tenue est dans
/// `to`. Sans `to` ou `to = head` → assimilé à du repos vocal (regen). Avec
/// `to = mid/throat/full` → coût comme un hold à cette profondeur (la
/// position doit être tenue pendant la supplique).
class BegRules extends ModeRules {
  const BegRules();

  @override
  Set<ModeSemanticRole> get roles => const {ModeSemanticRole.swallowOrder};

  /// Beg toujours candidat dès que `begLibre` est acquis : sa difficulté
  /// effective est portée par `from` (head doux, full ≈ hold profond) et
  /// non par `diff`. `begLibre` est le prérequis transverse à toutes les
  /// formes de beg (cf. doc `_isUnlocked`). Convention héritée
  /// (`unlockedKeys.isEmpty` = pas de gating) préservée.
  @override
  ({double min, double max})? difficultyRange(DifficultyCtx ctx) {
    final canBeg = ctx.unlockedKeys.isEmpty ||
        ctx.unlockedKeys.contains(UnlockKey.begLibre);
    if (!canBeg) return null;
    return (min: 0.0, max: double.infinity);
  }

  @override
  double baseWeight(SpecializationAllocation spec) =>
      1.0 + 0.90 * spec.pointsIn(SpecializationBranch.obeissance);

  /// Step swallow_order : beg libre court 5-7 s. Pas de position tenue,
  /// pas de BPM — c'est une mini-pause vocale qui matérialise l'ordre
  /// coach « avale tout » quand la sim salive sature. Le filtre
  /// d'éligibilité (sim ≥ 80, cooldown, marge finish, begLibre débloqué)
  /// est appliqué côté générateur — la rule peut donc retourner sans
  /// re-vérifier.
  @override
  StepDraft? buildSwallowOrder(SwallowCtx ctx) {
    final dur = 5 + ctx.rng.nextInt(3); // [5, 7]
    return StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Beg avec `to` tenu = la bouche reste sur la verge pendant la
  /// supplique → `bouche`. Beg libre (`to == null`) = supplique purement
  /// vocale, bouche libre → `libreMain`. Seul mode dont la classification
  /// dépend du paramètre `to`.
  @override
  StepType classify(Position? to) =>
      to == null ? StepType.libreMain : StepType.bouche;

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final to = draft.to;
    if (to == null || to == Position.head) {
      final regen = StaminaModel.lerp(
        1.0,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.0 * regen;
    }
    final depth = StaminaModel.positionDepth(to, to);
    return -depth * dur / 2.5;
  }

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.begBalls;
    }
    // Convention : hold/beg portent leur position dans `to`.
    if (draft.to == null) return UnlockKey.begLibre;
    if (draft.to == Position.full) return UnlockKey.begFull;
    // Toute supplique avec position tenue (head/mid/throat) reste gated
    // par begThroat (palier niveau 14). Avant ça, seule la supplique
    // libre (to=null) doit apparaître. Évite que le générateur produise
    // des beg head/mid après l'unlock de begLibre alors qu'aucune
    // milestone ne les a explicitement introduits.
    return UnlockKey.begThroat;
  }

  @override
  StepDraft clampToCapability(StepDraft draft, CapabilityClampSurface c) =>
      clampHeldDuration(draft, c);

  @override
  StepDraft? tryDegrade(StepDraft draft) {
    // (1) Descendre `to` d'un cran (beg jusqu'à `tip` comme hold).
    if (draft.to != null && draft.to!.index > Position.tip.index) {
      return StepDraft(
        mode: draft.mode,
        bpm: draft.bpm,
        from: draft.from,
        to: Position.values[draft.to!.index - 1],
        duration: draft.duration,
      );
    }
    // (2) Beg avec position tenue → repli sur beg libre.
    if (draft.to != null) {
      return StepDraft(
        mode: draft.mode,
        bpm: draft.bpm,
        from: null,
        to: null,
        duration: draft.duration,
      );
    }
    return null;
  }

  /// Si [draft] est un `beg` avec position tenue qui suit immédiatement
  /// un step doux (`lick` ou `breath`), retourne une copie sans `to`
  /// pour enchaîner sur une supplique purement vocale. Sinon, renvoie
  /// [draft] tel quel. Override de la méthode polymorphique
  /// `ModeRules.stripAfterSoft` (default = identité) — la branche
  /// historique « no-op si draft.mode != beg » devient inutile depuis
  /// que l'orchestrateur dispatche via `_rules[draft.mode]!`. Cf. C.PR7.
  @override
  StepDraft stripAfterSoft(
    StepDraft draft,
    List<SessionStep> steps,
  ) {
    if (draft.to == null) return draft;
    if (steps.isEmpty) return draft;
    final prev = steps.last.mode;
    if (prev != SessionMode.lick && prev != SessionMode.breath) return draft;
    return StepDraft(
      mode: draft.mode,
      bpm: draft.bpm,
      from: draft.from,
      to: null,
      duration: draft.duration,
    );
  }

  @override
  StepDraft build(DraftCtx ctx) {
    // Convention uniforme hold/beg : la position tenue est dans `to`.
    // Obéissance : beg plus profonds (ampScore boosté localement) et
    // plus longs.
    final obPts = ctx.gen.config.pts(SpecializationBranch.obeissance);
    final begAmp = (ctx.ampScore + 0.10 * obPts).clamp(0.0, 1.0);
    final to = ctx.gen.pickBegPosition(begAmp);
    final baseDur = ctx.gen.config.scaleDuration(
      StaminaModel.lerp(7.0, 16.0, ctx.durScore),
      enduranceFactor: 0.04,
      extraFactor: obPts * 0.06,
    );
    final chained = ctx.gen.maybePickBegWithChain(
      to: to,
      obPts: obPts,
    );
    if (chained != null) return chained;
    return StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: to,
      duration: baseDur,
    );
  }

  /// Beg n'entre dans la palette de récup que si la milestone
  /// `intro_beg` (= clé `begLibre`) est acquittée. Sinon la supplique
  /// libre n'est pas encore introduite ; toutes les autres formes de beg
  /// (avec `from` tenu) sont mécaniquement plus dures et gatées par
  /// `begThroat`.
  @override
  bool isRecoveryCandidate(RecoveryAvailability a) =>
      a.heritage || a.unlockedKeys.contains(UnlockKey.begLibre);

  @override
  StepDraft buildRecovery(RecoveryCtx ctx) {
    // Récup vocale par défaut : sans position (= beg libre). Durée plus
    // courte que la fenêtre standard de récup — une supplique tient
    // rarement plus de 10 s sans s'essouffler.
    final begDur = 6 + ctx.gen.rng.nextInt(6);
    return StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: null,
      duration: begDur,
    );
  }

  /// Beg post-final = 2 variantes (libre + head). Blocked si la dose
  /// Custom beg est 0, ou si la joueuse n'a pas encore acquitté la
  /// milestone d'introduction `begLibre` (pédagogiquement faux de
  /// demander une supplique post-orgasme à une débutante). Cible
  /// privilégiée par le biais spé obeissance ≥ 2 pts (« remercie-moi »).
  @override
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) {
    final canBeg = ctx.unlockedKeys.isEmpty ||
        ctx.unlockedKeys.contains(UnlockKey.begLibre);
    final blocked = !canBeg || ctx.isModeForbidden(SessionMode.beg);
    return [
      PostFinalVariant(
        req: 25.0,
        blocked: blocked,
        draft: StepDraft(
          mode: SessionMode.beg,
          bpm: null,
          from: null,
          to: null,
          duration: ctx.duration,
        ),
      ),
      PostFinalVariant(
        req: 60.0,
        blocked: blocked,
        draft: StepDraft(
          mode: SessionMode.beg,
          bpm: null,
          from: null,
          to: Position.head,
          duration: ctx.duration,
        ),
      ),
    ];
  }

  /// Beg post-final = consigne de supplique (jamais un compliment
  /// doux). Pool dédié `pickPostFinalBeg` avec fallback cascade vers le
  /// pool générique côté caller.
  @override
  String? pickPostFinalText(PhraseBank bank, Random rng) =>
      bank.pickPostFinalBeg(rng);
}
