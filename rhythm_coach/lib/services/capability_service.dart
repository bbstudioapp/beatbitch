import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_step.dart';
import 'capability_axis.dart';

class CapabilityAxisState {
  final double? best;
  final double? comfort;
  final double successRate;
  final int lastSeenSession;

  const CapabilityAxisState({
    this.best,
    this.comfort,
    this.successRate = CapabilityService.defaultSuccessRate,
    this.lastSeenSession = -1,
  });

  bool get hasData => best != null;
}

class CapabilityProfile {
  final Map<CapabilityAxis, CapabilityAxisState> _states;

  const CapabilityProfile(this._states);

  CapabilityAxisState stateOf(CapabilityAxis axis) =>
      _states[axis] ?? const CapabilityAxisState();

  double? bestOf(CapabilityAxis axis) => stateOf(axis).best;
  double? comfortOf(CapabilityAxis axis) => stateOf(axis).comfort;

  bool get hasAnyData => _states.values.any((s) => s.hasData);

  Iterable<CapabilityAxis> get axesWithData =>
      CapabilityAxis.displayOrder.where((a) => stateOf(a).hasData);
}

class SessionCapabilityReport {
  final Map<CapabilityAxis, double> reached;
  final Map<CapabilityAxis, double> sessionCeilings;

  const SessionCapabilityReport({
    required this.reached,
    required this.sessionCeilings,
  });

  bool get isEmpty => reached.isEmpty && sessionCeilings.isEmpty;
}

class CapabilityRegulator {
  CapabilityRegulator._();

  static const double kSurchargeMin = 1.03;
  static const double kSurchargeMax = 1.15;

  static const double kRatchetUpGainMin = 0.12;
  static const double kRatchetUpGainMax = 0.35;

  static const double kRatchetAnchorHeadroom = 1.15;

  static const double kRatchetDownFactor = 0.85;

  static const int kDecayAfterSessions = 4;
  static const double kDecayTargetFracOfBest = 0.70;

  static const double kDecayStepFrac = 0.34;

  static const double kBpmFloorPractical = 18.0;

  static const double kBreathMinDoseFloor = 2.0;

  static const double kSuccessRateAlpha = 0.30;

  static const double kDepthCranGate = 0.65;

  /// Absorbe les arrondis BPM/durée du clamp générateur.
  static const double kOvershootMargin = 1.02;

  static const int kProgressPhraseLevelGate = 4;
  static const double kProgressPhraseChancePerLevel = 0.05;
  static const double kProgressPhraseChanceMax = 0.40;

  static double surchargeFactor(double successRate) =>
      kSurchargeMin +
      (kSurchargeMax - kSurchargeMin) * successRate.clamp(0.0, 1.0);

  static double progressPhraseChanceForLevel(int level) =>
      ((level - kProgressPhraseLevelGate) * kProgressPhraseChancePerLevel)
          .clamp(0.0, kProgressPhraseChanceMax);

  static CapabilityAxis? attributeTapOut(
    Map<CapabilityAxis, double> ceilings,
    CapabilityProfile profile,
  ) {
    CapabilityAxis? attributed;
    double bestRatio = 1.0;
    ceilings.forEach((axis, ceiling) {
      final comfort = profile.comfortOf(axis);
      if (comfort == null || comfort <= 0 || ceiling <= 0) return;
      final ratio = axis.recordKind == CapabilityRecordKind.minimize
          ? comfort / ceiling
          : ceiling / comfort;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        attributed = axis;
      }
    });
    return attributed;
  }

  static Set<CapabilityAxis> accusedAxes(
    CapabilityAxis? attributed,
    Map<CapabilityAxis, double> ceilings,
  ) {
    if (attributed == null) return const {};
    final depth = ceilings[CapabilityAxis.rhythmDepthMax];
    final group = depth == null ? const <CapabilityAxis>{} : _deepRhythm(depth);
    if (!group.contains(attributed)) return {attributed};
    return group.where(ceilings.containsKey).toSet();
  }

  static Set<CapabilityAxis> _deepRhythm(double depth) {
    if (depth >= Position.full.index) {
      return const {
        CapabilityAxis.rhythmDepthMax,
        CapabilityAxis.rhythmBpmCeilFull,
        CapabilityAxis.gorgeCrossingsBpmFull,
      };
    }
    if (depth >= Position.throat.index) {
      return const {
        CapabilityAxis.rhythmDepthMax,
        CapabilityAxis.rhythmBpmCeilThroat,
        CapabilityAxis.gorgeCrossingsBpmThroat,
      };
    }
    return const {};
  }

  static CapabilityAxisState regulate({
    required CapabilityAxis axis,
    required CapabilityAxisState prev,
    double? reached,
    double? sessionCeiling,
    bool hardNegative = false,
    required int sessionIndex,
    bool quickie = false,
  }) {
    final bool isMinimize = axis.recordKind == CapabilityRecordKind.minimize;
    final bool isAccumulate =
        axis.recordKind == CapabilityRecordKind.accumulate;
    final bool isDepthCran = axis.unit == CapabilityUnit.depthCran;

    double? newBest = prev.best;
    if (reached != null) {
      if (isAccumulate) {
        newBest = (prev.best ?? 0) + reached;
      } else if (prev.best == null) {
        newBest = reached;
      } else if (isMinimize) {
        newBest = reached < prev.best! ? reached : prev.best;
      } else {
        newBest = reached > prev.best! ? reached : prev.best;
      }
    }

    if (isAccumulate) {
      if (newBest == null) return prev;
      return CapabilityAxisState(
        best: newBest,
        comfort: newBest,
        successRate: prev.successRate,
        lastSeenSession: reached != null ? sessionIndex : prev.lastSeenSession,
      );
    }

    if (prev.comfort == null) {
      if (newBest == null) return prev;
      return CapabilityAxisState(
        best: newBest,
        comfort: newBest,
        successRate: prev.successRate,
        lastSeenSession: sessionIndex,
      );
    }

    double comfort = prev.comfort!;
    double sr = prev.successRate;
    final int lastSeen =
        (reached != null) ? sessionIndex : prev.lastSeenSession;
    final double bestRef = newBest ?? comfort;
    final double absFloor = _absoluteFloor(axis);

    if (quickie && (reached != null || sessionCeiling != null)) {
      return CapabilityAxisState(
        best: newBest,
        comfort: comfort,
        successRate: sr,
        lastSeenSession: lastSeen,
      );
    }

    if (sessionCeiling != null) {
      if (hardNegative) {
        if (isDepthCran) {
          comfort = (comfort - 1).clamp(0.0, prev.comfort!);
          if (sessionCeiling < comfort) comfort = sessionCeiling;
        } else if (isMinimize) {
          // « plus facile » = comfort s'éloigne de best (monte pour un floor).
          final double base =
              sessionCeiling > comfort ? sessionCeiling : comfort;
          comfort = base / kRatchetDownFactor;
        } else {
          final double base =
              sessionCeiling < comfort ? sessionCeiling : comfort;
          comfort = base * kRatchetDownFactor;
        }
        sr = _ema(sr, 0.0);
      } else {
        sr = _ema(sr, 0.0, weight: 0.5);
      }
    } else if (reached != null) {
      final bool overshoot = isMinimize
          ? reached <= comfort * (2 - kOvershootMargin)
          : reached >= comfort * kOvershootMargin;
      if (overshoot) {
        final double gain = kRatchetUpGainMin +
            (kRatchetUpGainMax - kRatchetUpGainMin) * sr.clamp(0.0, 1.0);
        if (isDepthCran) {
          if (sr >= kDepthCranGate) {
            final double bumped = comfort + 1;
            comfort = bumped < reached ? bumped : reached;
          }
          sr = _ema(sr, 1.0);
        } else if (isMinimize) {
          double next = comfort * (1.0 - gain);
          final double anchorFloor = reached * (2.0 - kRatchetAnchorHeadroom);
          if (next < anchorFloor) next = anchorFloor;
          if (next < absFloor) next = absFloor;
          if (next < comfort) comfort = next;
          sr = _ema(sr, 1.0);
        } else {
          double next = comfort * (1.0 + gain);
          final double anchorCeil = reached * kRatchetAnchorHeadroom;
          if (next > anchorCeil) next = anchorCeil;
          if (next > comfort) comfort = next;
          sr = _ema(sr, 1.0);
        }
      }
    } else {
      if (prev.lastSeenSession >= 0 &&
          sessionIndex - prev.lastSeenSession >= kDecayAfterSessions &&
          newBest != null) {
        final double target = isMinimize
            ? newBest / kDecayTargetFracOfBest
            : newBest * kDecayTargetFracOfBest;
        comfort = comfort + (target - comfort) * kDecayStepFrac;
        sr = _ema(sr, 0.5, weight: 0.5);
      }
    }

    if (isMinimize) {
      if (comfort < absFloor) comfort = absFloor;
    } else {
      if (comfort < absFloor) comfort = absFloor;
      final double cap = bestRef * kSurchargeMax;
      if (comfort > cap) comfort = cap;
    }

    return CapabilityAxisState(
      best: newBest,
      comfort: comfort,
      successRate: sr.clamp(0.0, 1.0),
      lastSeenSession: lastSeen,
    );
  }

  static double _absoluteFloor(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.rhythmBpmFloorShallow:
      case CapabilityAxis.rhythmBpmFloorThroat:
      case CapabilityAxis.rhythmBpmFloorFull:
        return kBpmFloorPractical;
      case CapabilityAxis.breathMinDose:
        return kBreathMinDoseFloor;
      default:
        return 0.0;
    }
  }

  static double _ema(double prev, double towards, {double weight = 1.0}) =>
      prev + (towards - prev) * kSuccessRateAlpha * weight;
}

class CapabilityService {
  static const String _prefix = 'cap.';
  static const String _suffixBest = '.best';
  static const String _suffixComfort = '.comfort';
  static const String _suffixSuccessRate = '.sr';
  static const String _suffixLastSeen = '.seen';

  /// Lue directement pour ne pas dépendre de `StatsService`.
  static const String _kLegacyMaxHoldFullAtomic = 'stats.max_hold_full_atomic';

  /// Évite de re-seeder un record volontairement effacé.
  static const String _kLegacyMigrated = 'cap.legacy_migrated';

  static const double defaultSuccessRate = 0.5;

  Future<CapabilityProfile> snapshotProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    final states = <CapabilityAxis, CapabilityAxisState>{};
    for (final axis in CapabilityAxis.values) {
      states[axis] = _readState(prefs, axis);
    }
    return CapabilityProfile(states);
  }

  Future<CapabilityAxis?> commit(
    SessionCapabilityReport report, {
    required int sessionIndex,
    bool quickie = false,
  }) async {
    if (report.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);

    final prevStates = <CapabilityAxis, CapabilityAxisState>{
      for (final axis in CapabilityAxis.values) axis: _readState(prefs, axis),
    };

    final attributed = CapabilityRegulator.attributeTapOut(
      report.sessionCeilings,
      CapabilityProfile(prevStates),
    );
    final accused =
        CapabilityRegulator.accusedAxes(attributed, report.sessionCeilings);

    for (final axis in CapabilityAxis.values) {
      final prev = prevStates[axis]!;
      final reached = report.reached[axis];
      final ceiling = report.sessionCeilings[axis];
      if (reached == null && ceiling == null && prev.comfort == null) continue;
      final bool hard = accused.contains(axis) ||
          (axis == CapabilityAxis.noswallowStreak && ceiling != null);
      final next = CapabilityRegulator.regulate(
        axis: axis,
        prev: prev,
        reached: reached,
        sessionCeiling: ceiling,
        hardNegative: hard,
        sessionIndex: sessionIndex,
        quickie: quickie,
      );
      if (next.comfort == null || next.best == null) continue;
      _writeState(
        prefs,
        axis,
        best: next.best!,
        comfort: next.comfort!,
        successRate: next.successRate,
        lastSeenSession: next.lastSeenSession,
      );
    }
    return attributed;
  }

  /// Remet le drapeau de migration : un reset re-seede depuis la clé legacy.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final axis in CapabilityAxis.values) {
      await prefs.remove('$_prefix${axis.storageKey}$_suffixBest');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixComfort');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixSuccessRate');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixLastSeen');
    }
    await prefs.remove(_kLegacyMigrated);
  }

  CapabilityAxisState _readState(SharedPreferences prefs, CapabilityAxis axis) {
    final base = '$_prefix${axis.storageKey}';
    return CapabilityAxisState(
      best: prefs.getDouble('$base$_suffixBest'),
      comfort: prefs.getDouble('$base$_suffixComfort'),
      successRate:
          prefs.getDouble('$base$_suffixSuccessRate') ?? defaultSuccessRate,
      lastSeenSession: prefs.getInt('$base$_suffixLastSeen') ?? -1,
    );
  }

  void _writeState(
    SharedPreferences prefs,
    CapabilityAxis axis, {
    required double best,
    required double comfort,
    required double successRate,
    required int lastSeenSession,
  }) {
    final base = '$_prefix${axis.storageKey}';
    prefs.setDouble('$base$_suffixBest', best);
    prefs.setDouble('$base$_suffixComfort', comfort);
    prefs.setDouble('$base$_suffixSuccessRate', successRate);
    prefs.setInt('$base$_suffixLastSeen', lastSeenSession);
  }

  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (prefs.getBool(_kLegacyMigrated) ?? false) return;
    await prefs.setBool(_kLegacyMigrated, true);
    final legacy = prefs.getInt(_kLegacyMaxHoldFullAtomic) ?? 0;
    if (legacy <= 0) return;
    final base = '$_prefix${CapabilityAxis.holdFullStreak.storageKey}';
    if (prefs.getDouble('$base$_suffixBest') != null) return;
    final v = legacy.toDouble();
    prefs.setDouble('$base$_suffixBest', v);
    prefs.setDouble('$base$_suffixComfort', v);
    prefs.setDouble('$base$_suffixSuccessRate', defaultSuccessRate);
    prefs.setInt('$base$_suffixLastSeen', -1);
  }
}
