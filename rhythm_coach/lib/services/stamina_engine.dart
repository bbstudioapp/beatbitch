import 'package:flutter/foundation.dart';

import '../models/session.dart';
import '../models/session_step.dart';
import 'beep_engine.dart';

/// Modèle live de l'endurance : consomme les beats émis par le `BeepEngine`
/// et applique des deltas par tick (200 ms) pour les modes de maintien
/// (hold/beg avec position) et la regen passive.
///
/// Sert à l'UI : la `StaminaBar` affiche la valeur live (vraie réaction
/// à ce qui est joué) plutôt qu'une projection figée à la génération.
/// La projection (`profile[seconde]`) reste fournie par le générateur
/// pour servir de ghost « cible théorique » en filigrane.
class StaminaEngine extends ChangeNotifier {
  static const double _max = 100.0;

  /// Coût par beat selon la position effective du beat (rhythm/lick/hand
  /// /biffle). Le hand consomme moins que le rhythm (la bouche se repose).
  /// Calibré pour que la barre live oscille visiblement pendant la séance
  /// (avant : valeurs trop faibles + regen passive → barre figée à ~100).
  static const Map<Position, double> _beatCostByPosition = {
    Position.tip: 0.02,
    Position.head: 0.20,
    Position.mid: 0.45,
    Position.throat: 0.85,
    Position.full: 1.30,
  };

  /// Multiplicateur appliqué au coût par beat selon le mode (hand plus
  /// léger, biffle un poil plus dur que rhythm).
  static const Map<SessionMode, double> _beatModeMul = {
    SessionMode.rhythm: 1.0,
    SessionMode.lick: 0.4,
    SessionMode.hand: 0.5,
    SessionMode.biffle: 1.1,
  };

  /// Coût par seconde quand on TIENT une position (hold ou beg avec from).
  static const Map<Position, double> _holdCostPerSec = {
    Position.tip: 0.0,
    Position.head: 0.15,
    Position.mid: 0.45,
    Position.throat: 0.85,
    Position.full: 1.30,
  };

  /// Regen par seconde par mode de récup. `breath` est le levier le plus
  /// efficace, `freestyle` modéré, autres = 0. Lick à BPM ≤ 60 se comporte
  /// aussi en regen (cf. `onTickSecond`).
  static const Map<SessionMode, double> _regenPerSec = {
    SessionMode.breath: 1.0,
    SessionMode.freestyle: 0.3,
  };

  /// Regen lente quand un lick lent (≤60 BPM) joue : la bouche fatiguée
  /// récupère mais moins vite qu'un breath.
  static const double _slowLickRegenPerSec = 0.6;

  /// BPM en-dessous duquel le lick passe en mode regen.
  static const int _slowLickBpmCap = 60;

  double _value = _max;
  double get value => _value;
  double get max => _max;

  /// État courant du mode (mémorisé via [setCurrentMode] pour pouvoir
  /// appliquer le coût/regen par seconde dans [onTickSecond]).
  SessionMode _mode = SessionMode.rhythm;
  Position? _currentFrom;
  int _currentBpm = 0;

  void reset() {
    _value = _max;
    _mode = SessionMode.rhythm;
    _currentFrom = null;
    _currentBpm = 0;
    notifyListeners();
  }

  void setCurrentMode(SessionMode mode, {Position? from, int bpm = 0}) {
    _mode = mode;
    _currentFrom = from;
    _currentBpm = bpm;
  }

  /// À appeler à chaque beat émis par le BeepEngine (via beatStream).
  void onBeat(BeatEvent event) {
    final modeMul = _beatModeMul[event.mode];
    if (modeMul == null) return; // hold/breath/beg/freestyle : pas de beat
    final pos = event.position;
    final cost = (_beatCostByPosition[pos] ?? 0.0) * modeMul;
    if (cost <= 0) return;
    _add(-cost);
  }

  /// À appeler une fois par seconde par le SessionController (via tick).
  void onTickSecond() {
    var delta = 0.0;
    final regen = _regenPerSec[_mode];
    if (regen != null) {
      delta = regen;
    } else if (_mode == SessionMode.lick && _currentBpm <= _slowLickBpmCap) {
      // Lick lent (≤60 BPM) = bouche reposée + langue qui glisse :
      // regen lente, alignée sur la projection du générateur.
      delta = _slowLickRegenPerSec;
    } else if (_mode == SessionMode.hold || _mode == SessionMode.beg) {
      final pos = _currentFrom;
      if (pos != null) {
        final cost = _holdCostPerSec[pos] ?? 0.0;
        delta = -cost;
      }
    }
    if (delta == 0) return;
    _add(delta);
  }

  /// Reset partiel après un fail (perte d'un quart de l'endurance courante).
  void onFail() {
    _value = (_value * 0.75).clamp(0.0, _max);
    notifyListeners();
  }

  void _add(double delta) {
    final next = (_value + delta).clamp(0.0, _max);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}
