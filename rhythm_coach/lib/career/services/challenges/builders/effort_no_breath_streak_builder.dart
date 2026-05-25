import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';
import 'endurance_pool.dart';

/// Builder streaming pour `effortNoBreathStreak`.
///
/// Comme [RhythmMotionStreakBuilder] (pool rhythm+lick à amplitudes
/// débloquées, anti-répétition, BPM ±20 autour de la baseline, durée
/// 10-15 s par segment), mais avec **~30 % de chance** d'intercaler un
/// hold (`throat` ou `full` selon `unlocks`) entre 2 segments rythmés.
///
/// Aucun step `breath` dans la séquence : c'est explicitement le défi
/// « tenir sans respirer ». Continue à émettre pendant les extensions.
class EffortNoBreathStreakBuilder implements ChallengeSegmentBuilder {
  static const int _subDurMinSec = 10;
  static const int _subDurMaxSec = 15;
  static const int _baselineBpm = 90;
  static const int _bpmJitter = 20;

  /// Probabilité d'émettre un hold entre 2 rythmés. Sous condition : un
  /// hold est dispo dans le pool d'unlocks ET le dernier segment n'était
  /// pas déjà un hold (anti-empilement).
  static const double _holdInjectionProb = 0.30;

  /// Bornes de durée d'un hold intercalé, en secondes. Plus courts que les
  /// rythmés pour ne pas saturer la jauge d'apnée d'un coup.
  static const int _holdDurMinSec = 4;
  static const int _holdDurMaxSec = 8;

  Challenge? _challenge;
  Random _rng = Random();
  List<EnduranceDescriptor> _rhythmPool = const [];
  List<EnduranceDescriptor> _holdPool = const [];
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
    _rhythmPool = buildRhythmLickPool(maxDepthIdx: maxIdx);
    _holdPool = buildHoldPool(unlocks: unlocks);
    _lastDescriptor = null;
    _cumulativeSeconds = 0;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    final lastWasHold = _lastDescriptor?.mode == SessionMode.hold;
    final injectHold = !lastWasHold &&
        _holdPool.isNotEmpty &&
        _rng.nextDouble() < _holdInjectionProb;
    final EnduranceDescriptor? descriptor;
    final int dur;
    if (injectHold) {
      descriptor = pickNonRepeating(
        pool: _holdPool,
        last: _lastDescriptor,
        rng: _rng,
      );
      dur = _holdDurMinSec + _rng.nextInt(_holdDurMaxSec - _holdDurMinSec + 1);
    } else {
      descriptor = pickNonRepeating(
        pool: _rhythmPool,
        last: _lastDescriptor,
        rng: _rng,
      );
      dur = _subDurMinSec + _rng.nextInt(_subDurMaxSec - _subDurMinSec + 1);
    }
    if (descriptor == null) return null;
    _lastDescriptor = descriptor;
    _cumulativeSeconds += dur;
    if (descriptor.mode == SessionMode.hold) {
      return SessionStep(
        time: 0,
        mode: descriptor.mode,
        from: descriptor.from,
        to: descriptor.to,
        duration: dur,
      );
    }
    final bpm = _baselineBpm - _bpmJitter + _rng.nextInt(_bpmJitter * 2 + 1);
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
