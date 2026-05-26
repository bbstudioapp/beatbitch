import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_axis.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder monolithique pour `biffleStreak`.
///
/// Émet un unique segment biffle à BPM **constant** (`comfortAtCalibration`
/// du profil biffle, fallback 60 BPM) sur la durée cible (`targetThreshold`
/// secondes). Pas de rampe BPM — c'est l'endurance qui se mesure, pas la
/// vitesse.
class BiffleStreakBuilder implements ChallengeSegmentBuilder {
  /// BPM de confort par défaut quand le profil n'a pas de donnée
  /// `biffle.bpm_max` (joueuse neuve). Choisi modéré pour rester
  /// soutenable sur la durée totale du défi.
  static const int _defaultBpm = 60;

  Challenge? _challenge;
  int _bpm = _defaultBpm;
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
    // BPM de confort biffle si le profil l'a, sinon fallback. `ch.bpm` est
    // null pour les axes durée — ne pas s'en servir.
    final bpmComfort = profile?.comfortOf(CapabilityAxis.biffleBpmMax);
    _bpm = bpmComfort?.round() ?? _defaultBpm;
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
      mode: SessionMode.biffle,
      bpm: _bpm,
      duration: ch.targetThreshold,
    );
  }

  @override
  bool get thresholdReached => _segmentConsumed;

  @override
  int get elapsedSegmentSeconds =>
      _emitted ? (_challenge?.targetThreshold ?? 0) : 0;
}
