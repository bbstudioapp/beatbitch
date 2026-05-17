// Fichier part de `career_session_generator.dart` — palette du final
// d'apothéose + step post-final (aftercare).
//
// `_pickFinal` choisit l'**action longue tenue** qui clôture la séance :
// tri par humil croissante des candidats valides (filtre humilCap + gate
// final + unlock du composant + dose Custom), puis on prend le plus
// humiliant qui passe. Fallback dur sur un hand head→mid 50 BPM si la
// palette est vide.
//
// `_buildPostFinalDraft` choisit le **step post-orgasme** (aftercare ~12s) :
// mode contrastant avec le final, échelle req croissante, top-3 tiré
// uniformément. Biais spé sloppy/obeissance pour les niveaux avancés.
//
// Les deux méthodes partagent leur état — bundlé dans `FinalPicker`
// comme value object immuable construit une fois par `generate()`. Les 5
// champs immuables côté config (level, anatomy, spec, coachModeWeights,
// includeHand) sont consultés via `config.x` ; on garde `unlockedKeys` à
// part parce qu'il vit côté `_state` (mutable inter-séance via
// `markCompleted`, capturé en snapshot ici), et `rng` / `capClamps` sont
// des références non-config injectées par le caller.

part of 'career_session_generator.dart';

/// Picker du final + post-final. Immuable : le générateur en construit un
/// par appel à `generate()` après que `_capClamps` est posé. Toutes les
/// décisions de gating consultent ce snapshot — les mutations d'état du
/// tracking (`_lastMode`, etc.) ne concernent pas la palette finale.
class FinalPicker {
  /// Snapshot de la config de séance. On y lit `level`, `anatomy`, `spec`,
  /// `coachModeWeights`, `includeHand`.
  final SessionConfig config;

  /// Unlocks acquittés au moment où le picker est construit. Vit côté
  /// `_state` (peut être muté par `markCompleted` en cours de séance),
  /// snapshoté ici parce que le picker est lui-même immuable.
  final Set<UnlockKey> unlockedKeys;

  final Random rng;
  final CapabilityClamps capClamps;

  /// Registry des rules injecté par le générateur — consulté pour
  /// itérer sur les modes (`finalVariants`, `postFinalVariants`).
  final Map<SessionMode, ModeRules> rules;

  const FinalPicker({
    required this.config,
    required this.unlockedKeys,
    required this.rng,
    required this.capClamps,
    required this.rules,
  });

  int _pts(SpecializationBranch b) => config.spec.pointsIn(b);

  bool _isModeForbidden(SessionMode m) => config.isModeForbidden(m);

  bool _isUnlocked(StepDraft d) => _HumiliationGates.isUnlocked(
        d,
        anatomy: config.anatomy,
        unlockedKeys: unlockedKeys,
        rules: rules,
      );

  bool _finalUnlocked(UnlockKey? key) =>
      _HumiliationGates.finalUnlocked(key, unlockedKeys);

  /// Tronque la durée d'un hold final pour qu'elle reste finançable par
  /// `humilCap`. Le `target` peut être visé si l'humil suffit, sinon on
  /// redescend par paliers d'1s jusqu'à 10s minimum (= seuil d'unlock).
  /// Scaled par `finishMul` (mode encore). `maxDur` borne le cap haut,
  /// ouvert à 80s pour hold full + spé endurance maxée (cf. [pickFinal]).
  static int trimHoldFinalDuration({
    required int target,
    required double humilCap,
    required double baseReq,
    required double bonusPerSec,
    required double finishMul,
    int maxDur = 60,
  }) {
    final scaledTarget = (target * finishMul).round();
    var dur = scaledTarget.clamp(10, maxDur);
    while (dur > 10) {
      final req = baseReq + (dur - 10) * bonusPerSec;
      if (req <= humilCap) return dur;
      dur--;
    }
    return 10;
  }

  /// Final = action longue tenue qui clôture la séance. Distinct de la
  /// phase « finish » (boosts) ; le final est l'apothéose contemplative.
  /// Choisi parmi les candidats valides selon le score d'humiliation, le
  /// plafond de profondeur du niveau, et la durée des holds profonds qui
  /// scale avec le niveau et la chaîne d'encore.
  ///
  /// La palette est désormais portée par les rules via
  /// `ModeRules.finalVariants` : hand (baseline level<4), lick (tip→head
  /// + full→balls), hold (tip/head/mid + throat/full conditionnels),
  /// biffle (si `includeHand`). Le `gate` (`UnlockKey?` dédié final)
  /// remplace l'ancien `minLevel` : la progression est désormais
  /// gouvernée par les milestones `intro_final_*`, pas par un seuil de
  /// niveau implicite.
  StepDraft pickFinal({
    required double humilCap,
    required int maxDepth,
    required double finishMul,
  }) {
    final endPts = _pts(SpecializationBranch.endurance);
    final fastDur = ((14 + endPts) * finishMul).round().clamp(14, 60);
    final shortHoldDur = ((12 + endPts) * finishMul).round().clamp(12, 60);
    // Tirage rng UPFRONT pour préserver strictement l'ordre de
    // consommation (handBpm avant biffleBpm, conditionnels sur level<4
    // et includeHand comme dans la palette pré-refacto). Sans ça,
    // l'itération du registry (rhythm→lick→hold→biffle→…→hand→…)
    // rebattrait le rng et ferait diverger les sessions reproductibles.
    final handBaselineBpm = config.level < 4 ? (40 + rng.nextInt(21)) : null;
    final biffleBpm = config.includeHand ? (40 + rng.nextInt(21)) : null;

    final ctx = FinalCtx(
      humilCap: humilCap,
      maxDepth: maxDepth,
      finishMul: finishMul,
      level: config.level,
      anatomy: config.anatomy,
      unlockedKeys: unlockedKeys,
      includeHand: config.includeHand,
      endPts: endPts,
      fastDur: fastDur,
      shortHoldDur: shortHoldDur,
      handBaselineBpm: handBaselineBpm,
      biffleBpm: biffleBpm,
    );
    final candidates = <FinalVariant>[
      for (final rule in rules.values) ...rule.finalVariants(ctx),
    ];

    // Filtre humilCap + gate + unlocks composants, prend le plus humiliant
    // valide. Le gate est un `UnlockKey?` dédié au final ; null = libre.
    // `_isUnlocked` couvre les composants du draft (pour cohérence avec
    // le reste du générateur), `_finalUnlocked` couvre la gate du final.
    // Exclusions Custom (dose `none`) : on retire en plus les finals dont
    // le mode est explicitement banni — un final hold reste possible
    // quand rhythm est exclu, un final hand quand hold est exclu, etc.
    final valid = <FinalVariant>[];
    for (final c in candidates) {
      if (!_finalUnlocked(c.gate)) continue;
      if (_isModeForbidden(c.draft.mode)) continue;
      if (humilCap >= c.req && _isUnlocked(c.draft)) valid.add(c);
    }
    if (valid.isEmpty) {
      // Fallback dur : hand head→mid 50 BPM. Toujours unlocked, req=0,
      // garanti même si la palette change ou si humilCap est négatif.
      // Hand n'a pas d'axe de capacité → `clampToCapability` no-op.
      // Si hand est exclu en Custom, on retombe sur le 1ᵉʳ mode autorisé
      // disponible — hold head court reste un final acceptable.
      if (_isModeForbidden(SessionMode.hand)) {
        if (!_isModeForbidden(SessionMode.lick)) {
          return capClamps.clampToCapability(const StepDraft(
            mode: SessionMode.lick,
            bpm: 60,
            from: Position.tip,
            to: Position.head,
            duration: 16,
          ));
        }
        if (!_isModeForbidden(SessionMode.hold)) {
          return capClamps.clampToCapability(StepDraft(
            mode: SessionMode.hold,
            bpm: null,
            from: null,
            to: Position.head,
            duration: shortHoldDur,
          ));
        }
        // Aucun mode bouche dispo : on accepte le hand de secours
        // (l'éditeur Custom garantit qu'au moins un mode bouche reste —
        // ce chemin est un filet de sécurité pour les call sites
        // non-Custom).
      }
      return StepDraft(
        mode: SessionMode.hand,
        bpm: 50,
        from: Position.head,
        to: Position.mid,
        duration: fastDur,
      );
    }
    valid.sort((a, b) => a.req.compareTo(b.req));
    // 2ᵉ enveloppe : on tronque le final retenu au profil de capacités —
    // un hold throat/full d'apothéose ne dépasse pas la tenue prouvée.
    return capClamps.clampToCapability(valid.last.draft);
  }

  /// Step post-final (aftercare ~12 s après l'orgasme). Mode contrastant
  /// choisi selon le mode du final (si final = hold, pas de hold post ;
  /// si final = lick, pas de lick post ; etc.), puis on prend les **3
  /// plus humiliantes accessibles** et on tire uniformément dedans.
  /// Garde un peu de variété tout en respectant la progression : à
  /// humil 5 on tombe sur breath, à humil 100 on tombe sur les beg +
  /// hold head.
  ///
  /// [holdCeilingIdx] = profondeur max acquise pour les holds milestones
  /// (cf. instance `_milestoneHoldCeilingIdx`). Bloque holdTip si la
  /// joueuse a déjà acquis un palier plus profond — sémantique design
  /// « le seul hold qui a du sens est le plus profond que tu sais tenir ».
  StepDraft buildPostFinalDraft({
    required SessionMode finalMode,
    required double humilCap,
    required int holdCeilingIdx,
  }) {
    final dur = 10 + rng.nextInt(6); // [10, 15]
    final bpm = 38 + rng.nextInt(11); // [38, 48]
    // Échelle ordonnée. `blocked` (mode du final, holds obsolètes,
    // unlock beg, dose Custom) est calculé par chaque rule à partir du
    // ctx ci-dessous. Cf. `ModeRules.postFinalVariants` et la doc
    // mode-par-mode dans les rules.
    final ctx = PostFinalCtx(
      finalMode: finalMode,
      bpm: bpm,
      duration: dur,
      includeHand: config.includeHand,
      unlockedKeys: unlockedKeys,
      holdCeilingIdx: holdCeilingIdx,
      isModeForbidden: _isModeForbidden,
    );
    final candidates = <PostFinalVariant>[
      for (final rule in rules.values) ...rule.postFinalVariants(ctx),
    ];
    final valid = candidates
        .where((c) => c.req <= humilCap && !c.blocked)
        .toList()
      ..sort((a, b) => b.req.compareTo(a.req)); // req décroissante
    if (valid.isEmpty) {
      // Fallback safe : breath est req 0 / jamais blocked dans
      // `BreathRules.postFinalVariants` — `valid.isEmpty` ne devrait
      // donc survenir que sur un `humilCap < 0` aberrant. On reconstruit
      // un draft breath plutôt que de plonger dans le registry pour
      // garder un comportement déterministe.
      return StepDraft(
        mode: SessionMode.breath,
        bpm: null,
        from: null,
        to: null,
        duration: dur,
      );
    }
    // Biais spé pour les niveaux avancés : sloppy → lick (« lèche pour
    // nettoyer »), obeissance → beg (« remercie-moi », supplique
    // post-orgasme). Conditions cumulatives : level ≥ 7 (bas niveau on
    // garde le cadre doux pour ne pas brutaliser une débutante après son
    // orgasme), humilCap ≥ 30 (la chauffe doit être suffisante pour que
    // le ton tienne), spé ≥ 2 pts dans la branche concernée. 60 % de
    // chance — assez pour que la couleur de la spé soit perceptible
    // post-orgasme, mais 40 % de tirage standard pour conserver de la
    // variété (sinon chaque session avance signe la même fin).
    if (config.level >= 7 && humilCap >= 30) {
      final sloppyPts = _pts(SpecializationBranch.sloppy);
      final obPts = _pts(SpecializationBranch.obeissance);
      // Tirage prioritaire si les deux branches sont présentes : on
      // privilégie celle qui a le plus de pts. À égalité, sloppy d'abord
      // (l'aftercare de nettoyage colle mieux au ton « finition »).
      if (sloppyPts >= 2 && sloppyPts >= obPts && rng.nextDouble() < 0.60) {
        final lickCandidate =
            valid.where((c) => c.draft.mode == SessionMode.lick).firstOrNull;
        if (lickCandidate != null) return lickCandidate.draft;
      }
      if (obPts >= 2 && rng.nextDouble() < 0.60) {
        final begCandidate =
            valid.where((c) => c.draft.mode == SessionMode.beg).firstOrNull;
        if (begCandidate != null) return begCandidate.draft;
      }
    }
    // Top 3 : tirage uniforme dans les 3 plus humiliantes accessibles.
    // Donne de la variété sans casser la progression d'humiliation.
    final top = valid.take(3).toList();
    return top[rng.nextInt(top.length)].draft;
  }
}
