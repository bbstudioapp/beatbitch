import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder monolithique pour `holdFullStreak`.
///
/// Identique à [HoldThroatStreakBuilder] dans la mécanique — émet un unique
/// segment `hold full` de durée `challenge.targetThreshold`. Le `from`/`to`
/// du segment reprend exactement les positions calibrées sur le `Challenge`
/// (en pratique `full/full`). `thresholdReached` ne devient `true` qu'au 2ᵉ
/// appel à `next()` (= segment précédent consommé) pour éviter une bascule
/// instantanée en `atSeuil`.
class HoldFullStreakBuilder implements ChallengeSegmentBuilder {
  Challenge? _challenge;
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
      duration: ch.targetThreshold,
    );
  }

  @override
  bool get thresholdReached => _segmentConsumed;

  @override
  int get elapsedSegmentSeconds =>
      _emitted ? (_challenge?.targetThreshold ?? 0) : 0;
}
