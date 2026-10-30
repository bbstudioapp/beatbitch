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

  void load() {
    svc.debugResetForTest();
    svc.setBundle(BackgroundsBundle(
        entries: [..._pack('lina'), ..._pack('helene')].map(_e).toList()));
  }

  // Aucun fond des packs ne porte le tag `suckle`.
  test('séance de Lina sur un « gobe » : jamais un fond d\'Hélène', () {
    final strangers = <String>{};
    var picks = 0;
    for (final tier in [null, 'nu1', 'nu2']) {
      for (final position in [null, 'head']) {
        for (var i = 0; i < 40; i++) {
          load();
          svc.pickForContext(BackgroundContext(
              mode: 'suckle', position: position, coach: 'lina', tier: tier));
          while (svc.current.value!.isTierTransition) {
            svc.transitionFinished(svc.current.value!);
          }
          picks++;
          if (svc.current.value!.tags.contains('helene')) {
            strangers.add('${svc.current.value!.path} @ $tier/$position');
          }
        }
      }
    }
    expect(picks, 240, reason: 'témoin : tous les tirages ont eu lieu');
    expect(strangers, isEmpty,
        reason: 'fonds d\'Hélène tirés pour Lina : $strangers');
  });

  test('un « gobe » de Lina garde un fond de Lina à chaque palier', () {
    for (final tier in [null, 'nu1', 'nu2']) {
      load();
      svc.pickForContext(
          BackgroundContext(mode: 'suckle', coach: 'lina', tier: tier));
      while (svc.current.value!.isTierTransition) {
        svc.transitionFinished(svc.current.value!);
      }
      expect(svc.current.value!.tags, contains('lina'), reason: '@ $tier');
    }
  });
}
