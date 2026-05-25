import 'dart:math';

import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';
import 'endurance_pool.dart';

/// Builder streaming pour `rhythmMotionStreak`.
///
/// À chaque appel `next()`, tire un descriptor du pool (rhythm/lick à
/// amplitudes débloquées) différent du dernier, choisit une durée 10-15 s
/// et un BPM 70-110, et émet le segment. Continue tant que la joueuse
/// tient (extensions incluses). `thresholdReached` bascule dès que la
/// durée cumulée atteint `targetThreshold`.
///
/// Pas de step `breath` dans la séquence — le défi est explicitement
/// non-stop.
class RhythmMotionStreakBuilder implements ChallengeSegmentBuilder {
  /// Bornes de durée d'un sous-segment, en secondes. Spec § 6 :
  /// « Sous-segments ~10-15 s chacun ».
  static const int _subDurMinSec = 10;
  static const int _subDurMaxSec = 15;

  /// Bornes de BPM par sous-segment. Spec § 6 : « Varier le BPM entre
  /// sous-segments (±15-25 BPM autour du baseline `comfort`) ».
  /// Baseline = 90 BPM (compromis endurance), variation ±20.
  static const int _baselineBpm = 90;
  static const int _bpmJitter = 20;

  Challenge? _challenge;
  Random _rng = Random();
  List<EnduranceDescriptor> _pool = const [];
  EnduranceDescriptor? _lastDescriptor;
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
    final maxIdx = resolveMaxDepthIdx(unlocks: unlocks, profile: profile);
    _pool = buildRhythmLickPool(maxDepthIdx: maxIdx);
    _lastDescriptor = null;
    _cumulativeSeconds = 0;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    final descriptor = pickNonRepeating(
      pool: _pool,
      last: _lastDescriptor,
      rng: _rng,
    );
    if (descriptor == null) return null;
    _lastDescriptor = descriptor;
    final dur = _subDurMinSec + _rng.nextInt(_subDurMaxSec - _subDurMinSec + 1);
    final bpm = _baselineBpm - _bpmJitter + _rng.nextInt(_bpmJitter * 2 + 1);
    _cumulativeSeconds += dur;
    return SessionStep(
      time: 0,
      mode: descriptor.mode,
      from: descriptor.from,
      to: descriptor.to,
      bpm: bpm,
      duration: dur,
    );
  }

  @override
  bool get thresholdReached => _cumulativeSeconds >= _targetThreshold;

  @override
  int get elapsedSegmentSeconds => _cumulativeSeconds;
}
