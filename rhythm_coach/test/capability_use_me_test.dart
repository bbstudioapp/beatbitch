// tss2-037 : « Utilise-moi » ne doit plus fausser le profil de capacités.
// Banc : vrai générateur + vrai tracker + vrai service (cf. capability_use_me_bench.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';

import 'capability_use_me_bench.dart';

const _bpmAxes = [
  CapabilityAxis.rhythmBpmCeilThroat,
  CapabilityAxis.rhythmBpmCeilFull,
  CapabilityAxis.gorgeCrossingsBpmThroat,
  CapabilityAxis.gorgeCrossingsBpmFull,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(benchPrefsSeed()));

  test('T1 sans FAIL, « Utilise-moi » n\'écrit aucun best des axes normaux',
      () async {
    final o = await benchSession(useMe: true, useMeSec: 300);
    for (final a in [..._bpmAxes, CapabilityAxis.rhythmDepthMax]) {
      expect(o.after.bestOf(a), o.before.bestOf(a), reason: a.storageKey);
    }
    expect(o.after.bestOf(CapabilityAxis.gorgeEngagementStreak), lessThan(150),
        reason: 'le temps subi (318 s mesurés) ne gonfle plus le best normal');
    expect(o.after.bestOf(CapabilityAxis.effortNoBreathStreak), lessThan(150));
  });

  test('T2 un cran de +5 % du comfort, sur les 4 axes BPM, pas plus', () async {
    final o = await benchSession(useMe: true, useMeSec: 300);
    for (final a in _bpmAxes) {
      expect(o.after.comfortOf(a), closeTo(o.before.comfortOf(a)! * 1.05, 1e-6),
          reason: a.storageKey);
    }
    expect(o.after.comfortOf(CapabilityAxis.rhythmDepthMax),
        o.before.comfortOf(CapabilityAxis.rhythmDepthMax),
        reason: 'la profondeur n\'est pas relevée par le mode');
  });

  test('T2b comfort déjà à 1,15 × best normal : pas de cran', () async {
    final seed = benchPrefsSeed();
    seed['cap.rhythm.bpm_ceil.throat.comfort'] = 105 * 1.15;
    SharedPreferences.setMockInitialValues(seed);
    final o = await benchSession(useMe: true, useMeSec: 300);
    expect(o.after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        closeTo(105 * 1.15, 1e-6));
  });

  test('T3 deux épisodes dans une séance : un seul cran', () async {
    final tr = CapabilityTracker()..onSessionStart();
    final before = await CapabilityService().snapshotProfile();
    final normal = benchGen(100, 20 * 60, profile: before);
    benchReplay(tr, normal.session.steps, 0, 120);
    var t = 120;
    for (var episode = 0; episode < 2; episode++) {
      final um = benchGen(200 + episode, 150, useMe: true, profile: before);
      benchReplay(tr, benchShift(um.session.steps, t), t, t + 150,
          useMeFrom: t);
      t += 150;
      final gap = benchGen(300 + episode, 40, profile: before);
      benchReplay(tr, benchShift(gap.session.steps, t), t, t + 40);
      t += 40;
    }
    await CapabilityService().commit(tr.finalizeReport(), sessionIndex: 21);
    final after = await CapabilityService().snapshotProfile();
    expect(
        after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        closeTo(before.comfortOf(CapabilityAxis.rhythmBpmCeilThroat)! * 1.05,
            1e-6));
  });

  test('T4 le FAIL qui termine « Utilise-moi » n\'impose rien aux axes normaux',
      () async {
    for (final frac in [0.05, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 0.98]) {
      SharedPreferences.setMockInitialValues(benchPrefsSeed());
      final o = await benchSession(useMe: true, useMeSec: 300, failFrac: frac);
      final at = 'FAIL@${(frac * 100).round()}%';
      for (final a in [
        CapabilityAxis.rhythmMotionStreak,
        CapabilityAxis.gorgeApneeStreak,
        CapabilityAxis.holdThroatStreak,
      ]) {
        expect(o.after.comfortOf(a), o.before.comfortOf(a),
            reason: '$at ${a.storageKey}');
      }
      for (final a in _bpmAxes) {
        expect(o.after.bestOf(a), o.before.bestOf(a),
            reason: '$at ${a.storageKey} best');
        expect(
            o.after.comfortOf(a)!, greaterThanOrEqualTo(o.before.comfortOf(a)!),
            reason: '$at ${a.storageKey} : aucun hardNegative imputé');
      }
    }
  });

  test('T7 témoin : une séance normale ne relève aucun comfort BPM', () async {
    final o = await benchSession(useMe: false, useMeSec: 300);
    for (final a in _bpmAxes) {
      expect(o.after.comfortOf(a), o.before.comfortOf(a), reason: a.storageKey);
      expect(o.after.bestOf(a), o.before.bestOf(a), reason: a.storageKey);
    }
  });
}
