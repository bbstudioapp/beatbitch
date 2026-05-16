// Fichier part de `career_session_generator.dart` — 2ᵉ enveloppe de
// difficulté carrière (profil de capacités + surcharge isolée + bornes
// utilisateur Custom).
//
// `_CapabilityClamps` est un **value object immuable** construit une fois
// par `generate()` après que l'axe de surcharge a été choisi. Toute la
// logique de clamp (profondeur / BPM / durée) y vit en méthodes d'instance
// qui consomment les fields. Les helpers vraiment statiques (mapping
// position → axe BPM, min nullable, set des axes surchargables, choix de
// l'axe) sont des `static`.
//
// Conception : les méthodes de clamp s'appellent entre elles, et toutes
// ont besoin du même bundle (`profile`, `ceilings`, `overloadAxis`,
// `overloadFactor`, `bpmRange`, `holdRange`). Passer ces 6 fields à chaque
// appel rendrait les signatures illisibles — l'objet immuable est plus
// propre qu'une longue liste de paramètres répétés.

part of 'career_session_generator.dart';

/// 2ᵉ enveloppe de difficulté : profil de capacités persisté + plafonds
/// figés en cours de session + axe surchargé + bornes utilisateur Custom.
/// Immutable : le générateur en construit un par appel à `generate()`,
/// après que `pickOverloadAxis` a choisi l'axe à pousser cette séance.
class _CapabilityClamps {
  /// Profil persisté (lecture seule). `null` = mode hérité (Custom,
  /// scénarios JSON, tests) → toutes les méthodes de cap se neutralisent.
  final CapabilityProfile? profile;

  /// Plafonds figés sur un FAIL pendant la session courante (§6 de la
  /// spec) — plus contraignants que `comfort` quand présents.
  final Map<CapabilityAxis, double> ceilings;

  /// Axe surchargé cette séance (un seul, §5). `null` = pas de surcharge.
  final CapabilityAxis? overloadAxis;

  /// Facteur de surcharge appliqué au `comfort` de [overloadAxis]
  /// (1.03..1.15). 1.0 pour les autres axes.
  final double overloadFactor;

  /// Bornes BPM utilisateur (mode Custom). `null` hors Custom.
  final (int, int)? bpmRange;

  /// Bornes de durée pour les steps tenus (hold + beg avec position),
  /// utilisateur (mode Custom). `null` hors Custom.
  final (int, int)? holdRange;

  const _CapabilityClamps({
    required this.profile,
    required this.ceilings,
    required this.overloadAxis,
    required this.overloadFactor,
    required this.bpmRange,
    required this.holdRange,
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
    final p = profile;
    if (p == null) return null;
    var comfort = p.comfortOf(axis);
    if (comfort != null && axis == overloadAxis) {
      if (axis == CapabilityAxis.rhythmDepthMax) {
        // Profondeur = cran discret : on autorise +1 cran, et seulement si
        // la confiance au cran courant est là (cf. asymétries §5).
        // « Humiliation l'autorise » + « milestone d'unlock acquittée »
        // sont déjà garantis par `_maxDepthIndex` (qui borne `to` en amont).
        if (p.stateOf(axis).successRate >= CapabilityRegulator.kDepthCranGate) {
          comfort = comfort + 1;
        }
      } else {
        comfort = comfort * overloadFactor;
      }
    }
    return minNullable(comfort, ceilings[axis]);
  }

  /// Renvoie le facteur de surcharge applicable à [axis] (1.0 hors
  /// surcharge). Pour `rhythmDepthMax` la surcharge est un cran, pas un
  /// facteur — utiliser [capabilityCapFor] directement.
  double overloadFactorFor(CapabilityAxis axis) =>
      axis == overloadAxis ? overloadFactor : 1.0;

  /// Borne un draft à l'enveloppe « profil de capacités » : profondeur,
  /// BPM et durée ne dépassent pas ce que la joueuse a *prouvé* tenir.
  /// 2ᵉ enveloppe orthogonale à l'humiliation — un step n'est jouable
  /// que si **les deux** passent. No-op hors carrière ([profile] = null).
  ///
  /// Modes hors gating : `hand` (exclu de tout axe de difficulté — cf.
  /// règle « hand n'est jamais un levier »), `lick` (enregistré seulement,
  /// pas pilotant), `breath` / `freestyle` (aucun axe). Les steps scriptés
  /// (séquences milestone, beg insistant du Supplier) passent par d'autres
  /// chemins et ne sont pas clampés — comme ils ne sont pas gatés par
  /// l'humiliation non plus.
  _StepDraft clampToCapability(_StepDraft d) {
    if (profile == null) return clampToCustomLimits(d);
    final clampedChain =
        d.chainNext == null ? null : clampToCapability(d.chainNext!);
    var from = d.from;
    var to = d.to;
    var bpm = d.bpm;
    var bpmEnd = d.bpmEnd;
    var dur = d.duration;
    switch (d.mode) {
      case SessionMode.rhythm:
        // Profondeur (cran). Plancher `head` : un rhythm a besoin d'au
        // moins une amplitude tip↔head, jamais tip↔tip.
        final depthCap = capabilityCapFor(CapabilityAxis.rhythmDepthMax);
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
          var bpmCap = capabilityCapFor(rhythmBpmCeilAxisFor(to));
          if (from != null &&
              from.index <= Position.mid.index &&
              to.index >= Position.throat.index) {
            bpmCap = minNullable(
              bpmCap,
              capabilityCapFor(to == Position.throat
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
        if (from != null &&
            from.index >= Position.throat.index &&
            dur != null) {
          final apneaCap = capabilityCapFor(CapabilityAxis.gorgeApneeStreak);
          if (apneaCap != null && dur > apneaCap) {
            dur = max(2, apneaCap.floor());
          }
        }
      case SessionMode.hold:
      case SessionMode.beg:
        // Convention hold/beg : position tenue dans `to` (repli `from`).
        final held = to ?? from;
        if (held == Position.throat || held == Position.full) {
          final cap = minNullable(
            capabilityCapFor(held == Position.throat
                ? CapabilityAxis.holdThroatStreak
                : CapabilityAxis.holdFullStreak),
            capabilityCapFor(CapabilityAxis.gorgeApneeStreak),
          );
          if (cap != null && dur != null && dur > cap) {
            dur = max(2, cap.floor());
          }
        }
      case SessionMode.biffle:
        final durCap = capabilityCapFor(CapabilityAxis.biffleStreak);
        if (durCap != null && dur != null && dur > durCap) {
          dur = max(2, durCap.floor());
        }
        final bpmCap = capabilityCapFor(CapabilityAxis.biffleBpmMax);
        if (bpmCap != null && bpm != null && bpm > bpmCap) {
          bpm = bpmCap.round();
        }
      case SessionMode.hand:
      case SessionMode.lick:
      case SessionMode.breath:
      case SessionMode.freestyle:
      case SessionMode.suckle:
        // Suckle : pas de BPM, position figée par construction (head ou
        // balls, filtrée en amont par `_isUnlocked`). Aucun axe capability
        // pertinent → pas de cap difficile. Durée bornée par la palette,
        // pas par le profil.
        break; // pas de cap de difficulté pour ces modes
    }
    if (from == d.from &&
        to == d.to &&
        bpm == d.bpm &&
        bpmEnd == d.bpmEnd &&
        dur == d.duration &&
        identical(clampedChain, d.chainNext)) {
      return clampToCustomLimits(d);
    }
    return clampToCustomLimits(_StepDraft(
      mode: d.mode,
      bpm: bpm,
      bpmEnd: bpmEnd,
      from: from,
      to: to,
      duration: dur,
      chainNext: clampedChain,
    ));
  }

  /// Borne un draft aux limites utilisateur du mode Custom ([bpmRange] /
  /// [holdRange]). Appliqué après [clampToCapability] pour rester
  /// compatible avec le profil (qui ne sert qu'en carrière, désactivé en
  /// Custom). `chainNext` est récursé. No-op si aucune borne n'est
  /// fournie (carrière / scénario JSON).
  _StepDraft clampToCustomLimits(_StepDraft d) {
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
    return _StepDraft(
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
