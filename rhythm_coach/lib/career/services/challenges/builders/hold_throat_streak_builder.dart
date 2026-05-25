import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder monolithique pour `holdThroatStreak`.
///
/// Émet un unique segment `hold throat` de durée `challenge.targetThreshold`
/// (= comfort × 1.30). `thresholdReached` passe à `true` dès que ce segment
/// a été émis ; les extensions sont pilotées par le contrôleur après le
/// passage en `atSeuil`.
class HoldThroatStreakBuilder implements ChallengeSegmentBuilder {
  Challenge? _challenge;
  bool _emitted = false;

  @override
  void start({
    required Challenge challenge,
    required CapabilityProfile? profile,
    required Set<UnlockKey> unlocks,
    required Random rng,
  }) {
    _challenge = challenge;
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
      from: ch.from,
      to: ch.to,
      duration: ch.targetThreshold,
    );
  }

  @override
  bool get thresholdReached => _emitted;

  @override
  int get elapsedSegmentSeconds =>
      _emitted ? (_challenge?.targetThreshold ?? 0) : 0;
}
