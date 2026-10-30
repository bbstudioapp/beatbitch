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

  test('T3 deux épisodes de 2 min dans une séance : durées cumulées, +4 %',
      () async {
    final tr = CapabilityTracker()..onSessionStart();
    final before = await CapabilityService().snapshotProfile();
    final normal = benchGen(100, 20 * 60, profile: before);
    benchReplay(tr, normal.session.steps, 0, 120);
    var t = 120;
    for (var episode = 0; episode < 2; episode++) {
      final um = benchGen(200 + episode, 120, useMe: true, profile: before);
      benchReplay(tr, benchShift(um.session.steps, t), t, t + 120,
          useMeFrom: t);
      t += 120;
      final gap = benchGen(300 + episode, 40, profile: before);
      benchReplay(tr, benchShift(gap.session.steps, t), t, t + 40);
      t += 40;
    }
    await CapabilityService().commit(tr.finalizeReport(), sessionIndex: 21);
    final after = await CapabilityService().snapshotProfile();
    expect(
        after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        closeTo(before.comfortOf(CapabilityAxis.rhythmBpmCeilThroat)! * 1.04,
            1e-6));
  });

  double throatGain(BenchOutcome o) =>
      o.after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat)! /
      o.before.comfortOf(CapabilityAxis.rhythmBpmCeilThroat)!;

  test('T11 FAIL après 3 s de « Utilise-moi » : gain proportionnel, ≈ 0',
      () async {
    final tr = CapabilityTracker()..onSessionStart();
    final before = await CapabilityService().snapshotProfile();
    const escalade = SessionStep(
        time: 0,
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
        bpm: 160);
    benchReplay(tr, [escalade], 0, 3, useMeFrom: 0);
    tr.onFail();
    await CapabilityService().commit(tr.finalizeReport(), sessionIndex: 21);
    final after = await CapabilityService().snapshotProfile();
    expect(
        after.comfortOf(CapabilityAxis.rhythmBpmCeilThroat),
        closeTo(
            before.comfortOf(CapabilityAxis.rhythmBpmCeilThroat)! *
                (1 + 0.05 * 3 / 300),
            1e-6));
  });

  test('T12 2 min 30 tenues : +2,5 %', () async {
    final o = await benchSession(useMe: true, useMeSec: 150);
    expect(throatGain(o), closeTo(1.025, 1e-6));
  });

  test('T13 8 min tenues : plafonné à +5 % par séance', () async {
    final o = await benchSession(useMe: true, useMeSec: 480);
    expect(throatGain(o), closeTo(1.05, 1e-6));
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

  group('T11 le changement de régime clôt les streaks vivants', () {
    void secondes(CapabilityTracker tr, int n) {
      for (var i = 0; i < n; i++) {
        tr.onTickSecond(swallowMode: SwallowMode.allowed);
      }
    }

    void gorge(CapabilityTracker tr, {required bool useMe}) => tr.onStepApplied(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          bpm: useMe ? 280 : 100,
          useMe: useMe,
        );

    test('normal → « Utilise-moi » : le streak normal reste au normal', () {
      final tr = CapabilityTracker()..onSessionStart();
      gorge(tr, useMe: false);
      secondes(tr, 20);
      gorge(tr, useMe: true);
      secondes(tr, 30);
      final r = tr.finalizeReport();
      expect(r.reached[CapabilityAxis.gorgeEngagementStreak], 20);
      expect(r.useMeReached[CapabilityAxis.gorgeEngagementStreak], 30);
    });

    test(
        'après le FAIL, la boucle « Utilise-moi » rejouée n\'alimente plus '
        'useMeReached ; un nouvel épisode le rouvre', () {
      final tr = CapabilityTracker()..onSessionStart();
      void actif(int n) {
        for (var i = 0; i < n; i++) {
          tr.onTickSecond(swallowMode: SwallowMode.allowed, useMeActive: true);
        }
      }

      gorge(tr, useMe: true);
      actif(5);
      tr.onFail();
      gorge(tr, useMe: true);
      secondes(tr, 30);
      expect(
          tr
              .finalizeReport()
              .useMeReached[CapabilityAxis.gorgeEngagementStreak],
          isNull,
          reason: 'les 30 s rejouées après le FAIL ne comptent pas');

      final tr2 = CapabilityTracker()..onSessionStart();
      gorge(tr2, useMe: true);
      tr2.onFail();
      gorge(tr2, useMe: true);
      for (var i = 0; i < 30; i++) {
        tr2.onTickSecond(swallowMode: SwallowMode.allowed, useMeActive: true);
      }
      expect(
          tr2
              .finalizeReport()
              .useMeReached[CapabilityAxis.gorgeEngagementStreak],
          30,
          reason: 'un nouvel épisode, tick actif, rouvre le seuil');
    });

    test('« Utilise-moi » → normal : le streak subi ne gonfle pas le normal',
        () {
      final tr = CapabilityTracker()..onSessionStart();
      gorge(tr, useMe: true);
      secondes(tr, 30);
      gorge(tr, useMe: false);
      secondes(tr, 10);
      final r = tr.finalizeReport();
      expect(r.useMeReached[CapabilityAxis.gorgeEngagementStreak], 30);
      expect(r.reached[CapabilityAxis.gorgeEngagementStreak], 10);
    });
  });
}
