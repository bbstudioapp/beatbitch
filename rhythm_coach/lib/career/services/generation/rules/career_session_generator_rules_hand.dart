// Library autonome — règles du mode
// `hand`. Cf. contrat `ModeRules` dans
// `career_session_generator_mode_rules.dart`.

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

/// Règles `hand` : effort modéré côté endurance (la bouche se repose, mais
/// la main travaille). On consomme moins que rhythm équivalent.
class HandRules extends ModeRules {
  const HandRules();

  @override
  Set<ModeSemanticRole> get roles => const {ModeSemanticRole.burstNeutral};

  @override
  StepType classify(Position? to) => StepType.libreMain;

  @override
  bool get isRhythmic => true;

  /// Poids neutre + boost léger rythmeBiffle (hand est un mode rythmé
  /// — cohérent qu'une joueuse rythmeBiffle en voie un peu plus). La
  /// friction de continuité par type pilote toujours son apparition
  /// principale (intro + reprises de souffle).
  @override
  double baseWeight(SpecializationAllocation spec) =>
      1.0 + 0.15 * spec.pointsIn(SpecializationBranch.rythmeBiffle);

  /// Hand final → chime `easy` : la finition à la main reste douce, on
  /// ne dramatise pas avec un chime de gorge.
  @override
  FinalCategory finalCategory(StepDraft draft) => FinalCategory.easy;

  @override
  double delta(StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 6.0;
  }

  @override
  StepDraft? tryDegrade(StepDraft draft) =>
      tryDescendToWithGuard(draft) ?? tryDescendFrom(draft);

  @override
  StepDraft build(DraftCtx ctx) {
    // Hand sert d'outil d'excitation/endurance pure : sa fréquence peut
    // grimper sans coût d'humiliation. Plage très large pour permettre
    // récup lente (60 BPM) jusqu'à burst frénétique (180 BPM).
    final bpm = StaminaModel.lerp(60.0, 180.0, ctx.bpmScore).round();
    // Tirage spécifique hand : la main tient la base de la queue, donc
    // l'amplitude reste dans le haut (jamais plus profond que throat).
    // En revanche tip→head et head→head sont autorisés (le tirage
    // commun les exclut pour les autres modes).
    final (from, to) = ctx.gen.sampleFromToForHand(ctx.ampScore);
    final dur = ctx.gen.config.scaleDuration(
      StaminaModel.lerp(15.0, 30.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    return StepDraft(
      mode: SessionMode.hand,
      bpm: bpm,
      from: from,
      to: to,
      duration: dur,
    );
  }

  /// Hand post-final = finition douce tip→head. Blocked si le toggle
  /// Hand est off, si hand vient juste d'être joué en final (alternance),
  /// ou si la dose Custom hand est 0.
  @override
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) => [
        PostFinalVariant(
          req: 8.0,
          blocked: !ctx.includeHand ||
              ctx.finalMode == SessionMode.hand ||
              ctx.isModeForbidden(SessionMode.hand),
          draft: StepDraft(
            mode: SessionMode.hand,
            bpm: ctx.bpm,
            from: Position.tip,
            to: Position.head,
            duration: ctx.duration,
          ),
        ),
      ];

  /// Hand baseline en final (req 0, pas de gate dédiée — c'est le
  /// fallback universel quand aucun autre final n'est unlocké).
  /// Émis uniquement aux **niveaux 1-3** : le finish bas niveau a besoin
  /// de cette baseline tant que les finals gated (hold tip / lick tip→head
  /// / hold head…) ne sont pas acquittés. Niveau ≥ 4 : retiré
  /// (`ctx.handBaselineBpm == null`) — un hand-final est trop anodin
  /// pour clôturer une séance à ce stade. Il ne subsiste alors que
  /// comme fallback technique ultime côté picker, ou si une
  /// milestone-final venait à le scripter explicitement.
  @override
  List<FinalVariant> finalVariants(FinalCtx ctx) {
    if (ctx.handBaselineBpm == null) return const [];
    return [
      FinalVariant(
        req: 0.0,
        gate: null,
        draft: StepDraft(
          mode: SessionMode.hand,
          bpm: ctx.handBaselineBpm,
          from: Position.head,
          to: Position.mid,
          duration: ctx.fastDur,
        ),
      ),
    ];
  }

  /// Hand : profondeur d'amplitude max = `full` (4) pour la
  /// diversification — symétrique avec lick, pas de tension de
  /// profondeur côté gating (cf. règle « hand n'est jamais un levier
  /// de difficulté »).
  @override
  int? amplitudeDiversifyCeiling(GenFacadeSurface gen) => Position.full.index;

  /// Hand en throat/full à BPM ≥ 90 = profil intense capable de
  /// déclencher un faux-breath (même logique que rhythm).
  @override
  bool isIntenseForFakeBreath(StepDraft draft) =>
      (draft.to == Position.throat || draft.to == Position.full) &&
      (draft.bpm ?? 0) >= 90;

  /// Rang 1 (1er fallback) dans la chaîne d'intro intense/quickie :
  /// rythmé proche de rhythm, prend le relais quand rhythm est exclu
  /// en Custom.
  @override
  int? get introPriority => 1;

  /// Intro main : consomme les 4 params du ctx straight, comme rhythm
  /// (l'acoustique change mais la forme du step est identique).
  @override
  StepDraft buildIntroStep(IntroCtx ctx) => StepDraft(
        mode: SessionMode.hand,
        bpm: ctx.bpm,
        from: ctx.from,
        to: ctx.to,
        duration: ctx.duration,
      );

  /// Palette d'intro standard main : une seule variante `tip→head 55
  /// BPM 18s` quand le toggle `includeHand` est actif (le générateur
  /// thread la valeur via `IntroStandardCtx.includeHand`). Sinon palette
  /// vide — la rule porte elle-même le guard, plus de
  /// `if (_config.includeHand)` côté `_firstStep`.
  @override
  List<StepDraft> firstStepVariants(IntroStandardCtx ctx) {
    if (!ctx.includeHand) return const [];
    return const [
      StepDraft(
        mode: SessionMode.hand,
        bpm: 55,
        from: Position.tip,
        to: Position.head,
        duration: 18,
      ),
    ];
  }
}
