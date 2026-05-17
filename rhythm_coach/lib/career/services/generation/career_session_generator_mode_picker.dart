// Fichier part de `career_session_generator.dart` — tirage pondéré du mode
// pour la boucle main.
//
// Le picker combine 3 leviers indépendants :
//   1. Pondération par spécialisation (`baseWeight`) — quelle est la
//      branche dominante de la joueuse ?
//   2. Pondération coach / dose Custom (`coachWeights[mode]`) — quel
//      coach anime la séance, ou quel choix utilisateur côté Custom ?
//   3. Continuité par type (`continuityMultiplier`) — favorise les
//      séries cohérentes (bouche/bouche/bouche) plutôt qu'un saut à
//      chaque step.
//
// Le 3ᵉ levier dépend de l'état mutable du tracking (`_state.lastType`,
// `_stepsInLastType`, `_state.stepsOutsideBouche`). On le capture dans un
// snapshot [ModeContinuityState] que le générateur reconstruit à chaque
// pick — c'est cheap (4 lectures de fields), et ça garde [_ModePicker]
// 100 % statique-pur.
//
// Restent côté instance dans le fichier principal :
//   * `_isModeForbidden` — exposé par d'autres call sites (boosts, palette
//     finale, mini-vagues…) qui ne passent pas par le picker.
//   * `_pts` / `_scaleDuration` — partagés avec d'autres pondérations (cf.
//     `_mapDifficultyToStep`).

part of 'career_session_generator.dart';

/// Snapshot du tracking de continuité au moment d'un pick.
///
/// Reconstruit à chaque appel au picker depuis les fields d'instance
/// mutables (`_state.lastType`, `_stepsInLastType`, `_state.stepsOutsideBouche`,
/// `_state.lastMode`). Le picker reste pur en consommant ce snapshot.
class ModeContinuityState {
  /// Type du dernier step poussé (cluster sémantique bouche / langue /
  /// libreMain / transit). `null` au premier step de la séance.
  final StepType? lastType;

  /// Nombre de steps consécutifs sur [lastType]. 0 si [lastType] est null.
  final int stepsInLastType;

  /// Nombre de steps consécutifs **hors bouche** depuis la dernière
  /// excursion. Sert à forcer le retour à bouche après 2+ excursions.
  final int stepsOutsideBouche;

  /// Dernier mode poussé. Permet le filtre anti-répétition de [filterRepeated]
  /// pour les modes ponctuels (breath / beg / biffle / hold / freestyle).
  final SessionMode? lastMode;

  const ModeContinuityState({
    required this.lastType,
    required this.stepsInLastType,
    required this.stepsOutsideBouche,
    required this.lastMode,
  });
}

/// Tirage pondéré du mode pour la boucle main. Toutes les méthodes sont
/// statiques + pures — l'état mutable est consommé via [ModeContinuityState]
/// + [SpecializationAllocation] + `coachWeights` + `Random`.
class _ModePicker {
  /// Pondération issue de la spé seule, sans le filtre coach. Le coach
  /// (s'il en fournit) multiplie ce score dans [weight].
  ///
  /// Coefficients de spé renforcés (passe de +0.20..+0.60 à +0.35..+0.90
  /// par point investi). À 5 pts dans la branche, le mode correspondant
  /// pèse jusqu'à ×5.5 pour beg/obeissance, ×4.5 pour lick/sloppy, etc.
  /// — assez pour que la couleur de la séance soit clairement audible
  /// dès 3 pts dans une branche.
  static double baseWeight(SessionMode m, SpecializationAllocation spec) {
    int pts(SpecializationBranch b) => spec.pointsIn(b);
    switch (m) {
      case SessionMode.rhythm:
        return 1.0 +
            0.35 * pts(SpecializationBranch.rythmeBiffle) +
            0.10 * pts(SpecializationBranch.profondeur);
      case SessionMode.biffle:
        return 1.0 +
            0.60 * pts(SpecializationBranch.rythmeBiffle) +
            0.25 * pts(SpecializationBranch.sloppy);
      case SessionMode.hold:
        return 1.0 +
            0.60 * pts(SpecializationBranch.endurance) +
            0.40 * pts(SpecializationBranch.profondeur);
      case SessionMode.lick:
        // Base abaissée (retour utilisateur « moins de lèche ») : sans
        // point sloppy, le lick pèse ~0.6 contre ~1.0 pour un mode neutre.
        // Le boost sloppy (+0.70/pt) reste pleinement effectif → une
        // joueuse spé sloppy en voit toujours beaucoup (×4.1 à 5 pts).
        return 0.6 + 0.70 * pts(SpecializationBranch.sloppy);
      case SessionMode.beg:
        return 1.0 + 0.90 * pts(SpecializationBranch.obeissance);
      case SessionMode.hand:
        // Poids neutre + boost léger rythmeBiffle (hand est un mode
        // rythmé — cohérent qu'une joueuse rythmeBiffle en voie un peu
        // plus). La friction de continuité par type pilote toujours son
        // apparition principale (intro + reprises de souffle).
        return 1.0 + 0.15 * pts(SpecializationBranch.rythmeBiffle);
      case SessionMode.breath:
        return 1.0;
      case SessionMode.freestyle:
        // Freestyle = vraie pause libre, sans bip ni guidage. Seul mode
        // tiré uniquement par `_buildRecoveryStep`, donc son poids doit
        // rester marginal pour ne pas dominer toutes les récup une fois
        // débloqué (sinon ~25 % des récup partaient en freestyle parce
        // que son multiplicateur de continuité est neutre — `transit` —
        // alors que les autres candidats prennent la friction de quitter
        // bouche). Un poids bas le garde comme option ponctuelle.
        return 0.25;
      case SessionMode.suckle:
        // Aspiration : geste actif-statique. Sloppy boost (bouche humide)
        // et un peu d'obéissance (geste explicite et soumis). Pas de
        // boost profondeur — suckle n'est jamais une profondeur de
        // pompage, c'est une pratique latérale (head ou balls). Base 0.6
        // pour rester dans la veine « palette ponctuelle » comme
        // freestyle/breath — c'est un mode de couleur, pas un mode de
        // chauffe.
        return 0.6 +
            0.40 * pts(SpecializationBranch.sloppy) +
            0.15 * pts(SpecializationBranch.obeissance);
    }
  }

  /// Multiplicateur appliqué à [weight] pour favoriser la continuité par
  /// type de step. Le but est que la séance ressente une cohérence : on
  /// reste plusieurs steps consécutifs sur le même type, avec variation
  /// par paramètres (BPM, profondeur, phrases) plutôt que de sauter d'un
  /// type à l'autre à chaque step. La bouche est le cœur de l'app —
  /// continuité forte, friction marquée pour en sortir, retour activement
  /// favorisé après une excursion.
  ///
  /// Échelle (réglée pour que la bouche reste le type majoritaire en
  /// nombre de steps) :
  /// - même type que le précédent :
  ///     * bouche → bouche : ×3.0 (très collant — on n'en sort pas pour rien)
  ///     * langue → langue, libre → libre :
  ///         - 1er step : ×1.8 (continuité tolérée)
  ///         - 2e step+ : ×0.6 (dégradation rapide — une excursion hors
  ///           bouche doit rester courte, c'est une intro/transition)
  /// - changement vers bouche depuis langue/libre :
  ///     * 1 step hors bouche : ×1.4 (variété tolérée mais on encourage)
  ///     * 2 steps hors bouche : ×3.0 (forcer le retour)
  ///     * 3+ steps hors bouche : ×6.0 (verrouiller le retour)
  /// - changement DEPUIS bouche vers langue/libre :
  ///     * < 2 steps de bouche : ×0.30 (très peu de chances de partir)
  ///     * 2-3 steps de bouche : ×0.55
  ///     * 4+ steps de bouche : ×0.80 (variété tolérée après une vraie phase)
  /// - changement entre langue ↔ libre/main : ×0.50 (friction marquée —
  ///   on ne saute pas d'un type secondaire à l'autre, on repasse par
  ///   bouche)
  ///
  /// Cas neutres (×1.0) :
  /// - pas de [ModeContinuityState.lastType] encore (premier step)
  /// - dernier type = transit (breath/freestyle ne reset pas, donc rare)
  /// - candidat = beg (ambivalent — son type effectif dépend du `to` tiré
  ///   APRÈS le pick, donc on ne biaise pas le tirage du mode)
  /// - candidat = breath/freestyle (sont tirés par d'autres voies, jamais
  ///   par [pickWeighted], mais on reste neutre par sécurité)
  static double continuityMultiplier(
    SessionMode candidate,
    ModeContinuityState state, {
    required Map<SessionMode, ModeRules> rules,
  }) {
    final last = state.lastType;
    if (last == null) return 1.0;
    if (last == StepType.transit) return 1.0;

    if (candidate == SessionMode.breath || candidate == SessionMode.freestyle) {
      return 1.0;
    }

    // beg est ambivalent au moment du tirage : son `to` est décidé après
    // dans `_mapDifficultyToStep`. À diff bas (= début de session,
    // chauffe), `ampScore` tend vers 0 et le beg sort en libre (`to=null`).
    // Si on le traitait neutre (×1.0), il sortait ~14 % du temps en plein
    // milieu d'une série bouche et la fragmentait. On le classe donc en
    // libre/main par défaut — quitte à manquer un peu les beg-non-libre
    // (rares, n'apparaissent qu'à ampScore haut, donc à diff haut). Le
    // `null` passé à `classify` produit ce même verdict côté `BegRules`,
    // mais on garde le shortcut explicite pour que l'intention reste
    // lisible (« beg = libre, sauf décision contraire »).
    final cand = candidate == SessionMode.beg
        ? StepType.libreMain
        : rules[candidate]!.classify(null);
    if (cand == StepType.transit) return 1.0;

    // Verrou strict : si on a déjà 2+ steps consécutifs hors bouche
    // (peu importe lequel), on pousse fortement pour rebasculer sur
    // bouche. Plus on s'écarte longtemps, plus le retour est verrouillé.
    if (state.stepsOutsideBouche >= 2) {
      if (cand == StepType.bouche) {
        return 6.0 + state.stepsOutsideBouche * 1.5;
      }
      return 0.05; // quasi banni — sert juste de fallback si bouche bloqué
    }

    if (cand == last) {
      if (last == StepType.bouche) return 3.0;
      // langue / libre/main : continuité dégradée pour ne pas s'éterniser.
      // 1 step de plus est OK, mais au-delà on pousse le retour à bouche.
      return state.stepsInLastType >= 2 ? 0.6 : 1.8;
    }
    if (cand == StepType.bouche) {
      // Retour à bouche : encouragé dès la 1re excursion, fort dès 2.
      if (state.stepsOutsideBouche >= 1) return 3.0;
      return 1.4;
    }
    if (last == StepType.bouche) {
      // Quitter bouche est très onéreux : on n'en sort qu'après une vraie
      // phase de bouche (3+ steps), et même là la friction reste marquée.
      if (state.stepsInLastType < 3) return 0.10;
      if (state.stepsInLastType < 5) return 0.30;
      return 0.55;
    }
    return 0.50;
  }

  /// Poids combiné : [baseWeight] (spé) × `coachWeights[m]` (coach / dose
  /// Custom) × [continuityMultiplier]. Plancher à 0 — un mode exclu par le
  /// coach (poids 0) ne sort jamais via ce chemin.
  static double weight(
    SessionMode m, {
    required SpecializationAllocation spec,
    required Map<SessionMode, double> coachWeights,
    required ModeContinuityState continuity,
    required Map<SessionMode, ModeRules> rules,
  }) {
    final base = baseWeight(m, spec);
    final coachFactor = coachWeights[m] ?? 1.0;
    final continuityMul = continuityMultiplier(m, continuity, rules: rules);
    final result = base * coachFactor * continuityMul;
    return result < 0 ? 0 : result;
  }

  /// Retire `lastMode` des candidats si une alternative existe et que le
  /// mode est « ponctuel » (breath / beg / biffle / hold / freestyle) —
  /// deux events identiques d'affilé y sonneraient comme un bug.
  ///
  /// Pour les modes « flow » (rhythm / lick / hand), on **accepte la
  /// répétition** : la variété passe par les paramètres (BPM via
  /// `_applyBpmDiversity` qui force ≥18 BPM de delta, profondeur via
  /// `_diversifyAmplitude` qui décale d'un cran). Sans cette fenêtre de
  /// rester sur le même mode, on sortait nécessairement de rythme à chaque
  /// step ; l'utilisateur a relevé que la séance ressemblait à une rotation
  /// stricte au lieu de phases prolongées avec variation.
  static List<SessionMode> filterRepeated(
    List<SessionMode> candidates,
    SessionMode? lastMode,
  ) {
    if (lastMode == null || candidates.length <= 1) return candidates;
    const flowModes = {
      SessionMode.rhythm,
      SessionMode.lick,
      SessionMode.hand,
    };
    if (flowModes.contains(lastMode)) return candidates;
    final filtered = candidates.where((m) => m != lastMode).toList();
    if (filtered.isEmpty) return candidates;
    return filtered;
  }

  /// Pondère le tirage du mode selon la spécialisation + coach + continuité.
  /// Plus de points dans une branche → plus de chances de tirer les modes
  /// correspondants. Les coefficients restent modérés (0.3–0.6) pour ne
  /// pas écraser la variété — la spé donne une couleur, pas un monomode.
  ///
  /// Si tous les poids tombent à 0 (rare : coach a exclu tout le monde),
  /// fallback uniform sur les candidats **non explicitement exclus** par le
  /// coach. Si vraiment tout est exclu, on retombe sur la liste d'origine
  /// — c'est au caller de pré-filtrer pour que ce cas n'arrive pas.
  static SessionMode pickWeighted(
    List<SessionMode> candidates, {
    required SpecializationAllocation spec,
    required Map<SessionMode, double> coachWeights,
    required ModeContinuityState continuity,
    required Random rng,
    required Map<SessionMode, ModeRules> rules,
  }) {
    final weights = <double>[];
    for (final m in candidates) {
      weights.add(weight(
        m,
        spec: spec,
        coachWeights: coachWeights,
        continuity: continuity,
        rules: rules,
      ));
    }
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      // Fallback random : on garde la convention « jamais renvoyer un mode
      // explicitement exclu » (dose `none` en Custom). Si tous les
      // candidats sont exclus, on n'a rien de mieux que la liste d'origine.
      final allowed = candidates.where((m) {
        final w = coachWeights[m];
        return !(w != null && w <= 0);
      }).toList(growable: false);
      final pool = allowed.isEmpty ? candidates : allowed;
      return pool[rng.nextInt(pool.length)];
    }
    var roll = rng.nextDouble() * total;
    for (var i = 0; i < candidates.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return candidates[i];
    }
    return candidates.last;
  }
}
