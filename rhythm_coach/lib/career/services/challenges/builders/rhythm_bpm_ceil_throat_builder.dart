import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder pour `rhythmBpmCeilThroat`.
///
/// Tire une amplitude `*→throat` au `start()` parmi les options dont la
/// profondeur cible est débloquée. La position `throat` exige
/// `UnlockKey.throatPulse` ; sans cet unlock, le builder retombe sur
/// `head→mid` (safety net — en pratique le défi n'aurait jamais dû être
/// proposé sans cet unlock, cf. gating amont dans `ChallengeService`).
class RhythmBpmCeilThroatBuilder implements ChallengeSegmentBuilder {
  static const List<(Position, Position)> _ampPool = [
    (Position.tip, Position.throat),
    (Position.head, Position.throat),
    (Position.mid, Position.throat),
  ];

  static const (Position, Position) _fallback = (Position.head, Position.mid);

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
    final (from, to) = unlocks.contains(UnlockKey.throatPulse)
        ? _ampPool[rng.nextInt(_ampPool.length)]
        : _fallback;
    _from = from;
    _to = to;
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
