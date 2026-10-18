// tss2-037 : « Utilise-moi » ne doit plus fausser le profil de capacités.
// Banc : vrai générateur + vrai tracker + vrai service (cf. capability_use_me_bench.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';
import 'package:beat_bitch/services/saliva_engine.dart';
import 'package:beat_bitch/services/stats_service.dart';

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

  test('T5b l\'axe useMe.held_streak n\'est jamais lu par le générateur',
      () async {
    List<Map<String, dynamic>> steps(CapabilityProfile p) =>
        benchGen(100, 20 * 60, profile: p)
            .session
            .steps
            .map((st) => st.toJson())
            .toList();
    final plain = await CapabilityService().snapshotProfile();
    final seed = benchPrefsSeed();
    seed['cap.useMe.held_streak.best'] = 999.0;
    seed['cap.useMe.held_streak.comfort'] = 999.0;
    SharedPreferences.setMockInitialValues(seed);
    final withAxis = await CapabilityService().snapshotProfile();
    expect(withAxis.bestOf(CapabilityAxis.useMeHeldStreak), 999,
        reason: 'sonde non vide');
    expect(steps(withAxis), steps(plain));
  });

  test('T8 profil existant, best gonflé compris : lu sans erreur, axe amorcé',
      () async {
    final seed = benchPrefsSeed();
    seed['cap.rhythm.bpm_ceil.throat.best'] = 298.0;
    seed['stats.max_use_me_sec'] = 240;
    SharedPreferences.setMockInitialValues(seed);
    final p = await CapabilityService().snapshotProfile();
    expect(p.bestOf(CapabilityAxis.rhythmBpmCeilThroat), 298,
        reason: 'le best gonflé est lu tel quel, sans réparation');
    expect(p.bestOf(CapabilityAxis.useMeHeldStreak), 240);
    expect(p.comfortOf(CapabilityAxis.useMeHeldStreak), 240);
    expect(p.axesWithData, contains(CapabilityAxis.useMeHeldStreak));

    (await SharedPreferences.getInstance()).setInt('stats.max_use_me_sec', 400);
    final again = await CapabilityService().snapshotProfile();
    expect(again.bestOf(CapabilityAxis.useMeHeldStreak), 240,
        reason: 'amorçage unique');
  });

  test('T8b sans tenue passée : l\'axe reste vide', () async {
    final p = await CapabilityService().snapshotProfile();
    expect(p.stateOf(CapabilityAxis.useMeHeldStreak).hasData, isFalse);
    expect(p.axesWithData, isNot(contains(CapabilityAxis.useMeHeldStreak)));
  });

  test('T9 « Tout remettre à zéro » : l\'axe useMe.held_streak ne revient pas',
      () async {
    final seed = benchPrefsSeed();
    seed['stats.max_use_me_sec'] = 400;
    SharedPreferences.setMockInitialValues(seed);
    final amorce = await CapabilityService().snapshotProfile();
    expect(amorce.bestOf(CapabilityAxis.useMeHeldStreak), 400,
        reason:
            'sonde non vide : l\'axe est bien amorcé avant la remise à zéro');

    await Future.wait(
        [StatsService().resetAll(), CapabilityService().resetAll()]);

    final after = await CapabilityService().snapshotProfile();
    expect(after.stateOf(CapabilityAxis.useMeHeldStreak).hasData, isFalse);
    expect(after.axesWithData, isEmpty);
  });
}
