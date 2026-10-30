import 'dart:math';

import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _marc = [
  'marc-v1-play-lent-51_play_marc.webp',
  'marc-v1-play-rapide-51_play_marc.webp',
  'marc-v1-play-rapide-52_play_marc.webp',
  'marc-v1-play-fella-51_play_marc.webp',
  'marc-v1-final-53_final_marc.webp',
  'marc-v1-final-54_final_marc.webp',
];

void main() {
  final svc = BackgroundsService.instance;
  final bundle = BackgroundsBundle(entries: [
    for (final n in [
      ..._v3('lina'),
      ..._v3('nyx'),
      ..._marc,
      'pov-A-rhythm-full_pov_rhythm_full.webp',
    ])
      BackgroundsLoader.parseEntry('assets/backgrounds/$n')!,
  ]);

  setUp(() {
    svc.debugResetForTest();
    svc.setBundle(bundle);
    svc.debugRandom = Random(7);
  });
  tearDown(() => svc.debugRandom = Random());

  Set<String>? coachOf(BackgroundEntry? e) =>
      e?.tagsByCategory[BackgroundTagCategory.coach];

  test('le nom de Marc est lu comme une coach', () {
    expect(BackgroundTagVocabulary.categorize('marc'),
        BackgroundTagCategory.coach);
  });

  test('séance avec Marc : ses fonds de bout en bout, jouissance au final', () {
    final all = <BackgroundEntry?>[];
    void record() => all.add(svc.current.value);
    svc.current.addListener(record);

    expect(svc.pickIntro('marc'), isTrue);
    expect(coachOf(svc.current.value), {'marc'});

    final gestures = <BackgroundEntry?>[];
    for (var i = 0; i < 60; i++) {
      svc.pickForContext(
        BackgroundContext(
          mode: i.isEven ? 'rhythm' : 'hold',
          position: i.isEven ? 'mid' : 'throat',
          coach: 'marc',
          phase: switch (i) { 58 => 'final', 59 => 'post-final', _ => null },
          tier: i < 20 ? null : (i < 40 ? 'nu1' : 'nu2'),
        ),
        playerScene: true,
      );
      gestures.add(svc.current.value);
    }
    svc
      ..pickFail('marc')
      ..pickPunish('marc')
      ..pickMilestone('marc');
    svc.current.removeListener(record);

    expect(gestures, everyElement(isNotNull));
    expect(gestures[58]!.id, startsWith('marc-v1-final-'));
    expect(gestures[59]!.id, startsWith('marc-v1-play-'));
    expect(
      gestures.take(58).map((e) => e!.id),
      everyElement(isNot(startsWith('marc-v1-final-'))),
    );
    final shown = all.whereType<BackgroundEntry>().where((e) => !e.isPov);
    expect(shown, isNotEmpty);
    expect(shown.map(coachOf), everyElement({'marc'}));
  });
}
