import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder monolithique pour `holdThroatStreak`.
///
/// Émet un unique segment `hold throat` de durée `challenge.targetThreshold`
/// (= comfort × 1.30). `thresholdReached` ne passe à `true` qu'au **2ᵉ appel
/// à `next()`** : ce 2ᵉ appel signale que le contrôleur revient chercher un
/// nouveau segment, donc que le précédent a été consommé entièrement (durée
/// tenue jusqu'au bout). Sans cela, le contrôleur passe immédiatement en
/// `atSeuil` à l'entrée en `live` et le défi se termine instantanément.
class HoldThroatStreakBuilder implements ChallengeSegmentBuilder {
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
