import 'dart:math';

import '../models/session.dart';
import '../models/session_step.dart';

/// Phrase tier d'un step (utilisé pour les beg, où la dureté de la
/// phrase prononcée fait varier l'humiliation requise).
enum PhraseTier { soft, medium, hard }

/// Échelle d'humiliation requise par action.
///
/// `requiredFor(...)` retourne le seuil d'humiliation minimal qu'une
/// utilisatrice doit avoir pour qu'une action soit jouable. Le score
/// d'humiliation effectif (`careerScore + sessionScore`, cf.
/// [HumiliationEngine]) doit être supérieur ou égal à ce seuil.
class HumiliationScale {
  static double requiredFor({
    required SessionMode mode,
    Position? from,
    Position? to,
    int? bpm,
    int? duration,
    PhraseTier? phraseTier,
  }) {
    final raw = _rawRequired(
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
      duration: duration,
      phraseTier: phraseTier,
    );
    return raw < 0 ? 0.0 : raw;
  }

  static double _rawRequired({
    required SessionMode mode,
    Position? from,
    Position? to,
    int? bpm,
    int? duration,
    PhraseTier? phraseTier,
  }) {
    switch (mode) {
      case SessionMode.breath:
      case SessionMode.freestyle:
      case SessionMode.hand:
        return 0.0;

      case SessionMode.lick:
        // Pas de bonus BPM (lick reste lent par nature). Coefficient
        // amplitude réduit (×1.0 au lieu de ×1.5 du rhythm) : sortir la
        // langue est moins frontal qu'un mouvement de bouche, mais ce
        // n'est pas gratuit non plus dès lors qu'on dépasse le bout.
        // tip→head = 0 + 1×1 = 1 (cible pédagogique, juste au-dessus
        // du gratuit) ; tip→mid = 2 + 2 = 4 ; head→mid = 2 + 1 = 3.
        final deepest = _deepest(from, to);
        if (deepest == null) return 0.0;
        final amplitude = _amplitudeCrans(from, to);
        return _depthScoreRhythm(deepest) + 1.0 * amplitude;

      case SessionMode.rhythm:
        // Idem lick : ≤ mid → seul le bonus BPM compte (vitesse extrême
        // garde son coût). Profondeur gérée par milestones, pas humiliation.
        final deepest = _deepest(from, to);
        if (deepest == null || deepest.index <= Position.mid.index) {
          return _bpmExtra(bpm);
        }
        final amplitude = _amplitudeCrans(from, to);
        return _depthScoreRhythm(deepest) + 1.5 * amplitude + _bpmExtra(bpm);

      case SessionMode.biffle:
        // Pas de profondeur fonctionnelle pour le biffle, juste la vitesse.
        return 8.0 + _bpmExtra(bpm);

      case SessionMode.hold:
        // Convention uniforme hold/beg : la position tenue est dans `to`.
        final base = _depthScoreHold(to);
        final factor = _holdDurationFactor(to);
        final extra = factor * max(0, (duration ?? 1) - 1);
        return base + extra;

      case SessionMode.beg:
        // Convention uniforme hold/beg : la position tenue est dans `to`.
        // `to == null` → beg libre (bouche libre, juste la voix).
        final base = _depthScoreBeg(to);
        final phraseBonus = _phraseBonus(phraseTier);
        return base + phraseBonus;

      case SessionMode.suckle:
        // Aspiration / téter : la position tenue est dans `to` (head ou
        // balls, le filtre `_isUnlocked` du générateur garantit qu'on ne
        // demande pas autre chose). Base par zone + montée linéaire avec
        // la durée — plus on aspire longtemps, plus c'est humiliant.
        // - head  : base 5, +0.3/s (sloppy modéré, geste explicite)
        // - balls : base 12, +0.6/s (sloppy soumis, zone humiliante)
        final base = _depthScoreSuckle(to);
        final factor = _suckleDurationFactor(to);
        final extra = factor * max(0, (duration ?? 1) - 1);
        return base + extra;
    }
  }

  static double _depthScoreSuckle(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.head:
        return 5.0;
      case Position.balls:
        return 12.0;
      case Position.tip:
      case Position.mid:
      case Position.throat:
      case Position.full:
        // Positions interdites pour suckle (filtre `_isUnlocked` du
        // générateur). On retourne un coût neutre — la requête ne
        // devrait jamais atteindre ce point.
        return 0.0;
    }
  }

  static double _suckleDurationFactor(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.head:
        return 0.3;
      case Position.balls:
        return 0.6;
      case Position.tip:
      case Position.mid:
      case Position.throat:
      case Position.full:
        return 0.0;
    }
  }

  /// Bonus exponentiel de BPM au-delà de 90 : à 90 = 0, à 120 = +5,
  /// à 150 = +20, à 180 = +45, à 240 = +125 (clampé par requiredFor).
  static double _bpmExtra(int? bpm) {
    if (bpm == null || bpm <= 90) return 0.0;
    final excess = (bpm - 90) / 30.0;
    return excess * excess * 5.0;
  }

  /// Score de profondeur pour rhythm/lick (la cible la plus profonde).
  /// Recalibré pour le modèle 2 thermomètres (cap effectif career+session
  /// jusqu'à ~50 sur une session menée à terme par une débutante) :
  /// throat et full tirent vers la zone "carrière mature".
  static double _depthScoreRhythm(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.tip:
        return 0.0;
      case Position.head:
        return 0.0;
      case Position.mid:
        return 2.0;
      case Position.throat:
        return 8.0;
      case Position.full:
        return 18.0;
      case Position.balls:
        // Zone très sloppy mais pas asphyxiante. Plus humiliante
        // qu'un throat (8) sans atteindre le full (18) qui a sa
        // composante apnée. Le combo cible `lick full/balls`
        // (amplitude 1) tombe à 16 + 1 = 17 — sous le seuil d'un
        // final hold full (req 25), accessible passé une chauffe.
        return 16.0;
    }
  }

  /// Score de base pour un hold à la position [p]. Tip et head ont un
  /// petit coût (1) pour ne plus être complètement gratuit, mais restent
  /// au-dessous du seuil de candidature minimum d'une milestone d'intro
  /// (humil 0 + tolerance 1 = cap 1) pour ne pas bloquer `intro_basics`.
  static double _depthScoreHold(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.tip:
        return 1.0;
      case Position.head:
        return 1.0;
      case Position.mid:
        return 4.0;
      case Position.throat:
        return 10.0;
      case Position.full:
        return 25.0;
      case Position.balls:
        // Tenir les couilles dans la bouche : très humiliant (sloppy +
        // soumis) mais respirable, donc entre throat (10) et full (25).
        return 14.0;
    }
  }

  /// Multiplicateur de durée pour un hold : tip/head ne dépendent pas
  /// de la durée, mid à peine, throat et full clairement (montée plus
  /// douce que l'ancien tuning, pour que la durée reste accessible
  /// passé le cap effectif de session).
  static double _holdDurationFactor(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.tip:
      case Position.head:
        return 0.0;
      case Position.mid:
        return 0.3;
      case Position.throat:
        return 1.2;
      case Position.full:
        return 2.5;
      case Position.balls:
        // Pas d'apnée à compenser, mais l'humil augmente avec la
        // durée (plus longtemps = plus humiliant). Modéré : entre
        // mid (0.3) et throat (1.2).
        return 0.8;
    }
  }

  /// Score de base pour un beg (verbal + position tenue).
  static double _depthScoreBeg(Position? p) {
    if (p == null) return 4.0;
    switch (p) {
      case Position.tip:
        return 4.0;
      case Position.head:
        return 6.0;
      case Position.mid:
        return 9.0;
      case Position.throat:
        return 18.0;
      case Position.full:
        return 28.0;
      case Position.balls:
        // Supplier la bouche sur les couilles : très humiliant
        // (zone basse + verbal soumis), entre throat (18) et
        // full (28). Pas de composante apnée donc en deçà de full.
        return 22.0;
    }
  }

  static double _phraseBonus(PhraseTier? tier) {
    switch (tier) {
      case PhraseTier.medium:
        return 4.0;
      case PhraseTier.hard:
        return 9.0;
      case PhraseTier.soft:
      case null:
        return 0.0;
    }
  }

  static int _amplitudeCrans(Position? from, Position? to) {
    if (from == null || to == null) return 0;
    return (to.index - from.index).abs();
  }

  static Position? _deepest(Position? a, Position? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }
}

/// Modèle d'humiliation à **deux thermomètres** :
///
/// - `careerScore` (persisté entre sessions, stable pendant la session) :
///   représente l'acceptance d'humiliation construite au fil de la
///   carrière. C'est le « plancher » du cap effectif d'une nouvelle
///   session — ce qu'on peut imposer dès la première minute, sans
///   préchauffe. Recalculée au `_finish` via [applyEndOfSessionDelta]
///   selon le vécu de la séance.
///
/// - `sessionScore` (intra-session, plafonné à [sessionCap] = 50) :
///   représente la chauffe accumulée pendant la séance. Démarre à 0
///   (ou à la valeur transmise par la session précédente sur encore
///   enchaîné), monte avec le tick automatique, les holds profonds
///   complétés, les punitions complétées, les milestones acquises, etc.
///   Redescend sur fail / punition abandonnée. Non persisté.
///
/// Le cap effectif vu par le générateur est `careerScore + sessionScore`
/// (cf. [effectiveCap]). Le générateur applique en plus une rampe
/// interne basée sur le tick rate (~+1/min en clean, ×3 max avec obed).
///
/// **Évolution `sessionScore` en cours de session** :
/// - Tick automatique : +1 tous les 60s (modulé par obed × 1..3)
/// - Punition complétée : +2 ; abandonnée : −4 (×2 dernière minute)
/// - Hold throat complété : +1 ; hold full complété : +3
/// - Milestone acquise : +3
/// - Crachat sur ordre : +1 ; débordement salive : +0.5
/// - Fail manuel : −5 (×2 dernière minute)
/// - Plafond [sessionCap] : 50. Plancher : 0.
///
/// **Recalcul `careerScore` au `_finish`** (cf. [applyEndOfSessionDelta]) :
/// `Δ = α × sessionScore + β × encoresAsked − β × failsCount + γ × clean`
/// avec `α = 0.10`, `β = 1.5/1.0`, `γ = 1.0`.
class HumiliationEngine {
  /// Plafond du score session. Une session ultra-longue ne peut pas
  /// débloquer indéfiniment d'actions — au-delà du cap, la chauffe ne
  /// monte plus, seul le `careerScore` (persisté) progresse.
  static const double sessionCap = 50.0;

  /// Période entre deux bumps automatiques en cours de session (1 min).
  /// Modulée par obédiance dans [onTickSecond] (cap ×3).
  static const Duration tickInterval = Duration(seconds: 60);

  static const double bumpPerInterval = 1.0;
  static const double bumpPunishmentCompleted = 2.0;
  static const double bumpHoldThroatCompleted = 1.0;
  static const double bumpHoldFullCompleted = 3.0;
  static const double bumpMilestoneAcquired = 3.0;

  /// Bump permanent (career) quand un record du profil de capacités est battu
  /// (Phase 4) — « l'exploit *est* une soumission acceptée » (§9 de la spec).
  static const double bumpProgressRecord = 2.0;
  static const double bumpSalivaOverflow = 0.5;
  static const double bumpSalivaSpit = 1.0;
  static const double malusFail = 5.0;
  static const double malusPunishmentAbandoned = 4.0;

  /// Coefficients du delta `careerScore` calculé en fin de session.
  /// Cf. [applyEndOfSessionDelta].
  static const double careerAlpha = 0.10;
  static const double careerBetaEncore = 1.5;
  static const double careerBetaFail = 1.0;
  static const double careerGammaClean = 1.0;

  double _careerScore = 0.0;
  double _sessionScore = 0.0;
  int _secondsSinceLastBump = 0;

  double get careerScore => _careerScore;
  double get sessionScore => _sessionScore;

  /// Cap effectif consommé par le générateur et les checks de
  /// disponibilité d'action. Le générateur applique sa propre rampe
  /// interne par-dessus, basée sur le tick rate.
  double get effectiveCap => _careerScore + _sessionScore;

  /// Compat shim : ancien API `score` (lifetime). Retourne le cap
  /// effectif. À termes, les call sites devraient consulter
  /// `careerScore` ou `effectiveCap` selon leur intention.
  double get score => effectiveCap;

  /// Initialise depuis le score persisté + une éventuelle valeur de
  /// session conservée (cas encore enchaîné). Appelé par le
  /// SessionController au start.
  void seed({required double career, double session = 0.0}) {
    _careerScore = career < 0 ? 0 : career;
    _sessionScore =
        session < 0 ? 0 : (session > sessionCap ? sessionCap : session);
    _secondsSinceLastBump = 0;
  }

  /// Tick par seconde. Tous les `tickInterval` (modulé par obed),
  /// +1 sur le score session.
  ///
  /// **Modulation par obédiance** : à `obedienceLevel = 100`, l'intervalle
  /// est divisé par 2 (humil tick toutes les 30s au lieu de 60s). À
  /// `obed = 200`, divisé par 3. Cap d'accélération à ×3.
  ///
  /// Sémantique : « tu obéis bien, tu en redemandes silencieusement,
  /// donc je peux t'imposer des choses plus humiliantes plus tôt ».
  void onTickSecond({double obedienceLevel = 0.0}) {
    _secondsSinceLastBump++;
    final accel = (1.0 + (obedienceLevel / 100.0)).clamp(1.0, 3.0);
    final period = (tickInterval.inSeconds / accel).round();
    if (_secondsSinceLastBump >= period) {
      _secondsSinceLastBump = 0;
      _bumpSession(bumpPerInterval);
    }
  }

  void onPunishmentCompleted() => _bumpSession(bumpPunishmentCompleted);
  void onHoldThroatCompleted() => _bumpSession(bumpHoldThroatCompleted);
  void onHoldFullCompleted() => _bumpSession(bumpHoldFullCompleted);
  void onMilestoneAcquired() => _bumpSession(bumpMilestoneAcquired);
  void onSalivaOverflow() => _bumpSession(bumpSalivaOverflow);
  void onSalivaSpit() => _bumpSession(bumpSalivaSpit);

  /// Fail manuel. Le [multiplier] est typiquement 2.0 quand on craque
  /// dans la dernière minute (cf. [SessionController.triggerFail]).
  ///
  /// [milestoneOpportunityMissed] applique en plus un facteur ×2,
  /// **cumulable** avec le multiplicateur de dernière minute (×4 au pire).
  /// Sémantique : « tu pouvais avancer (une milestone candidate était là),
  /// tu as raté ». Le mur de contenu rend le fail plus coûteux.
  void onFail(
      {double multiplier = 1.0, bool milestoneOpportunityMissed = false}) {
    final mul = multiplier * (milestoneOpportunityMissed ? 2.0 : 1.0);
    _bumpSession(-malusFail * mul);
  }

  void onPunishmentAbandoned({double multiplier = 1.0}) =>
      _bumpSession(-malusPunishmentAbandoned * multiplier);

  /// Bump direct sur le score career — utilisé en fin de session uniquement,
  /// pour les bonus d'unlock milestone (compétence acquise = chauffe
  /// permanente sur la carrière).
  void bumpCareer(double delta) {
    final next = _careerScore + delta;
    _careerScore = next < 0 ? 0 : next;
  }

  /// Applique en fin de session le delta sur le score career, basé sur
  /// le vécu de la séance. Remplace les anciens bumps évènementiels qui
  /// touchaient directement le score persisté pendant la séance.
  ///
  /// Formule :
  /// ```
  /// Δ = α × sessionScore + β_encore × encoresAsked
  ///   − β_fail × failsCount + γ × (clean ? 1 : 0)
  /// ```
  ///
  /// Retourne le delta appliqué (informatif).
  double applyEndOfSessionDelta({
    required bool clean,
    int encoresAsked = 0,
    int failsCount = 0,
  }) {
    final delta = careerAlpha * _sessionScore +
        careerBetaEncore * encoresAsked -
        careerBetaFail * failsCount +
        (clean ? careerGammaClean : 0.0);
    final next = _careerScore + delta;
    _careerScore = next < 0 ? 0 : next;
    return delta;
  }

  void _bumpSession(double delta) {
    final next = _sessionScore + delta;
    if (next < 0) {
      _sessionScore = 0;
    } else if (next > sessionCap) {
      _sessionScore = sessionCap;
    } else {
      _sessionScore = next;
    }
  }
}
