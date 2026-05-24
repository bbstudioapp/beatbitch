// Library autonome — tirage pondéré du mode pour la boucle main.
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
// pick — c'est cheap (4 lectures de fields), et ça garde [ModePicker]
// 100 % statique-pur.
//
// Sortie du `part of 'career_session_generator.dart'` historique en
// D.PR3 du plan de refacto. Toutes les méthodes étaient déjà statiques
// pures depuis B.PR1 — l'extraction est triviale, juste un renommage
// `_ModePicker` → `ModePicker`.

import 'dart:math';

import '../../../models/session.dart';
import '../../models/specialization.dart';
import 'mode_continuity_state.dart';
import 'mode_rules.dart';
import 'step_type.dart';

/// Tirage pondéré du mode pour la boucle main. Toutes les méthodes sont
/// statiques + pures — l'état mutable est consommé via [ModeContinuityState]
/// + [SpecializationAllocation] + `coachWeights` + `Random`.
class ModePicker {
  /// Pondération issue de la spé seule, sans le filtre coach. Le coach
  /// (s'il en fournit) multiplie ce score dans [weight].
  ///
  /// Depuis C.PR2 : chaque équation vit côté rule
  /// (`ModeRules.baseWeight`). Cette méthode est un thin delegate
  /// — l'orchestrateur reste mode-agnostic, les coefficients de spé
  /// éditoriaux (boosts par branche) restent versionnés avec la rule
  /// du mode concerné.
  static double baseWeight(
    SessionMode m,
    SpecializationAllocation spec, {
    required Map<SessionMode, ModeRules> rules,
  }) =>
      rules[m]!.baseWeight(spec);

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
  /// Détecte si émettre [candidate] prolongerait un cycle déjà répété
  /// dans `recent`. Couvre :
  /// - cycle de longueur 2 : `[..., A, B, A, B]` + candidate `A` →
  ///   le cycle `(A, B)` se serait répété 2× puis amorce une 3e fois.
  /// - cycle de longueur 3 : `[..., A, B, C, A, B, C]` + candidate `A` →
  ///   le cycle `(A, B, C)` se serait répété 2× puis amorce une 3e fois.
  ///
  /// On exclut le cas dégénéré `A == B` (déjà capté par
  /// [filterRepeated] / `REPEAT-STREAK` pour les modes non-flow, et
  /// volontairement toléré pour les modes flow type rhythm/lick/hand).
  static bool _extendsRepeatedCycle(
      SessionMode candidate, List<SessionMode> recent) {
    final n = recent.length;
    if (n >= 4) {
      final a = recent[n - 4];
      final b = recent[n - 3];
      final a2 = recent[n - 2];
      final b2 = recent[n - 1];
      if (a == candidate && a == a2 && b == b2 && a != b) {
        return true;
      }
    }
    if (n >= 6) {
      final a = recent[n - 6];
      final b = recent[n - 5];
      final c = recent[n - 4];
      final a2 = recent[n - 3];
      final b2 = recent[n - 2];
      final c2 = recent[n - 1];
      if (a == candidate &&
          a == a2 &&
          b == b2 &&
          c == c2 &&
          (a != b || b != c)) {
        return true;
      }
    }
    return false;
  }

  /// Seuil au-dessus duquel un `coachWeight` est considéré comme un
  /// dosage utilisateur explicite (= `frequent` en mode Custom = 2.2,
  /// au-dessus du `normal` = 1.0). Au-delà, le verrou de continuité
  /// « tout ramène à bouche » est neutralisé : l'utilisatrice a choisi
  /// de privilégier ce mode, on respecte. En dessous (rare/normal/none),
  /// la friction de continuité s'applique normalement — la bouche reste
  /// le cœur de l'app par défaut.
  static const double _explicitDoseThreshold = 1.5;

  static double continuityMultiplier(
    SessionMode candidate,
    ModeContinuityState state, {
    required Map<SessionMode, ModeRules> rules,
    double coachWeight = 1.0,
  }) {
    // Malus anti-cycle (×0.2) appliqué EN PLUS du multiplicateur de
    // type ci-dessous : si émettre `candidate` prolongerait un cycle
    // de 2 ou 3 modes déjà répété, on freine sans bloquer (il reste un
    // poids non nul, c'est juste moins probable). Le ×0.2 est assez fort
    // pour casser un cycle même quand la continuité bouche pousse ×3.0
    // (résultat net 0.6) sans interdire complètement le candidat (un mode
    // hold rare ne disparaît pas s'il n'y a pas d'alternative crédible).
    final cycleMul =
        _extendsRepeatedCycle(candidate, state.recentModes) ? 0.2 : 1.0;
    return _typeMultiplier(
          candidate,
          state,
          rules: rules,
          coachWeight: coachWeight,
        ) *
        cycleMul;
  }

  /// Multiplicateur historique basé uniquement sur le **type** du
  /// candidat vs le dernier type (bouche/langue/libreMain/transit) et
  /// les compteurs `stepsInLastType` / `stepsOutsideBouche`. Extrait
  /// pour permettre la composition avec le malus anti-cycle.
  static double _typeMultiplier(
    SessionMode candidate,
    ModeContinuityState state, {
    required Map<SessionMode, ModeRules> rules,
    double coachWeight = 1.0,
  }) {
    final last = state.lastType;
    if (last == null) return 1.0;
    if (last == StepType.transit) return 1.0;

    // `classify(null)` retourne le type effectif du mode au moment du
    // tirage : breath/freestyle → `transit` (filtré juste en dessous),
    // beg → `libreMain` (sa convention « to-null ⇒ libre » s'applique
    // tant que le `to` n'est pas encore décidé ; le beg-non-libre est
    // rare en pratique — il n'apparaît qu'à ampScore haut, donc à diff
    // haut, et on accepte de le manquer pour ne pas fragmenter les
    // séries bouche en début de session). Les rules portent désormais
    // leur propre classification ; le picker reste mode-agnostic.
    final cand = rules[candidate]!.classify(null);
    if (cand == StepType.transit) return 1.0;

    // L'utilisatrice a explicitement priorisé ce mode (dose `frequent`
    // en Custom). On respecte son dosage : pas de friction de continuité
    // qui le repousserait au profit de la bouche. Le `coachWeight` brut
    // (2.2) suffit alors à dominer naturellement les modes en `normal`
    // (×1.0) ou `rare` (×0.4). La logique « ramener à bouche » reste
    // active pour les modes non priorisés, et le « retour à bouche »
    // reste lui-même favorable pour ne pas casser les phases bouche.
    final isExplicitlyDosed = coachWeight >= _explicitDoseThreshold;

    // Verrou strict : si on a déjà 2+ steps consécutifs hors bouche
    // (peu importe lequel), on pousse fortement pour rebasculer sur
    // bouche. Plus on s'écarte longtemps, plus le retour est verrouillé.
    if (state.stepsOutsideBouche >= 2) {
      if (cand == StepType.bouche) {
        return 6.0 + state.stepsOutsideBouche * 1.5;
      }
      if (isExplicitlyDosed) return 1.0; // dosage utilisateur respecté
      return 0.05; // quasi banni — sert juste de fallback si bouche bloqué
    }

    if (cand == last) {
      if (last == StepType.bouche) return 3.0;
      // langue / libre/main : continuité dégradée pour ne pas s'éterniser.
      // 1 step de plus est OK, mais au-delà on pousse le retour à bouche.
      if (state.stepsInLastType >= 2 && !isExplicitlyDosed) return 0.6;
      return 1.8;
    }
    if (cand == StepType.bouche) {
      // Retour à bouche : encouragé dès la 1re excursion, fort dès 2.
      if (state.stepsOutsideBouche >= 1) return 3.0;
      return 1.4;
    }
    if (last == StepType.bouche) {
      if (isExplicitlyDosed) return 1.0; // dosage utilisateur respecté
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
    final base = baseWeight(m, spec, rules: rules);
    final coachFactor = coachWeights[m] ?? 1.0;
    final continuityMul = continuityMultiplier(
      m,
      continuity,
      rules: rules,
      coachWeight: coachFactor,
    );
    final result = base * coachFactor * continuityMul;
    return result < 0 ? 0 : result;
  }

  /// Retire `lastMode` des candidats si une alternative existe et que le
  /// mode n'est pas « flow » : deux events ponctuels identiques
  /// d'affilé sonneraient comme un bug.
  ///
  /// Les modes « flow » ([ModeRules.isFlow] — rhythm / lick / hand)
  /// **acceptent la répétition** : la variété passe par les paramètres
  /// (BPM via `_applyBpmDiversity` qui force ≥18 BPM de delta,
  /// profondeur via `_diversifyAmplitude` qui décale d'un cran). Sans
  /// cette fenêtre, on sortait nécessairement de rythme à chaque step ;
  /// retour utilisateur « la séance ressemble à une rotation stricte
  /// au lieu de phases prolongées avec variation ».
  static List<SessionMode> filterRepeated(
    List<SessionMode> candidates,
    SessionMode? lastMode, {
    required Map<SessionMode, ModeRules> rules,
  }) {
    if (lastMode == null || candidates.length <= 1) return candidates;
    if (rules[lastMode]!.isFlow) return candidates;
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
