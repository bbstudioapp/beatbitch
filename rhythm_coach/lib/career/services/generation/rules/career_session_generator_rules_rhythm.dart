// Library autonome — règles du mode
// `rhythm`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

import 'dart:math';

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `rhythm` : coût modulé par profondeur cible (mid pèse le plus :
/// c'est la zone où on tient le rythme le plus longtemps), atténué par le
/// bénéfice de respiration au creux du va-et-vient (qui s'évanouit à haute
/// vitesse).
///
/// Multiplicateurs de coût accentués dès que `to` atteint mid (idx 2).
/// to=mid: ×1.45, to=throat: ×1.30, to=full: ×1.15.
///
/// Bénéfice respi : un step à grande amplitude (tip→full, mid→throat)
/// laisse une fenêtre de respi. À l'inverse, throat/full ou throat/throat
/// = pas de respi, coût plein. Formule :
///   `amplitudeFactor ∈ [0,1] = (toIdx − fromIdx) / 4`
///   `bpmFactor ∈ [0,1] = clamp((100 − bpm) / 40, 0, 1)`
///   `respiBenefit = amplitudeFactor × bpmFactor × 0.40`
/// → tip→full 60 bpm : −40 % de coût
/// → mid→full 60 bpm : −20 %
/// → throat→full 60 bpm : −10 %
/// → mid→full 100 bpm : 0 % (BPM trop haut)
class RhythmRules extends ModeRules {
  const RhythmRules();

  @override
  Set<ModeSemanticRole> get roles => const {
        ModeSemanticRole.burstHumiliating,
        ModeSemanticRole.miniWaveCore,
        ModeSemanticRole.preFinisherCore,
      };

  @override
  StepType classify(Position? to) => StepType.bouche;

  @override
  UnlockKey? unlockKeyFor(StepDraft draft) {
    // Rhythm n'a pas de variante balls valide (les modes-incompatibles
    // balls sont filtrés en amont par `HumiliationGates.isUnlocked`).
    // Pour rester strictement isomorphe au switch historique on retourne
    // null si touchesBalls — le filtre amont coupe avant.
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return null;
    }
    if (draft.to == Position.full) return UnlockKey.fullPulse;
    if (draft.to == Position.throat) return UnlockKey.throatPulse;
    if (draft.to == Position.mid) return UnlockKey.rhythmMidBasic;
    // Rythme superficiel (tip→head) = socle de base, pas de clé.
    if ((draft.bpm ?? 0) >= 160) return UnlockKey.rhythmExtreme;
    return null;
  }

  @override
  StepDraft? tryDegrade(StepDraft draft) {
    // Cascade rythme : descendre `to` → descendre `from` → cap BPM à 80.
    final desc = tryDescendToWithGuard(draft) ?? tryDescendFrom(draft);
    if (desc != null) return desc;
    if ((draft.bpm ?? 0) > 80) {
      return StepDraft(
        mode: draft.mode,
        bpm: 80,
        from: draft.from,
        to: draft.to,
        duration: draft.duration,
      );
    }
    return null;
  }

  @override
  StepDraft clampToCapability(StepDraft draft, CapabilityClampSurface c) {
    var from = draft.from;
    var to = draft.to;
    var bpm = draft.bpm;
    var bpmEnd = draft.bpmEnd;
    var dur = draft.duration;

    // Profondeur (cran). Plancher `head` : un rhythm a besoin d'au moins
    // une amplitude tip↔head, jamais tip↔tip.
    final depthCap = c.capabilityCapFor(CapabilityAxis.rhythmDepthMax);
    if (depthCap != null && to != null) {
      final capIdx = max(Position.head.index,
          depthCap.round().clamp(0, Position.values.length - 1));
      if (to.index > capIdx) to = Position.values[capIdx];
    }
    // Garde-fou amplitude `from < to` strict après abaissement de `to`.
    if (from != null && to != null && from.index >= to.index) {
      from = to.index > 0 ? Position.values[to.index - 1] : null;
    }
    // BPM : plafond de bande + plafond franchissement si pattern
    // franchissant (`from ≤ mid` ET `to ≥ throat`).
    if (to != null && (bpm != null || bpmEnd != null)) {
      var bpmCap =
          c.capabilityCapFor(CapabilityClamps.rhythmBpmCeilAxisFor(to));
      if (from != null &&
          from.index <= Position.mid.index &&
          to.index >= Position.throat.index) {
        bpmCap = CapabilityClamps.minNullable(
          bpmCap,
          c.capabilityCapFor(to == Position.throat
              ? CapabilityAxis.gorgeCrossingsBpmThroat
              : CapabilityAxis.gorgeCrossingsBpmFull),
        );
      }
      if (bpmCap != null) {
        final cap = bpmCap.round();
        if (bpm != null && bpm > cap) bpm = cap;
        if (bpmEnd != null && bpmEnd > cap) bpmEnd = cap;
      }
    }
    // Apnée : un stroke airless (`from ≥ throat`) borne sa durée à
    // l'apnée prouvée.
    if (from != null && from.index >= Position.throat.index && dur != null) {
      final apneaCap = c.capabilityCapFor(CapabilityAxis.gorgeApneeStreak);
      if (apneaCap != null && dur > apneaCap) {
        dur = max(2, apneaCap.floor());
      }
    }
    if (from == draft.from &&
        to == draft.to &&
        bpm == draft.bpm &&
        bpmEnd == draft.bpmEnd &&
        dur == draft.duration) {
      return draft;
    }
    return StepDraft(
      mode: draft.mode,
      bpm: bpm,
      bpmEnd: bpmEnd,
      from: from,
      to: to,
      duration: dur,
      chainNext: draft.chainNext,
    );
  }

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 60).toDouble();
    final depth = StaminaModel.positionDepth(draft.from, draft.to);
    final toIdx = (draft.to ?? draft.from)?.index ?? 0;
    final depthMul = toIdx >= Position.full.index
        ? 1.15
        : toIdx >= Position.throat.index
            ? 1.30
            : toIdx >= Position.mid.index
                ? 1.45
                : 1.0;
    final fromIdx = draft.from?.index ?? toIdx;
    final amplitude = (toIdx - fromIdx).clamp(0, 4);
    final amplitudeFactor = amplitude / 4.0;
    final respiBpmFactor = ((100.0 - bpm) / 40.0).clamp(0.0, 1.0);
    final respiBenefit = amplitudeFactor * respiBpmFactor * 0.40;
    final costFactor = (1.0 - respiBenefit).clamp(0.6, 1.0);
    return -(bpm / 100.0) * depth * dur * depthMul * costFactor / 3.0;
  }

  @override
  StepDraft build(DraftCtx ctx) {
    final bpm = StaminaModel.lerp(60.0, 140.0, ctx.bpmScore).round();
    final (from, to) = ctx.gen.sampleFromTo(ctx.ampScore);
    var dur = ctx.gen.config.scaleDuration(
      StaminaModel.lerp(20.0, 60.0, ctx.durScore),
      enduranceFactor: 0.05,
    );
    // Cap par nombre d'aller-retours sur les profondeurs throat/full :
    // un step rythme à `to=throat` ne devrait pas enchaîner 30+ pulses
    // consécutifs (à 90 bpm, 60 s = 45 throats — la joueuse étouffe).
    // Cf. règle « passé to:throat, on se limite à un certain nombre
    // d'aller-retours par step ». Le cap est calculé en secondes :
    // durMax = maxPulses × 120 / bpm (×2 car pulse = 2 beats).
    dur = ctx.gen.capRhythmDurationByPulses(dur, bpm, to);
    // Cap rythme soutenu : tant que la milestone
    // `intro_rhythm_sustained` n'a pas été acquittée, la chaîne rythme
    // consécutive est plafonnée à 60 s. Le candidat n'arrive ici que
    // si `_rhythmChain.canChain()` était vrai au tirage, donc il reste
    // au moins `RhythmChainTracker._minStepSeconds` de marge.
    dur = ctx.gen.rhythmChain.capDuration(dur);
    return StepDraft(
      mode: SessionMode.rhythm,
      bpm: bpm,
      from: from,
      to: to,
      duration: dur,
    );
  }

  /// Mini-vague rhythm : 3 steps head→mid puis head→mid puis
  /// head→throat-or-mid, BPMs montants 100 / 120 / 135. Durées
  /// décroissantes (12 / 10 / 8) — la vague accélère et se condense.
  /// Le `to` du dernier step est `throat` si débloqué (cf.
  /// `MiniWaveCtx.hasThroat`), sinon `mid` (vague plus douce mais
  /// dramaturgie préservée). Les BPMs sont volontairement espacés ≥ 20
  /// pour que `_patternBuffer.wouldBeFlat` ne déclenche pas.
  ///
  /// Le filtrage humil + clamp capacité + dédoublonnage post-cascade
  /// restent côté générateur (cf. `_buildMiniWave`).
  @override
  List<StepDraft>? buildMiniWaveSegment(MiniWaveCtx ctx) {
    return [
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 100,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 120,
        from: Position.head,
        to: Position.mid,
        duration: 10,
      ),
      StepDraft(
        mode: SessionMode.rhythm,
        bpm: 135,
        from: Position.head,
        to: ctx.hasThroat ? Position.throat : Position.mid,
        duration: 8,
      ),
    ];
  }

  /// Rhythm très doux comme « récup en bouche » : BPM bas, tip→head ou
  /// head→mid selon les unlocks, coût stamina modéré. Toujours candidat
  /// — la friction de continuité (`_ModePicker`) décide s'il gagne. Sans
  /// ça, une recovery déclenchée depuis bouche reste systématiquement
  /// bloquée hors bouche, et le pattern « rhythm → recovery → rhythm »
  /// fait des séries de 1 step.
  @override
  bool isRecoveryCandidate(RecoveryAvailability a) => true;

  @override
  StepDraft buildRecovery(RecoveryCtx ctx) {
    // La baseline (tip→head) reste ouverte tant que la joueuse n'a pas
    // appris la gorge — gate sur `throatHoldShort` plutôt que
    // `holdMidShort` : les premiers paliers ont besoin de variété
    // (tip→head, tip→mid, head→mid se mélangent), ce serait trop pauvre
    // de tout aligner sur head→mid dès le niveau 4. Dès que la gorge est
    // débloquée, le rhythm de recovery passe à head→mid — la baseline
    // doit refléter le niveau. BPM bas — le coût stamina reste modéré
    // pour ne pas creuser la dette d'endurance qu'on cherche justement
    // à combler ailleurs.
    final hasThroat =
        ctx.gen.state.unlockedKeys.contains(UnlockKey.throatHoldShort);
    return StepDraft(
      mode: SessionMode.rhythm,
      bpm: ctx.bpm,
      from: hasThroat ? Position.head : Position.tip,
      to: hasThroat ? Position.mid : Position.head,
      duration: ctx.duration,
    );
  }

  /// Rhythm post-final = reprise douce tip→head. Blocked si rhythm vient
  /// juste d'être joué en final (alternance) ou si la dose Custom rhythm
  /// est 0.
  @override
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) => [
        PostFinalVariant(
          req: 55.0,
          blocked: ctx.finalMode == SessionMode.rhythm ||
              ctx.isModeForbidden(SessionMode.rhythm),
          draft: StepDraft(
            mode: SessionMode.rhythm,
            bpm: ctx.bpm,
            from: Position.tip,
            to: Position.head,
            duration: ctx.duration,
          ),
        ),
      ];

  /// Pré-finisher rhythm : courte accélération `head → preFinisherTarget`
  /// qui prépare la phase boosts pour les bas niveaux. BPM 62-70 et
  /// durée 22-30 s — fenêtres historiques, deux tirages rng dans cet
  /// ordre exact pour préserver les sessions reproductibles à seed égal.
  /// La position cible est pré-pickée par le générateur via
  /// `_positionPickers.pickFinisherPosition` (consomme rng + état) et
  /// threadée via `ctx.preFinisherTarget`. Le clamp capacité et le pick
  /// de phrase restent côté générateur.
  @override
  StepDraft? buildPreFinisher(PreFinisherCtx ctx) {
    final dur = 22 + ctx.rng.nextInt(9); // [22, 30]
    final bpm = 62 + ctx.rng.nextInt(9); // [62, 70]
    return StepDraft(
      mode: SessionMode.rhythm,
      bpm: bpm,
      from: Position.head,
      to: ctx.preFinisherTarget,
      duration: dur,
    );
  }

  /// Rhythm consulte le plafond milestone pour la diversification
  /// d'amplitude : on ne décale jamais `to` au-dessus du palier de
  /// profondeur acquis.
  @override
  int? amplitudeDiversifyCeiling(GenFacadeSurface gen) =>
      gen.milestoneRhythmCeilingIdx();

  /// Rhythm en throat/full à BPM ≥ 90 = profil intense capable de
  /// déclencher un faux-breath taquin.
  @override
  bool isIntenseForFakeBreath(StepDraft draft) =>
      (draft.to == Position.throat || draft.to == Position.full) &&
      (draft.bpm ?? 0) >= 90;

  /// Rang 0 (préféré) dans la chaîne d'intro intense/quickie : un
  /// rythme bouche profond reste l'ouverture canonique.
  @override
  int? get introPriority => 0;

  /// Intro rythmée : consomme les 4 params du ctx straight (la fixture
  /// posée par `_firstStep` choisit déjà bpm/from/to/dur appropriés).
  @override
  StepDraft buildIntroStep(IntroCtx ctx) => StepDraft(
        mode: SessionMode.rhythm,
        bpm: ctx.bpm,
        from: ctx.from,
        to: ctx.to,
        duration: ctx.duration,
      );

  /// Palette d'intro standard rythme : 3 variantes douces qui couvrent
  /// le socle de base. `tip→head 65 BPM 16s` (variante d'amorce, dispo
  /// dès `intro_basics`), `head→mid 70 BPM 14s` et `tip→mid 65 BPM 16s`
  /// (gatées par `rhythm_mid_basic` = `intro_deeper_basics`, niveau 2).
  /// Le gating est appliqué côté générateur via `_isUnlocked`.
  @override
  List<StepDraft> firstStepVariants(IntroStandardCtx ctx) => const [
        StepDraft(
          mode: SessionMode.rhythm,
          bpm: 65,
          from: Position.tip,
          to: Position.head,
          duration: 16,
        ),
        StepDraft(
          mode: SessionMode.rhythm,
          bpm: 70,
          from: Position.head,
          to: Position.mid,
          duration: 14,
        ),
        StepDraft(
          mode: SessionMode.rhythm,
          bpm: 65,
          from: Position.tip,
          to: Position.mid,
          duration: 16,
        ),
      ];
}
