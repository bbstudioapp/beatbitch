// Library autonome — règles du mode
// `hold`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`. Partage le helper
// `clampHeldDuration` avec `BegRules` (cap durée sur position tenue).

import 'dart:math';

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `hold` : coût pur lié à la profondeur tenue (`to`). Convention
/// uniforme hold/beg : la position tenue est dans `to`.
class HoldRules extends ModeRules {
  const HoldRules();

  @override
  Set<ModeSemanticRole> get roles => const {ModeSemanticRole.staticHeld};

  @override
  StepType classify(Position? to) => StepType.bouche;

  @override
  double baseWeight(SpecializationAllocation spec) =>
      1.0 +
      0.60 * spec.pointsIn(SpecializationBranch.endurance) +
      0.40 * spec.pointsIn(SpecializationBranch.profondeur);

  /// Hold final → chime escaladé sur la profondeur tenue. Échelle :
  /// tip → easy (bisou final, geste doux), head/mid → medium (en bouche
  /// sans gorge), throat → hard (gorge profonde tenue), full → extreme
  /// (apnée + gorge). Balls = `hard` (sloppy + soumis mais sans apnée).
  /// `to == null` ne devrait pas survenir pour un hold ; fallback medium.
  @override
  FinalCategory finalCategory(StepDraft draft) {
    switch (draft.to) {
      case Position.tip:
        return FinalCategory.easy;
      case Position.head:
      case Position.mid:
        return FinalCategory.medium;
      case Position.throat:
        return FinalCategory.hard;
      case Position.full:
        return FinalCategory.extreme;
      case Position.balls:
        return FinalCategory.hard;
      case null:
        return FinalCategory.medium;
    }
  }

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final depth = StaminaModel.positionDepth(draft.to, draft.to);
    return -depth * dur / 2.5;
  }

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) {
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
  StepDraft clampToCapability(StepDraft draft, CapabilityClampSurface c) =>
      clampHeldDuration(draft, c);

  @override
  StepDraft? tryDegrade(StepDraft draft) {
    // (1) Hold throat/full long → raccourcir d'abord (la durée pèse
    // beaucoup sur l'humiliation requise, la position reste contractuelle).
    if ((draft.to == Position.throat || draft.to == Position.full) &&
        (draft.duration ?? 0) > 5) {
      return StepDraft(
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
      return StepDraft(
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
  StepDraft build(DraftCtx ctx) {
    // Convention uniforme hold/beg : la position tenue est dans `to`
    // (matche BeepEngine et le format SessionStep des JSON).
    final to = ctx.gen.pickHoldPosition(ctx.ampScore);
    final dur = ctx.gen.config.scaleDuration(
      StaminaModel.lerp(8.0, 30.0, max(ctx.durScore, ctx.bpmScore)),
      enduranceFactor: 0.08,
    );
    return StepDraft(
      mode: SessionMode.hold,
      bpm: null,
      from: null,
      to: to,
      duration: dur,
    );
  }

  /// Hold court tip/head/mid/throat/full en recovery : bisou prolongé /
  /// immobilisation douce qui insère l'alternance rhythm/hold même
  /// pendant les phases où la stamina est basse (sinon on n'a que des
  /// hold sur les rares moments hors recovery). Toujours candidat — le
  /// choix de la position dépend du plafond milestone.
  @override
  bool isRecoveryCandidate(RecoveryAvailability a) => true;

  @override
  StepDraft buildRecovery(RecoveryCtx ctx) {
    // La position dépend du niveau de la joueuse : tant qu'elle n'a pas
    // dépassé hold mid, c'est tip ou head (bisou / gland tenu, vraie
    // respiration). Dès que throat est débloqué, le hold de récup n'a
    // plus de sens à profondeur basse — on garde le hold mais à la
    // profondeur max (= throat ou full), assumée comme l'unique geste
    // de tenue. La durée courte (4-7 s) garde une marge de respi avant
    // de redescendre.
    final ceilingIdx = ctx.gen.milestoneHoldCeilingIdx();
    final holdDur = 4 + ctx.gen.rng.nextInt(4);
    final Position to;
    if (ceilingIdx >= Position.throat.index) {
      // Throat ou full débloqué : on tient profond même en récup. Le
      // user a explicitement validé la règle — pas de hold doux quand
      // tu sais tenir gorge.
      to = ceilingIdx >= Position.full.index && ctx.gen.rng.nextDouble() < 0.30
          ? Position.full
          : Position.throat;
    } else if (ceilingIdx >= Position.mid.index) {
      to = Position.mid;
    } else {
      to = ctx.gen.rng.nextBool() ? Position.tip : Position.head;
    }
    return StepDraft(
      mode: SessionMode.hold,
      bpm: null,
      from: null,
      to: to,
      duration: holdDur,
    );
  }

  /// Hold post-final = 2 variantes (tip + head). Blocked si le final
  /// vient juste d'être un hold (alternance), si la dose Custom hold
  /// est 0, ou si la joueuse a déjà acquis un palier de hold plus
  /// profond (philo design : « le seul hold qui a du sens est le plus
  /// profond que tu sais tenir » — un hold tip/head post-orgasme alors
  /// que mid est acquis est juste une régression arbitraire).
  @override
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) {
    final isFinalHold = ctx.finalMode == SessionMode.hold;
    final forbidden = ctx.isModeForbidden(SessionMode.hold);
    final tipObsolete = ctx.holdCeilingIdx > Position.tip.index;
    final headObsolete = ctx.holdCeilingIdx > Position.head.index;
    return [
      PostFinalVariant(
        req: 20.0,
        blocked: isFinalHold || tipObsolete || forbidden,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.tip,
          duration: ctx.duration,
        ),
      ),
      PostFinalVariant(
        req: 70.0,
        blocked: isFinalHold || headObsolete || forbidden,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.head,
          duration: ctx.duration,
        ),
      ),
    ];
  }

  /// Jusqu'à 5 variantes finales :
  ///  * `tip` (req 5, gate `finalHoldTip`) — surcote 5 : faible
  ///    profondeur mais sauce sur la langue.
  ///  * `head` (req 14, gate `finalHoldHead`) — surcote 14 : sauce sur
  ///    le gland / bouche.
  ///  * `mid` (req 10, gate `finalHoldMid`) — surcote 10 : sauce
  ///    profonde dans la bouche.
  ///  * `throat` (gate `finalHoldThroat`) — si `maxDepth >= throat`.
  ///    Durée et req adaptatives : à humilCap=10 on tient 10 s minimum ;
  ///    +2 s par tranche de 5 points d'humil au-dessus, +2 s par point
  ///    endurance. Cap 80 s (aligné full). `trimHoldFinalDuration`
  ///    redescend la durée si humilCap est trop juste.
  ///  * `full` (gate `finalHoldFull`) — si `maxDepth >= full`. Même
  ///    formule mais introduction à humilCap=30, +3 s par tranche de 8,
  ///    +3 s par point endurance.
  ///
  /// Le cap haut 80 s n'est mordant qu'en mode hérité (Custom, scénarios) ;
  /// en carrière, c'est `clampToCapability` qui pilote la durée vécue
  /// d'après le profil de capacités prouvé.
  @override
  List<FinalVariant> finalVariants(FinalCtx ctx) {
    final out = <FinalVariant>[
      FinalVariant(
        req: 5.0,
        gate: UnlockKey.finalHoldTip,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.tip,
          duration: ctx.shortHoldDur,
        ),
      ),
      FinalVariant(
        req: 14.0,
        gate: UnlockKey.finalHoldHead,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.head,
          duration: ctx.shortHoldDur,
        ),
      ),
      FinalVariant(
        req: 10.0,
        gate: UnlockKey.finalHoldMid,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.mid,
          duration: ctx.shortHoldDur,
        ),
      ),
    ];

    if (ctx.maxDepth >= Position.throat.index) {
      final humilOver = max(0.0, ctx.humilCap - 10.0);
      final targetDur =
          (10 + (humilOver / 5).floor() * 2 + ctx.endPts * 2).clamp(10, 80);
      final dur = FinalPicker.trimHoldFinalDuration(
        target: targetDur,
        humilCap: ctx.humilCap,
        baseReq: 21.5, // hold throat 10s
        bonusPerSec: 1.5,
        finishMul: ctx.finishMul,
        maxDur: 80,
      );
      final req = 8.0 + (dur - 1) * 1.5;
      out.add(FinalVariant(
        req: req,
        gate: UnlockKey.finalHoldThroat,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.throat,
          duration: dur,
        ),
      ));
    }

    if (ctx.maxDepth >= Position.full.index) {
      final humilOver = max(0.0, ctx.humilCap - 30.0);
      final targetDur =
          (10 + (humilOver / 8).floor() * 3 + ctx.endPts * 3).clamp(10, 80);
      final dur = FinalPicker.trimHoldFinalDuration(
        target: targetDur,
        humilCap: ctx.humilCap,
        baseReq: 49.0, // hold full 10s
        bonusPerSec: 3.0,
        finishMul: ctx.finishMul,
        maxDur: 80,
      );
      final req = 22.0 + (dur - 1) * 3.0;
      out.add(FinalVariant(
        req: req,
        gate: UnlockKey.finalHoldFull,
        draft: StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.full,
          duration: dur,
        ),
      ));
    }

    return out;
  }

  /// Hold en throat/full = profil intense capable de déclencher un
  /// faux-breath. Pas de check BPM (hold n'a pas de tempo).
  @override
  bool isIntenseForFakeBreath(StepDraft draft) =>
      draft.to == Position.throat || draft.to == Position.full;

  /// Rang 3 (fallback ultime) dans la chaîne d'intro intense/quickie :
  /// hold statique quand tous les modes rythmés/langue sont exclus.
  @override
  int? get introPriority => 3;

  /// Intro hold : ignore bpm/from du ctx, garde seulement la position
  /// tenue (`to`) et la durée. Le hold n'a ni tempo ni amplitude.
  @override
  StepDraft buildIntroStep(IntroCtx ctx) => StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: null,
        to: ctx.to,
        duration: ctx.duration,
      );
}
