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

void main() {
  final svc = BackgroundsService.instance;
  final bundle = BackgroundsBundle(entries: [
    for (final c in _coaches)
      for (final n in _v3(c))
        BackgroundsLoader.parseEntry('assets/backgrounds/$n')!,
  ]);

  setUp(() {
    svc.debugResetForTest();
    svc.setBundle(bundle);
    svc.debugRandom = Random(7);
  });
  tearDown(() => svc.debugRandom = Random());

  List<BackgroundEntry> playWithoutCoach() {
    final shown = <BackgroundEntry>[];
    for (var i = 0; i < 60; i++) {
      svc.pickForContext(BackgroundContext(
        mode: i.isEven ? 'rhythm' : 'hold',
        position: i.isEven ? 'mid' : 'throat',
      ));
      final cur = svc.current.value;
      if (cur != null) shown.add(cur);
    }
    return shown;
  }

  test('sans coach, un geste ordinaire ne montre ni final ni fail ni punition',
      () {
    final shown = playWithoutCoach();
    expect(shown, isNotEmpty);
    final offPhase = shown
        .where((e) =>
            e.tags.contains('final') ||
            e.tags.contains('post-final') ||
            e.tags.contains('fail') ||
            e.tags.contains('punish'))
        .map((e) => e.id)
        .toSet();
    expect(offPhase, isEmpty,
        reason: 'un fond de phase ou de moment hors de son moment');
  });

  test('sans coach, la séance garde une seule coach', () {
    final coaches = playWithoutCoach()
        .expand((e) => e.tagsByCategory[BackgroundTagCategory.coach] ?? {})
        .toSet();
    expect(coaches, hasLength(1), reason: 'coachs montrées : $coaches');
  });
}
