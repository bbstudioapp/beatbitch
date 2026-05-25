import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder pour `rhythmBpmCeilFull`.
///
/// Tire une amplitude `*→full` au `start()` parmi les options dont la
/// profondeur cible est débloquée. La position `full` exige
/// `UnlockKey.fullPulse` ; le `from = throat` exige en plus
/// `UnlockKey.throatPulse` (jamais déclenché en pratique : `fullPulse`
/// implique `throatPulse` via la chaîne milestones, mais on filtre
/// défensivement).
///
/// Sans `fullPulse`, on retombe sur une amplitude `*→throat` (si
/// `throatPulse` acquis), sinon `head→mid` — safety net pour le cas
/// dégénéré où le défi serait proposé sans le bon socle.
class RhythmBpmCeilFullBuilder implements ChallengeSegmentBuilder {
  // Pool plein (toutes les amplitudes `*→full`). `(throat, full)` exige en
  // plus `throatPulse` côté `from` — filtré dynamiquement à `start()`.
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
    final (from, to) = _pickAmplitude(unlocks, rng);
    _from = from;
    _to = to;
    _emitted = false;
  }

  static (Position, Position) _pickAmplitude(
    Set<UnlockKey> unlocks,
    Random rng,
  ) {
    if (unlocks.contains(UnlockKey.fullPulse)) {
      final candidates = [
        for (final amp in _ampPoolFull)
          if (amp.$1 != Position.throat ||
              unlocks.contains(UnlockKey.throatPulse))
            amp,
      ];
      return candidates[rng.nextInt(candidates.length)];
    }
    if (unlocks.contains(UnlockKey.throatPulse)) {
      return _ampPoolThroat[rng.nextInt(_ampPoolThroat.length)];
    }
    return _fallbackShallow;
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
