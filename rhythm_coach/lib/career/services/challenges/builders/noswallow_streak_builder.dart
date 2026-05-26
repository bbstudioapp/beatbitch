import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder streaming pour `noswallowStreak`.
///
/// Mode principal : `beg` libre (bouche ouverte, langue dehors — pas de
/// `from`/`to`, le BeepEngine joue le mode beg sans position ancrée).
/// Holds intercalés à ~25 % de proba : `hold throat` ou `hold tip` 4-6 s
/// (la salope alterne entre supplique « langue dehors » et tenues plus
/// engageantes pour casser la monotonie).
///
/// Le critère « salive non-avalée » n'est pas porté par le builder mais
/// par le contrôleur via `_swallowMode = SwallowMode.forbidden` activé
/// automatiquement à l'entrée en phase live pour cet axe.
///
/// Pas de texte injecté sur les sous-steps : le banner UI affiche en
/// permanence « Bouche ouverte, langue dehors — N s sans avaler » via
/// `challengeObjectiveText()`, et la phrase coach `attempt` est dite à
/// l'entrée en phase breath. Inutile que la coach répète la consigne
/// toutes les 10 s — ça brouillerait le mantra visuel.
class NoswallowStreakBuilder implements ChallengeSegmentBuilder {
  static const int _begDurMin = 8;
  static const int _begDurMax = 15;
  static const int _holdDurMin = 4;
  static const int _holdDurMax = 6;

  /// Probabilité d'intercaler un hold entre 2 begs. Anti-empilement : si
  /// le dernier était un hold, on émet forcément un beg.
  static const double _holdInjectionProb = 0.25;

  /// Positions disponibles pour les holds intercalés. `throat` exige
  /// l'unlock `throatPulse` — sans ça, on retombe sur `tip` uniquement.
  static const List<Position> _holdPoolWithThroat = [
    Position.throat,
    Position.tip,
  ];

  static const List<Position> _holdPoolTipOnly = [Position.tip];

  Challenge? _challenge;
  Random _rng = Random();
  List<Position> _holdPool = const [];
  bool _lastWasHold = false;
  int _cumulativeSeconds = 0;
  int _targetThreshold = 0;

  @override
  void start({
    required Challenge challenge,
    required CapabilityProfile? profile,
    required Set<UnlockKey> unlocks,
    required Random rng,
  }) {
    _challenge = challenge;
    _rng = rng;
    _targetThreshold = challenge.targetThreshold;
    _holdPool = unlocks.contains(UnlockKey.throatPulse)
        ? _holdPoolWithThroat
        : _holdPoolTipOnly;
    _lastWasHold = false;
    _cumulativeSeconds = 0;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    final shouldHold = !_lastWasHold && _rng.nextDouble() < _holdInjectionProb;
    if (shouldHold) {
      _lastWasHold = true;
      final pos = _holdPool[_rng.nextInt(_holdPool.length)];
      final dur = _holdDurMin + _rng.nextInt(_holdDurMax - _holdDurMin + 1);
      _cumulativeSeconds += dur;
      return SessionStep(
        time: 0,
        mode: SessionMode.hold,
        from: pos,
        to: pos,
        duration: dur,
      );
    }
    _lastWasHold = false;
    final dur = _begDurMin + _rng.nextInt(_begDurMax - _begDurMin + 1);
    _cumulativeSeconds += dur;
    return SessionStep(
      time: 0,
      mode: SessionMode.beg,
      duration: dur,
    );
  }

  @override
  bool get thresholdReached => _cumulativeSeconds >= _targetThreshold;

  @override
  int get elapsedSegmentSeconds => _cumulativeSeconds;
}
