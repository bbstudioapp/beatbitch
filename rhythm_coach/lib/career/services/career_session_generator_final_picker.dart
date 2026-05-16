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
// Les deux méthodes partagent leur état (level, anatomy, unlockedKeys,
// spec, coachModeWeights, includeHand, rng, capClamps) — bundlé dans
// `_FinalPicker` comme value object immuable construit une fois par
// `generate()`. Pattern identique à `_CapabilityClamps` (cf. phase 2.d).

part of 'career_session_generator.dart';

/// Picker du final + post-final. Immuable : le générateur en construit un
/// par appel à `generate()` après que `_capClamps` est posé. Toutes les
/// décisions de gating consultent ce snapshot — les mutations d'état du
/// tracking (`_lastMode`, etc.) ne concernent pas la palette finale.
class _FinalPicker {
  final int level;
  final AnatomyProfile anatomy;
  final Set<UnlockKey> unlockedKeys;
  final SpecializationAllocation spec;
  final Map<SessionMode, double> coachModeWeights;
  final bool includeHand;
  final Random rng;
  final _CapabilityClamps capClamps;

  const _FinalPicker({
    required this.level,
    required this.anatomy,
    required this.unlockedKeys,
    required this.spec,
    required this.coachModeWeights,
    required this.includeHand,
    required this.rng,
    required this.capClamps,
  });

  int _pts(SpecializationBranch b) => spec.pointsIn(b);

  bool _isModeForbidden(SessionMode m) {
    final w = coachModeWeights[m];
    return w != null && w <= 0;
  }

  bool _isUnlocked(_StepDraft d) => _HumiliationGates.isUnlocked(
        d,
        anatomy: anatomy,
        unlockedKeys: unlockedKeys,
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
  _StepDraft pickFinal({
    required double humilCap,
    required int maxDepth,
    required double finishMul,
  }) {
    final endPts = _pts(SpecializationBranch.endurance);
    final fastDur = ((14 + endPts) * finishMul).round().clamp(14, 60);
    final shortHoldDur = ((12 + endPts) * finishMul).round().clamp(12, 60);
    // Tuple : (draft, req_humiliation, gate). Le `gate` est l'`UnlockKey?`
    // dédié au final, qui doit être présent dans `unlockedKeys` pour que
    // le candidat soit retenu. `null` = libre par défaut (cas hand
    // baseline : c'est le fallback universel). Ce gating remplace
    // l'ancien `minLevel` : la progression d'un final est désormais
    // gouvernée par sa milestone d'introduction dédiée (intro_final_*),
    // pas par un seuil de niveau implicite.
    final candidates = <(_StepDraft, double, UnlockKey?)>[];

    // Hand baseline : non humiliant, BPM tiré dans [40, 60] pour rester
    // dans la zone "lent contemplatif". Pas de gate dédiée — c'est le
    // fallback universel quand aucun autre final n'est unlocké.
    //
    // Niveaux 1-3 : candidat NORMAL — le finish bas niveau a besoin de
    // cette baseline (req 0) tant que les finals gated (hold tip / lick
    // tip→head / hold head…) ne sont pas acquittés.
    // Niveau ≥ 4 : retiré des candidats normaux (un hand-final est trop
    // anodin pour clôturer une séance à ce stade). Il ne subsiste alors
    // que (a) comme fallback technique ultime si AUCUN autre candidat ne
    // passe (cf. `valid.isEmpty` plus bas), ou (b) si une milestone-final
    // venait à le scripter explicitement (placement "final", backlog).
    if (level < 4) {
      final handBpm = 40 + rng.nextInt(21);
      candidates.add((
        _StepDraft(
          mode: SessionMode.hand,
          bpm: handBpm,
          from: Position.head,
          to: Position.mid,
          duration: fastDur,
        ),
        0.0,
        null,
      ));
    }

    // Hold tip : surcote 5 (faible profondeur mais sauce sur la langue).
    // Gate : intro_final_hold_tip (niveau 2).
    candidates.add((
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: null,
        to: Position.tip,
        duration: shortHoldDur,
      ),
      5.0,
      UnlockKey.finalHoldTip,
    ));

    // Lick tip→head 60 BPM lent : palier intermédiaire (req 8).
    // Gate : intro_final_lick_tip_head (niveau 3).
    candidates.add((
      const _StepDraft(
        mode: SessionMode.lick,
        bpm: 60,
        from: Position.tip,
        to: Position.head,
        duration: 16,
      ),
      8.0,
      UnlockKey.finalLickTipHead,
    ));

    // Hold head : surcote 14 (sauce sur le gland/bouche).
    // Gate : intro_final_hold_head (niveau 4).
    candidates.add((
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: null,
        to: Position.head,
        duration: shortHoldDur,
      ),
      14.0,
      UnlockKey.finalHoldHead,
    ));

    // Hold mid : surcote 10 (sauce profonde dans la bouche).
    // Gate : intro_final_hold_mid (niveau 5, requires hold_mid_short).
    candidates.add((
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: null,
        to: Position.mid,
        duration: shortHoldDur,
      ),
      10.0,
      UnlockKey.finalHoldMid,
    ));

    if (includeHand) {
      // Biffle 40-60 BPM : coups lents + sauce sur le visage.
      // Gate : intro_final_biffle (niveau 5, requires biffle_basic).
      final biffleBpm = 40 + rng.nextInt(21);
      candidates.add((
        _StepDraft(
          mode: SessionMode.biffle,
          bpm: biffleBpm,
          from: null,
          to: null,
          duration: fastDur,
        ),
        13.0,
        UnlockKey.finalBiffle,
      ));
    }

    if (maxDepth >= Position.throat.index) {
      // Cible évolutive avec l'humiliation accumulée (humilCap = score
      // courant + rampe de finish). Seuil d'introduction throat ≈ 10
      // d'humiliation (req intrinsèque hold throat 10s = 8, marge
      // de tolérance) : à humilCap=10 on tient le minimum (10s) ;
      // +2s par tranche de 5 points d'humil au-dessus. Cap aligné sur
      // full (80s) : en carrière, c'est le comfort du profil de
      // capacités qui pilote la durée vécue (cf. `clampToCapability`),
      // pas ce cap — le cap ne mord qu'en mode hérité (Custom,
      // scénarios) où le profil de capacités est désactivé.
      final humilOver = max(0.0, humilCap - 10.0);
      final targetDur =
          (10 + (humilOver / 5).floor() * 2 + endPts * 2).clamp(10, 80);
      final dur = trimHoldFinalDuration(
        target: targetDur,
        humilCap: humilCap,
        baseReq: 21.5, // hold throat 10s
        bonusPerSec: 1.5,
        finishMul: finishMul,
        maxDur: 80,
      );
      final req = 8.0 + (dur - 1) * 1.5;
      // Gate : intro_final_hold_throat (niveau 6, requires throat_hold_short).
      candidates.add((
        _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.throat,
          duration: dur,
        ),
        req,
        UnlockKey.finalHoldThroat,
      ));
    }

    // Lick full→balls : variante d'apothéose « sloppy descente » introduite
    // par la milestone `intro_balls_lick`. Pas de gate-final dédiée — on
    // réutilise `UnlockKey.lickBalls` (la zone est apprise une fois pour
    // toutes, le gating de niveau est porté implicitement par la milestone
    // qui débloque la clé). Filtre anatomy assuré par `_isUnlocked` sur
    // le composant. req = 16 (depthLick balls) + 1 (amplitude full→balls)
    // = 17, donc accessible passé chauffe sans atteindre hold full (req 22).
    if (anatomy.hasBalls) {
      candidates.add((
        const _StepDraft(
          mode: SessionMode.lick,
          bpm: 55,
          from: Position.full,
          to: Position.balls,
          duration: 16,
        ),
        17.0,
        UnlockKey.lickBalls,
      ));
    }

    if (maxDepth >= Position.full.index) {
      // Cible évolutive avec l'humiliation accumulée. Seuil d'introduction
      // full ≈ 30 d'humiliation (req intrinsèque hold full 10s = 22,
      // marge de tolérance) : à humilCap=30 on tient le minimum (10s) ;
      // +3s par tranche de 8 points d'humil au-dessus. Cap relâché à 80s.
      final humilOver = max(0.0, humilCap - 30.0);
      final targetDur =
          (10 + (humilOver / 8).floor() * 3 + endPts * 3).clamp(10, 80);
      final dur = trimHoldFinalDuration(
        target: targetDur,
        humilCap: humilCap,
        baseReq: 49.0, // hold full 10s
        bonusPerSec: 3.0,
        finishMul: finishMul,
        maxDur: 80,
      );
      final req = 22.0 + (dur - 1) * 3.0;
      // Gate : intro_final_hold_full (niveau 11, requires full_hold_short).
      candidates.add((
        _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.full,
          duration: dur,
        ),
        req,
        UnlockKey.finalHoldFull,
      ));
    }

    // Filtre humilCap + gate + unlocks composants, prend le plus humiliant
    // valide. Le gate est un `UnlockKey?` dédié au final ; null = libre.
    // `_isUnlocked` couvre les composants du draft (pour cohérence avec
    // le reste du générateur), `_finalUnlocked` couvre la gate du final.
    // Exclusions Custom (dose `none`) : on retire en plus les finals dont
    // le mode est explicitement banni — un final hold reste possible
    // quand rhythm est exclu, un final hand quand hold est exclu, etc.
    final valid = <(_StepDraft, double, UnlockKey?)>[];
    for (final c in candidates) {
      if (!_finalUnlocked(c.$3)) continue;
      if (_isModeForbidden(c.$1.mode)) continue;
      if (humilCap >= c.$2 && _isUnlocked(c.$1)) valid.add(c);
    }
    if (valid.isEmpty) {
      // Fallback dur : hand head→mid 50 BPM. Toujours unlocked, req=0,
      // garanti même si la palette change ou si humilCap est négatif.
      // Hand n'a pas d'axe de capacité → `clampToCapability` no-op.
      // Si hand est exclu en Custom, on retombe sur le 1ᵉʳ mode autorisé
      // disponible — hold head court reste un final acceptable.
      if (_isModeForbidden(SessionMode.hand)) {
        if (!_isModeForbidden(SessionMode.lick)) {
          return capClamps.clampToCapability(const _StepDraft(
            mode: SessionMode.lick,
            bpm: 60,
            from: Position.tip,
            to: Position.head,
            duration: 16,
          ));
        }
        if (!_isModeForbidden(SessionMode.hold)) {
          return capClamps.clampToCapability(_StepDraft(
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
      return _StepDraft(
        mode: SessionMode.hand,
        bpm: 50,
        from: Position.head,
        to: Position.mid,
        duration: fastDur,
      );
    }
    valid.sort((a, b) => a.$2.compareTo(b.$2));
    // 2ᵉ enveloppe : on tronque le final retenu au profil de capacités —
    // un hold throat/full d'apothéose ne dépasse pas la tenue prouvée.
    return capClamps.clampToCapability(valid.last.$1);
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
  _StepDraft buildPostFinalDraft({
    required SessionMode finalMode,
    required double humilCap,
    required int holdCeilingIdx,
  }) {
    final dur = 10 + rng.nextInt(6); // [10, 15]
    final bpm = 38 + rng.nextInt(11); // [38, 48]
    // Builders à la volée — un `const` figerait dur/bpm tirés ici.
    _StepDraft breath() => _StepDraft(
          mode: SessionMode.breath,
          bpm: null,
          from: null,
          to: null,
          duration: dur,
        );
    _StepDraft hand() => _StepDraft(
          mode: SessionMode.hand,
          bpm: bpm,
          from: Position.tip,
          to: Position.head,
          duration: dur,
        );
    _StepDraft holdTip() => _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.tip,
          duration: dur,
        );
    _StepDraft lick() => _StepDraft(
          mode: SessionMode.lick,
          bpm: bpm,
          from: Position.tip,
          to: Position.head,
          duration: dur,
        );
    _StepDraft rhythm() => _StepDraft(
          mode: SessionMode.rhythm,
          bpm: bpm,
          from: Position.tip,
          to: Position.head,
          duration: dur,
        );
    _StepDraft holdHead() => _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.head,
          duration: dur,
        );
    _StepDraft begLibre() => _StepDraft(
          mode: SessionMode.beg,
          bpm: null,
          from: null,
          to: null,
          duration: dur,
        );
    _StepDraft begHead() => _StepDraft(
          mode: SessionMode.beg,
          bpm: null,
          from: null,
          to: Position.head,
          duration: dur,
        );
    // Échelle ordonnée. `blocked` exclut le mode du final (alternance) et,
    // pour les beg, vérifie l'unlock `begLibre` (sinon on demanderait à
    // une utilisatrice qui n'a pas encore validé la milestone d'introduction
    // au beg de supplier post-orgasme — pédagogiquement faux).
    //
    // Holds tip/head : bloqués dès que la joueuse a débloqué un palier de
    // hold plus profond (`holdMidShort` ou plus). Cohérent avec la philo
    // design « le seul hold qui a du sens est le plus profond que tu sais
    // tenir » — un hold tip/head post-orgasme alors que mid est acquis
    // est juste une régression arbitraire.
    final isFinalHold = finalMode == SessionMode.hold;
    final canBeg =
        unlockedKeys.isEmpty || unlockedKeys.contains(UnlockKey.begLibre);
    final holdTipObsolete = holdCeilingIdx > Position.tip.index;
    final holdHeadObsolete = holdCeilingIdx > Position.head.index;
    // Note : breath n'est pas dosable côté Custom (cf. CustomSessionConfig.
    // dosableModes), donc `_isModeForbidden(breath)` est toujours false.
    final candidates =
        <(double req, bool blocked, _StepDraft Function() build)>[
      (0.0, false, breath),
      (
        8.0,
        !includeHand ||
            finalMode == SessionMode.hand ||
            _isModeForbidden(SessionMode.hand),
        hand
      ),
      (
        20.0,
        isFinalHold || holdTipObsolete || _isModeForbidden(SessionMode.hold),
        holdTip
      ),
      (25.0, !canBeg || _isModeForbidden(SessionMode.beg), begLibre),
      (
        35.0,
        finalMode == SessionMode.lick || _isModeForbidden(SessionMode.lick),
        lick
      ),
      (
        55.0,
        finalMode == SessionMode.rhythm || _isModeForbidden(SessionMode.rhythm),
        rhythm
      ),
      (60.0, !canBeg || _isModeForbidden(SessionMode.beg), begHead),
      (
        70.0,
        isFinalHold || holdHeadObsolete || _isModeForbidden(SessionMode.hold),
        holdHead
      ),
    ];
    final valid = candidates.where((c) => c.$1 <= humilCap && !c.$2).toList()
      ..sort((a, b) => b.$1.compareTo(a.$1)); // req décroissante
    if (valid.isEmpty) return breath();
    // Biais spé pour les niveaux avancés : sloppy → lick (« lèche pour
    // nettoyer »), obeissance → beg (« remercie-moi », supplique
    // post-orgasme). Conditions cumulatives : level ≥ 7 (bas niveau on
    // garde le cadre doux pour ne pas brutaliser une débutante après son
    // orgasme), humilCap ≥ 30 (la chauffe doit être suffisante pour que
    // le ton tienne), spé ≥ 2 pts dans la branche concernée. 60 % de
    // chance — assez pour que la couleur de la spé soit perceptible
    // post-orgasme, mais 40 % de tirage standard pour conserver de la
    // variété (sinon chaque session avance signe la même fin).
    if (level >= 7 && humilCap >= 30) {
      final sloppyPts = _pts(SpecializationBranch.sloppy);
      final obPts = _pts(SpecializationBranch.obeissance);
      // Tirage prioritaire si les deux branches sont présentes : on
      // privilégie celle qui a le plus de pts. À égalité, sloppy d'abord
      // (l'aftercare de nettoyage colle mieux au ton « finition »).
      if (sloppyPts >= 2 && sloppyPts >= obPts && rng.nextDouble() < 0.60) {
        final lickCandidate = valid.where((c) {
          final draft = c.$3();
          return draft.mode == SessionMode.lick;
        }).firstOrNull;
        if (lickCandidate != null) return lickCandidate.$3();
      }
      if (obPts >= 2 && rng.nextDouble() < 0.60) {
        final begCandidate = valid.where((c) {
          final draft = c.$3();
          return draft.mode == SessionMode.beg;
        }).firstOrNull;
        if (begCandidate != null) return begCandidate.$3();
      }
    }
    // Top 3 : tirage uniforme dans les 3 plus humiliantes accessibles.
    // Donne de la variété sans casser la progression d'humiliation.
    final top = valid.take(3).toList();
    return top[rng.nextInt(top.length)].$3();
  }
}
