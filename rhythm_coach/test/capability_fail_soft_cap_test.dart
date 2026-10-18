import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';
import 'package:beat_bitch/services/saliva_engine.dart';

void _tick(CapabilityTracker t, int n,
    {SwallowMode swallow = SwallowMode.allowed}) {
  for (var i = 0; i < n; i++) {
    t.onTickSecond(swallowMode: swallow);
  }
}

Future<CapabilityProfile> _seedProfile(CapabilityService svc) async {
  await svc.commit(
    SessionCapabilityReport(reached: {
      CapabilityAxis.rhythmMotionStreak: 90,
      CapabilityAxis.rhythmBpmCeilShallow: 140,
      CapabilityAxis.rhythmBpmCeilThroat: 100,
      CapabilityAxis.rhythmBpmCeilFull: 80,
      CapabilityAxis.gorgeCrossingsBpmThroat: 100,
      CapabilityAxis.gorgeCrossingsBpmFull: 80,
      CapabilityAxis.rhythmDepthMax: Position.throat.index.toDouble(),
      CapabilityAxis.gorgeEngagementStreak: 60,
      CapabilityAxis.gorgeApneeStreak: 30,
      CapabilityAxis.holdThroatStreak: 22,
      CapabilityAxis.effortNoBreathStreak: 120,
      CapabilityAxis.noswallowStreak: 120,
    }, sessionCeilings: const {}),
    sessionIndex: 1,
  );
  return svc.snapshotProfile();
}

SessionCapabilityReport _failAfter(
  int seconds, {
  required Position from,
  required Position to,
  required int bpm,
}) {
  final t = CapabilityTracker()..onSessionStart();
  t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 10);
  _tick(t, 10);
  t.onStepApplied(
      mode: SessionMode.rhythm, from: from, to: to, bpm: bpm, duration: 30);
  _tick(t, seconds);
  t.onFail();
  return t.finalizeReport();
}

SessionCapabilityReport _failEachRhythm(
    List<(Position from, Position to, int bpm)> rhythms) {
  final t = CapabilityTracker()..onSessionStart();
  for (final (from, to, bpm) in rhythms) {
    t.onStepApplied(
        mode: SessionMode.rhythm, from: from, to: to, bpm: bpm, duration: 30);
    _tick(t, 2);
    t.onFail();
  }
  return t.finalizeReport();
}

Map<String, String> _offRule(
  CapabilityProfile before,
  CapabilityProfile after,
  SessionCapabilityReport report,
  Map<CapabilityAxis, double> lowered,
) {
  final out = <String, String>{};
  for (final axis in lowered.keys) {
    if (!report.sessionCeilings.containsKey(axis) ||
        before.comfortOf(axis) == null) {
      out[axis.storageKey] = 'accusé attendu sans plafond ni confort';
    }
  }
  for (final axis in report.sessionCeilings.keys) {
    final prev = before.comfortOf(axis);
    if (prev == null) continue;
    final expected = lowered[axis] ?? prev;
    final got = after.comfortOf(axis)!;
    if ((got - expected).abs() > 1e-9) {
      out[axis.storageKey] = '$prev → $got (attendu $expected)';
    }
    final srBefore = before.stateOf(axis).successRate;
    final srExpected = lowered.containsKey(axis) ? 0.35 : srBefore;
    final srGot = after.stateOf(axis).successRate;
    if ((srGot - srExpected).abs() > 1e-9) {
      out['${axis.storageKey}.sr'] = '$srBefore → $srGot (attendu $srExpected)';
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'rythme profond, vitesse sondée : BPM et profondeur accusés, streaks '
      'vivants intacts', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report =
        _failAfter(2, from: Position.mid, to: Position.throat, bpm: 112);
    expect(report.sessionCeilings[CapabilityAxis.rhythmMotionStreak], 2.0);
    expect(report.sessionCeilings[CapabilityAxis.rhythmBpmCeilThroat], 112.0);

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, CapabilityAxis.rhythmBpmCeilThroat);
    final after = await svc.snapshotProfile();
    expect(after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        closeTo(100 * CapabilityRegulator.kRatchetDownFactor, 1e-9));
    expect(after.comfortOf(CapabilityAxis.rhythmDepthMax),
        Position.mid.index.toDouble());

    expect(
        _offRule(before, after, report, {
          CapabilityAxis.rhythmBpmCeilThroat: 85,
          CapabilityAxis.gorgeCrossingsBpmThroat: 85,
          CapabilityAxis.rhythmDepthMax: 2,
        }),
        isEmpty);
  });

  test(
      'rythme profond, profondeur sondée lentement : la vitesse accusée avec '
      'elle perd 15 %, pas jusqu\'au BPM de la sonde', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report =
        _failAfter(2, from: Position.throat, to: Position.full, bpm: 40);
    expect(report.sessionCeilings[CapabilityAxis.rhythmDepthMax],
        Position.full.index.toDouble());
    expect(report.sessionCeilings[CapabilityAxis.rhythmBpmCeilFull], 40.0);

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, CapabilityAxis.rhythmDepthMax);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {
          CapabilityAxis.rhythmDepthMax: 2,
          CapabilityAxis.rhythmBpmCeilFull: 68,
        }),
        isEmpty);
  });

  test(
      'franchissement vers full, profondeur sondée : profondeur, BPM de bande '
      'et BPM franchissant accusés', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report =
        _failAfter(2, from: Position.mid, to: Position.full, bpm: 70);
    expect(report.sessionCeilings[CapabilityAxis.gorgeCrossingsBpmFull], 70.0);

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, CapabilityAxis.rhythmDepthMax);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {
          CapabilityAxis.rhythmDepthMax: 2,
          CapabilityAxis.rhythmBpmCeilFull: 68,
          CapabilityAxis.gorgeCrossingsBpmFull: 68,
        }),
        isEmpty);
  });

  test('rythme peu profond, vitesse sondée : seul le BPM est accusé', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report =
        _failAfter(2, from: Position.head, to: Position.mid, bpm: 154);
    expect(report.sessionCeilings[CapabilityAxis.rhythmDepthMax],
        Position.mid.index.toDouble());

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, CapabilityAxis.rhythmBpmCeilShallow);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(
            before, after, report, {CapabilityAxis.rhythmBpmCeilShallow: 119}),
        isEmpty);
  });

  test('FAIL sur un step lent, aucun axe surchargé : rien ne baisse', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report =
        _failAfter(6, from: Position.mid, to: Position.throat, bpm: 50);
    expect(report.sessionCeilings[CapabilityAxis.rhythmMotionStreak], 6.0);
    expect(report.sessionCeilings[CapabilityAxis.rhythmBpmCeilThroat], 50.0);

    final attributed = await svc.commit(report, sessionIndex: 2);
    expect(attributed, isNull);
    final after = await svc.snapshotProfile();

    expect(_offRule(before, after, report, const {}), isEmpty);
  });

  test(
      'deux FAIL : un 2ᵉ FAIL peu profond ne retire pas la profondeur accusée '
      'par le 1ᵉʳ', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report = _failEachRhythm([
      (Position.mid, Position.throat, 112),
      (Position.tip, Position.head, 40),
    ]);
    expect(report.sessionCeilings[CapabilityAxis.rhythmDepthMax],
        Position.head.index.toDouble());

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {
          CapabilityAxis.rhythmBpmCeilThroat: 85,
          CapabilityAxis.gorgeCrossingsBpmThroat: 85,
          CapabilityAxis.rhythmDepthMax: 2,
        }),
        isEmpty);
  });

  test('deux FAIL de causes différentes : chacun garde ses accusés', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final report = _failEachRhythm([
      (Position.mid, Position.throat, 112),
      (Position.head, Position.mid, 154),
    ]);

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {
          CapabilityAxis.rhythmBpmCeilThroat: 85,
          CapabilityAxis.gorgeCrossingsBpmThroat: 85,
          CapabilityAxis.rhythmDepthMax: 2,
          CapabilityAxis.rhythmBpmCeilShallow: 119,
        }),
        isEmpty);
  });

  test('FAIL pendant un « sans avaler » : elle a avalé, noswallow perd 15 %',
      () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 10, swallow: SwallowMode.forbidden);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.noswallowStreak], 10.0);

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {CapabilityAxis.noswallowStreak: 102}),
        isEmpty);
  });

  test(
      'FAIL en « sans avaler » sur une tenue trop longue : seul noswallow '
      'baisse', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 25, swallow: SwallowMode.forbidden);
    t.onFail();
    final report = t.finalizeReport();

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {CapabilityAxis.noswallowStreak: 102}),
        isEmpty);
  });

  test(
      'FAIL où « sans avaler » dépasse le plus : la tenue au-delà de son '
      'confort ne baisse pas', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.breath, duration: 140);
    _tick(t, 130, swallow: SwallowMode.forbidden);
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 23, swallow: SwallowMode.forbidden);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.noswallowStreak], 153.0);

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {CapabilityAxis.noswallowStreak: 102}),
        isEmpty);
  });

  test('débordement de salive : noswallow ne baisse pas', () async {
    final svc = CapabilityService();
    await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 10, swallow: SwallowMode.forbidden);
    _tick(t, 5, swallow: SwallowMode.forbidden);
    t.onStepApplied(mode: SessionMode.breath, duration: 10);
    _tick(t, 5);
    final report = t.finalizeReport();
    expect(report.sessionCeilings.containsKey(CapabilityAxis.noswallowStreak),
        isFalse);
    expect(report.reached[CapabilityAxis.noswallowStreak], 15.0);

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(after.comfortOf(CapabilityAxis.noswallowStreak), 120.0);
    expect(after.stateOf(CapabilityAxis.noswallowStreak).successRate, 0.5);
  });

  test('FAIL où « sans avaler » est le plus au-delà de son confort : accusé',
      () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.breath, duration: 140);
    _tick(t, 130, swallow: SwallowMode.forbidden);
    t.onFail();
    final report = t.finalizeReport();

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {CapabilityAxis.noswallowStreak: 102}),
        isEmpty);
  });

  test(
      'FAIL non accusé : un record de la séance fait monter l\'axe figé comme '
      'sans FAIL', () async {
    final svc = CapabilityService();
    await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 30);
    t.onStepApplied(mode: SessionMode.breath, duration: 10);
    _tick(t, 10);
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 5);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.holdThroatStreak], 5.0);
    expect(report.reached[CapabilityAxis.holdThroatStreak], 30.0);

    expect(await svc.commit(report, sessionIndex: 2), isNull);
    final after = await svc.snapshotProfile();

    const gain = CapabilityRegulator.kRatchetUpGainMin +
        (CapabilityRegulator.kRatchetUpGainMax -
                CapabilityRegulator.kRatchetUpGainMin) *
            0.5;
    expect(after.comfortOf(CapabilityAxis.holdThroatStreak),
        closeTo(22 * (1 + gain), 1e-9));
    expect(after.stateOf(CapabilityAxis.holdThroatStreak).successRate,
        closeTo(0.65, 1e-9));
  });

  test('FAIL accusé : un record de la séance ne fait pas monter l\'axe accusé',
      () async {
    final svc = CapabilityService();
    await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 30);
    t.onStepApplied(mode: SessionMode.breath, duration: 10);
    _tick(t, 10);
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 30);
    _tick(t, 25);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.reached[CapabilityAxis.holdThroatStreak], 30.0);

    expect(await svc.commit(report, sessionIndex: 2),
        CapabilityAxis.holdThroatStreak);
    final after = await svc.snapshotProfile();

    expect(after.comfortOf(CapabilityAxis.holdThroatStreak),
        closeTo(22 * CapabilityRegulator.kRatchetDownFactor, 1e-9));
  });

  test(
      'deux FAIL de rythme profond : la vitesse franchissante figée par le 1ᵉʳ '
      'sans être accusée n\'est pas entraînée par le groupe du 2ᵉ', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(
        mode: SessionMode.rhythm,
        from: Position.mid,
        to: Position.throat,
        bpm: 50,
        duration: 30);
    _tick(t, 6);
    t.onFail();
    t.onStepApplied(
        mode: SessionMode.rhythm,
        from: Position.throat,
        to: Position.throat,
        bpm: 112,
        duration: 30);
    _tick(t, 2);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.failCeilings.last
        .containsKey(CapabilityAxis.gorgeCrossingsBpmThroat), isFalse);
    expect(report.sessionCeilings[CapabilityAxis.gorgeCrossingsBpmThroat], 50.0);

    await svc.commit(report, sessionIndex: 2);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {
          CapabilityAxis.rhythmBpmCeilThroat: 85,
          CapabilityAxis.rhythmDepthMax: 2,
        }),
        isEmpty);
  });

  test(
      'FAIL dû à la durée en gorge sur un rythme profond lent : seul '
      'l\'engagement est accusé', () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hold, to: Position.throat, duration: 50);
    _tick(t, 50);
    t.onStepApplied(
        mode: SessionMode.rhythm,
        from: Position.mid,
        to: Position.throat,
        bpm: 50,
        duration: 90);
    _tick(t, 80);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.gorgeEngagementStreak], 130.0);

    expect(await svc.commit(report, sessionIndex: 2),
        CapabilityAxis.gorgeEngagementStreak);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report,
            {CapabilityAxis.gorgeEngagementStreak: 51}),
        isEmpty);
  });

  test('FAIL en apnée sur un rythme en gorge lent : seule l\'apnée est accusée',
      () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(
        mode: SessionMode.rhythm,
        from: Position.throat,
        to: Position.throat,
        bpm: 50,
        duration: 60);
    _tick(t, 40);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.gorgeApneeStreak], 40.0);

    expect(await svc.commit(report, sessionIndex: 2),
        CapabilityAxis.gorgeApneeStreak);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report, {CapabilityAxis.gorgeApneeStreak: 25.5}),
        isEmpty);
  });

  test('FAIL après un long effort sans souffle : seul cet effort est accusé',
      () async {
    final svc = CapabilityService();
    final before = await _seedProfile(svc);
    final t = CapabilityTracker()..onSessionStart();
    t.onStepApplied(mode: SessionMode.hand, duration: 140);
    _tick(t, 130);
    t.onFail();
    final report = t.finalizeReport();
    expect(report.sessionCeilings[CapabilityAxis.effortNoBreathStreak], 130.0);

    expect(await svc.commit(report, sessionIndex: 2),
        CapabilityAxis.effortNoBreathStreak);
    final after = await svc.snapshotProfile();

    expect(
        _offRule(before, after, report,
            {CapabilityAxis.effortNoBreathStreak: 102}),
        isEmpty);
  });
}
