import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_service.dart';
import '../../../models/challenge.dart';
import '../../../models/unlock_key.dart';
import '../challenge_segment_builder.dart';

/// Builder streaming pour `gorgeEngagementStreak`.
///
/// Pré-requis : `unlocks` contient `throatPulse`. Le pool est **filtré
/// dynamiquement** par les unlocks :
/// - `hold throat` si `throatHold`
/// - `hold full` si `fullHold`
/// - `rhythm head→throat` (toujours présent — `throatPulse` est le pré-requis)
/// - `rhythm mid→full` si `fullPulse`
///
/// Différence avec `gorgeApneeStreak` : les **fenêtres d'air** sont
/// autorisées entre sous-steps (le streak compte le temps cumulé « gorge
/// en jeu », pas l'apnée). Le builder intercale donc occasionnellement un
/// `breath` court entre 2 segments d'engagement. Les breaths ne sont
/// **pas** comptés dans `elapsedSegmentSeconds` (seul le temps gorge
/// compte vers le seuil).
class GorgeEngagementStreakBuilder implements ChallengeSegmentBuilder {
  /// Probabilité d'intercaler un breath entre 2 segments d'engagement.
  /// Pas trop fréquent — la joueuse doit travailler la gorge, pas
  /// respirer la moitié du temps.
  static const double _breathInjectionProb = 0.20;
  static const int _breathDurMinSec = 3;
  static const int _breathDurMaxSec = 5;

  /// Bornes de durée des sous-steps d'engagement (hold + rythme).
  static const int _engageDurMinSec = 5;
  static const int _engageDurMaxSec = 10;

  /// Bornes BPM pour les sous-steps rythmés. Modéré : on travaille la
  /// présence de la gorge, pas un sprint.
  static const int _bpmMin = 70;
  static const int _bpmMax = 100;

  Challenge? _challenge;
  Random _rng = Random();
  List<_EngagementDescriptor> _pool = const [];
  _EngagementDescriptor? _lastDescriptor;
  bool _lastWasBreath = false;
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
    _pool = _buildPool(unlocks);
    _lastDescriptor = null;
    _lastWasBreath = false;
    _cumulativeSeconds = 0;
  }

  static List<_EngagementDescriptor> _buildPool(Set<UnlockKey> unlocks) {
    final pool = <_EngagementDescriptor>[];
    if (unlocks.contains(UnlockKey.throatHold)) {
      pool.add(const _EngagementDescriptor(
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
      ));
    }
    if (unlocks.contains(UnlockKey.fullHold)) {
      pool.add(const _EngagementDescriptor(
        mode: SessionMode.hold,
        from: Position.full,
        to: Position.full,
      ));
    }
    // Rhythm head→throat toujours présent quand throatPulse est acquis
    // (pré-requis du défi — sinon `_buildPool` est appelé en safety net
    // et le pool peut être vide → fallback head→throat ajouté ci-dessous).
    if (unlocks.contains(UnlockKey.throatPulse)) {
      pool.add(const _EngagementDescriptor(
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
        bpmKind: _BpmKind.rhythm,
      ));
    }
    if (unlocks.contains(UnlockKey.fullPulse)) {
      pool.add(const _EngagementDescriptor(
        mode: SessionMode.rhythm,
        from: Position.mid,
        to: Position.full,
        bpmKind: _BpmKind.rhythm,
      ));
    }
    // Safety net : si aucun unlock gorge → impossible de tenir le défi.
    // On ajoute un rythme shallow pour ne pas retourner null à `next()`.
    if (pool.isEmpty) {
      pool.add(const _EngagementDescriptor(
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.mid,
        bpmKind: _BpmKind.rhythm,
      ));
    }
    return pool;
  }

  @override
  SessionStep? next() {
    final ch = _challenge;
    if (ch == null) return null;
    // Fenêtre d'air : intercale un breath court entre 2 segments
    // d'engagement (pas 2 breaths d'affilée, pas un breath en premier).
    final shouldBreath = _lastDescriptor != null &&
        !_lastWasBreath &&
        _rng.nextDouble() < _breathInjectionProb;
    if (shouldBreath) {
      _lastWasBreath = true;
      final dur = _breathDurMinSec +
          _rng.nextInt(_breathDurMaxSec - _breathDurMinSec + 1);
      // Le breath ne compte PAS dans `elapsedSegmentSeconds` — seul le
      // temps gorge cumulé pousse vers le seuil.
      return SessionStep(
        time: 0,
        mode: SessionMode.breath,
        duration: dur,
      );
    }
    _lastWasBreath = false;
    final desc = _pickNonRepeating();
    _lastDescriptor = desc;
    final dur = _engageDurMinSec +
        _rng.nextInt(_engageDurMaxSec - _engageDurMinSec + 1);
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
    final bpm = _bpmMin + _rng.nextInt(_bpmMax - _bpmMin + 1);
    return SessionStep(
      time: 0,
      mode: desc.mode,
      from: desc.from,
      to: desc.to,
      bpm: bpm,
      duration: dur,
    );
  }

  _EngagementDescriptor _pickNonRepeating() {
    if (_pool.length == 1) return _pool.first;
    while (true) {
      final desc = _pool[_rng.nextInt(_pool.length)];
      if (!desc.sameKindAs(_lastDescriptor)) return desc;
    }
  }

  @override
  bool get thresholdReached => _cumulativeSeconds >= _targetThreshold;

  @override
  int get elapsedSegmentSeconds => _cumulativeSeconds;
}

enum _BpmKind { none, rhythm }

class _EngagementDescriptor {
  final SessionMode mode;
  final Position from;
  final Position to;
  final _BpmKind bpmKind;

  const _EngagementDescriptor({
    required this.mode,
    required this.from,
    required this.to,
    this.bpmKind = _BpmKind.none,
  });

  bool sameKindAs(_EngagementDescriptor? other) {
    if (other == null) return false;
    return mode == other.mode && from == other.from && to == other.to;
  }
}
