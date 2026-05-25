import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder streaming pour `gorgeCrossingsBpmFull`.
///
/// Comme [GorgeCrossingsBpmThroatBuilder] : sous-segments rythmés courts
/// (~3 s) à BPM constant maximum, anti-répétition immédiate sur l'amplitude.
/// Pool étendu `tip/head/mid/throat → full` (selon `unlocks` : `(throat,
/// full)` exige aussi `throatPulse` pour le `from`).
///
/// `thresholdReached` reste toujours `false` — la transition est pilotée
/// par `_challengeCrossingsCount` côté contrôleur.
class GorgeCrossingsBpmFullBuilder implements ChallengeSegmentBuilder {
  static const List<(Position, Position)> _ampPoolFull = [
    (Position.tip, Position.full),
    (Position.head, Position.full),
    (Position.mid, Position.full),
    (Position.throat, Position.full),
  ];

  static const List<(Position, Position)> _ampPoolThroat = [
    (Position.tip, Position.throat),
    (Position.head, Position.throat),
    (Position.mid, Position.throat),
  ];

  static const (Position, Position) _fallbackShallow =
      (Position.head, Position.mid);

  static const int _subDurSec = 3;

  Challenge? _challenge;
  Random _rng = Random();
  List<(Position, Position)> _pool = const [];
  (Position, Position)? _lastPick;
  int _bpm = 60;
  int _cumulativeSeconds = 0;

  @override
  void start({
    required Challenge challenge,
    required CapabilityProfile? profile,
    required Set<UnlockKey> unlocks,
    required Random rng,
  }) {
    _challenge = challenge;
    _rng = rng;
    _pool = _resolvePool(unlocks);
    _lastPick = null;
    _cumulativeSeconds = 0;
    _bpm = challenge.bpmEnd ?? challenge.targetThreshold;
  }

  static List<(Position, Position)> _resolvePool(Set<UnlockKey> unlocks) {
    if (unlocks.contains(UnlockKey.fullPulse)) {
      return [
        for (final amp in _ampPoolFull)
          if (amp.$1 != Position.throat ||
              unlocks.contains(UnlockKey.throatPulse))
            amp,
      ];
    }
    if (unlocks.contains(UnlockKey.throatPulse)) {
      return _ampPoolThroat;
    }
    return const [_fallbackShallow];
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    final pick = _pickNonRepeating();
    _lastPick = pick;
    _cumulativeSeconds += _subDurSec;
    return SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: pick.$1,
      to: pick.$2,
      bpm: _bpm,
      duration: _subDurSec,
    );
  }

  (Position, Position) _pickNonRepeating() {
    if (_pool.length == 1) return _pool.first;
    while (true) {
      final pick = _pool[_rng.nextInt(_pool.length)];
      if (pick != _lastPick) return pick;
    }
  }

  @override
  bool get thresholdReached => false;

  @override
  int get elapsedSegmentSeconds => _cumulativeSeconds;
}
