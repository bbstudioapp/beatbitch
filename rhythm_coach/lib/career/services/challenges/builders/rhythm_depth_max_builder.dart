import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder monolithique pour `rhythmDepthMax`.
///
/// Émet un unique segment `rhythm head→<cran cible>` à BPM modéré sur la
/// durée nominale du défi (12 s par défaut). Le `from`/`to`/`bpm` sont
/// fournis tels quels par le `Challenge`. `thresholdReached` ne devient
/// `true` qu'au 2ᵉ appel à `next()` (= segment précédent consommé) pour
/// éviter une bascule instantanée en `atSeuil`.
class RhythmDepthMaxBuilder implements ChallengeSegmentBuilder {
  Challenge? _challenge;
  int _duration = 0;
  bool _emitted = false;
  bool _segmentConsumed = false;

  @override
  void start({
    required Challenge challenge,
    required CapabilityProfile? profile,
    required Set<UnlockKey> unlocks,
    required Random rng,
  }) {
    _challenge = challenge;
    _duration = challenge.nominalDurationSeconds;
    _emitted = false;
    _segmentConsumed = false;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    if (_emitted) {
      _segmentConsumed = true;
      return null;
    }
    _emitted = true;
    return SessionStep(
      time: 0,
      mode: ch.mode,
      from: ch.from,
      to: ch.to,
      bpm: ch.bpm,
      bpmEnd: ch.bpmEnd,
      duration: _duration,
    );
  }

  @override
  bool get thresholdReached => _segmentConsumed;

  @override
  int get elapsedSegmentSeconds => _emitted ? _duration : 0;
}
