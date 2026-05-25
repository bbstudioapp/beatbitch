import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder streaming pour `gorgeApneeStreak`.
///
/// Pré-requis (gating Phase A, déjà vérifié côté `ChallengeService`) :
/// `unlocks` contient `fullPulse` ET `fullHold`. Le builder est défensif —
/// si un des deux manque (cas dégénéré), il continue avec le pool complet
/// puisqu'il est appelé via `_isUnlocked` côté contrôleur uniquement
/// quand le défi a été retenu pour la séance.
///
/// Pool fixe de 6 sous-step descriptors (cf. spec § 6 gorgeApneeStreak),
/// alternant tenues et coups profonds, avec 2 plages BPM (lent/modéré)
/// pour la variété. Toutes les actions maintiennent l'apnée (≥ throat
/// sans air autorisé) — aucun step `breath` n'est jamais émis.
class GorgeApneeStreakBuilder implements ChallengeSegmentBuilder {
  /// Descripteur d'un sous-step apnée. `bpmMin`/`bpmMax` `null` pour les
  /// holds (pas de BPM applicable).
  static const List<_ApneeDescriptor> _pool = [
    _ApneeDescriptor(
      mode: SessionMode.hold,
      from: Position.throat,
      to: Position.throat,
      durMinSec: 6,
      durMaxSec: 10,
    ),
    _ApneeDescriptor(
      mode: SessionMode.hold,
      from: Position.full,
      to: Position.full,
      durMinSec: 5,
      durMaxSec: 8,
    ),
    _ApneeDescriptor(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpmMin: 80,
      bpmMax: 110,
      durMinSec: 6,
      durMaxSec: 10,
    ),
    _ApneeDescriptor(
      mode: SessionMode.rhythm,
      from: Position.mid,
      to: Position.full,
      bpmMin: 80,
      bpmMax: 110,
      durMinSec: 5,
      durMaxSec: 8,
    ),
    _ApneeDescriptor(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpmMin: 50,
      bpmMax: 70,
      durMinSec: 8,
      durMaxSec: 12,
    ),
    _ApneeDescriptor(
      mode: SessionMode.rhythm,
      from: Position.mid,
      to: Position.full,
      bpmMin: 50,
      bpmMax: 70,
      durMinSec: 5,
      durMaxSec: 8,
    ),
  ];

  Challenge? _challenge;
  Random _rng = Random();
  int? _lastDescriptorIndex;
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
    _lastDescriptorIndex = null;
    _cumulativeSeconds = 0;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    final idx = _pickIndex();
    final desc = _pool[idx];
    _lastDescriptorIndex = idx;
    final dur =
        desc.durMinSec + _rng.nextInt(desc.durMaxSec - desc.durMinSec + 1);
    _cumulativeSeconds += dur;
    if (desc.mode == SessionMode.hold) {
      return SessionStep(
        time: 0,
        mode: desc.mode,
        from: desc.from,
        to: desc.to,
        duration: dur,
      );
    }
    final bpm = desc.bpmMin! + _rng.nextInt(desc.bpmMax! - desc.bpmMin! + 1);
    return SessionStep(
      time: 0,
      mode: desc.mode,
      from: desc.from,
      to: desc.to,
      bpm: bpm,
      duration: dur,
    );
  }

  int _pickIndex() {
    while (true) {
      final idx = _rng.nextInt(_pool.length);
      if (idx != _lastDescriptorIndex) return idx;
    }
  }

  @override
  bool get thresholdReached => _cumulativeSeconds >= _targetThreshold;

  @override
  int get elapsedSegmentSeconds => _cumulativeSeconds;
}

class _ApneeDescriptor {
  final SessionMode mode;
  final Position from;
  final Position to;
  final int? bpmMin;
  final int? bpmMax;
  final int durMinSec;
  final int durMaxSec;

  const _ApneeDescriptor({
    required this.mode,
    required this.from,
    required this.to,
    this.bpmMin,
    this.bpmMax,
    required this.durMinSec,
    required this.durMaxSec,
  });
}
