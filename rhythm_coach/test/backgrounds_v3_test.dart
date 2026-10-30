import 'dart:io';
import 'dart:math';

import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _packCoaches = [
  'lina',
  'helene',
  'jade',
  'victoria',
  'nyx',
  'morgan',
  'lilith',
];

List<String> _v3(String c) => [
      for (final (act, tier) in [
        ('a1', ''),
        ('a2', '_nu1'),
        ('a3', '_nu2')
      ]) ...[
        for (final m in ['beg', 'challenge', 'fail', 'milestone', 'punish'])
          '$c-v3-$act-${m}_${m}_$c$tier.webp',
        for (final n in ['01', '02', '03'])
          '$c-v3-$act-play-${n}_play_$c$tier.webp',
      ],
      '$c-v3-final_final_${c}_nu2.webp',
      '$c-v3-postfinal_post-final_${c}_nu2.webp',
      '$c-v3-strip1_${c}_nu1.webp',
      '$c-v3-strip2_${c}_nu2.webp',
    ];

List<String> _holdsAB(String c, String seed) => [
      for (final (prefix, tier) in [
        ('', ''),
        ('nu1-', '_nu1'),
        ('nu2-', '_nu2')
      ])
        for (final v in ['a', 'b'])
          '$c-pack-${prefix}hold-$v-$seed-anim_hold_$c$tier.webp',
    ];

const _marc = [
  'marc-v2-a1-play-debout-38201-s81_play_marc.webp',
  'marc-v2-a1-play-debout-38201-s82_play_marc.webp',
  'marc-v2-a1-play-debout-38201-s83_play_marc.webp',
  'marc-v2-a1-play-debout-38201-s85_play_marc.webp',
  'marc-v2-a1-play-fauteuil-38202-s81_play_marc.webp',
  'marc-v2-a1-play-fauteuil-38202-s82_play_marc.webp',
  'marc-v2-a1-play-fauteuil-38202-s83_play_marc.webp',
  'marc-v2-a1-play-fauteuil-38202-s84_play_marc.webp',
  'marc-v2-a1-play-fauteuil-38202-s85_play_marc.webp',
  'marc-v2-a2-play-debout-38201-s81_play_marc_nu1.webp',
  'marc-v2-a2-play-debout-38201-s82_play_marc_nu1.webp',
  'marc-v2-a2-play-debout-38201-s83_play_marc_nu1.webp',
  'marc-v2-a2-play-debout-38201-s84_play_marc_nu1.webp',
  'marc-v2-a2-play-debout-38201-s85_play_marc_nu1.webp',
  'marc-v2-a2-play-fauteuil-38201-s81_play_marc_nu1.webp',
  'marc-v2-a2-play-fauteuil-38201-s82_play_marc_nu1.webp',
  'marc-v2-a2-play-fauteuil-38201-s83_play_marc_nu1.webp',
  'marc-v2-a2-play-fauteuil-38201-s84_play_marc_nu1.webp',
  'marc-v2-a2-play-fauteuil-38201-s85_play_marc_nu1.webp',
  'marc-v2-a3-play-fauteuil-38301-s81_play_marc_nu2.webp',
  'marc-v2-a3-play-fauteuil-38301-s82_play_marc_nu2.webp',
  'marc-v2-a3-play-fauteuil-38302-s81_play_marc_nu2.webp',
  'marc-v2-a3-play-fauteuil-38302-s82_play_marc_nu2.webp',
  'marc-v2-a3-play-fauteuil-38302-s83_play_marc_nu2.webp',
  'marc-v2-a3-play-fauteuil-38302-s84_play_marc_nu2.webp',
  'marc-v2-a3-play-fauteuil-38302-s85_play_marc_nu2.webp',
  'marc-v2-a3-play-sexe-fella-51_play_marc_nu2.webp',
  'marc-v2-a3-play-sexe-lent-51_play_marc_nu2.webp',
  'marc-v2-a3-play-sexe-rapide-51_play_marc_nu2.webp',
  'marc-v2-a3-play-sexe-rapide-52_play_marc_nu2.webp',
  'marc-v2-final-53_final_marc_nu2.webp',
  'marc-v2-final-54_final_marc_nu2.webp',
  'marc-v2-strip1_marc_nu1.webp',
];

const _povs = [
  'pov-A-gag_pov_hold_full.webp',
  'pov-A-rhythm-full_pov_rhythm_full.webp',
  'pov-A-suckle_pov_suckle.webp',
  'pov-E-gag_pov_hold_full.webp',
  'pov-E-rhythm-full_pov_rhythm_full.webp',
  'pov-E-suckle_pov_suckle.webp',
  'pov-B-penchee-37101_pov_rhythm_throat_full.webp',
  'pov-B-reverse-cote-37401_pov_rhythm_throat_full.webp',
  'pov-B-reverse-cote-37402_pov_rhythm_throat_full.webp',
  'pov-B-reverse-dos-37402_pov_rhythm_throat_full.webp',
  'pov-C-genoux-37001_pov_rhythm_throat_full.webp',
  'pov-C-reverse-cote-37402_pov_rhythm_throat_full.webp',
  'pov-C-reverse-dos-37101_pov_rhythm_throat_full.webp',
  'pov-C-reverse-dos-37402_pov_rhythm_throat_full.webp',
  'pov-D-reverse-cote-37401_pov_rhythm_throat_full.webp',
  'pov-D-reverse-cote-37402_pov_rhythm_throat_full.webp',
  'pov-F-penchee-37101_pov_rhythm_throat_full.webp',
  'pov-F-profil-37101_pov_rhythm_throat_full.webp',
  'pov-F-reverse-cote-37401_pov_rhythm_throat_full.webp',
  'pov-F-reverse-dos-37401_pov_rhythm_throat_full.webp',
  'pov-G-4pattes-cote-37301_pov_rhythm_throat_full.webp',
  'pov-G-4pattes-cote-37303_pov_rhythm_throat_full.webp',
  'pov-G-reverse-cote-37401_pov_rhythm_throat_full.webp',
  'pov-G-reverse-cote-37402_pov_rhythm_throat_full.webp',
  'pov-G-reverse-dos-37101_pov_rhythm_throat_full.webp',
  'pov-G-reverse-dos-37102_pov_rhythm_throat_full.webp',
  'pov-G-reverse-dos-37401_pov_rhythm_throat_full.webp',
];

final _all = [
  for (final c in _packCoaches) ..._v3(c),
  ..._holdsAB('lina', '25002'),
  ..._holdsAB('helene', '26002'),
  ..._povs,
  ..._marc,
];

BackgroundEntry _e(String basename) =>
    BackgroundsLoader.parseEntry('assets/backgrounds/$basename')!;

const _modes = [
  'rhythm',
  'lick',
  'biffle',
  'hold',
  'breath',
  'beg',
  'freestyle',
  'hand',
  'suckle',
];

void main() {
  final svc = BackgroundsService.instance;
  final bundle = BackgroundsBundle(entries: _all.map(_e).toList());

  void load() {
    svc.debugResetForTest();
    svc.setBundle(bundle);
  }

  setUp(() => svc.debugRandom = Random(7));
  tearDown(() => svc.debugRandom = Random());

  final local = Directory('assets/backgrounds');
  final localNames = local.existsSync()
      ? local
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.webp'))
          .toSet()
      : <String>{};
  test('les noms du banc sont ceux du dossier d\'assets', () {
    expect(localNames, _all.toSet());
  }, skip: localNames.isEmpty ? 'fonds absents (gitignorés)' : false);

  test('chaque coach livrée a sa slug de fond, Lilith comprise', () {
    for (final c in CoachCatalog.defaults) {
      if (c.slug == 'marc') continue;
      expect(_packCoaches, contains(c.slug));
    }
    expect(BackgroundTagVocabulary.categorize('lilith'),
        BackgroundTagCategory.coach);
  });

  test('les noms v3 sont lus : moments, phases, paliers et transitions', () {
    for (final name in _all) {
      final e = _e(name);
      expect(e.id.contains('_'), isFalse, reason: '$name : tag non lu');
    }
    final play = _e('nyx-v3-a2-play-01_play_nyx_nu1.webp');
    expect(play.tagsByCategory[BackgroundTagCategory.moment], {'play'});
    expect(play.tier, 'nu1');
    expect(play.isTierTransition, isFalse);
    for (final m in ['punish', 'milestone']) {
      final e = _e('nyx-v3-a3-${m}_${m}_nyx_nu2.webp');
      expect(e.tagsByCategory[BackgroundTagCategory.moment], {m});
      expect(e.isTierTransition, isFalse);
    }
    expect(_e('nyx-v3-strip1_nyx_nu1.webp').isTierTransition, isTrue);
    expect(_e('nyx-v3-strip2_nyx_nu2.webp').isTierTransition, isTrue);
    expect(_e('nyx-v3-final_final_nyx_nu2.webp').tagsByCategory,
        containsPair(BackgroundTagCategory.phase, {'final'}));
    expect(_all.map(_e).where((e) => e.isTierTransition),
        hasLength(_packCoaches.length * 2 + 1));
  });

  for (final coach in [..._packCoaches, 'marc']) {
    final hasPack = _packCoaches.contains(coach);
    bool owned(BackgroundEntry e) =>
        e.tagsByCategory[BackgroundTagCategory.coach]?.contains(coach) ?? false;

    void expectAllowed(String where) {
      final e = svc.current.value;
      if (!hasPack) {
        expect(e == null || e.isPov || owned(e), isTrue,
            reason: '$where : ${e?.id}');
        return;
      }
      expect(e, isNotNull, reason: '$where : la coach n\'a pas de fond');
      expect(owned(e!) || e.isPov, isTrue,
          reason: '$where : fond d\'une autre coach ${e.id}');
      expect(e.tags.intersection({'punish', 'milestone'}), isEmpty,
          reason: '$where : moment jamais demandé ${e.id}');
    }

    void drain(String where) {
      for (var guard = 0; guard < 5; guard++) {
        final e = svc.current.value;
        if (e == null || !(e.isTierTransition || e.isPov)) return;
        expectAllowed('$where (transition)');
        svc.transitionFinished(e);
      }
      fail('$where : transition sans fin');
    }

    test('$coach : ses fonds seuls, à chaque palier et chaque moment', () {
      var picks = 0;
      for (final tier in [null, 'nu1', 'nu2']) {
        for (final phase in [null, 'challenge', 'final', 'post-final']) {
          for (final mode in _modes) {
            for (final pos in [null, ...Position.values.map((p) => p.name)]) {
              final where = '$tier/$phase/$mode/$pos';
              final ctx = BackgroundContext(
                  mode: mode,
                  position: pos,
                  coach: coach,
                  phase: phase,
                  tier: tier);
              load();
              svc.pickForContext(ctx);
              drain(where);
              expectAllowed(where);
              svc.pickForContext(ctx, playerScene: true);
              expectAllowed('$where (scène joueuse)');
              drain('$where (scène joueuse)');
              expectAllowed('$where (après scène)');
              final e = svc.current.value;
              if (hasPack && !e!.isPov) {
                expect(e.tier, tier, reason: '$where : palier ${e.id}');
              }
              svc.pickFail(coach);
              expectAllowed('$where (fail)');
              if (hasPack) {
                expect(svc.current.value!.tags, contains('fail'));
                expect(svc.current.value!.tier, tier);
              }
              for (final (moment, pick) in [
                ('punish', svc.pickPunish),
                ('milestone', svc.pickMilestone),
              ]) {
                final before = svc.current.value;
                expect(pick(coach), hasPack, reason: '$where : $moment');
                final e = svc.current.value;
                if (!hasPack) {
                  expect(e, before, reason: '$where : $moment sans pack');
                  continue;
                }
                expect(owned(e!), isTrue, reason: '$where : $moment ${e.id}');
                expect(e.tags, contains(moment), reason: '$where : ${e.id}');
                expect(e.tier, tier, reason: '$where : $moment ${e.id}');
              }
              picks++;
            }
          }
        }
        load();
        expect(svc.pickIntro(coach, tier: tier), isTrue);
        expect(
            svc.current.value?.id,
            hasPack
                ? '$coach-v3-a1-play-01'
                : '$coach-v2-a1-play-debout-38201-s81',
            reason: '$tier : intro');
      }
      expect(picks, 3 * 4 * _modes.length * (Position.values.length + 1));
    });

    if (!hasPack) continue;

    test('$coach : aucune scène joueuse ne coupe son intro', () {
      load();
      svc.debugRandom = _Zero();
      svc.pickIntro(coach);
      final ctx =
          BackgroundContext(mode: 'rhythm', position: 'full', coach: coach);
      svc.pickForContext(ctx, playerScene: true);
      expect(svc.current.value!.isPov, isFalse, reason: svc.current.value!.id);
      svc.pickForContext(ctx);
      expect(svc.current.value!.id, '$coach-v3-a1-play-01');
      svc.pickForContext(ctx, playerScene: true);
      expect(svc.current.value!.isPov, isTrue,
          reason: 'revenue à son premier plan après le premier geste');
    });

    test('$coach : l\'étape franchie joue une fois puis rend le fond d\'avant',
        () {
      for (final tier in [null, 'nu1', 'nu2']) {
        load();
        svc.pickForContext(BackgroundContext(
            mode: 'rhythm', position: 'tip', coach: coach, tier: tier));
        drain('$tier');
        final before = svc.current.value;
        expect(svc.pickMilestone(coach), isTrue);
        final milestone = svc.current.value!;
        expect(milestone.id, startsWith('$coach-v3-'));
        expect(milestone.isMilestone, isTrue, reason: milestone.id);
        svc.transitionFinished(milestone);
        expect(svc.current.value, before, reason: '$tier : ${before?.id}');
      }
    });

    test('$coach : le bon moment gagne quand le pack l\'a', () {
      String? shown(BackgroundContext ctx) {
        load();
        svc.pickForContext(ctx);
        while (svc.current.value!.isTierTransition) {
          svc.transitionFinished(svc.current.value!);
        }
        return svc.current.value!.id;
      }

      bool tagged(String? id, String tag) =>
          _all.map(_e).firstWhere((e) => e.id == id).tags.contains(tag);

      for (final tier in [null, 'nu1', 'nu2']) {
        for (var i = 0; i < 10; i++) {
          final rhythm = shown(BackgroundContext(
              mode: 'rhythm', position: 'tip', coach: coach, tier: tier));
          expect(tagged(rhythm, 'play'), isTrue, reason: '$tier : $rhythm');
          final beg =
              shown(BackgroundContext(mode: 'beg', coach: coach, tier: tier));
          expect(tagged(beg, 'beg'), isTrue, reason: '$tier : $beg');
          final challenge = shown(BackgroundContext(
              mode: 'rhythm',
              position: 'full',
              coach: coach,
              phase: 'challenge',
              tier: tier));
          expect(tagged(challenge, 'challenge'), isTrue,
              reason: '$tier : $challenge');
          final hold =
              shown(BackgroundContext(mode: 'hold', coach: coach, tier: tier));
          expect(
              tagged(
                  hold, coach == 'lina' || coach == 'helene' ? 'hold' : 'play'),
              isTrue,
              reason: '$tier : $hold');
        }
      }
      for (final phase in ['final', 'post-final']) {
        final id = shown(BackgroundContext(
            mode: 'rhythm',
            position: 'tip',
            coach: coach,
            phase: phase,
            tier: 'nu2'));
        expect(tagged(id, phase), isTrue, reason: '$phase : $id');
      }
    });
  }
}

class _Zero implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}
