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
/// d'humiliation (cumul lifetime, cf. [HumiliationEngine]) doit être
/// supérieur ou égal à ce seuil.
class HumiliationScale {
  /// Niveau de carrière minimum requis pour débloquer le freestyle.
  /// Indépendant du score d'humiliation.
  static const int freestyleMinLevel = 4;

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
    // Pas de borne haute : un hold full 60s exige ~199 d'humil cumulée,
    // un hold throat 30s ~52, etc. Le clamp à 100 historique masquait
    // les écarts entre actions extrêmes (toutes ramenées à 100).
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
        // Pas de bonus BPM (lick reste lent par nature).
        // Profondeur ≤ mid : action « bases » gated par milestone (intro
        // niveau 1 / niveau 2), pas par humiliation. Au-delà (throat/full)
        // la profondeur reprend le coût d'humiliation classique.
        final deepest = _deepest(from, to);
        if (deepest == null || deepest.index <= Position.mid.index) return 0.0;
        final amplitude = _amplitudeCrans(from, to);
        return _depthScoreRhythm(deepest) + 1.5 * amplitude;

      case SessionMode.rhythm:
        // Idem lick : ≤ mid → seul le bonus BPM compte (vitesse extrême
        // garde son coût). Profondeur gérée par milestones, pas humiliation.
        final deepest = _deepest(from, to);
        if (deepest == null || deepest.index <= Position.mid.index) {
          return _bpmExtra(bpm);
        }
        final amplitude = _amplitudeCrans(from, to);
        return _depthScoreRhythm(deepest) +
            1.5 * amplitude +
            _bpmExtra(bpm);

      case SessionMode.biffle:
        // Pas de profondeur fonctionnelle pour le biffle, juste la vitesse.
        return 10.0 + _bpmExtra(bpm);

      case SessionMode.hold:
        final base = _depthScoreHold(from);
        final factor = _holdDurationFactor(from);
        final extra = factor * max(0, (duration ?? 1) - 1);
        return base + extra;

      case SessionMode.beg:
        final base = _depthScoreBeg(from);
        final phraseBonus = _phraseBonus(phraseTier);
        return base + phraseBonus;
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
        return 6.0;
      case Position.full:
        return 15.0;
    }
  }

  /// Score de base pour un hold à la position [p].
  static double _depthScoreHold(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.tip:
        return 0.0;
      case Position.head:
        return 1.0;
      case Position.mid:
        return 4.0;
      case Position.throat:
        return 8.0;
      case Position.full:
        return 22.0;
    }
  }

  /// Multiplicateur de durée pour un hold : tip/head ne dépendent pas
  /// de la durée, mid à peine, throat et full clairement.
  static double _holdDurationFactor(Position? p) {
    if (p == null) return 0.0;
    switch (p) {
      case Position.tip:
      case Position.head:
        return 0.0;
      case Position.mid:
        return 0.3;
      case Position.throat:
        return 1.5;
      case Position.full:
        return 3.0;
    }
  }

  /// Score de base pour un beg (verbal + position tenue).
  static double _depthScoreBeg(Position? p) {
    if (p == null) return 5.0;
    switch (p) {
      case Position.tip:
        return 5.0;
      case Position.head:
        return 7.0;
      case Position.mid:
        return 10.0;
      case Position.throat:
        return 20.0;
      case Position.full:
        return 30.0;
    }
  }

  static double _phraseBonus(PhraseTier? tier) {
    switch (tier) {
      case PhraseTier.medium:
        return 5.0;
      case PhraseTier.hard:
        return 10.0;
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

/// Score d'humiliation cumulé sur la **durée de vie du compte**, démarre
/// à 0, pas de borne haute (peut dépasser 100 sur les longues carrières).
/// Persisté entre sessions par `StatsService.humiliationLevel`.
///
/// Démarre à 0. En session, monte lentement (`+1 toutes les 4 min`),
/// remonte un peu sur événements positifs (encore, punition complétée,
/// session clean), descend à chaque fail. Borne basse : 0.
class HumiliationEngine {
  /// Période entre deux bumps automatiques en cours de session (4 min).
  static const Duration tickInterval = Duration(seconds: 240);

  static const double bumpPerInterval = 1.0;
  static const double bumpEncore = 1.0;
  static const double bumpPunishmentCompleted = 1.0;
  static const double bumpSessionClean = 1.0;
  static const double malusFail = 1.0;
  static const double malusPunishmentAbandoned = 1.0;

  double _score = 0.0;
  double get score => _score;

  /// Secondes écoulées dans la session courante depuis le dernier bump.
  /// Sert au tick automatique (+1 toutes les `tickInterval`).
  int _secondsSinceLastBump = 0;

  /// Initialise depuis le score persisté. Appelé par le SessionController
  /// au start (une fois la valeur récupérée de StatsService).
  void seed(double persisted) {
    _score = persisted < 0 ? 0 : persisted;
    _secondsSinceLastBump = 0;
  }

  /// Tick par seconde. Tous les `tickInterval`, +1 au score.
  ///
  /// **Modulation par obédiance** : à `obedienceLevel = 100`, l'intervalle
  /// est divisé par 2 (humil tick toutes les 120s au lieu de 240s). À
  /// `obed = 200`, divisé par 3. Cap d'accélération à ×3 pour ne pas
  /// laisser une obédiance extrême faire monter humil instantanément.
  /// Le levier ne ralentit jamais le tick (`obed = 0` = base 240s).
  ///
  /// Sémantique : « tu obéis bien, tu en redemandes silencieusement,
  /// donc je peux t'imposer des choses plus humiliantes plus tôt ».
  void onTickSecond({double obedienceLevel = 0.0}) {
    _secondsSinceLastBump++;
    final accel = (1.0 + (obedienceLevel / 100.0)).clamp(1.0, 3.0);
    final period = (tickInterval.inSeconds / accel).round();
    if (_secondsSinceLastBump >= period) {
      _secondsSinceLastBump = 0;
      _bump(bumpPerInterval);
    }
  }

  void onEncoreRequested() => _bump(bumpEncore);
  void onPunishmentCompleted() => _bump(bumpPunishmentCompleted);
  void onSessionCleanFinish() => _bump(bumpSessionClean);
  void onMilestoneAcquired() => _bump(2.0);
  void onFail({double multiplier = 1.0}) => _bump(-malusFail * multiplier);
  void onPunishmentAbandoned({double multiplier = 1.0}) =>
      _bump(-malusPunishmentAbandoned * multiplier);

  void _bump(double delta) {
    final next = _score + delta;
    _score = next < 0 ? 0 : next;
  }
}
