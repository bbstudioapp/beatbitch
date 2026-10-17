import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:flutter_test/flutter_test.dart';

BackgroundEntry _e(String basename) =>
    BackgroundsLoader.parseEntry('assets/backgrounds/$basename')!;

// Noms calqués sur les packs Lina et Hélène (`<id>_<tags>.webp`).
List<String> _pack(String coach) {
  final p = '$coach-pack';
  return [
    '$p-intro-1-x_$coach.webp',
    for (final n in ['', 'nu1', 'nu2']) ...[
      for (final m in ['hold', 'breath', 'fail', 'lick'])
        '$p-${n}x-$m-1-x_${m}_$coach${n.isEmpty ? '' : '_$n'}.webp',
      '$p-${n}x-rhythm-tip-1-x_rhythm_tip_$coach${n.isEmpty ? '' : '_$n'}.webp',
      if (n.isNotEmpty) ...[
        '$p-${n}x-final-1-x_final_${coach}_$n.webp',
        '$p-${n}x-postfinal-1-x_post-final_${coach}_$n.webp',
      ],
    ],
    '$p-strip1-1-x_${coach}_nu1.webp',
    '$p-strip2-1-x_${coach}_nu2.webp',
  ];
}

void main() {
  final svc = BackgroundsService.instance;
  setUp(() {
    svc.debugResetForTest();
    svc.setBundle(BackgroundsBundle(
        entries: [..._pack('lina'), ..._pack('helene')].map(_e).toList()));
  });

  BackgroundEntry now() => svc.current.value!;

  String slugOf(String id) =>
      CoachCatalog.defaults.firstWhere((c) => c.id == id).slug;

  test('l\'id de coach d\'Hélène donne le tag de ses fichiers', () {
    expect(slugOf('coach_02_helene'), 'helene');
    expect(slugOf('coach_01_lina'), 'lina');
    expect(BackgroundTagVocabulary.categorize('helene'),
        BackgroundTagCategory.coach);
  });

  test('les transitions d\'Hélène sont reconnues et lui appartiennent', () {
    for (final f in ['strip1-1-x_helene_nu1', 'strip2-1-x_helene_nu2']) {
      final e = _e('helene-pack-$f.webp');
      expect(e.isTierTransition, isTrue);
      expect(e.tags, contains('helene'));
    }
  });

  for (final coach in ['helene', 'lina']) {
    final other = coach == 'helene' ? 'lina' : 'helene';

    test('$coach : ses fonds de palier, jamais un fond de $other', () {
      final slug =
          slugOf(coach == 'helene' ? 'coach_02_helene' : 'coach_01_lina');
      const contexts = [
        (mode: 'hold', position: null, phase: null),
        (mode: 'breath', position: null, phase: null),
        (mode: 'lick', position: null, phase: null),
        (mode: 'rhythm', position: 'tip', phase: null),
        (mode: 'hold', position: null, phase: 'final'),
        (mode: 'hold', position: null, phase: 'post-final'),
      ];
      for (final tier in [null, 'nu1', 'nu2']) {
        for (final c in contexts) {
          if (tier == null && c.phase != null) continue;
          for (var i = 0; i < 15; i++) {
            svc.clear();
            if (tier != null) {
              svc.pickForContext(BackgroundContext(
                  mode: c.mode,
                  position: c.position,
                  coach: slug,
                  phase: c.phase,
                  tier: tier));
              while (now().isTierTransition) {
                expect(now().tags, contains(coach));
                expect(now().tags, isNot(contains(other)));
                svc.transitionFinished(now());
              }
            } else {
              svc.pickForContext(BackgroundContext(
                  mode: c.mode,
                  position: c.position,
                  coach: slug,
                  phase: c.phase));
            }
            final e = now();
            expect(e.tags, contains(coach), reason: '${e.path} @ $tier');
            expect(e.tags, isNot(contains(other)));
            expect(e.tier, tier, reason: '${e.path} @ $tier');
            if (c.phase != null) expect(e.tags, contains(c.phase));
            if (c.position != null && c.phase == null)
              expect(e.tags, contains(c.position));
          }
        }
      }
    });

    test('$coach : transitions de palier et fond d\'échec à lui', () {
      final slug =
          slugOf(coach == 'helene' ? 'coach_02_helene' : 'coach_01_lina');
      BackgroundContext at(String? tier) =>
          BackgroundContext(mode: 'hold', coach: slug, tier: tier);

      svc.pickForContext(at(null));
      svc.pickForContext(at('nu1'));
      expect(now().isTierTransition, isTrue);
      expect(now().tags, {coach, 'nu1'});
      svc.transitionFinished(now());
      svc.pickForContext(at('nu2'));
      expect(now().tags, {coach, 'nu2'});
      svc.transitionFinished(now());

      expect(svc.pickFail(slug), isTrue);
      expect(now().tags, {'fail', coach, 'nu2'});
    });
  }
}
