import 'dart:math';

import '../models/session.dart';
import '../models/session_step.dart';

/// Mode de déglutition pour la session courante. Sticky entre steps.
enum SwallowMode {
  /// Déglutition autorisée. Auto-déglutition au-dessus de [SalivaEngine.autoSwallowThreshold].
  allowed,

  /// Déglutition interdite. Auto-déglutition désactivée. Si la joueuse
  /// avale, c'est une transgression → bouton FAIL avec phrase dédiée.
  /// Le crachat reste autorisé.
  forbidden,
}

/// Jauge de salive in-session, 0..[maxValue].
///
/// **Production** (par seconde selon mode/position) :
/// - lick : forte (multipliée par 1.5 si `sloppyDroolBasic`)
/// - rhythm : moyenne, modulée par profondeur
/// - biffle : faible (×3 si `sloppyBiffleSlow`)
/// - hand : aucune, légère évaporation (-0.2/s)
/// - hold : selon profondeur (tip 0.5 → full 1.0)
/// - beg libre : -0.5/s (parler assèche)
/// - beg non-libre : comme hold à -20%
/// - breath : -0.8/s (bouche ouverte)
/// - freestyle : +0.2/s
///
/// **Élimination** :
/// - Auto-déglutition à [autoSwallowThreshold] = 75 si [SwallowMode.allowed] :
///   `value × autoSwallowRatio` à intervalle aléatoire (8-15s).
/// - Crachat (manuel via [forceSpit]) : reset à 0.
/// - Déglutition coachée (manuel via [forceSwallow]) : reset à 0.
/// - Fail : reset à 0 (la salope a craqué, tout part).
///
/// Pas de persistance entre sessions. Initialisée à [defaultInitial] = 12
/// (un peu de salive de base, naturel).
class SalivaEngine {
  /// Valeur initiale au start de session (bouche pas désertique).
  static const double defaultInitial = 12.0;

  /// Plafond par défaut (sans `sloppyDroolBasic`).
  static const double defaultMax = 60.0;

  /// Plafond avec `sloppyDroolBasic` acquis.
  static const double sloppyBaseMax = 100.0;

  /// Bonus de plafond avec `sloppyDroolDeep` acquis.
  static const double sloppyDeepBonus = 20.0;

  /// Seuil au-dessus duquel l'auto-déglutition peut se déclencher.
  static const double autoSwallowThreshold = 75.0;

  /// Ratio appliqué lors d'une auto-déglutition (val ← val × ratio).
  static const double autoSwallowRatio = 0.5;

  /// Borne inf/sup en secondes de l'intervalle aléatoire entre deux
  /// auto-déglutitions possibles (quand au-dessus du seuil).
  static const int autoSwallowMinSeconds = 8;
  static const int autoSwallowMaxSeconds = 15;

  /// Seuil au-dessus duquel un débordement est compté (utilisé par le
  /// SessionController pour le bonus humiliation, capé 3/session).
  static const double overflowThreshold = 90.0;

  /// Production par seconde selon le mode courant (avant modulation
  /// position/BPM/compétences).
  static const Map<SessionMode, double> _baseProductionByMode = {
    SessionMode.lick: 0.8,
    SessionMode.rhythm: 0.4,
    SessionMode.biffle: 0.3,
    SessionMode.hand: -0.2,
    SessionMode.breath: -0.8,
    SessionMode.freestyle: 0.2,
    // hold et beg : traités à part (dépend de la position).
  };

  /// Production hold par profondeur (par seconde).
  static const Map<Position, double> _holdProductionByPos = {
    Position.tip: 0.5,
    Position.head: 0.5,
    Position.mid: 0.6,
    Position.throat: 0.8,
    Position.full: 1.0,
  };

  /// Multiplicateur de production rhythm par profondeur (zone la plus
  /// profonde du couple from/to). Throat/full stimulent davantage.
  static const Map<Position, double> _rhythmDepthMultiplier = {
    Position.tip: 1.0,
    Position.head: 1.0,
    Position.mid: 1.1,
    Position.throat: 1.3,
    Position.full: 1.3,
  };

  // ─── État courant ───────────────────────────────────────────────────────

  double _maxValue = defaultMax;
  double get maxValue => _maxValue;

  double _value = defaultInitial;
  double get value => _value;
  double get ratio => (_value / _maxValue).clamp(0.0, 1.0);

  /// Compteur d'overflows comptabilisés cette session (cap à 3 côté
  /// SessionController qui consomme [popOverflowEvent]).
  int _overflowEventsPending = 0;

  /// Dernier instant où une auto-déglutition s'est déclenchée. Sert au
  /// throttling aléatoire (intervalle [autoSwallowMinSeconds, autoSwallowMaxSeconds]).
  int _lastAutoSwallowAtSecond = -1;

  /// Délai aléatoire courant avant la prochaine auto-déglutition possible.
  /// Re-tiré à chaque auto-swallow.
  int _nextAutoSwallowDelaySeconds = 8;

  /// Production multiplier `lick`. Default 1.0, monté à 1.5 si
  /// `sloppyDroolBasic` acquis (set via [setLickProductionMultiplier]).
  double _lickProductionMultiplier = 1.0;

  /// Production multiplier `biffle`. Default 1.0, monté à 3.0 si
  /// `sloppyBiffleSlow` acquis.
  double _biffleProductionMultiplier = 1.0;

  /// Production multiplier `hold` profondeur (throat/full). Default 1.0,
  /// monté à 1.5 si `sloppyDroolDeep` acquis.
  double _holdDepthProductionMultiplier = 1.0;

  final Random _rng;

  SalivaEngine({Random? rng}) : _rng = rng ?? Random();

  // ─── Configuration ─────────────────────────────────────────────────────

  /// Configure le plafond. Préserve la valeur courante si elle est dans
  /// la nouvelle borne, sinon clamp.
  void setMax(double max) {
    _maxValue = max < 1 ? 1 : max;
    if (_value > _maxValue) _value = _maxValue;
  }

  void setLickProductionMultiplier(double m) {
    _lickProductionMultiplier = m < 0 ? 0 : m;
  }

  void setBiffleProductionMultiplier(double m) {
    _biffleProductionMultiplier = m < 0 ? 0 : m;
  }

  void setHoldDepthProductionMultiplier(double m) {
    _holdDepthProductionMultiplier = m < 0 ? 0 : m;
  }

  /// Reset complet à l'état de start de session.
  void reset() {
    _value = defaultInitial;
    _overflowEventsPending = 0;
    _lastAutoSwallowAtSecond = -1;
    _nextAutoSwallowDelaySeconds = autoSwallowMinSeconds;
    _lickProductionMultiplier = 1.0;
    _biffleProductionMultiplier = 1.0;
    _holdDepthProductionMultiplier = 1.0;
  }

  /// Initialise la valeur courante. Réservé à la simulation projetée
  /// (générateur carrière) et aux tests.
  void seed(double v) {
    _value = v.clamp(0.0, _maxValue);
  }

  // ─── API publique ──────────────────────────────────────────────────────

  /// Tick par seconde. Applique la production/perte du mode courant et,
  /// si autorisée, l'éventuelle auto-déglutition.
  ///
  /// [elapsedSecond] : compteur de session pour throttler les auto-déglutitions.
  void onTickSecond({
    required SessionMode mode,
    required Position? from,
    required Position? to,
    required SwallowMode swallowMode,
    required int elapsedSecond,
  }) {
    final production = _productionFor(mode: mode, from: from, to: to);
    if (production != 0.0) _add(production);

    // Auto-déglutition : seulement en mode allowed, au-dessus du seuil,
    // après le délai aléatoire courant.
    if (swallowMode == SwallowMode.allowed && _value >= autoSwallowThreshold) {
      final since = elapsedSecond - _lastAutoSwallowAtSecond;
      if (_lastAutoSwallowAtSecond < 0 ||
          since >= _nextAutoSwallowDelaySeconds) {
        _value = _value * autoSwallowRatio;
        _lastAutoSwallowAtSecond = elapsedSecond;
        _nextAutoSwallowDelaySeconds = autoSwallowMinSeconds +
            _rng.nextInt(
                autoSwallowMaxSeconds - autoSwallowMinSeconds + 1);
      }
    }
  }

  /// Déglutition contrôlée (ordre coach « avale » ou ack joueuse).
  /// Reset complet à 0.
  void forceSwallow() {
    _value = 0.0;
  }

  /// Crachat (ordre coach « crache » ou spontané sous saturation).
  /// Reset complet à 0. Le SessionController peut consommer cet appel
  /// pour bumper humil +1.
  void forceSpit() {
    _value = 0.0;
  }

  /// Reset post-fail. Tout part : la salope a craqué.
  void onFail() {
    _value = 0.0;
    _overflowEventsPending = 0;
    _lastAutoSwallowAtSecond = -1;
  }

  /// Consomme et retourne le nombre d'overflows accumulés depuis le
  /// dernier appel. Permet au SessionController de bumper humiliation.
  int popOverflowEvents() {
    final c = _overflowEventsPending;
    _overflowEventsPending = 0;
    return c;
  }

  // ─── Helpers internes ──────────────────────────────────────────────────

  double _productionFor({
    required SessionMode mode,
    required Position? from,
    required Position? to,
  }) {
    switch (mode) {
      case SessionMode.lick:
        return (_baseProductionByMode[mode] ?? 0.0) *
            _lickProductionMultiplier;
      case SessionMode.rhythm:
        final deepest = _deepestOf(from, to);
        final mult =
            deepest == null ? 1.0 : (_rhythmDepthMultiplier[deepest] ?? 1.0);
        return (_baseProductionByMode[mode] ?? 0.0) * mult;
      case SessionMode.biffle:
        return (_baseProductionByMode[mode] ?? 0.0) *
            _biffleProductionMultiplier;
      case SessionMode.hand:
      case SessionMode.breath:
      case SessionMode.freestyle:
        return _baseProductionByMode[mode] ?? 0.0;
      case SessionMode.hold:
        // Convention uniforme hold/beg : la position tenue est dans `to`
        // (cf. HumiliationScale). On retombe sur `from` si `to` absent.
        final pos = to ?? from;
        if (pos == null) return 0.0;
        var prod = _holdProductionByPos[pos] ?? 0.0;
        if (pos == Position.throat || pos == Position.full) {
          prod *= _holdDepthProductionMultiplier;
        }
        return prod;
      case SessionMode.beg:
        // beg libre = bouche libre, parler assèche.
        // beg non-libre = position tenue, comme hold mais -20% (la voix sèche un peu).
        final pos = to ?? from;
        if (pos == null) return -0.5;
        return (_holdProductionByPos[pos] ?? 0.0) * 0.8;
    }
  }

  Position? _deepestOf(Position? a, Position? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }

  void _add(double delta) {
    final previous = _value;
    final next = (_value + delta).clamp(0.0, _maxValue);
    if (previous < overflowThreshold && next >= overflowThreshold) {
      _overflowEventsPending++;
    }
    _value = next;
  }
}
