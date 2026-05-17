// Fichier part de `career_session_generator.dart` — contrat « ModeRules ».
//
// Objectif : remplacer progressivement les gros `switch (draft.mode)`
// éparpillés (stamina, humiliation gates, capability clamp, dispatch
// difficulté…) par un dispatch polymorphique. Un fichier par mode (à
// terme), chacun posant ses règles locales, le générateur n'orchestre
// plus que la cascade commune.
//
// Migration **incrémentale** : pour chaque méthode ajoutée au contrat,
// on fournit une implémentation par défaut, puis on migre mode par mode.
// Tant qu'un mode n'a pas override, le switch historique reste autoritaire.
//
// Migrations livrées :
//   * `delta` — calcul du Δ endurance (cf. `_StaminaModel.delta`).
//   * `unlockKeyFor` — gate UnlockKey requis pour qu'un draft soit jouable
//     en mode carrière (cf. `_HumiliationGates.unlockKeyFor`).
//   * `clampToCapability` — bornes profondeur / BPM / durée issues du
//     profil de capacités (cf. `_CapabilityClamps.clampToCapability`).
//   * `tryDegrade` — stratégie de dégradation d'un cran pour la cascade
//     humiliation (cf. `_HumiliationGates.stepDownOne`).
//   * `build` — assemblage final du `_StepDraft` à partir des scores
//     (bpm/amp/dur) déjà budgétés par l'orchestrateur (cf. switch de
//     `_DifficultyDispatch._mapDifficultyToStep`).

part of 'career_session_generator.dart';

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

  /// Clé d'unlock requise pour qu'un step de ce mode soit jouable en mode
  /// carrière, ou `null` quand le step est dans le socle de base (pas de
  /// gate explicite).
  ///
  /// Override par défaut `null` — la migration depuis le switch de
  /// `_HumiliationGates.unlockKeyFor` se fait mode par mode, un mode non
  /// migré n'aura pas encore d'override ici et continuera à être servi
  /// par le switch historique.
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
  /// Migration **obligatoire** : toute rule doit override `build`. Le
  /// défaut throw plutôt qu'un fallback silencieux — `_DifficultyDispatch`
  /// est dispatcher pur, il n'y a plus de switch historique vers lequel
  /// retomber.
  _StepDraft build(_DraftCtx ctx) {
    throw UnimplementedError(
      '_ModeRules.build non implémenté pour $runtimeType',
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

/// Règles `breath` : toujours regen. Vitesse 2.8 stamina/s — règle de
/// design : un breath doit être plus court que les steps d'action qu'il
/// sépare, sinon la dramaturgie ressemble à « action / longue pause /
/// action / longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui
/// couvre un step rythme moyen (~20 de coût) et permet d'enchaîner.
class _BreathRules extends _ModeRules {
  const _BreathRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final regen = _StaminaModel.lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    return dur * 2.8 * regen;
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    final dur = _StaminaModel.lerp(6.0, 15.0, ctx.durScore).round();
    return _StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }
}

/// Règles `freestyle` : phase libre, neutre côté endurance (ni effort
/// ni vraie regen). Toujours gaté par `freestyle` (palier d'intro
/// `intro_freestyle` au niveau 7).
class _FreestyleRules extends _ModeRules {
  const _FreestyleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) => 0.0;

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) => UnlockKey.freestyle;

  @override
  _StepDraft build(_DraftCtx ctx) {
    final dur = _StaminaModel.lerp(8.0, 18.0, ctx.durScore).round();
    return _StepDraft(
      mode: SessionMode.freestyle,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }
}

/// Règles `suckle` : aspiration / téter. La bouche bosse sans aller-retour.
/// Coût par seconde modéré, plus marqué sur head (zone sensible → pompage
/// actif) que sur balls (sloppy soumis mais peu intense musculairement).
/// On modélise sur `_holdCostPerSec` de StaminaEngine en l'ajustant :
/// head ≈ 60 % d'un hold mid, balls ≈ 30 % (moins d'effort de la bouche,
/// plus de l'humil).
class _SuckleRules extends _ModeRules {
  const _SuckleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final pos = draft.to ?? draft.from;
    if (pos == Position.head) return -0.30 * dur;
    if (pos == Position.balls) return -0.15 * dur;
    return 0.0;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    // Suckle hors balls (filtré ailleurs) → forcément head. Gating
    // dédié, indépendant de la profondeur générique (suckle head n'est
    // pas une généralisation de hold head — c'est un geste explicite à
    // introduire pédagogiquement par sa propre milestone).
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.suckleBalls;
    }
    return UnlockKey.suckleHead;
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Aspiration : pas de BPM (pulse fixe ~1.2s côté audio), position
    // tenue dans `to`. Cibles valides = head ou balls (cf. `_isUnlocked`).
    // - En carrière : unlock `suckleHead` au level 4-5, `suckleBalls`
    //   plus tard ; le filtre `_isUnlocked` rejette ce qui n'est pas
    //   encore acquis et la cascade dégrade.
    // - En mode hérité (Custom) : balls n'est candidat que si l'anatomy
    //   l'inclut et que la profondeur max le permet (`_maxDepthIndex >=
    //   Position.balls.index`). On biaise vers head (zone classique) avec
    //   ~30 % de chances de tirer balls quand dispo, pour rester audible
    //   mais marginal.
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(8.0, 18.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    final ballsAllowed = ctx.gen._anatomy.hasBalls &&
        ctx.gen._maxDepthIndex >= Position.balls.index &&
        (ctx.gen._unlockedKeys.isEmpty ||
            ctx.gen._unlockedKeys.contains(UnlockKey.suckleBalls));
    final to = (ballsAllowed && ctx.gen._rng.nextDouble() < 0.30)
        ? Position.balls
        : Position.head;
    return _StepDraft(
      mode: SessionMode.suckle,
      bpm: null,
      from: null,
      to: to,
      duration: dur,
    );
  }
}

/// Règles `hand` : effort modéré côté endurance (la bouche se repose, mais
/// la main travaille). On consomme moins que rhythm équivalent.
class _HandRules extends _ModeRules {
  const _HandRules();

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
}

/// Règles `biffle` : effort soutenu (la fille encaisse), conso entre
/// rythme et hold, modulée par la profondeur.
class _BiffleRules extends _ModeRules {
  const _BiffleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 3.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) =>
      (draft.bpm ?? 0) > 100 ? UnlockKey.biffleFast : UnlockKey.biffleBasic;

  @override
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) {
    var bpm = draft.bpm;
    var dur = draft.duration;
    final durCap = c.capabilityCapFor(CapabilityAxis.biffleStreak);
    if (durCap != null && dur != null && dur > durCap) {
      dur = max(2, durCap.floor());
    }
    final bpmCap = c.capabilityCapFor(CapabilityAxis.biffleBpmMax);
    if (bpmCap != null && bpm != null && bpm > bpmCap) {
      bpm = bpmCap.round();
    }
    if (bpm == draft.bpm && dur == draft.duration) return draft;
    return _StepDraft(
      mode: draft.mode,
      bpm: bpm,
      bpmEnd: draft.bpmEnd,
      from: draft.from,
      to: draft.to,
      duration: dur,
      chainNext: draft.chainNext,
    );
  }

  @override
  _StepDraft? tryDegrade(_StepDraft draft) {
    // Biffle n'a pas de from/to (coups de queue sur le visage). Cascade :
    // cap BPM à 80, sinon repli sur lick tip→head qui devient une vraie
    // récup en bouche.
    if ((draft.bpm ?? 0) > 80) {
      return _StepDraft(
        mode: draft.mode,
        bpm: 80,
        from: draft.from,
        to: draft.to,
        duration: draft.duration,
      );
    }
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: draft.bpm ?? 60,
      from: draft.from ?? Position.tip,
      to: draft.to ?? Position.head,
      duration: draft.duration,
    );
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Biffle = coups de queue sur le visage : pas de notion de position.
    // from/to restent null.
    final bpm = _StaminaModel.lerp(80.0, 140.0, ctx.bpmScore).round();
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(15.0, 40.0, ctx.durScore),
      enduranceFactor: 0.05,
    );
    return _StepDraft(
      mode: SessionMode.biffle,
      bpm: bpm,
      from: null,
      to: null,
      duration: dur,
    );
  }
}

/// Règles `lick` : BPM ≤ 60 = vraie récup vocale (regen), au-delà = effort
/// léger (consommation modérée, plus de regen).
class _LickRules extends _ModeRules {
  const _LickRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = draft.bpm ?? 60;
    if (bpm <= 60) {
      final regen = _StaminaModel.lerp(
        cfg.regenStartMultiplier,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.2 * regen;
    }
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -depth * dur / 8.0;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.lickBalls;
    }
    // Lick X→full nécessite la milestone `intro_lick_full`. Sinon, lick
    // from=tip (toutes amplitudes ≤ throat) est du socle de base.
    if (draft.to == Position.full) return UnlockKey.lickFull;
    return null;
  }

  @override
  _StepDraft? tryDegrade(_StepDraft draft) =>
      _tryDescendToWithGuard(draft) ?? _tryDescendFrom(draft);

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Sloppy : monte le BPM minimum (≥ 65 = lick humide / saliveux).
    final sloppyPts = ctx.gen._pts(SpecializationBranch.sloppy);
    final lickBpmScore = sloppyPts > 0 ? max(ctx.bpmScore, 0.3) : ctx.bpmScore;
    final bpm = _StaminaModel.lerp(55.0, 80.0, lickBpmScore).round();
    // Tirage spécifique lick : tip→head forcé tant qu'humiliation < 2,
    // toutes amplitudes (incluant tip → throat/full) à partir de 2.
    final (from, to) = ctx.gen._sampleFromToForLick(ctx.ampScore);
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(10.0, 25.0, ctx.durScore),
      enduranceFactor: 0.04,
    );
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: bpm,
      from: from,
      to: to,
      duration: dur,
    );
  }
}

/// Règles `hold` : coût pur lié à la profondeur tenue (`to`). Convention
/// uniforme hold/beg : la position tenue est dans `to`.
class _HoldRules extends _ModeRules {
  const _HoldRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final depth = _StaminaModel.positionDepth(draft.to, draft.to);
    return -depth * dur / 2.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
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
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) =>
      _clampHeldDuration(draft, c);

  @override
  _StepDraft? tryDegrade(_StepDraft draft) {
    // (1) Hold throat/full long → raccourcir d'abord (la durée pèse
    // beaucoup sur l'humiliation requise, la position reste contractuelle).
    if ((draft.to == Position.throat || draft.to == Position.full) &&
        (draft.duration ?? 0) > 5) {
      return _StepDraft(
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
      return _StepDraft(
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
  _StepDraft build(_DraftCtx ctx) {
    // Convention uniforme hold/beg : la position tenue est dans `to`
    // (matche BeepEngine et le format SessionStep des JSON).
    final to = ctx.gen._pickHoldPosition(ctx.ampScore);
    final dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(8.0, 30.0, max(ctx.durScore, ctx.bpmScore)),
      enduranceFactor: 0.08,
    );
    return _StepDraft(
      mode: SessionMode.hold,
      bpm: null,
      from: null,
      to: to,
      duration: dur,
    );
  }
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

/// Règles `beg` : convention uniforme hold/beg, la position tenue est dans
/// `to`. Sans `to` ou `to = head` → assimilé à du repos vocal (regen). Avec
/// `to = mid/throat/full` → coût comme un hold à cette profondeur (la
/// position doit être tenue pendant la supplique).
class _BegRules extends _ModeRules {
  const _BegRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final to = draft.to;
    if (to == null || to == Position.head) {
      final regen = _StaminaModel.lerp(
        cfg.regenStartMultiplier,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.0 * regen;
    }
    final depth = _StaminaModel.positionDepth(to, to);
    return -depth * dur / 2.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
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
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) =>
      _clampHeldDuration(draft, c);

  @override
  _StepDraft? tryDegrade(_StepDraft draft) {
    // (1) Descendre `to` d'un cran (beg jusqu'à `tip` comme hold).
    if (draft.to != null && draft.to!.index > Position.tip.index) {
      return _StepDraft(
        mode: draft.mode,
        bpm: draft.bpm,
        from: draft.from,
        to: Position.values[draft.to!.index - 1],
        duration: draft.duration,
      );
    }
    // (2) Beg avec position tenue → repli sur beg libre.
    if (draft.to != null) {
      return _StepDraft(
        mode: draft.mode,
        bpm: draft.bpm,
        from: null,
        to: null,
        duration: draft.duration,
      );
    }
    return null;
  }

  @override
  _StepDraft build(_DraftCtx ctx) {
    // Convention uniforme hold/beg : la position tenue est dans `to`.
    // Obéissance : beg plus profonds (ampScore boosté localement) et
    // plus longs.
    final obPts = ctx.gen._pts(SpecializationBranch.obeissance);
    final begAmp = (ctx.ampScore + 0.10 * obPts).clamp(0.0, 1.0);
    final to = ctx.gen._pickBegPosition(begAmp);
    final baseDur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(7.0, 16.0, ctx.durScore),
      enduranceFactor: 0.04,
      extraFactor: obPts * 0.06,
    );
    final chained = ctx.gen._maybePickBegWithChain(
      to: to,
      obPts: obPts,
    );
    if (chained != null) return chained;
    return _StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: to,
      duration: baseDur,
    );
  }
}

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
class _RhythmRules extends _ModeRules {
  const _RhythmRules();

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    // Rhythm n'a pas de variante balls valide (les modes-incompatibles
    // balls sont filtrés en amont par `_HumiliationGates.isUnlocked`).
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
  _StepDraft? tryDegrade(_StepDraft draft) {
    // Cascade rythme : descendre `to` → descendre `from` → cap BPM à 80.
    final desc = _tryDescendToWithGuard(draft) ?? _tryDescendFrom(draft);
    if (desc != null) return desc;
    if ((draft.bpm ?? 0) > 80) {
      return _StepDraft(
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
  _StepDraft clampToCapability(_StepDraft draft, _CapabilityClamps c) {
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
          c.capabilityCapFor(_CapabilityClamps.rhythmBpmCeilAxisFor(to));
      if (from != null &&
          from.index <= Position.mid.index &&
          to.index >= Position.throat.index) {
        bpmCap = _CapabilityClamps.minNullable(
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
    return _StepDraft(
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
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 60).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
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
  _StepDraft build(_DraftCtx ctx) {
    final bpm = _StaminaModel.lerp(60.0, 140.0, ctx.bpmScore).round();
    final (from, to) = ctx.gen._sampleFromTo(ctx.ampScore);
    var dur = ctx.gen._scaleDuration(
      _StaminaModel.lerp(20.0, 60.0, ctx.durScore),
      enduranceFactor: 0.05,
    );
    // Cap par nombre d'aller-retours sur les profondeurs throat/full :
    // un step rythme à `to=throat` ne devrait pas enchaîner 30+ pulses
    // consécutifs (à 90 bpm, 60 s = 45 throats — la joueuse étouffe).
    // Cf. règle « passé to:throat, on se limite à un certain nombre
    // d'aller-retours par step ». Le cap est calculé en secondes :
    // durMax = maxPulses × 120 / bpm (×2 car pulse = 2 beats).
    dur = ctx.gen._capRhythmDurationByPulses(dur, bpm, to);
    // Cap rythme soutenu : tant que la milestone
    // `intro_rhythm_sustained` n'a pas été acquittée, la chaîne rythme
    // consécutive est plafonnée à 60 s. Le candidat n'arrive ici que
    // si `_canChainRhythm()` était vrai au tirage, donc il reste au
    // moins `_minRhythmStepSeconds` de marge.
    dur = ctx.gen._capRhythmConsecutive(dur);
    return _StepDraft(
      mode: SessionMode.rhythm,
      bpm: bpm,
      from: from,
      to: to,
      duration: dur,
    );
  }
}

/// Registry des règles par mode. La migration `staminaDelta` est terminée :
/// les 9 modes sont couverts, le switch de `_StaminaModel.delta` n'est plus
/// qu'un dispatch unique vers ce registry (cf. la méthode `delta`).
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
