import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';
import 'package:beat_bitch/services/saliva_engine.dart';

void _tick(CapabilityTracker t, int n) {
  for (var i = 0; i < n; i++) {
    t.onTickSecond(swallowMode: SwallowMode.allowed);
  }
}

Future<CapabilityProfile> _seedProfile(CapabilityService svc) async {
  await svc.commit(
    SessionCapabilityReport(reached: {
      CapabilityAxis.rhythmMotionStreak: 90,
      CapabilityAxis.rhythmBpmCeilThroat: 100,
      CapabilityAxis.rhythmDepthMax: Position.throat.index.toDouble(),
      CapabilityAxis.gorgeEngagementStreak: 60,
      CapabilityAxis.gorgeApneeStreak: 30,
      CapabilityAxis.holdThroatStreak: 22,
      CapabilityAxis.effortNoBreathStreak: 120,
    }, sessionCeilings: const {}),
    sessionIndex: 1,
  );
  return svc.snapshotProfile();
}

/// Axes figés, non imputés, dont le confort a baissé plus que ne l'aurait
/// fait un FAIL imputé à cet axe à sa limite (`figé = comfort`, ratchet dur).
Map<String, String> _worseThanImputed(
  CapabilityProfile before,
  CapabilityProfile after,
  SessionCapabilityReport report,
  CapabilityAxis? attributed,
) {
  final out = <String, String>{};
  for (final axis in report.sessionCeilings.keys) {
    if (axis == attributed) continue;
    final prev = before.stateOf(axis);
    if (prev.comfort == null) continue;
    final imputed = CapabilityRegulator.regulate(
      axis: axis,
      prev: prev,
      sessionCeiling: prev.comfort,
      hardNegative: true,
      sessionIndex: 2,
    ).comfort!;
    final got = after.comfortOf(axis)!;
    final worse = axis.recordKind == CapabilityRecordKind.minimize
        ? got > imputed + 1e-9
        : got < imputed - 1e-9;
    if (worse) {
      out[axis.storageKey] = '${prev.comfort} → $got '
          '(imputé : ${imputed.toStringAsFixed(1)})';
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'tap-out imputé au BPM : les streaks vivants non imputés ne baissent pas '
      'plus que l\'axe imputé', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);

    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 10);
    _tick(t, 10);
    t.onStepApplied(
      mode: SessionMode.rhythm,
      from: Position.mid,
      to: Position.throat,
      bpm: 112,
      duration: 30,
    );
    _tick(t, 2);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.rhythmMotionStreak], 2.0);
    expect(report.sessionCeilings[CapabilityAxis.rhythmBpmCeilThroat], 112.0);

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, CapabilityAxis.rhythmBpmCeilThroat);
    final after = await svc.snapshotProfile();
    expect(after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        closeTo(100 * CapabilityRegulator.kRatchetDownFactor, 1e-9));

    expect(_worseThanImputed(before, after, report, attributed), isEmpty);
  });

  test(
      'FAIL sur un step lent (non imputé) : ni le BPM ni les streaks ne '
      'baissent plus qu\'un FAIL imputé', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);

    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(
      mode: SessionMode.rhythm,
      from: Position.mid,
      to: Position.throat,
      bpm: 50,
      duration: 30,
    );
    _tick(t, 6);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.rhythmMotionStreak], 6.0);
    expect(report.sessionCeilings[CapabilityAxis.rhythmBpmCeilThroat], 50.0);

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, isNull);
    final after = await svc.snapshotProfile();

    expect(_worseThanImputed(before, after, report, attributed), isEmpty);
  });
}
