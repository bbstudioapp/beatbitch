import 'dart:math';

import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _coaches = ['lina', 'helene', 'jade', 'victoria', 'nyx', 'morgan'];

List<String> _v3(String c) => [
      for (final (act, tier) in [('a1', ''), ('a2', '_nu1'), ('a3', '_nu2')])
        for (final m in ['beg', 'challenge', 'fail', 'milestone', 'punish'])
          '$c-v3-$act-${m}_${m}_$c$tier.webp',
      for (final (act, tier) in [('a1', ''), ('a2', '_nu1'), ('a3', '_nu2')])
        for (final n in ['01', '02', '03'])
          '$c-v3-$act-play-${n}_play_$c$tier.webp',
      '$c-v3-final_final_${c}_nu2.webp',
      '$c-v3-postfinal_post-final_${c}_nu2.webp',
    ];

const _povs = [
  'pov-A-gag_pov_hold_full.webp',
  'pov-A-rhythm-full_pov_rhythm_full.webp',
  'pov-A-suckle_pov_suckle.webp',
];

void main() {
  final svc = BackgroundsService.instance;
  final bundle = BackgroundsBundle(entries: [
    for (final n in [for (final c in _coaches) ..._v3(c), ..._povs])
      BackgroundsLoader.parseEntry('assets/backgrounds/$n')!,
  ]);

  setUp(() {
    svc.debugResetForTest();
    svc.setBundle(bundle);
    svc.debugRandom = Random(7);
  });
  tearDown(() => svc.debugRandom = Random());

  ({List<BackgroundEntry?> gestures, List<BackgroundEntry?> all}) play(
      String? coach) {
    final all = <BackgroundEntry?>[];
    void record() => all.add(svc.current.value);
    svc.current.addListener(record);
    svc.pickIntro(coach);
    final gestures = <BackgroundEntry?>[];
    for (var i = 0; i < 60; i++) {
      svc.pickForContext(
        BackgroundContext(
          mode: i.isEven ? 'rhythm' : 'hold',
          position: i.isEven ? 'mid' : 'throat',
          coach: coach,
          phase: switch (i) { 58 => 'final', 59 => 'post-final', _ => null },
          tier: i < 20 ? null : (i < 40 ? 'nu1' : 'nu2'),
        ),
        playerScene: true,
      );
      gestures.add(svc.current.value);
    }
    svc
      ..pickFail(coach)
      ..pickPunish(coach)
      ..pickMilestone(coach);
    svc.current.removeListener(record);
    return (gestures: gestures, all: all);
  }

  test('sans coach, aucun fond de coach : le fond neutre de bout en bout', () {
    final shown = play(null).all.whereType<BackgroundEntry>().map((e) => e.id);
    expect(shown, isEmpty);
    expect(svc.current.value, isNull);
  });

  test('avec coach, chaque geste montre un fond de cette coach', () {
    final gestures = play('lina').gestures;
    expect(gestures, everyElement(isNotNull));
    final coaches = gestures
        .where((e) => !e!.isPov)
        .expand((e) => e!.tagsByCategory[BackgroundTagCategory.coach] ?? {})
        .toSet();
    expect(coaches, {'lina'});
  });
}
