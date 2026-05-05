import 'dart:math';

import '../models/session.dart';
import '../models/session_step.dart';

/// Jauge d'excitation 0–100. Modèle physique :
///
/// **Décroissance naturelle** (toujours active) : `dV/dt = −V² / 800`.
/// Donne ≈ −0.5/s à V=20, −2/s à V=40, −10/s à V=90 (plus on est haut,
/// plus ça redescend vite, puis ça ralentit).
///
/// **Spike** (hold, beg-non-libre, beat de rhythm/hand) : appliqué à la
/// position visée, atténué par l'excitation courante :
///
///     Δ = base × max(0, 1 − (V / V_plafond)²)
///
/// Ainsi un coup full vaut +25 à V=10, +20 à V=35, +5 à V=70, +1 à V=75.
/// Pour rhythm/lick avec amplitude (`from`/`to` distincts), `V_plafond`
/// gagne +5 par cran d'écart — un rhythm tip→full peut donc grimper plus
/// haut qu'un hold full pur.
///
/// **Plateau** (lick, biffle) : pas de spike par coup, le mode pousse
/// doucement vers un palier (0.5 par coup en-dessous, freine la descente
/// à ×0.5 au-dessus). Le palier dépend de la zone la plus profonde :
/// lick tip→x = 50, head→x = 30 (head est la zone la plus sensible),
/// mid/throat/full descendent à 25/20/15. Biffle = 25 fixe.
///
/// **Hold/beg-non-libre** : spike au déclenchement + apport de maintien
/// (`+0.33/s` à mid, `+0.5/s` à throat, `+0.67/s` à full) qui freine
/// la décroissance sans la stopper. Beg-libre (sans `from` ou `from=tip/head`)
/// = juste décroissance naturelle.
///
/// **Free actions** (breath, freestyle, beg libre) : décroissance naturelle
/// pure.
///
/// **Résistance** : multiplicateur `1 / (1 + R)` sur tous les apports
/// positifs. Persisté par `StatsService.resistanceLevel`, +0.3 par
/// « encore » réclamé.
///
/// **Reset après fail** : `value × (1 − 0.30)`.
class ExcitationEngine {
  static const double defaultMax = 100.0;
  static const double failResetRatio = 0.30;

  /// Seuils d'annonce TTS (déclenchés une seule fois chacun par session).
  static const List<int> announcePercents = [25, 50, 75, 90];

  // ─── Tables de constantes ───────────────────────────────────────────────

  /// Spike de base par position visée (avant atténuation).
  static const Map<Position, double> _spikeByTarget = {
    Position.tip: 2.0,
    Position.head: 5.0,
    Position.mid: 8.0,
    Position.throat: 15.0,
    Position.full: 25.0,
  };

  /// Spike biffle (pas de notion de profondeur — entre tip et head).
  static const double _biffleBeatBase = 3.0;

  /// V_plafond par profondeur pour une action « pure » (sans amplitude).
  /// Pour rhythm/lick avec amplitude, on ajoute +5 par cran d'écart.
  static const Map<Position, double> _capByDeepest = {
    Position.tip: 30.0,
    Position.head: 45.0,
    Position.mid: 60.0,
    Position.throat: 72.0,
    Position.full: 78.0,
  };

  /// Bonus de V_plafond par cran d'amplitude (rhythm/lick from→to).
  static const double _amplitudeCapBonus = 7.0;

  /// Bonus de V_plafond pour les modes rythmiques (rhythm, lick, hand)
  /// proportionnel au BPM. À 60 BPM = 0, à 100 BPM = +16, à 140 BPM = +32.
  /// Permet à un head→mid intense d'atteindre 100 sans toucher full.
  static const double _bpmCapCoef = 0.4;
  static const double _bpmCapReference = 60.0;

  /// V_plafond du biffle (pas de profondeur, ~entre tip et head).
  static const double _biffleCap = 35.0;

  /// Apport de maintien par seconde pendant un hold ou un beg non-libre.
  /// Compense partiellement la décroissance naturelle.
  static const Map<Position, double> _holdMaintenance = {
    Position.tip: 0.0,
    Position.head: 0.0,
    Position.mid: 1.0 / 3.0,
    Position.throat: 1.5 / 3.0,
    Position.full: 2.0 / 3.0,
  };

  /// Plateau biffle (au-dessus : freine descente, en-dessous : pousse).
  static const double _bifflePlateau = 25.0;

  /// Plateau lick selon la zone la plus profonde du couple from/to.
  /// Volontaire : head est la zone la plus sensible en lick (l'utilisatrice
  /// y sature vite), donc plateau plus bas qu'à tip.
  static const Map<Position, double> _lickPlateauByDeepest = {
    Position.tip: 50.0,
    Position.head: 30.0,
    Position.mid: 25.0,
    Position.throat: 20.0,
    Position.full: 15.0,
  };

  /// Apport par coup de lick en-dessous du plateau (pousse vers le plateau).
  static const double _plateauPushPerBeat = 0.5;

  /// Multiplicateur appliqué à la décroissance naturelle quand le mode
  /// courant la freine activement (hold, beg-non-libre, lick/biffle au-dessus
  /// de leur plateau).
  static const double _dampenedDecayFactor = 0.5;

  /// Coefficient diviseur de la décroissance (V² / k). Calibré pour −2/s
  /// à V=40.
  static const double _decayCoef = 800.0;

  // ─── État courant ───────────────────────────────────────────────────────

  double _maxValue = defaultMax;
  double get maxValue => _maxValue;

  double _value = 0.0;
  double get value => _value;
  double get ratio => (_value / _maxValue).clamp(0.0, 1.0);
  bool get isFull => _value >= _maxValue;

  double _resistance = 0.0;

  SessionMode _currentMode = SessionMode.rhythm;
  Position? _currentFrom;
  Position? _currentTo;

  /// Mode/from du dernier step de config qui a déclenché un spike. Sert à
  /// éviter de réappliquer le spike à chaque tick quand rien n'a changé.
  SessionMode? _lastSpikeMode;
  Position? _lastSpikeFrom;

  final Set<int> _announcedPercents = {};
  void Function(int percent)? onThresholdCrossed;

  // ─── API publique ───────────────────────────────────────────────────────

  void setMax(double max) {
    _maxValue = max < 1 ? 1 : max;
  }

  void setResistance(double r) {
    _resistance = r < 0 ? 0 : r;
  }

  void reset() {
    _value = 0.0;
    _announcedPercents.clear();
    _lastSpikeMode = null;
    _lastSpikeFrom = null;
  }

  /// Initialise la valeur courante. Réservé à la simulation projetée
  /// (générateur carrière) et aux tests — pas appelé depuis le runtime.
  void seed(double v) {
    _value = v.clamp(0.0, _maxValue);
  }

  /// Mémorise le mode courant pour le tick passif. Si le couple
  /// `(mode, from)` change vers un hold ou un beg non-libre, applique
  /// le spike initial une seule fois.
  void setCurrentMode({
    required SessionMode mode,
    required Position? from,
    required Position? to,
  }) {
    _currentMode = mode;
    _currentFrom = from;
    _currentTo = to;
    _maybeApplyConfigSpike(mode, from);
  }

  /// Bonus par bip émis par BeepEngine. Chaque coup applique un spike
  /// (rhythm/hand) ou pousse vers le plateau (lick/biffle). Le BPM influe
  /// sur le V_plafond pour les modes rythmiques (rapide → cap plus haut).
  void onBeat({
    required SessionMode mode,
    required Position? to,
    required Position? from,
    int? bpm,
  }) {
    if (mode == SessionMode.rhythm || mode == SessionMode.hand) {
      final target = to ?? from;
      if (target != null) {
        final cap = _capForRhythmTarget(target, from: from, to: to, bpm: bpm);
        _applyAttenuatedSpike(_spikeByTarget[target] ?? 0.0, cap);
      }
    } else if (mode == SessionMode.biffle) {
      // Spike biffle si en-dessous du plateau (effet d'humiliation).
      // Au-dessus du plateau : juste maintien (freiné par le tick).
      if (_value < _bifflePlateau) {
        _add(_plateauPushPerBeat * _resistanceFactor());
      } else {
        _applyAttenuatedSpike(_biffleBeatBase, _biffleCap);
      }
    } else if (mode == SessionMode.lick) {
      final deepest = _deepestOf(from, to);
      final plateau = deepest == null
          ? 30.0
          : (_lickPlateauByDeepest[deepest] ?? 30.0);
      if (_value < plateau) {
        _add(_plateauPushPerBeat * _resistanceFactor());
      }
      // Au-dessus : laisse le tick freiner la descente, pas d'apport.
    }
  }

  /// Appliqué une fois par seconde par le SessionController.
  void onTickSecond() {
    final natural = _value * _value / _decayCoef;
    var positiveDelta = 0.0;
    var dampen = 1.0;

    switch (_currentMode) {
      case SessionMode.hold:
        if (_currentFrom != null) {
          positiveDelta = _holdMaintenance[_currentFrom] ?? 0.0;
          dampen = _dampenedDecayFactor;
        }
      case SessionMode.beg:
        // beg non-libre = beg avec from au moins mid : la position est
        // tenue pendant la supplique.
        final from = _currentFrom;
        if (from != null && from.index >= Position.mid.index) {
          positiveDelta = _holdMaintenance[from] ?? 0.0;
          dampen = _dampenedDecayFactor;
        }
      case SessionMode.lick:
        final deepest = _deepestOf(_currentFrom, _currentTo);
        final plateau = deepest == null
            ? 30.0
            : (_lickPlateauByDeepest[deepest] ?? 30.0);
        if (_value > plateau) {
          dampen = _dampenedDecayFactor;
        }
      case SessionMode.biffle:
        if (_value > _bifflePlateau) {
          dampen = _dampenedDecayFactor;
        }
      case SessionMode.rhythm:
      case SessionMode.hand:
      case SessionMode.breath:
      case SessionMode.freestyle:
        break;
    }

    final delta = -natural * dampen + positiveDelta * _resistanceFactor();
    if (delta != 0.0) _add(delta);
  }

  void onFail() {
    _value = max(0.0, _value * (1.0 - failResetRatio));
  }

  // ─── Helpers internes ───────────────────────────────────────────────────

  double _resistanceFactor() => 1.0 / (1.0 + _resistance);

  Position? _deepestOf(Position? a, Position? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }

  /// V_plafond pour un beat de rhythm/hand. Base = cap de la cible, +7
  /// par cran d'amplitude (from↔to), + bonus BPM pour les modes rapides.
  double _capForRhythmTarget(
    Position target, {
    Position? from,
    Position? to,
    int? bpm,
  }) {
    var cap = _capByDeepest[target] ?? 50.0;
    if (from != null && to != null) {
      final crans = (to.index - from.index).abs();
      cap += _amplitudeCapBonus * crans;
    }
    if (bpm != null && bpm > _bpmCapReference) {
      cap += (bpm - _bpmCapReference) * _bpmCapCoef;
    }
    return cap;
  }

  void _applyAttenuatedSpike(double base, double cap) {
    if (base <= 0 || cap <= 0) return;
    final ratio = _value / cap;
    final attenuation = max(0.0, 1.0 - ratio * ratio);
    final delta = base * attenuation * _resistanceFactor();
    if (delta > 0) _add(delta);
  }

  void _maybeApplyConfigSpike(SessionMode mode, Position? from) {
    final isNewConfig = mode != _lastSpikeMode || from != _lastSpikeFrom;
    if (!isNewConfig) return;
    _lastSpikeMode = mode;
    _lastSpikeFrom = from;
    if (mode == SessionMode.hold && from != null) {
      _applyAttenuatedSpike(
        _spikeByTarget[from] ?? 0.0,
        _capByDeepest[from] ?? 50.0,
      );
    } else if (mode == SessionMode.beg &&
        from != null &&
        from.index >= Position.mid.index) {
      _applyAttenuatedSpike(
        _spikeByTarget[from] ?? 0.0,
        _capByDeepest[from] ?? 50.0,
      );
    }
  }

  void _add(double delta) {
    final previous = _value;
    _value = (_value + delta).clamp(0.0, _maxValue);
    if (delta > 0) {
      for (final p in announcePercents) {
        final absolute = _maxValue * p / 100.0;
        if (previous < absolute &&
            _value >= absolute &&
            !_announcedPercents.contains(p)) {
          _announcedPercents.add(p);
          onThresholdCrossed?.call(p);
          break;
        }
      }
    }
  }
}
