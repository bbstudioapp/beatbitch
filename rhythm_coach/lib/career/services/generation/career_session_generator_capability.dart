// Fichier part de `career_session_generator.dart` — 2ᵉ enveloppe de
// difficulté carrière (profil de capacités + surcharge isolée + bornes
// utilisateur Custom).
//
// `CapabilityClamps` est un **value object immuable** construit une fois
// par `generate()` après que l'axe de surcharge a été choisi. Toute la
// logique de clamp (profondeur / BPM / durée) y vit en méthodes d'instance
// qui consomment les fields. Les helpers vraiment statiques (mapping
// position → axe BPM, min nullable, set des axes surchargables, choix de
// l'axe) sont des `static`.
//
// Conception : les méthodes de clamp s'appellent entre elles, et toutes
// ont besoin du même bundle (profil, ceilings, axe/facteur de surcharge,
// bornes Custom). Plutôt qu'une longue liste de paramètres répétés, on
// snapshot une référence vers le `SessionConfig` de la séance pour les 4
// fields capacités (profil + ceilings + axe + facteur), et on garde
// `bpmRange` / `holdRange` comme fields explicites — la path punition
// les nullifie alors que la session principale les hérite de `_config`.

part of 'career_session_generator.dart';

/// 2ᵉ enveloppe de difficulté : profil de capacités persisté + plafonds
/// figés en cours de session + axe surchargé + bornes utilisateur Custom.
/// Immutable : le générateur en construit un par appel à `generate()`,
/// après que `pickOverloadAxis` a choisi l'axe à pousser cette séance.
class CapabilityClamps {
  /// Snapshot de la config de séance. On y lit `capProfile`,
  /// `capCeilings`, `overloadAxis`, `overloadFactor` — figés au début de
  /// `generate()`.
  final SessionConfig config;

  /// Bornes BPM utilisateur (mode Custom). `null` hors Custom **ou** quand
  /// le caller veut explicitement désactiver le clamp (cf. path punition
  /// dans `generatePunishment`).
  final (int, int)? bpmRange;

  /// Bornes de durée pour les steps tenus (hold + beg avec position).
  /// Même semantics que [bpmRange] côté override.
  final (int, int)? holdRange;

  /// Registry des rules injecté par le générateur — consulté pour
  /// dispatcher `clampToCapability` au mode du draft.
  final Map<SessionMode, ModeRules> rules;

  const CapabilityClamps({
    required this.config,
    required this.bpmRange,
    required this.holdRange,
    required this.rules,
  });

  /// Axes éligibles à la surcharge : pilotants, hors `hand` / `lick` /
  /// `breath` (jamais des leviers de difficulté) et hors floors BPM /
  /// souffle (rien ne les consomme côté générateur — les surcharger ne
  /// ferait rien).
  static const Set<CapabilityAxis> overloadableAxes = {
    CapabilityAxis.gorgeApneeStreak,
    CapabilityAxis.gorgeEngagementStreak,
    CapabilityAxis.gorgeCrossingsBpmThroat,
    CapabilityAxis.gorgeCrossingsBpmFull,
    CapabilityAxis.rhythmBpmCeilShallow,
    CapabilityAxis.rhythmBpmCeilThroat,
    CapabilityAxis.rhythmBpmCeilFull,
    CapabilityAxis.rhythmDepthMax,
    CapabilityAxis.rhythmMotionStreak,
    CapabilityAxis.holdThroatStreak,
    CapabilityAxis.holdFullStreak,
    CapabilityAxis.noswallowStreak,
    CapabilityAxis.biffleStreak,
    CapabilityAxis.biffleBpmMax,
  };

  /// Minimum de deux doubles nullable. `null` est considéré comme « pas
  /// de contrainte » → l'autre l'emporte.
  static double? minNullable(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }

  /// Axe « plafond BPM rhythm » correspondant à la bande de profondeur de
  /// `to` (`≤ mid` / `throat` / `full`). Aligné sur `_rhythmBand` du
  /// `CapabilityTracker`.
  static CapabilityAxis rhythmBpmCeilAxisFor(Position to) {
    if (to.index <= Position.mid.index) {
      return CapabilityAxis.rhythmBpmCeilShallow;
    }
    if (to == Position.throat) return CapabilityAxis.rhythmBpmCeilThroat;
    return CapabilityAxis.rhythmBpmCeilFull;
  }

  /// Choisit l'axe à surcharger pour la séance (surcharge isolée, §5).
  /// Priorité aux axes pas vus depuis longtemps (à reprouver avant que le
  /// decay ne les érode), aux axes confiants (`successRate` haut, prêts à
  /// monter), évitement des axes fragiles. Exclut les axes déjà figés
  /// cette session (`ceilings` = verrou §6) et ceux sans donnée.
  ///
  /// Retourne `(null, 1.0)` quand il n'y a rien à pousser (profil neuf,
  /// tous les axes figés, mode hérité…).
  static ({CapabilityAxis? axis, double factor}) pickOverloadAxis({
    required CapabilityProfile? profile,
    required Map<CapabilityAxis, double> ceilings,
    required Random rng,
  }) {
    if (profile == null) return (axis: null, factor: 1.0);
    // On ne connaît pas l'index de session courant ici : on prend le plus
    // grand `lastSeenSession` du profil comme pseudo-horloge (≈ session
    // précédente) et l'ancienneté = écart à ce repère.
    var pseudoNow = 0;
    for (final a in CapabilityAxis.values) {
      final s = profile.stateOf(a).lastSeenSession;
      if (s > pseudoNow) pseudoNow = s;
    }
    CapabilityAxis? best;
    var bestScore = double.negativeInfinity;
    for (final axis in overloadableAxes) {
      final st = profile.stateOf(axis);
      if (st.comfort == null) continue; // rien de prouvé → rien à pousser
      if (ceilings.containsKey(axis)) continue; // déjà calé cette séance
      final staleness =
          st.lastSeenSession < 0 ? 0 : (pseudoNow - st.lastSeenSession);
      final stalenessNorm = (staleness / 6.0).clamp(0.0, 1.0);
      final sr = st.successRate;
      final score = 0.45 * stalenessNorm +
          0.45 * sr -
          0.10 * (1 - sr) +
          rng.nextDouble() * 0.05;
      if (score > bestScore) {
        bestScore = score;
        best = axis;
      }
    }
    if (best == null) return (axis: null, factor: 1.0);
    final factor =
        CapabilityRegulator.surchargeFactor(profile.stateOf(best).successRate);
    return (axis: best, factor: factor);
  }

  /// Plafond effectif (= le plus contraignant) d'un axe de capacité pour
  /// la génération en cours : minimum de `comfort` (éventuellement
  /// **surchargé** si c'est [overloadAxis] de la séance) et du plafond
  /// figé sur un FAIL de cette session ([ceilings], §6 — qui plafonne
  /// *même* l'axe surchargé : pas de re-fail dans la même séance).
  /// `null` si aucune donnée — l'enveloppe ne contraint alors rien
  /// (joueuse neuve ou axe jamais sollicité ; le profil prend le relais
  /// après ~3-5 sessions).
  double? capabilityCapFor(CapabilityAxis axis) {
    final p = config.capProfile;
    if (p == null) return null;
    var comfort = p.comfortOf(axis);
    if (comfort != null && axis == config.overloadAxis) {
      if (axis == CapabilityAxis.rhythmDepthMax) {
        // Profondeur = cran discret : on autorise +1 cran, et seulement si
        // la confiance au cran courant est là (cf. asymétries §5).
        // « Humiliation l'autorise » + « milestone d'unlock acquittée »
        // sont déjà garantis par `_maxDepthIndex` (qui borne `to` en amont).
        if (p.stateOf(axis).successRate >= CapabilityRegulator.kDepthCranGate) {
          comfort = comfort + 1;
        }
      } else {
        comfort = comfort * config.overloadFactor;
      }
    }
    return minNullable(comfort, config.capCeilings[axis]);
  }

  /// Renvoie le facteur de surcharge applicable à [axis] (1.0 hors
  /// surcharge). Pour `rhythmDepthMax` la surcharge est un cran, pas un
  /// facteur — utiliser [capabilityCapFor] directement.
  double overloadFactorFor(CapabilityAxis axis) =>
      axis == config.overloadAxis ? config.overloadFactor : 1.0;

  /// Borne un draft à l'enveloppe « profil de capacités » : profondeur,
  /// BPM et durée ne dépassent pas ce que la joueuse a *prouvé* tenir.
  /// 2ᵉ enveloppe orthogonale à l'humiliation — un step n'est jouable
  /// que si **les deux** passent. No-op hors carrière ([profile] = null).
  ///
  /// Dispatch polymorphique : chaque mode porte ses propres caps dans
  /// `_*Rules.clampToCapability` (cf. `career_session_generator_mode_rules.dart`).
  /// Modes hors gating (default identité) : `hand` (exclu de tout axe de
  /// difficulté — cf. règle « hand n'est jamais un levier »), `lick`
  /// (enregistré seulement, pas pilotant), `breath` / `freestyle` /
  /// `suckle` (aucun axe). Les steps scriptés (séquences milestone, beg
  /// insistant du Supplier) passent par d'autres chemins et ne sont pas
  /// clampés — comme ils ne sont pas gatés par l'humiliation non plus.
  ///
  /// La récursion sur `chainNext` et la composition avec
  /// [clampToCustomLimits] (bornes utilisateur Custom) restent
  /// orchestrées ici.
  StepDraft clampToCapability(StepDraft d) {
    if (config.capProfile == null) return clampToCustomLimits(d);
    final clampedChain =
        d.chainNext == null ? null : clampToCapability(d.chainNext!);
    final clamped = rules[d.mode]!.clampToCapability(d, this);
    final composed = identical(clampedChain, d.chainNext)
        ? clamped
        : StepDraft(
            mode: clamped.mode,
            bpm: clamped.bpm,
            bpmEnd: clamped.bpmEnd,
            from: clamped.from,
            to: clamped.to,
            duration: clamped.duration,
            chainNext: clampedChain,
          );
    return clampToCustomLimits(composed);
  }

  /// Borne un draft aux limites utilisateur du mode Custom ([bpmRange] /
  /// [holdRange]). Appliqué après [clampToCapability] pour rester
  /// compatible avec le profil (qui ne sert qu'en carrière, désactivé en
  /// Custom). `chainNext` est récursé. No-op si aucune borne n'est
  /// fournie (carrière / scénario JSON).
  StepDraft clampToCustomLimits(StepDraft d) {
    if (bpmRange == null && holdRange == null) return d;
    final clampedChain =
        d.chainNext == null ? null : clampToCustomLimits(d.chainNext!);
    var bpm = d.bpm;
    var bpmEnd = d.bpmEnd;
    var dur = d.duration;
    if (bpmRange != null) {
      final (lo, hi) = bpmRange!;
      if (bpm != null) bpm = bpm.clamp(lo, hi);
      if (bpmEnd != null) bpmEnd = bpmEnd.clamp(lo, hi);
    }
    if (holdRange != null && dur != null) {
      // S'applique aux modes qui *tiennent* une position : hold et beg
      // avec position (`from` ou `to` renseigné). Les autres modes ont
      // aussi un `duration`, mais c'est la durée totale du step rythmé,
      // pas un temps de maintien — on ne touche pas pour éviter de
      // tronquer les phases.
      final held = d.to ?? d.from;
      final isHeld = d.mode == SessionMode.hold ||
          (d.mode == SessionMode.beg && held != null);
      if (isHeld) {
        final (lo, hi) = holdRange!;
        dur = dur.clamp(lo, hi);
      }
    }
    if (bpm == d.bpm &&
        bpmEnd == d.bpmEnd &&
        dur == d.duration &&
        identical(clampedChain, d.chainNext)) {
      return d;
    }
    return StepDraft(
      mode: d.mode,
      bpm: bpm,
      bpmEnd: bpmEnd,
      from: d.from,
      to: d.to,
      duration: dur,
      chainNext: clampedChain,
    );
  }
}
