import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder streaming pour `gorgeCrossingsBpmThroat`.
///
/// Émet des sous-segments rythmés courts (~3 s) **à BPM constant maximum**
/// (= `ch.bpmEnd` ou `ch.targetThreshold`), en variant l'amplitude entre
/// `tip/head/mid → throat` (anti-répétition immédiate). Le défi mesure un
/// **nombre de franchissements** : le seuil est donc piloté par le
/// contrôleur via `_challengeCrossingsCount`, pas par le builder. Ce
/// builder retourne donc toujours `thresholdReached = false` — la
/// transition `live → atSeuil` est déclenchée côté `SessionController` dès
/// que `nbFranchissements >= ch.targetCrossings`.
///
/// Sans `throatPulse` (cas dégénéré — le gating amont l'exige), le pool
/// retombe sur `head→mid` (safety net).
class GorgeCrossingsBpmThroatBuilder implements ChallengeSegmentBuilder {
  static const List<(Position, Position)> _ampPool = [
    (Position.tip, Position.throat),
    (Position.head, Position.throat),
    (Position.mid, Position.throat),
  ];

  static const (Position, Position) _fallback = (Position.head, Position.mid);

  /// Durée d'un sous-segment, en secondes. La spec parle d'« ~3 s
  /// chacun » pour une séquence totale de ~8 s (avant extensions).
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
    _pool =
        unlocks.contains(UnlockKey.throatPulse) ? _ampPool : const [_fallback];
    _lastPick = null;
    _cumulativeSeconds = 0;
    // BPM constant = haut de la rampe (= comfort × 1.30). Le contrôleur
    // n'a pas besoin d'un bpmEnd différent puisque la rampe est plate.
    _bpm = challenge.bpmEnd ?? challenge.targetThreshold;
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

  /// Toujours `false` : la transition `live → atSeuil` est pilotée par
  /// `_challengeCrossingsCount` côté contrôleur, pas par la durée cumulée
  /// du builder.
  @override
  bool get thresholdReached => false;

  @override
  int get elapsedSegmentSeconds => _cumulativeSeconds;
}
