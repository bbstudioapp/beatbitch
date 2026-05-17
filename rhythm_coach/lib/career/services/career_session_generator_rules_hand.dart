// Fichier part de `career_session_generator.dart` — règles du mode
// `hand`. Cf. contrat `_ModeRules` dans
// `career_session_generator_mode_rules.dart`.

part of 'career_session_generator.dart';

/// Règles `hand` : effort modéré côté endurance (la bouche se repose, mais
/// la main travaille). On consomme moins que rhythm équivalent.
class _HandRules extends _ModeRules {
  const _HandRules();

  @override
  _StepType classify(Position? to) => _StepType.libreMain;

  /// Hand final → chime `easy` : la finition à la main reste douce, on
  /// ne dramatise pas avec un chime de gorge.
  @override
  FinalCategory finalCategory(_StepDraft draft) => FinalCategory.easy;

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

  /// Hand post-final = finition douce tip→head. Blocked si le toggle
  /// Hand est off, si hand vient juste d'être joué en final (alternance),
  /// ou si la dose Custom hand est 0.
  @override
  List<_PostFinalVariant> postFinalVariants(_PostFinalCtx ctx) => [
        _PostFinalVariant(
          req: 8.0,
          blocked: !ctx.includeHand ||
              ctx.finalMode == SessionMode.hand ||
              ctx.isModeForbidden(SessionMode.hand),
          draft: _StepDraft(
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
  List<_FinalVariant> finalVariants(_FinalCtx ctx) {
    if (ctx.handBaselineBpm == null) return const [];
    return [
      _FinalVariant(
        req: 0.0,
        gate: null,
        draft: _StepDraft(
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
  int? amplitudeDiversifyCeiling(CareerSessionGenerator gen) =>
      Position.full.index;

  /// Hand en throat/full à BPM ≥ 90 = profil intense capable de
  /// déclencher un faux-breath (même logique que rhythm).
  @override
  bool isIntenseForFakeBreath(_StepDraft draft) =>
      (draft.to == Position.throat || draft.to == Position.full) &&
      (draft.bpm ?? 0) >= 90;
}
