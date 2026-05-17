// Fichier part de `career_session_generator.dart` — contrat « ModeRules »,
// value object de contexte (`_DraftCtx`), helpers mutualisés (descente
// d'amplitude, cap durée tenue) et registry par mode.
//
// Les implémentations vivent dans 9 fichiers `career_session_generator_rules_<mode>.dart`
// (un par `SessionMode`). Le générateur n'orchestre plus que la cascade
// commune ; tout ce qui est mode-specific est polymorphisé via ce contrat.
//
// Méthodes du contrat — chacune a remplacé un gros `switch (mode)`
// historique du générateur :
//   * `delta` — Δ endurance (ex-`_StaminaModel.delta`).
//   * `unlockKeyFor` — gate UnlockKey requis pour qu'un draft soit jouable
//     en carrière (ex-`_HumiliationGates.unlockKeyFor`).
//   * `clampToCapability` — bornes profondeur / BPM / durée du profil
//     de capacités (ex-`_CapabilityClamps.clampToCapability`).
//   * `tryDegrade` — un cran de dégradation pour la cascade humiliation
//     (ex-`_HumiliationGates.stepDownOne`).
//   * `build` — assemblage du `_StepDraft` final à partir des scores
//     (bpm/amp/dur) budgétés par l'orchestrateur (ex-switch de
//     `_DifficultyDispatch._mapDifficultyToStep`).
//   * `classify` — cluster sémantique (`_StepType`) consommé par la
//     friction de continuité (`_ModePicker.continuityMultiplier`) et le
//     tracking (`_SessionRuntimeState.recordContinuity`).
//   * `finalCategory` — variante de `finale_chime` à piocher si le mode
//     se retrouve en final d'apothéose (ex-`_categorizeFinal`).

part of 'career_session_generator.dart';

/// Cluster sémantique d'un step, utilisé pour assurer la cohérence de
/// la séance : on doit rester plusieurs steps consécutifs sur le même
/// type avant d'en changer (sauf `transit` qui est une parenthèse
/// transparente : breath de récup, freestyle).
///
/// - `bouche` (rhythm, hold, beg-non-libre, suckle) : cœur de l'app, on
///   y passe la majorité du temps.
/// - `langue` (lick) : variante douce, intros et transitions.
/// - `libreMain` (hand, biffle, beg-libre) : la bouche est libre, la
///   stim vient de la main / d'un coup / d'une supplique vocale pure.
/// - `transit` (breath, freestyle) : pause neutre, ne casse pas la
///   continuité du type courant.
enum _StepType { bouche, langue, libreMain, transit }

/// Contexte d'assemblage d'un step passé à `_ModeRules.build`. Porte les
/// trois scores déjà budgétés par l'orchestrateur (cf.
/// `_DifficultyDispatch._mapDifficultyToStep` pour la simplex + le bonus
/// de spé par axe) et un handle vers le générateur pour accéder aux
/// samplers (`_positionPickers`), caps (`_capRhythm*`, `_scaleDuration`),
/// lecture de spé (`_pts`) et state stable (`_rng`, `_anatomy`,
/// `_maxDepthIndex`, `_unlockedKeys`).
///
/// Le couplage est explicite (`ctx.gen.x`) — la consolidation de la
/// logique mode-specific dans les rules s'arrête à la frontière des
/// services déjà extraits (`_positionPickers`, `_BpmPacing`). Le ctx
/// n'a pas vocation à grossir : si une rule a besoin d'une donnée
/// supplémentaire, la passer via `gen` plutôt que d'ajouter un field.
class _DraftCtx {
  const _DraftCtx({
    required this.bpmScore,
    required this.ampScore,
    required this.durScore,
    required this.gen,
  });

  final double bpmScore;
  final double ampScore;
  final double durScore;
  final CareerSessionGenerator gen;
}

/// Snapshot des conditions d'éligibilité d'un mode à la phase de récup,
/// passé à `_ModeRules.isRecoveryCandidate`. Construit une seule fois par
/// `_buildRecoveryStep` et partagé avec toutes les rules consultées.
///
/// `heritage` (= `unlockedKeys.isEmpty`) marque les sessions hors-carrière :
/// dans ce mode, le gating par milestone est court-circuité (tous les
/// modes passent par défaut). Symétrique de la convention déjà appliquée
/// par `_isUnlocked` ailleurs.
class _RecoveryAvailability {
  const _RecoveryAvailability({
    required this.heritage,
    required this.unlockedKeys,
    required this.includeHand,
  });

  final bool heritage;
  final Set<UnlockKey> unlockedKeys;
  final bool includeHand;
}

/// Contexte d'assemblage d'un draft de récup passé à
/// `_ModeRules.buildRecovery`. Le BPM et la durée par défaut sont tirés
/// une seule fois par `_buildRecoveryStep` pour garantir une cohérence
/// inter-modes du contrat de récup (BPM ≤ 60, fenêtre 10–18 s) ; les
/// rules qui dérivent leur propre durée (beg 6–11 s, freestyle 8–15 s,
/// hold 4–7 s) peuvent simplement les ignorer.
class _RecoveryCtx {
  const _RecoveryCtx({
    required this.gen,
    required this.bpm,
    required this.duration,
  });

  final CareerSessionGenerator gen;
  final int bpm;
  final int duration;
}

/// Règles d'un mode : tout ce qui est spécifique au mode et qui était
/// auparavant porté par les gros switches du générateur (stamina,
/// unlock gate, capability clamp, dégradation, construction de step).
///
/// La plupart des méthodes sont **pures** (signature `(draft, …) →
/// résultat`, pas d'accès à l'état). Seule `build` reçoit un `_DraftCtx`
/// qui expose le générateur — la rule y consomme ses samplers / caps
/// (`_positionPickers`, `_capRhythm*`, `_scaleDuration`) et state stable
/// (`_rng`, `_anatomy`, `_maxDepthIndex`, `_unlockedKeys`, `_spec` via
/// `_pts`). Les helpers numériques partagés vivent côté `_StaminaModel`
/// (`positionDepth`, `lerp`).
abstract class _ModeRules {
  const _ModeRules();

  /// Coût (négatif) ou regen (positif) d'endurance pour le step.
  double delta(_StepDraft draft, double progress, CareerLevel cfg);

  /// Cluster sémantique du step (`bouche` / `langue` / `libreMain` /
  /// `transit`) consommé par la friction de continuité (`_ModePicker`)
  /// et le tracking (`_SessionRuntimeState.recordContinuity`).
  ///
  /// Le paramètre `to` n'est utilisé que par `beg` (avec position tenue
  /// → `bouche`, libre → `libreMain`) ; les autres rules l'ignorent. Au
  /// moment du tirage d'un candidat (`_ModePicker.continuityMultiplier`),
  /// le caller passe `null` — un beg-candidat est traité comme libre par
  /// défaut (cf. doc du caller).
  _StepType classify(Position? to);

  /// Variante de `finale_chime` à piocher si le mode se retrouve en
  /// final d'apothéose (cf. `_FinalPicker.pickFinal` côté palette,
  /// `BeepEngine.playFinaleChime` côté audio). Default `medium` —
  /// couvre biffle, lick, rhythm, beg, breath, freestyle, suckle qui
  /// soit n'apparaissent jamais en final, soit reçoivent une finition
  /// neutre. Hand override en `easy` (finition douce), hold override
  /// avec un switch sur `to` (tip→easy, head/mid→medium, throat→hard,
  /// full→extreme, balls→hard).
  FinalCategory finalCategory(_StepDraft draft) => FinalCategory.medium;

  /// Clé d'unlock requise pour qu'un step de ce mode soit jouable en mode
  /// carrière, ou `null` quand le step est dans le socle de base (pas de
  /// gate explicite). Default `null` = socle (rhythm tip→head, hold tip…).
  ///
  /// Convention `_isUnlocked` (hors interface ici, mais appliquée par le
  /// caller) : `unlockedKeys.isEmpty` = mode hérité, aucun gating. Cette
  /// méthode ne tient pas compte de cette convention — elle retourne
  /// toujours la clé mécanique.
  UnlockKey? unlockKeyFor(_StepDraft draft) => null;

  /// Borne un draft à l'enveloppe « profil de capacités » : profondeur,
  /// BPM et durée ne dépassent pas ce que la joueuse a *prouvé* tenir.
  /// Default = identité (les modes non pilotants — `hand`, `lick`,
  /// `breath`, `freestyle`, `suckle` — ne sont jamais clampés par le
  /// profil ; cf. règle « hand n'est jamais un levier de difficulté »).
  ///
  /// La gestion centrale de `chainNext` (récursion) et de la composition
  /// avec `clampToCustomLimits` (bornes utilisateur Custom) reste côté
  /// `_CapabilityClamps.clampToCapability` — chaque rule ne touche qu'à
  /// son draft principal.
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) => draft;

  /// Une étape de dégradation : retourne le draft modifié si la rule sait
  /// adoucir, ou `null` pour passer la main au fallback global (lick
  /// tip→head). Appelée en boucle par `_HumiliationGates.enforceRequired`
  /// jusqu'à ce que le draft satisfasse `humilCap` ET `isUnlocked`.
  ///
  /// Chaque rule choisit l'ordre de ses propres stratégies (raccourcir,
  /// baisser `to`, baisser `from`, capper BPM, changer de mode) ; on ne
  /// retourne qu'**un seul** cran par appel pour permettre à la cascade
  /// externe de re-vérifier l'humil/unlock après chaque pas.
  _StepDraft? tryDegrade(_StepDraft draft) => null;

  /// Assemble le `_StepDraft` final du mode à partir des scores déjà
  /// budgétés par l'orchestrateur. Voir `_DraftCtx` pour la surface du
  /// contexte. La rule consomme ses propres samplers / caps mode-specific
  /// via `ctx.gen.*` (le couplage est explicite, cf. doc de `_DraftCtx`).
  ///
  /// **Obligatoire** : toute rule doit override `build`. Le défaut throw
  /// plutôt qu'un fallback silencieux — `_DifficultyDispatch` est
  /// dispatcher pur, il n'y a plus de switch historique vers lequel
  /// retomber.
  _StepDraft build(_DraftCtx ctx) {
    throw UnimplementedError(
      '_ModeRules.build non implémenté pour $runtimeType',
    );
  }

  /// Indique si ce mode est candidat à la phase de récup étant donné
  /// les unlocks acquis et le toggle Hand. Default `false` (opt-in
  /// explicite) — `hand`, `breath` et `suckle` ne sont jamais tirés
  /// en récup, ils gardent le défaut.
  ///
  /// Le filtrage par dose Custom (`coachModeWeights`), la friction de
  /// continuité (`_ModePicker.filterRepeated` / `pickWeighted`) et le
  /// check final `_isUnlocked` (qui dégrade en cascade) restent côté
  /// orchestrateur — ce gate est uniquement « éligibilité par défaut
  /// + unlock requis pour entrer dans la palette ».
  bool isRecoveryCandidate(_RecoveryAvailability a) => false;

  /// Construit le draft de récup pour ce mode. Appelé uniquement après
  /// que le mode a été retenu par le tirage pondéré (donc après que
  /// `isRecoveryCandidate` a retourné `true`). Default throw — toute
  /// rule qui opt-in doit override.
  _StepDraft buildRecovery(_RecoveryCtx ctx) {
    throw UnimplementedError(
      '_ModeRules.buildRecovery non implémenté pour $runtimeType',
    );
  }
}

/// Baisse `to` d'un cran en s'arrêtant à `head` (jamais à `tip` — un step
/// rythmique a besoin d'au moins une amplitude tip↔head). Garde-fou
/// collision : si la descente ferait `from >= to` (ex. head→mid → head→head
/// interdit), on retourne `null` pour passer à la stratégie suivante.
/// Helper mutualisé par les modes à amplitude (rhythm / lick / hand).
_StepDraft? _tryDescendToWithGuard(_StepDraft d) {
  if (d.to == null || d.to!.index <= Position.head.index) return null;
  final newToIdx = d.to!.index - 1;
  final fromIdx = d.from?.index ?? -1;
  if (newToIdx <= fromIdx) return null;
  return _StepDraft(
    mode: d.mode,
    bpm: d.bpm,
    from: d.from,
    to: Position.values[newToIdx],
    duration: d.duration,
    chainNext: d.chainNext,
  );
}

/// Baisse `from` d'un cran en s'arrêtant à `tip`. Helper mutualisé par les
/// modes à amplitude.
_StepDraft? _tryDescendFrom(_StepDraft d) {
  if (d.from == null || d.from!.index <= Position.tip.index) return null;
  return _StepDraft(
    mode: d.mode,
    bpm: d.bpm,
    from: Position.values[d.from!.index - 1],
    to: d.to,
    duration: d.duration,
    chainNext: d.chainNext,
  );
}

/// Cap durée mutualisé hold + beg : convention `to` porte la position
/// tenue (repli `from`). Pour throat / full, on prend le min des deux
/// axes pertinents — la durée tenable de la position ET l'apnée prouvée.
_StepDraft _clampHeldDuration(_StepDraft draft, _CapabilityClamps c) {
  var dur = draft.duration;
  final held = draft.to ?? draft.from;
  if (held != Position.throat && held != Position.full) return draft;
  final cap = _CapabilityClamps.minNullable(
    c.capabilityCapFor(held == Position.throat
        ? CapabilityAxis.holdThroatStreak
        : CapabilityAxis.holdFullStreak),
    c.capabilityCapFor(CapabilityAxis.gorgeApneeStreak),
  );
  if (cap == null || dur == null || dur <= cap) return draft;
  dur = max(2, cap.floor());
  return _StepDraft(
    mode: draft.mode,
    bpm: draft.bpm,
    bpmEnd: draft.bpmEnd,
    from: draft.from,
    to: draft.to,
    duration: dur,
    chainNext: draft.chainNext,
  );
}

/// Registry des règles par mode. Les 9 modes sont couverts par leurs
/// fichiers dédiés ; les cinq call sites (`_StaminaModel.delta`,
/// `_HumiliationGates.unlockKeyFor`, `_CapabilityClamps.clampToCapability`,
/// `_HumiliationGates.stepDownOne`, `_DifficultyDispatch._mapDifficultyToStep`)
/// sont devenus de simples lookups + appel polymorphique sur ce registry.
final Map<SessionMode, _ModeRules> _modeRulesRegistry = {
  SessionMode.rhythm: const _RhythmRules(),
  SessionMode.lick: const _LickRules(),
  SessionMode.hold: const _HoldRules(),
  SessionMode.biffle: const _BiffleRules(),
  SessionMode.beg: const _BegRules(),
  SessionMode.hand: const _HandRules(),
  SessionMode.breath: const _BreathRules(),
  SessionMode.freestyle: const _FreestyleRules(),
  SessionMode.suckle: const _SuckleRules(),
};
