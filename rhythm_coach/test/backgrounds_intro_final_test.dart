import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:flutter_test/flutter_test.dart';

BackgroundEntry _e(String basename) =>
    BackgroundsLoader.parseEntry('assets/backgrounds/$basename')!;

// Noms calqués sur le pack Lina (`<id>_<tags>.webp`).
final _lingerie = [
  'lina-pack-intro-1-x_lina.webp',
  'lina-pack-hold-1-x_hold_lina.webp',
  'lina-pack-rhythm-tip-1-x_rhythm_tip_lina.webp',
  'lina-pack-fail-1-x_fail_lina.webp',
];
List<String> _tier(String n) => [
      'lina-pack-$n-hold-1-x_hold_lina_$n.webp',
      'lina-pack-$n-rhythm-tip-1-x_rhythm_tip_lina_$n.webp',
      'lina-pack-$n-fail-1-x_fail_lina_$n.webp',
      'lina-pack-$n-final-1-x_final_lina_$n.webp',
      'lina-pack-$n-postfinal-1-x_post-final_lina_$n.webp',
    ];
const _strips = [
  'lina-pack-strip1-1-x_lina_nu1.webp',
  'lina-pack-strip2-1-x_lina_nu2.webp',
];

void _load(List<String> names) => BackgroundsService.instance
    .setBundle(BackgroundsBundle(entries: names.map(_e).toList()));

BackgroundEntry get _now => BackgroundsService.instance.current.value!;

BackgroundContext _ctx({
  String mode = 'hold',
  String? position,
  String? phase,
  String? tier,
}) =>
    BackgroundContext(
        mode: mode,
        position: position,
        coach: 'lina',
        phase: phase,
        tier: tier);

void main() {
  final svc = BackgroundsService.instance;
  setUp(svc.debugResetForTest);

  const introNu1 = 'helene-pack-nu1-intro-26002-ltx-pp-s26002_helene_nu1.webp';
  const introNu2 = 'helene-pack-nu2-intro-26002-anim_helene_nu2.webp';
  const linaIntroNu1 = 'lina-pack-nu1-intro-26002-ltx-pp-s26002_lina_nu1.webp';

  test('l\'intro d\'un palier est une intro, pas une transition', () {
    for (final n in [introNu1, introNu2]) {
      final e = _e(n);
      expect(e.isIntro, isTrue, reason: 'témoin : $n est bien une intro');
      expect(e.tier, isNotNull, reason: 'témoin : le palier est lu');
      expect(e.isTierTransition, isFalse,
          reason: '$n porte coach + palier seuls, comme un strip');
    }
    expect(_e(_strips[0]).isTierTransition, isTrue,
        reason: 'témoin : le strip reste une transition');
  });

  test('passage lingerie → nu1 : jamais l\'intro nu1 à la place du strip', () {
    var intros = 0;
    const runs = 200;
    for (var i = 0; i < runs; i++) {
      svc.debugResetForTest();
      _load([..._lingerie, ..._tier('nu1'), _strips[0], linaIntroNu1]);
      svc.pickForContext(_ctx());
      svc.pickForContext(_ctx(tier: 'nu1'));
      expect(_now.isIntro || _now.isTierTransition, isTrue,
          reason: 'témoin : une transition est en cours');
      if (_now.isIntro) intros++;
    }
    expect(intros, 0,
        reason: 'l\'intro a été jouée comme transition $intros fois sur $runs');
  });

  test('l\'intro d\'un palier reste trouvée par pickIntro', () {
    _load([..._lingerie, ..._tier('nu1'), _strips[0], linaIntroNu1]);
    expect(svc.pickIntro('lina', tier: 'nu1'), isTrue);
    expect(_now.id, _e(linaIntroNu1).id);
  });

  test('step final en rhythm+position à nu1 : le fond final gagne', () {
    var finals = 0;
    const runs = 200;
    for (var i = 0; i < runs; i++) {
      svc.debugResetForTest();
      _load([..._lingerie, ..._tier('nu1')]);
      svc.pickForContext(
          _ctx(mode: 'rhythm', position: 'tip', phase: 'final', tier: 'nu1'));
      expect(_now.isTierTransition, isFalse,
          reason: 'témoin : le banc est sorti de la transition');
      if (_now.tagsByCategory.containsKey(BackgroundTagCategory.phase)) {
        finals++;
      }
    }
    expect(finals, runs, reason: 'fond final tiré $finals fois sur $runs');
  });
}
