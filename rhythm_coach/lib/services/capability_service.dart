import 'package:shared_preferences/shared_preferences.dart';

import 'capability_axis.dart';

/// État persistant d'un axe du profil de capacités.
///
/// - [best] : meilleure valeur **complétée proprement** (sans fail, sans
///   « je peux pas », sans débordement de salive pour les axes concernés).
///   `null` tant qu'aucune donnée n'a été enregistrée. Monotone (croissant
///   pour `maximize` / `accumulate`, décroissant pour `minimize`).
/// - [comfort] : la cible autour de laquelle le générateur travaille. Seedée à
///   `best` à la 1ʳᵉ donnée, puis rendue adaptative par `CapabilityRegulator`
///   (ratchet ↑ modulé par [successRate], ratchet ↓ sur signal négatif, decay
///   « use it or lose it »). Peut dépasser `best` (cible un peu plus ambitieuse
///   que l'exploit prouvé).
/// - [successRate] : EMA des réussites/échecs récents sur cet axe (0..1).
///   Module l'agressivité de la surcharge.
/// - [lastSeenSession] : index de la dernière session où l'axe a produit un
///   record propre. Sert au decay « use it or lose it ».
class CapabilityAxisState {
  final double? best;
  final double? comfort;
  final double successRate;
  final int lastSeenSession;

  const CapabilityAxisState({
    this.best,
    this.comfort,
    this.successRate = CapabilityService.defaultSuccessRate,
    this.lastSeenSession = -1,
  });

  bool get hasData => best != null;
}

/// Vue lecture seule du profil complet, passée (à terme) au générateur de
/// session. En Phase 1 seul le ProfileScreen la consomme pour l'affichage.
class CapabilityProfile {
  final Map<CapabilityAxis, CapabilityAxisState> _states;

  const CapabilityProfile(this._states);

  CapabilityAxisState stateOf(CapabilityAxis axis) =>
      _states[axis] ?? const CapabilityAxisState();

  double? bestOf(CapabilityAxis axis) => stateOf(axis).best;
  double? comfortOf(CapabilityAxis axis) => stateOf(axis).comfort;

  /// `true` si au moins un axe porte des données — sert au ProfileScreen
  /// pour décider d'afficher (ou non) la section « Capacités ».
  bool get hasAnyData => _states.values.any((s) => s.hasData);

  Iterable<CapabilityAxis> get axesWithData =>
      CapabilityAxis.displayOrder.where((a) => stateOf(a).hasData);
}

/// Rapport produit par `CapabilityTracker` à la fin d'une session.
///
/// [reached] : pour chaque axe sollicité proprement, la valeur atteinte
/// (max streak / max BPM / cran max ; min pour les axes `minimize` ;
/// somme de la session pour les axes `accumulate`).
///
/// [sessionCeilings] : valeurs figées lors d'un appui FAIL (cf. §6 de la
/// spec). En Phase 1 elles sont collectées mais pas encore consommées —
/// le générateur ne les lira qu'en Phase 2.
class SessionCapabilityReport {
  final Map<CapabilityAxis, double> reached;
  final Map<CapabilityAxis, double> sessionCeilings;

  const SessionCapabilityReport({
    required this.reached,
    required this.sessionCeilings,
  });

  bool get isEmpty => reached.isEmpty && sessionCeilings.isEmpty;
}

/// Boucle d'autorégulation du profil de capacités (Phase 3, cf. §5 / §11 de
/// la spec). Fonction **pure** : aucun accès aux `shared_preferences`, tout se
/// joue sur des `CapabilityAxisState` immuables — ce qui la rend directement
/// testable. `CapabilityService.commit` l'orchestre (lecture/écriture prefs +
/// attribution du tap-out).
///
/// Modèle, par axe et par session :
/// - **`best`** : record propre, monotone — ne baisse jamais (croissant pour
///   `maximize`/`accumulate`, décroissant pour `minimize`).
/// - **`comfort`** : la cible du générateur.
///   - 1ʳᵉ donnée → seedé à `best` (= comportement Phase 1/2).
///   - réussite *au-dessus* de `comfort` (= l'axe surchargé de la séance, les
///     autres étant clampés à `comfort` par le générateur) → ratchet ↑ : gain
///     `comfort × (1 + lerp(kRatchetUpGainMin, kRatchetUpGainMax, successRate))`
///     (confiance haute → ~+14 %, fragile → ~+4 %), ancré pour ne pas dépasser
///     `reached × kRatchetAnchorHeadroom` (on ne va jamais beaucoup plus loin
///     que ce qu'elle vient de prouver) ; profondeur = +1 cran au plus, gaté
///     par `successRate ≥ kDepthCranGate`.
///   - signal négatif **imputé** (tap-out attribué à cet axe, ou débordement
///     de salive pour `noswallow`) → ratchet ↓ : `min(comfort, figé) × 0,85`
///     (profondeur : −1 cran). `best` ne bouge pas.
///   - signal négatif **subi sans être imputé** (un fail a figé l'axe sans
///     qu'il soit le plus surchargé) → simple soft-cap à la valeur figée.
///   - axe non sollicité depuis `kDecayAfterSessions` sessions → dérive lente
///     vers `kDecayTargetFracOfBest × best`.
/// - **`successRate`** : EMA (`α = kSuccessRateAlpha`) — vers 1 sur réussite
///   surchargée, vers 0 sur signal négatif, dérive douce vers 0,5 en cas de
///   non-sollicitation prolongée.
class CapabilityRegulator {
  CapabilityRegulator._();

  /// Facteur de surcharge appliqué par le **générateur** au `comfort` de l'axe
  /// poussé, modulé par la confiance (`successRate ∈ [0,1]`). 1.0 = pas de
  /// surcharge. (≠ du gain de ratchet ci-dessous : la surcharge gen pousse la
  /// *cible du step*, le ratchet consolide ensuite le *comfort*.)
  static const double kSurchargeMin = 1.03;
  static const double kSurchargeMax = 1.15;

  /// Gain de `comfort` sur une session de réussite surchargée, modulé par
  /// `successRate` (fraction de `comfort` ; sert aussi de plafond par session).
  static const double kRatchetUpGainMin = 0.04;
  static const double kRatchetUpGainMax = 0.14;

  /// Le `comfort` après ratchet ↑ ne dépasse pas `reached × ce facteur` (et,
  /// pour les axes `minimize`, ne descend pas sous `reached × (2 − ce facteur)`)
  /// — on reste ancré sur ce que la joueuse vient de démontrer.
  static const double kRatchetAnchorHeadroom = 1.05;

  /// Rabot du `comfort` sur tap-out/fail/débordement imputé.
  static const double kRatchetDownFactor = 0.85;

  /// Inactivité (en sessions) avant que `comfort` ne commence à dériver, et
  /// cible (fraction de `best`) vers laquelle il dérive.
  static const int kDecayAfterSessions = 4;
  static const double kDecayTargetFracOfBest = 0.70;

  /// Fraction du chemin parcouru vers la cible de decay à chaque session
  /// au-delà du seuil (convergence géométrique).
  static const double kDecayStepFrac = 0.34;

  /// Plancher pratique des BPM rythme (en dessous c'est un hold, plus du
  /// rythme — cf. clamp `CameraMotionDetector` [24..300]).
  static const double kBpmFloorPractical = 18.0;

  /// Plancher de durée d'un sas `breath` (axe `breathMinDose`).
  static const double kBreathMinDoseFloor = 2.0;

  /// Lissage de l'EMA `successRate`.
  static const double kSuccessRateAlpha = 0.30;

  /// `successRate` minimal pour autoriser l'avancée d'un cran de profondeur.
  static const double kDepthCranGate = 0.65;

  /// Marge relative au-delà de laquelle `reached` compte comme un dépassement
  /// du `comfort` (absorbe les arrondis BPM/durée du clamp générateur).
  static const double kOvershootMargin = 1.02;

  /// Probabilité de déclencher une `progressPhrase` (Phase 4 — coach audible) :
  /// 0 tant que `level ≤ kProgressPhraseLevelGate`, puis montée linéaire de
  /// `kProgressPhraseChancePerLevel`/niveau, plafonnée à `kProgressPhraseChanceMax`.
  /// Quasi-muet aux premiers paliers — et de toute façon silencieux tant
  /// qu'aucun axe n'est consolidé (pas d'axe surchargé sur un profil neuf).
  static const int kProgressPhraseLevelGate = 4;
  static const double kProgressPhraseChancePerLevel = 0.05;
  static const double kProgressPhraseChanceMax = 0.40;

  /// Facteur de surcharge pour l'axe poussé, en fonction de sa `successRate`.
  static double surchargeFactor(double successRate) =>
      kSurchargeMin +
      (kSurchargeMax - kSurchargeMin) * successRate.clamp(0.0, 1.0);

  /// Probabilité de prononcer une `progressPhrase` au niveau [level]
  /// (cf. `kProgressPhrase*`). `level ≤ 4 → 0`.
  static double progressPhraseChanceForLevel(int level) =>
      ((level - kProgressPhraseLevelGate) * kProgressPhraseChancePerLevel)
          .clamp(0.0, kProgressPhraseChanceMax);

  /// Attribution du tap-out (§6) : parmi les axes figés sur un FAIL ([ceilings]),
  /// celui le plus surchargé relativement à son `comfort` (ratio `figé/comfort`
  /// > 1 ⇒ poussé au-delà de sa zone de confort ; inversé pour les axes
  /// `minimize` — un floor « trop lent » a `figé < comfort`). Grâce à la
  /// surcharge isolée du générateur, en pratique un seul axe dépasse son comfort
  /// → attribution non ambiguë. Retourne `null` si le fail s'est produit *dans*
  /// la zone de confort de tous les axes figés (= « fail-flemme », pas un
  /// tap-out de limite légitime).
  ///
  /// Fonction **pure** : ré-utilisée par `CapabilityService.commit` (ratchet ↓
  /// en fin de séance) ET par `SessionController` mid-session (choix d'une
  /// phrase `tapout` du coach, Phase 4).
  static CapabilityAxis? attributeTapOut(
    Map<CapabilityAxis, double> ceilings,
    CapabilityProfile profile,
  ) {
    CapabilityAxis? attributed;
    double bestRatio = 1.0;
    ceilings.forEach((axis, ceiling) {
      final comfort = profile.comfortOf(axis);
      if (comfort == null || comfort <= 0 || ceiling <= 0) return;
      final ratio = axis.recordKind == CapabilityRecordKind.minimize
          ? comfort / ceiling
          : ceiling / comfort;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        attributed = axis;
      }
    });
    return attributed;
  }

  /// Recalcule l'état d'un axe en fin de session carrière.
  ///
  /// [reached] : valeur propre atteinte cette session (`null` si l'axe n'a pas
  /// produit de record propre — il peut quand même avoir un [sessionCeiling]).
  /// [sessionCeiling] : valeur figée sur un FAIL de la séance (§6), ou `null`.
  /// [hardNegative] : vrai si le signal négatif est *imputé* à cet axe (tap-out
  /// attribué, ou débordement de salive pour `noswallow`) → ratchet ↓ dur ;
  /// sinon un `sessionCeiling` non nul ne fait qu'un soft-cap.
  /// [sessionIndex] : index de la session courante (horloge de decay).
  static CapabilityAxisState regulate({
    required CapabilityAxis axis,
    required CapabilityAxisState prev,
    double? reached,
    double? sessionCeiling,
    bool hardNegative = false,
    required int sessionIndex,
  }) {
    final bool isMinimize = axis.recordKind == CapabilityRecordKind.minimize;
    final bool isAccumulate =
        axis.recordKind == CapabilityRecordKind.accumulate;
    final bool isDepthCran = axis.unit == CapabilityUnit.depthCran;

    // ── best : record propre, monotone ──────────────────────────────────
    double? newBest = prev.best;
    if (reached != null) {
      if (isAccumulate) {
        newBest = (prev.best ?? 0) + reached;
      } else if (prev.best == null) {
        newBest = reached;
      } else if (isMinimize) {
        newBest = reached < prev.best! ? reached : prev.best;
      } else {
        newBest = reached > prev.best! ? reached : prev.best;
      }
    }

    // Compteurs lifetime : aucune notion de comfort/ratchet — comfort suit best.
    if (isAccumulate) {
      if (newBest == null) return prev;
      return CapabilityAxisState(
        best: newBest,
        comfort: newBest,
        successRate: prev.successRate,
        lastSeenSession: reached != null ? sessionIndex : prev.lastSeenSession,
      );
    }

    // Pas encore de cible : on seede `comfort = best` dès qu'un record propre
    // existe (= comportement Phase 1/2). Un `sessionCeiling` seul (fail sur un
    // axe jamais complété proprement) ne crée pas de comfort — le générateur
    // n'a rien à gater tant que la joueuse n'a rien prouvé.
    if (prev.comfort == null) {
      if (newBest == null) return prev;
      return CapabilityAxisState(
        best: newBest,
        comfort: newBest,
        successRate: prev.successRate,
        lastSeenSession: sessionIndex,
      );
    }

    double comfort = prev.comfort!;
    double sr = prev.successRate;
    final int lastSeen =
        (reached != null) ? sessionIndex : prev.lastSeenSession;
    final double bestRef = newBest ?? comfort;
    final double absFloor = _absoluteFloor(axis);

    if (sessionCeiling != null) {
      // Signal négatif (fail / débordement).
      if (hardNegative) {
        if (isDepthCran) {
          comfort = (comfort - 1).clamp(0.0, prev.comfort!);
          if (sessionCeiling < comfort) comfort = sessionCeiling;
        } else if (isMinimize) {
          // « plus facile » = comfort s'éloigne de best (monte pour un floor).
          final double base =
              sessionCeiling > comfort ? sessionCeiling : comfort;
          comfort = base / kRatchetDownFactor;
        } else {
          final double base =
              sessionCeiling < comfort ? sessionCeiling : comfort;
          comfort = base * kRatchetDownFactor;
        }
        sr = _ema(sr, 0.0);
      } else {
        // Soft-cap : on tempère sans le ×0,85 (cf. §6 « tempère l'agressivité »).
        if (isMinimize) {
          if (sessionCeiling > comfort) comfort = sessionCeiling;
        } else {
          if (sessionCeiling < comfort) comfort = sessionCeiling;
        }
        sr = _ema(sr, 0.0, weight: 0.5);
      }
    } else if (reached != null) {
      // Pas de signal négatif et un record propre a été posé.
      final bool overshoot = isMinimize
          ? reached <= comfort * (2 - kOvershootMargin)
          : reached >= comfort * kOvershootMargin;
      if (overshoot) {
        final double gain = kRatchetUpGainMin +
            (kRatchetUpGainMax - kRatchetUpGainMin) * sr.clamp(0.0, 1.0);
        if (isDepthCran) {
          // Cran discret : +1 au plus, et seulement si la confiance est là.
          if (sr >= kDepthCranGate) {
            final double bumped = comfort + 1;
            comfort = bumped < reached ? bumped : reached;
          }
          sr = _ema(sr, 1.0);
        } else if (isMinimize) {
          // Ratchet « vers le bas » (= vers plus dur), creep limité, ancré sur
          // le tempo qu'elle vient de tenir, planché par `absFloor`.
          double next = comfort * (1.0 - gain);
          final double anchorFloor = reached * (2.0 - kRatchetAnchorHeadroom);
          if (next < anchorFloor) next = anchorFloor;
          if (next < absFloor) next = absFloor;
          if (next < comfort) comfort = next;
          sr = _ema(sr, 1.0);
        } else {
          double next = comfort * (1.0 + gain);
          final double anchorCeil = reached * kRatchetAnchorHeadroom;
          if (next > anchorCeil) next = anchorCeil;
          if (next > comfort) comfort = next;
          sr = _ema(sr, 1.0);
        }
      }
      // sinon : neutre (axe clampé qui a juste fait son step) — rien ne bouge.
    } else {
      // Axe non sollicité cette session : decay éventuel.
      if (prev.lastSeenSession >= 0 &&
          sessionIndex - prev.lastSeenSession >= kDecayAfterSessions &&
          newBest != null) {
        final double target = isMinimize
            ? newBest / kDecayTargetFracOfBest
            : newBest * kDecayTargetFracOfBest;
        comfort = comfort + (target - comfort) * kDecayStepFrac;
        sr = _ema(sr, 0.5, weight: 0.5);
      }
      // lastSeen inchangé → continue de décroître.
    }

    // Garde-fous d'unité et cohérence comfort/best.
    if (isMinimize) {
      if (comfort < absFloor) comfort = absFloor;
    } else {
      if (comfort < absFloor) comfort = absFloor;
      // `comfort` peut dépasser `best` (la cible est un peu plus ambitieuse que
      // l'exploit prouvé) mais on l'ancre : pas plus de `+kSurchargeMax`.
      final double cap = bestRef * kSurchargeMax;
      if (comfort > cap) comfort = cap;
    }

    return CapabilityAxisState(
      best: newBest,
      comfort: comfort,
      successRate: sr.clamp(0.0, 1.0),
      lastSeenSession: lastSeen,
    );
  }

  /// Plancher absolu d'un axe (en deçà la valeur n'a plus de sens).
  static double _absoluteFloor(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.rhythmBpmFloorShallow:
      case CapabilityAxis.rhythmBpmFloorThroat:
      case CapabilityAxis.rhythmBpmFloorFull:
        return kBpmFloorPractical;
      case CapabilityAxis.breathMinDose:
        return kBreathMinDoseFloor;
      default:
        return 0.0;
    }
  }

  static double _ema(double prev, double towards, {double weight = 1.0}) =>
      prev + (towards - prev) * kSuccessRateAlpha * weight;
}

/// Persistance du profil de capacités (`shared_preferences`).
///
/// Mode **carrière uniquement** : Custom et scénarios JSON n'écrivent rien
/// (le `CapabilityTracker` n'y est tout simplement pas câblé).
class CapabilityService {
  static const String _prefix = 'cap.';
  static const String _suffixBest = '.best';
  static const String _suffixComfort = '.comfort';
  static const String _suffixSuccessRate = '.sr';
  static const String _suffixLastSeen = '.seen';

  /// Clé legacy de `StatsService` migrée vers `holdFullStreak.best` au 1er
  /// lancement. On lit la valeur directement depuis `shared_preferences`
  /// pour ne pas créer de dépendance sur `StatsService` — la clé reste en
  /// place (le badge IronLungs continue de la consommer).
  static const String _kLegacyMaxHoldFullAtomic = 'stats.max_hold_full_atomic';

  /// Drapeau « migration legacy déjà tentée » — évite de re-seeder si la
  /// joueuse a depuis fait reculer son record (impossible aujourd'hui, mais
  /// défensif) ou si le seed a été volontairement effacé.
  static const String _kLegacyMigrated = 'cap.legacy_migrated';

  static const double defaultSuccessRate = 0.5;

  /// Lit l'état persisté de tous les axes (après migration legacy).
  Future<CapabilityProfile> snapshotProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    final states = <CapabilityAxis, CapabilityAxisState>{};
    for (final axis in CapabilityAxis.values) {
      states[axis] = _readState(prefs, axis);
    }
    return CapabilityProfile(states);
  }

  /// Intègre un rapport de fin de session dans le profil persisté en appliquant
  /// la boucle d'autorégulation (`CapabilityRegulator`).
  ///
  /// [sessionIndex] = compteur de sessions carrière complétées (horloge de
  /// decay, mémorisé dans `lastSeenSession` des axes sollicités).
  ///
  /// Renvoie l'axe auquel le tap-out de la séance a été imputé (l'axe le plus
  /// surchargé relativement à son `comfort` au moment du fail, cf. §6), ou
  /// `null` si la séance n'a connu aucun fail « parlant » — utile au coach
  /// (Phase 4) ; le ratchet, lui, est déjà appliqué en interne.
  Future<CapabilityAxis?> commit(
    SessionCapabilityReport report, {
    required int sessionIndex,
  }) async {
    if (report.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);

    final prevStates = <CapabilityAxis, CapabilityAxisState>{
      for (final axis in CapabilityAxis.values) axis: _readState(prefs, axis),
    };

    // Attribution du tap-out (cf. CapabilityRegulator.attributeTapOut) : parmi
    // les axes figés sur un FAIL, celui le plus surchargé relativement à son
    // `comfort`. Grâce à la surcharge isolée du générateur, en pratique un seul
    // axe dépasse son comfort → attribution non ambiguë.
    final attributed = CapabilityRegulator.attributeTapOut(
      report.sessionCeilings,
      CapabilityProfile(prevStates),
    );

    for (final axis in CapabilityAxis.values) {
      final prev = prevStates[axis]!;
      final reached = report.reached[axis];
      final ceiling = report.sessionCeilings[axis];
      // Rien à faire si l'axe n'a ni record propre, ni plafond figé, ni cible
      // existante (donc rien à faire dériver/decayer non plus).
      if (reached == null && ceiling == null && prev.comfort == null) continue;
      // Un débordement de salive sur `noswallow` est un signal négatif imputé
      // de plein droit (§5.3), indépendamment du ratio — le `sessionCeiling`
      // posé par `CapabilityTracker.onSalivaOverflow` le matérialise.
      final bool hard = axis == attributed ||
          (axis == CapabilityAxis.noswallowStreak && ceiling != null);
      final next = CapabilityRegulator.regulate(
        axis: axis,
        prev: prev,
        reached: reached,
        sessionCeiling: ceiling,
        hardNegative: hard,
        sessionIndex: sessionIndex,
      );
      if (next.comfort == null || next.best == null) continue;
      _writeState(
        prefs,
        axis,
        best: next.best!,
        comfort: next.comfort!,
        successRate: next.successRate,
        lastSeenSession: next.lastSeenSession,
      );
    }
    return attributed;
  }

  /// Efface tout le profil de capacités (bouton « tout remettre à zéro » du
  /// ProfileScreen). Ne touche pas la clé legacy `stats.max_hold_full_atomic`
  /// (gérée par `StatsService.resetAll`), mais reset le drapeau de migration
  /// pour qu'un éventuel reset partiel se re-seede correctement.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final axis in CapabilityAxis.values) {
      await prefs.remove('$_prefix${axis.storageKey}$_suffixBest');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixComfort');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixSuccessRate');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixLastSeen');
    }
    await prefs.remove(_kLegacyMigrated);
  }

  // ── interne ───────────────────────────────────────────────────────────

  CapabilityAxisState _readState(SharedPreferences prefs, CapabilityAxis axis) {
    final base = '$_prefix${axis.storageKey}';
    return CapabilityAxisState(
      best: prefs.getDouble('$base$_suffixBest'),
      comfort: prefs.getDouble('$base$_suffixComfort'),
      successRate:
          prefs.getDouble('$base$_suffixSuccessRate') ?? defaultSuccessRate,
      lastSeenSession: prefs.getInt('$base$_suffixLastSeen') ?? -1,
    );
  }

  void _writeState(
    SharedPreferences prefs,
    CapabilityAxis axis, {
    required double best,
    required double comfort,
    required double successRate,
    required int lastSeenSession,
  }) {
    final base = '$_prefix${axis.storageKey}';
    prefs.setDouble('$base$_suffixBest', best);
    prefs.setDouble('$base$_suffixComfort', comfort);
    prefs.setDouble('$base$_suffixSuccessRate', successRate);
    prefs.setInt('$base$_suffixLastSeen', lastSeenSession);
  }

  /// Migration au 1er lancement : `StatsService.maxHoldFullAtomic` (« plus
  /// long hold full sans fail ») n'est rien d'autre qu'un axe de ce profil.
  /// On l'importe dans `holdFullStreak` si l'axe n'a pas encore de donnée.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (prefs.getBool(_kLegacyMigrated) ?? false) return;
    await prefs.setBool(_kLegacyMigrated, true);
    final legacy = prefs.getInt(_kLegacyMaxHoldFullAtomic) ?? 0;
    if (legacy <= 0) return;
    final base = '$_prefix${CapabilityAxis.holdFullStreak.storageKey}';
    if (prefs.getDouble('$base$_suffixBest') != null) return;
    final v = legacy.toDouble();
    prefs.setDouble('$base$_suffixBest', v);
    prefs.setDouble('$base$_suffixComfort', v);
    prefs.setDouble('$base$_suffixSuccessRate', defaultSuccessRate);
    prefs.setInt('$base$_suffixLastSeen', -1);
  }
}
