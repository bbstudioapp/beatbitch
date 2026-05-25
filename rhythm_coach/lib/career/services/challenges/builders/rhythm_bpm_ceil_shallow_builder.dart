import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder pour `rhythmBpmCeilShallow`.
///
/// Tire une amplitude shallow (`tip→head`, `tip→mid`, `head→mid`) au
/// `start()`, conservée pour toute la durée du défi. Émet un unique segment
/// `rhythm <amplitude> bpm → bpmEnd` sur la durée nominale (25 s par
/// défaut). Toutes ces amplitudes sont accessibles dès le socle de la
/// carrière (pas de gating unlocks à appliquer).
class RhythmBpmCeilShallowBuilder implements ChallengeSegmentBuilder {
  static const List<(Position, Position)> _ampPool = [
    (Position.tip, Position.head),
    (Position.tip, Position.mid),
    (Position.head, Position.mid),
  ];

  Challenge? _challenge;
  int _duration = 0;
  Position? _from;
  Position? _to;
  bool _emitted = false;

  @override
  void start({
    required Challenge challenge,
    required CapabilityProfile? profile,
    required Set<UnlockKey> unlocks,
    required Random rng,
  }) {
    _challenge = challenge;
    _duration = challenge.nominalDurationSeconds;
    final pick = _ampPool[rng.nextInt(_ampPool.length)];
    _from = pick.$1;
    _to = pick.$2;
    _emitted = false;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null || _emitted) return null;
    _emitted = true;
    return SessionStep(
      time: 0,
      mode: ch.mode,
      from: _from,
      to: _to,
      bpm: ch.bpm,
      bpmEnd: ch.bpmEnd,
      duration: _duration,
    );
  }

  @override
  bool get thresholdReached => _emitted;

  @override
  int get elapsedSegmentSeconds => _emitted ? _duration : 0;
}
