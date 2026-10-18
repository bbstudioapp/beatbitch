import 'package:flutter/foundation.dart';

import '../models/session.dart';
import '../models/session_step.dart';
import 'capability_axis.dart';
import 'capability_service.dart';
import 'saliva_engine.dart';

class CapabilityTracker {
  static const int sustainedRecordSeconds = 3;

  _ConfigState? _config;
  int _configSeconds = 0;
  bool _configRecordsLogged = false;

  double _apnea = 0;
  double _engagement = 0;
  double _motion = 0;
  double _holdThroat = 0;
  double _holdFull = 0;
  double _noswallow = 0;
  bool _noswallowHadOverflow = false;
  double _biffleStreak = 0;
  double _lickStreak = 0;
  double _handStreak = 0;
  double _effortNoBreath = 0;

  double _crossingsAccum = 0;

  final Map<CapabilityAxis, double> _reached = {};
  final Map<CapabilityAxis, double> _ceilings = {};
  final List<Map<CapabilityAxis, double>> _failCeilings = [];
  bool _salivaOverflowed = false;

  Map<CapabilityAxis, double> get sessionCeilings =>
      Map.unmodifiable(_ceilings);

  void onSessionStart() {
    _config = null;
    _configSeconds = 0;
    _configRecordsLogged = false;
    _apnea = _engagement = _motion = 0;
    _holdThroat = _holdFull = 0;
    _noswallow = 0;
    _noswallowHadOverflow = false;
    _biffleStreak = _lickStreak = _handStreak = _effortNoBreath = 0;
    _crossingsAccum = 0;
    _reached.clear();
    _ceilings.clear();
    _failCeilings.clear();
    _salivaOverflowed = false;
  }

  void onStepApplied({
    required SessionMode mode,
    Position? from,
    Position? to,
    int? bpm,
    int? duration,
  }) {
    final next = _ConfigState(
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
    );
    final prev = _config;

    if (!next.airless) _flushStreak(CapabilityAxis.gorgeApneeStreak, _apnea);
    if (!next.engagesThroat) {
      _flushStreak(CapabilityAxis.gorgeEngagementStreak, _engagement);
    }
    if (!next.isMotion) {
      _flushStreak(CapabilityAxis.rhythmMotionStreak, _motion);
    }
    if (next.heldPos != Position.throat) {
      _flushStreak(CapabilityAxis.holdThroatStreak, _holdThroat);
    }
    if (next.heldPos != Position.full) {
      _flushStreak(CapabilityAxis.holdFullStreak, _holdFull);
    }
    if (!next.isBiffle) {
      _flushStreak(CapabilityAxis.biffleStreak, _biffleStreak);
    }
    if (!next.isLick) _flushStreak(CapabilityAxis.lickStreak, _lickStreak);
    if (!next.isHand) _flushStreak(CapabilityAxis.handStreak, _handStreak);

    if (next.isBreath) {
      _flushStreak(CapabilityAxis.effortNoBreathStreak, _effortNoBreath);
      _effortNoBreath = 0;
    }
    if ((prev?.isBreath ?? false) && !next.isBreath && _configSeconds > 0) {
      _recordReached(
        CapabilityAxis.breathMinDose,
        _configSeconds.toDouble(),
        minimize: true,
      );
    }

    if (!next.airless) _apnea = 0;
    if (!next.engagesThroat) _engagement = 0;
    if (!next.isMotion) _motion = 0;
    if (next.heldPos != Position.throat) _holdThroat = 0;
    if (next.heldPos != Position.full) _holdFull = 0;
    if (!next.isBiffle) _biffleStreak = 0;
    if (!next.isLick) _lickStreak = 0;
    if (!next.isHand) _handStreak = 0;

    _config = next;
    _configSeconds = 0;
    _configRecordsLogged = false;
  }

  void onTickSecond({required SwallowMode swallowMode}) {
    if (swallowMode == SwallowMode.forbidden) {
      _noswallow += 1;
    } else if (_noswallow > 0) {
      if (!_noswallowHadOverflow) {
        _flushStreak(CapabilityAxis.noswallowStreak, _noswallow);
      }
      _noswallow = 0;
      _noswallowHadOverflow = false;
    }

    final c = _config;
    if (c == null) return;
    _configSeconds += 1;

    if (c.airless) _apnea += 1;
    if (c.engagesThroat) _engagement += 1;
    if (c.isMotion) _motion += 1;
    if (c.heldPos == Position.throat) _holdThroat += 1;
    if (c.heldPos == Position.full) _holdFull += 1;
    if (c.isBiffle) _biffleStreak += 1;
    if (c.isLick) _lickStreak += 1;
    if (c.isHand) _handStreak += 1;
    if (!c.isBreath) _effortNoBreath += 1;
    if (c.isCrossingPattern) _crossingsAccum += (c.bpm ?? 60) / 60.0;

    if (!_configRecordsLogged && _configSeconds >= sustainedRecordSeconds) {
      _configRecordsLogged = true;
      _logSustainedConfigRecords(c);
    }
  }

  void onSalivaOverflow() {
    if (_noswallow > 0) {
      _noswallowHadOverflow = true;
      _salivaOverflowed = true;
      _ceilFrom(CapabilityAxis.noswallowStreak, _noswallow);
    }
  }

  void onFail() {
    final frozen = <CapabilityAxis, double>{};
    void freeze(CapabilityAxis axis, double value) {
      if (value > 0) frozen[axis] = value;
    }

    freeze(CapabilityAxis.gorgeApneeStreak, _apnea);
    freeze(CapabilityAxis.gorgeEngagementStreak, _engagement);
    freeze(CapabilityAxis.rhythmMotionStreak, _motion);
    freeze(CapabilityAxis.holdThroatStreak, _holdThroat);
    freeze(CapabilityAxis.holdFullStreak, _holdFull);
    freeze(CapabilityAxis.biffleStreak, _biffleStreak);
    freeze(CapabilityAxis.lickStreak, _lickStreak);
    freeze(CapabilityAxis.handStreak, _handStreak);
    freeze(CapabilityAxis.effortNoBreathStreak, _effortNoBreath);
    freeze(CapabilityAxis.noswallowStreak, _noswallow);

    final c = _config;
    if (c != null) {
      if (c.mode == SessionMode.rhythm && c.to != null) {
        freeze(CapabilityAxis.rhythmDepthMax, c.to!.index.toDouble());
        final bpm = (c.bpm ?? 60).toDouble();
        freeze(_rhythmBand(c.to!).$1, bpm);
        if (c.isCrossingPattern) {
          freeze(
            c.to == Position.throat
                ? CapabilityAxis.gorgeCrossingsBpmThroat
                : CapabilityAxis.gorgeCrossingsBpmFull,
            bpm,
          );
        }
      } else if (c.isBiffle) {
        freeze(CapabilityAxis.biffleBpmMax, (c.bpm ?? 80).toDouble());
      }
    }
    frozen.forEach(_ceilFrom);
    _failCeilings.add(Map.unmodifiable(frozen));

    _apnea = _engagement = _motion = 0;
    _holdThroat = _holdFull = 0;
    _noswallow = 0;
    _noswallowHadOverflow = false;
    _biffleStreak = _lickStreak = _handStreak = _effortNoBreath = 0;
    _config = null;
    _configSeconds = 0;
    _configRecordsLogged = false;
  }

  SessionCapabilityReport finalizeReport() {
    _flushStreak(CapabilityAxis.gorgeApneeStreak, _apnea);
    _flushStreak(CapabilityAxis.gorgeEngagementStreak, _engagement);
    _flushStreak(CapabilityAxis.rhythmMotionStreak, _motion);
    _flushStreak(CapabilityAxis.holdThroatStreak, _holdThroat);
    _flushStreak(CapabilityAxis.holdFullStreak, _holdFull);
    _flushStreak(CapabilityAxis.biffleStreak, _biffleStreak);
    _flushStreak(CapabilityAxis.lickStreak, _lickStreak);
    _flushStreak(CapabilityAxis.handStreak, _handStreak);
    _flushStreak(CapabilityAxis.effortNoBreathStreak, _effortNoBreath);
    if (_noswallow > 0 && !_noswallowHadOverflow) {
      _flushStreak(CapabilityAxis.noswallowStreak, _noswallow);
    }
    final crossings = _crossingsAccum.floor();
    if (crossings > 0) {
      _reached[CapabilityAxis.gorgeCrossingsLifetime] = crossings.toDouble();
    }
    final report = SessionCapabilityReport(
      reached: Map.unmodifiable(_reached),
      sessionCeilings: Map.unmodifiable(_ceilings),
      failCeilings: List.unmodifiable(_failCeilings),
      salivaOverflowed: _salivaOverflowed,
    );
    if (kDebugMode && !report.isEmpty) {
      debugPrint('[Capability] report reached=${report.reached} '
          'ceilings=${report.sessionCeilings}');
    }
    return report;
  }

  void _logSustainedConfigRecords(_ConfigState c) {
    if (c.mode == SessionMode.rhythm) {
      final to = c.to;
      if (to != null) {
        _recordReached(CapabilityAxis.rhythmDepthMax, to.index.toDouble());
        final bpm = (c.bpm ?? 60).toDouble();
        final band = _rhythmBand(to);
        _recordReached(band.$1, bpm);
        _recordReached(band.$2, bpm, minimize: true);
      }
    } else if (c.mode == SessionMode.lick) {
      final to = c.to;
      if (to != null) {
        _recordReached(CapabilityAxis.lickDepthMax, to.index.toDouble());
      }
    }
    if (c.isCrossingPattern) {
      final bpm = (c.bpm ?? 60).toDouble();
      if (c.to == Position.throat) {
        _recordReached(CapabilityAxis.gorgeCrossingsBpmThroat, bpm);
      } else if (c.to == Position.full) {
        _recordReached(CapabilityAxis.gorgeCrossingsBpmFull, bpm);
      }
    }
    if (c.isBiffle) {
      _recordReached(CapabilityAxis.biffleBpmMax, (c.bpm ?? 80).toDouble());
    }
  }

  (CapabilityAxis, CapabilityAxis) _rhythmBand(Position to) {
    if (to.index <= Position.mid.index) {
      return (
        CapabilityAxis.rhythmBpmCeilShallow,
        CapabilityAxis.rhythmBpmFloorShallow
      );
    }
    if (to == Position.throat) {
      return (
        CapabilityAxis.rhythmBpmCeilThroat,
        CapabilityAxis.rhythmBpmFloorThroat
      );
    }
    return (
      CapabilityAxis.rhythmBpmCeilFull,
      CapabilityAxis.rhythmBpmFloorFull
    );
  }

  void _flushStreak(CapabilityAxis axis, double value) {
    if (value <= 0) return;
    _recordReached(axis, value);
  }

  void recordChallengeReached(CapabilityAxis axis, double value) {
    if (value <= 0) return;
    final minimize = axis.recordKind == CapabilityRecordKind.minimize;
    _recordReached(axis, value, minimize: minimize);
  }

  void _recordReached(CapabilityAxis axis, double value,
      {bool minimize = false}) {
    final current = _reached[axis];
    if (current == null) {
      _reached[axis] = value;
    } else if (minimize) {
      if (value < current) _reached[axis] = value;
    } else {
      if (value > current) _reached[axis] = value;
    }
  }

  void _ceilFrom(CapabilityAxis axis, double value) {
    if (value <= 0) return;
    final current = _ceilings[axis];
    if (current == null || value < current) _ceilings[axis] = value;
  }
}

@immutable
class _ConfigState {
  final SessionMode mode;
  final Position? from;
  final Position? to;
  final int? bpm;

  const _ConfigState({
    required this.mode,
    this.from,
    this.to,
    this.bpm,
  });

  bool get _isRhythmic =>
      mode == SessionMode.rhythm || mode == SessionMode.lick;

  Position? get heldPos => (mode == SessionMode.hold || mode == SessionMode.beg)
      ? (to ?? from)
      : null;

  bool get isBreath => mode == SessionMode.breath;
  bool get isBiffle => mode == SessionMode.biffle;
  bool get isLick => mode == SessionMode.lick;
  bool get isHand => mode == SessionMode.hand;

  bool get isMotion => _isRhythmic;

  bool get engagesThroat {
    final h = heldPos;
    if (h != null && h.index >= Position.throat.index) return true;
    final t = to;
    return _isRhythmic && t != null && t.index >= Position.throat.index;
  }

  bool get airless {
    final h = heldPos;
    if (h != null && h.index >= Position.throat.index) return true;
    final f = from;
    return _isRhythmic && f != null && f.index >= Position.throat.index;
  }

  bool get isCrossingPattern {
    final f = from;
    final t = to;
    return _isRhythmic &&
        f != null &&
        t != null &&
        f.index <= Position.mid.index &&
        t.index >= Position.throat.index;
  }
}
