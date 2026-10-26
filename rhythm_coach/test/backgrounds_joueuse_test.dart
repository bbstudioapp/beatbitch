import 'dart:math';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/play_once_image.dart';
import 'package:beat_bitch/widgets/session_background.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _load(List<String> names) =>
    BackgroundsService.instance.setBundle(BackgroundsBundle(entries: [
      for (final n in names)
        BackgroundsLoader.parseEntry('assets/backgrounds/$n.webp')!,
    ]));

BackgroundEntry get _now => BackgroundsService.instance.current.value!;

BackgroundContext _ctx(String mode,
        {String? position,
        String coach = 'lina',
        String? phase,
        String? tier}) =>
    BackgroundContext(
        mode: mode, position: position, coach: coach, phase: phase, tier: tier);

const _handRaised = [
  'helene-pack-hold-26002-ltx-pp-s26002_hold_helene',
  'helene-pack-nu1-hold-26002-ltx-pp-s26002_hold_helene_nu1',
  'helene-pack-nu2-hold-26002-anim_hold_helene_nu2',
  'lina-pack-hold-25001-ltx-pp-s25001_hold_lina',
  'lina-pack-hold-25002-ltx-pp-s25002_hold_lina',
  'lina-pack-nu1-hold-25001-anim_hold_lina_nu1',
  'lina-pack-nu1-hold-25002-anim_hold_lina_nu1',
  'lina-pack-nu2-hold-25001-anim_hold_lina_nu2',
  'lina-pack-nu2-hold-25002-anim_hold_lina_nu2',
];

const _povs = [
  'pov-E-suckle_pov_suckle',
  'pov-E-rhythm-full_pov_rhythm_full',
  'pov-E-gag_pov_hold_full',
];

const _pack = [
  'helene-pack-beg-26002-ltx-pp-s26002_beg_helene',
  'helene-pack-biffle-26002-ltx-pp-s26002_biffle_helene',
  'helene-pack-breath-26002-ltx-pp-s26002_breath_helene',
  'helene-pack-fail-26002-ltx-pp-s26002_fail_helene',
  'helene-pack-freestyle-26002-ltx-pp-s26002_freestyle_helene',
  'helene-pack-hand-26002-ltx-pp-s26002_hand_helene',
  'helene-pack-hold-26002-ltx-pp-s26002_hold_helene',
  'helene-pack-intro-26002-ltx-pp-s26002_helene',
  'helene-pack-lick-26002-ltx-pp-s26002_lick_helene',
  'helene-pack-nu1-beg-26002-ltx-pp-s26002_beg_helene_nu1',
  'helene-pack-nu1-biffle-26002-ltx-pp-s26002_biffle_helene_nu1',
  'helene-pack-nu1-breath-26002-ltx-pp-s26002_breath_helene_nu1',
  'helene-pack-nu1-fail-26002-ltx-pp-s26002_fail_helene_nu1',
  'helene-pack-nu1-final-26002-ltx-pp-s26002_final_helene_nu1',
  'helene-pack-nu1-freestyle-26002-ltx-pp-s26002_freestyle_helene_nu1',
  'helene-pack-nu1-hand-26002-ltx-pp-s26002_hand_helene_nu1',
  'helene-pack-nu1-hold-26002-ltx-pp-s26002_hold_helene_nu1',
  'helene-pack-nu1-intro-26002-ltx-pp-s26002_helene_nu1',
  'helene-pack-nu1-lick-26002-ltx-pp-s26002_lick_helene_nu1',
  'helene-pack-nu1-postfinal-26002-ltx-pp-s26002_post-final_helene_nu1',
  'helene-pack-nu1-rhythm-full-26002-ltx-pp-s26002_rhythm_full_helene_nu1',
  'helene-pack-nu1-rhythm-head-26002-ltx-pp-s26002_rhythm_head_helene_nu1',
  'helene-pack-nu1-rhythm-mid-26002-ltx-pp-s26002_rhythm_mid_helene_nu1',
  'helene-pack-nu1-rhythm-throat-26002-ltx-pp-s26002_rhythm_throat_helene_nu1',
  'helene-pack-nu1-rhythm-tip-26002-ltx-pp-s26002_rhythm_tip_helene_nu1',
  'helene-pack-nu2-beg-26002-anim_beg_helene_nu2',
  'helene-pack-nu2-biffle-26002-anim_biffle_helene_nu2',
  'helene-pack-nu2-breath-26002-anim_breath_helene_nu2',
  'helene-pack-nu2-fail-26002-anim_fail_helene_nu2',
  'helene-pack-nu2-final-26002-anim_final_helene_nu2',
  'helene-pack-nu2-freestyle-26002-anim_freestyle_helene_nu2',
  'helene-pack-nu2-hand-26002-anim_hand_helene_nu2',
  'helene-pack-nu2-hold-26002-anim_hold_helene_nu2',
  'helene-pack-nu2-intro-26002-anim_helene_nu2',
  'helene-pack-nu2-lick-26002-anim_lick_helene_nu2',
  'helene-pack-nu2-postfinal-26002-anim_post-final_helene_nu2',
  'helene-pack-nu2-rhythm-full-26002-anim_rhythm_full_helene_nu2',
  'helene-pack-nu2-rhythm-head-26002-anim_rhythm_head_helene_nu2',
  'helene-pack-nu2-rhythm-mid-26002-anim_rhythm_mid_helene_nu2',
  'helene-pack-nu2-rhythm-throat-26002-anim_rhythm_throat_helene_nu2',
  'helene-pack-nu2-rhythm-tip-26002-anim_rhythm_tip_helene_nu2',
  'helene-pack-rhythm-full-26002-ltx-pp-s26002_rhythm_full_helene',
  'helene-pack-rhythm-head-26002-ltx-pp-s26002_rhythm_head_helene',
  'helene-pack-rhythm-mid-26002-ltx-pp-s26002_rhythm_mid_helene',
  'helene-pack-rhythm-throat-26002-ltx-pp-s26002_rhythm_throat_helene',
  'helene-pack-rhythm-tip-26002-ltx-pp-s26002_rhythm_tip_helene',
  'helene-pack-strip1-26002-anim_helene_nu1',
  'helene-pack-strip2-26002-anim_helene_nu2',
  'lina-pack-beg-25001-ltx-pp-s25001_beg_lina',
  'lina-pack-beg-25002-ltx-pp-s25002_beg_lina',
  'lina-pack-biffle-25001-ltx-pp-s25001_biffle_lina',
  'lina-pack-biffle-25002-ltx-pp-s25002_biffle_lina',
  'lina-pack-breath-25001-ltx-pp-s25001_breath_lina',
  'lina-pack-breath-25002-ltx-pp-s25002_breath_lina',
  'lina-pack-fail-25001-ltx-pp-s25001_fail_lina',
  'lina-pack-fail-25002-ltx-pp-s25002_fail_lina',
  'lina-pack-freestyle-25001-ltx-pp-s25001_freestyle_lina',
  'lina-pack-freestyle-25002-ltx-pp-s25002_freestyle_lina',
  'lina-pack-hand-25001-ltx-pp-s25001_hand_lina',
  'lina-pack-hand-25002-ltx-pp-s25002_hand_lina',
  'lina-pack-hold-25001-ltx-pp-s25001_hold_lina',
  'lina-pack-hold-25002-ltx-pp-s25002_hold_lina',
  'lina-pack-intro-25001-ltx-pp-s25001_lina',
  'lina-pack-intro-25002-ltx-pp-s25002_lina',
  'lina-pack-lick-25001-ltx-pp-s25001_lick_lina',
  'lina-pack-lick-25002-ltx-pp-s25002_lick_lina',
  'lina-pack-nu1-beg-25001-anim_beg_lina_nu1',
  'lina-pack-nu1-beg-25002-anim_beg_lina_nu1',
  'lina-pack-nu1-biffle-25001-anim_biffle_lina_nu1',
  'lina-pack-nu1-biffle-25002-anim_biffle_lina_nu1',
  'lina-pack-nu1-breath-25001-anim_breath_lina_nu1',
  'lina-pack-nu1-breath-25002-anim_breath_lina_nu1',
  'lina-pack-nu1-fail-25001-anim_fail_lina_nu1',
  'lina-pack-nu1-fail-25002-anim_fail_lina_nu1',
  'lina-pack-nu1-final-25001-anim_final_lina_nu1',
  'lina-pack-nu1-final-25002-anim_final_lina_nu1',
  'lina-pack-nu1-freestyle-25001-anim_freestyle_lina_nu1',
  'lina-pack-nu1-freestyle-25002-anim_freestyle_lina_nu1',
  'lina-pack-nu1-hand-25001-anim_hand_lina_nu1',
  'lina-pack-nu1-hand-25002-anim_hand_lina_nu1',
  'lina-pack-nu1-hold-25001-anim_hold_lina_nu1',
  'lina-pack-nu1-hold-25002-anim_hold_lina_nu1',
  'lina-pack-nu1-lick-25001-anim_lick_lina_nu1',
  'lina-pack-nu1-lick-25002-anim_lick_lina_nu1',
  'lina-pack-nu1-postfinal-25001-anim_post-final_lina_nu1',
  'lina-pack-nu1-postfinal-25002-anim_post-final_lina_nu1',
  'lina-pack-nu1-rhythm-full-25001-anim_rhythm_full_lina_nu1',
  'lina-pack-nu1-rhythm-full-25002-anim_rhythm_full_lina_nu1',
  'lina-pack-nu1-rhythm-head-25001-anim_rhythm_head_lina_nu1',
  'lina-pack-nu1-rhythm-head-25002-anim_rhythm_head_lina_nu1',
  'lina-pack-nu1-rhythm-mid-25001-anim_rhythm_mid_lina_nu1',
  'lina-pack-nu1-rhythm-mid-25002-anim_rhythm_mid_lina_nu1',
  'lina-pack-nu1-rhythm-throat-25001-anim_rhythm_throat_lina_nu1',
  'lina-pack-nu1-rhythm-throat-25002-anim_rhythm_throat_lina_nu1',
  'lina-pack-nu1-rhythm-tip-25001-anim_rhythm_tip_lina_nu1',
  'lina-pack-nu1-rhythm-tip-25002-anim_rhythm_tip_lina_nu1',
  'lina-pack-nu2-beg-25001-anim_beg_lina_nu2',
  'lina-pack-nu2-beg-25002-anim_beg_lina_nu2',
  'lina-pack-nu2-biffle-25001-anim_biffle_lina_nu2',
  'lina-pack-nu2-biffle-25002-anim_biffle_lina_nu2',
  'lina-pack-nu2-breath-25001-anim_breath_lina_nu2',
  'lina-pack-nu2-breath-25002-anim_breath_lina_nu2',
  'lina-pack-nu2-fail-25001-anim_fail_lina_nu2',
  'lina-pack-nu2-fail-25002-anim_fail_lina_nu2',
  'lina-pack-nu2-final-25001-anim_final_lina_nu2',
  'lina-pack-nu2-final-25002-anim_final_lina_nu2',
  'lina-pack-nu2-freestyle-25001-anim_freestyle_lina_nu2',
  'lina-pack-nu2-freestyle-25002-anim_freestyle_lina_nu2',
  'lina-pack-nu2-hand-25001-anim_hand_lina_nu2',
  'lina-pack-nu2-hand-25002-anim_hand_lina_nu2',
  'lina-pack-nu2-hold-25001-anim_hold_lina_nu2',
  'lina-pack-nu2-hold-25002-anim_hold_lina_nu2',
  'lina-pack-nu2-lick-25001-anim_lick_lina_nu2',
  'lina-pack-nu2-lick-25002-anim_lick_lina_nu2',
  'lina-pack-nu2-postfinal-25001-anim_post-final_lina_nu2',
  'lina-pack-nu2-postfinal-25002-anim_post-final_lina_nu2',
  'lina-pack-nu2-rhythm-full-25001-anim_rhythm_full_lina_nu2',
  'lina-pack-nu2-rhythm-full-25002-anim_rhythm_full_lina_nu2',
  'lina-pack-nu2-rhythm-head-25001-anim_rhythm_head_lina_nu2',
  'lina-pack-nu2-rhythm-head-25002-anim_rhythm_head_lina_nu2',
  'lina-pack-nu2-rhythm-mid-25001-anim_rhythm_mid_lina_nu2',
  'lina-pack-nu2-rhythm-mid-25002-anim_rhythm_mid_lina_nu2',
  'lina-pack-nu2-rhythm-throat-25001-anim_rhythm_throat_lina_nu2',
  'lina-pack-nu2-rhythm-throat-25002-anim_rhythm_throat_lina_nu2',
  'lina-pack-nu2-rhythm-tip-25001-anim_rhythm_tip_lina_nu2',
  'lina-pack-nu2-rhythm-tip-25002-anim_rhythm_tip_lina_nu2',
  'lina-pack-rhythm-full-25001-ltx-pp-s25001_rhythm_full_lina',
  'lina-pack-rhythm-full-25002-ltx-pp-s25002_rhythm_full_lina',
  'lina-pack-rhythm-head-25001-ltx-pp-s25001_rhythm_head_lina',
  'lina-pack-rhythm-head-25002-ltx-pp-s25002_rhythm_head_lina',
  'lina-pack-rhythm-mid-25001-ltx-pp-s25001_rhythm_mid_lina',
  'lina-pack-rhythm-mid-25002-ltx-pp-s25002_rhythm_mid_lina',
  'lina-pack-rhythm-throat-25001-ltx-pp-s25001_rhythm_throat_lina',
  'lina-pack-rhythm-throat-25002-ltx-pp-s25002_rhythm_throat_lina',
  'lina-pack-rhythm-tip-25001-ltx-pp-s25001_rhythm_tip_lina',
  'lina-pack-rhythm-tip-25002-ltx-pp-s25002_rhythm_tip_lina',
  'lina-pack-strip1-25001-anim_lina_nu1',
  'lina-pack-strip1-25002-anim_lina_nu1',
  'lina-pack-strip2-25001-anim_lina_nu2',
  'lina-pack-strip2-25002-anim_lina_nu2',
  'pov-A-gag_pov_hold_full',
  'pov-A-rhythm-full_pov_rhythm_full',
  'pov-A-suckle_pov_suckle',
  'pov-E-gag_pov_hold_full',
  'pov-E-rhythm-full_pov_rhythm_full',
  'pov-E-suckle_pov_suckle',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = BackgroundsService.instance;
  tearDown(() {
    svc.debugResetForTest();
    svc.debugRandom = Random();
  });

  group('tenues où la coach lève la main', () {
    test('ne sont jamais tirées', () {
      _load([..._handRaised, 'a_rhythm_full_lina']);
      svc.pickForContext(_ctx('rhythm', position: 'full'));
      for (var i = 0; i < 50; i++) {
        svc.pickForContext(_ctx('hold', position: 'full'));
        expect(_now.id, 'a');
      }
    });

    for (final (coach, pack) in [('helene', '26002'), ('lina', '25001')]) {
      test('$coach sans tenue, garde son geste au palier atteint', () {
        _load([
          ..._handRaised,
          '$coach-pack-rhythm-full-$pack-ltx-pp-s${pack}_rhythm_full_$coach',
          '$coach-pack-nu1-rhythm-full-$pack-ltx-pp-s${pack}_rhythm_full_${coach}_nu1',
          '$coach-pack-strip1-$pack-anim_${coach}_nu1',
          'jade-pack-rhythm-full-1_rhythm_full_jade',
          '$coach-pack-intro-$pack-ltx-pp-s${pack}_$coach',
        ]);
        svc.pickIntro(coach);
        svc.pickForContext(_ctx('rhythm', position: 'full', coach: coach));
        svc.pickForContext(_ctx('hold', position: 'full', coach: coach));
        expect(_now.id, '$coach-pack-rhythm-full-$pack-ltx-pp-s$pack');

        svc.pickForContext(
            _ctx('hold', position: 'full', coach: coach, tier: 'nu1'));
        expect(_now.isTierTransition, isTrue);
        svc.transitionFinished(_now);
        expect(_now.id, '$coach-pack-nu1-rhythm-full-$pack-ltx-pp-s$pack',
            reason:
                'après la transition, le geste précédent au nouveau palier');
      });
    }
    test('une tenue montrable passe devant une tenue retirée', () {
      _load([..._handRaised, 'z_hold_lina', 'lina-pack-intro-25001_lina']);
      svc.pickForContext(_ctx('hold', position: 'full'));
      expect(_now.id, 'z');
    });

    test("une séance neuve n'hérite pas du geste de la précédente", () {
      _load(
          [..._handRaised, 'a_rhythm_full_lina', 'lina-pack-intro-25001_lina']);
      svc.pickForContext(_ctx('rhythm', position: 'full'));
      svc.clear();
      svc.pickIntro('lina');
      svc.pickForContext(_ctx('hold', position: 'full'));
      expect(_now.isIntro, isTrue);
    });

    test('pendant une tenue, la bande de palier laisse place à la coach', () {
      svc.debugRandom = _Zero();
      const nu1Tip = 'lina-pack-nu1-rhythm-tip-25001-anim';
      const nu1Full = 'lina-pack-nu1-rhythm-full-25001-anim';
      _load([
        ..._handRaised,
        'lina-pack-rhythm-full-25001-ltx-pp-s25001_rhythm_full_lina',
        'helene-pack-nu1-rhythm-full-26002-ltx-pp-s26002_rhythm_full_helene_nu1',
        'lina-pack-intro-25001-ltx-pp-s25001_lina',
        'lina-pack-lick-25001-ltx-pp-s25001_lick_lina',
        'lina-pack-strip1-25001-anim_lina_nu1',
        'lina-pack-nu1-fail-25001-anim_fail_lina_nu1',
        '${nu1Tip}_rhythm_tip_lina_nu1',
        '${nu1Full}_rhythm_full_lina_nu1',
      ]);
      svc.pickIntro('lina');
      svc.pickForContext(_ctx('hold', position: 'full'));
      expect(_now.isIntro, isTrue, reason: 'aucun geste avant la tenue');
      svc.pickForContext(_ctx('hold', position: 'full', tier: 'nu1'));
      expect(_now.isTierTransition, isTrue);
      svc.transitionFinished(_now);
      expect(_now.id, nu1Full, reason: 'à la même profondeur');

      svc.clear();
      svc.pickForContext(_ctx('lick'));
      svc.pickForContext(_ctx('hold', position: 'full', tier: 'nu1'));
      svc.transitionFinished(_now);
      expect(_now.id, nu1Full, reason: 'le geste précédent manque au palier');

      svc.clear();
      svc.pickForContext(_ctx('lick'));
      svc.pickForContext(_ctx('hold', position: 'balls', tier: 'nu1'));
      svc.transitionFinished(_now);
      expect(_now.id, nu1Tip, reason: 'aucun geste à cette profondeur');
    });

    test("pendant une tenue, la coach n'emprunte pas le fond d'une autre phase",
        () {
      svc.debugRandom = _Zero();
      const tip = 'lina-pack-nu1-rhythm-tip-25001-anim';
      const finalFull = 'lina-pack-nu1-final-rhythm-full-25001-anim';
      _load([
        ..._handRaised,
        'lina-pack-lick-25001-ltx-pp-s25001_lick_lina',
        'lina-pack-strip1-25001-anim_lina_nu1',
        '${tip}_rhythm_tip_lina_nu1',
        'lina-pack-nu1-challenge-hold-full-25001-anim_challenge_hold_full_lina_nu1',
        '${finalFull}_final_rhythm_full_lina_nu1',
      ]);
      svc.pickForContext(_ctx('lick'));
      svc.pickForContext(_ctx('hold', position: 'full', tier: 'nu1'));
      svc.transitionFinished(_now);
      expect(_now.id, tip, reason: 'tenue hors phase');

      svc.clear();
      svc.pickForContext(_ctx('lick'));
      svc.pickForContext(
          _ctx('hold', position: 'full', phase: 'final', tier: 'nu1'));
      svc.transitionFinished(_now);
      expect(_now.id, finalFull, reason: 'tenue de la phase finale');
    });

    for (final coach in ['lina', 'helene']) {
      for (final tier in ['nu1', 'nu2']) {
        for (final position in ['balls', null]) {
          test(
              '$coach $tier, 1re tenue $position sans fond de rythme à '
              'sa profondeur : la coach suce', () {
            _load(_pack);
            for (var seed = 0; seed < 60; seed++) {
              svc.clear();
              svc.debugRandom = Random(seed);
              svc.pickForContext(
                  _ctx('hold', position: position, coach: coach, tier: tier));
              while (_now.isTierTransition) {
                svc.transitionFinished(_now);
              }
              expect(_now.tagsByCategory[BackgroundTagCategory.mode],
                  contains('rhythm'),
                  reason: 'graine $seed : ${_now.id}');
            }
          });
        }
      }
    }

    for (final coach in ['lina', 'helene']) {
      for (final tier in ['nu1', 'nu2']) {
        for (final mode in [
          'lick',
          'beg',
          'biffle',
          'hand',
          'breath',
          'freestyle',
        ]) {
          test('$coach $tier, tenue après $mode : la coach suce', () {
            _load(_pack);
            for (var seed = 0; seed < 40; seed++) {
              svc.clear();
              svc.debugRandom = Random(seed);
              svc.pickForContext(_ctx(mode, coach: coach, tier: tier));
              while (_now.isTierTransition) {
                svc.transitionFinished(_now);
              }
              expect(_now.tagsByCategory[BackgroundTagCategory.mode],
                  contains(mode),
                  reason: 'graine $seed : le geste est bien affiché');
              svc.pickForContext(
                  _ctx('hold', position: 'throat', coach: coach, tier: tier));
              expect(_now.tagsByCategory[BackgroundTagCategory.mode],
                  contains('rhythm'),
                  reason: 'graine $seed : ${_now.id}');
              expect(_now.tagsByCategory[BackgroundTagCategory.position],
                  contains('throat'),
                  reason: 'graine $seed : même profondeur que la tenue');
              final held = _now;
              svc.pickForContext(
                  _ctx('hold', position: 'throat', coach: coach, tier: tier));
              expect(_now, held, reason: 'graine $seed : tenue suivante');
            }
          });
        }

        test('$coach $tier, tenue après un rythme : la coach le garde', () {
          _load(_pack);
          for (var seed = 0; seed < 40; seed++) {
            svc.clear();
            svc.debugRandom = Random(seed);
            svc.pickForContext(
                _ctx('rhythm', position: 'mid', coach: coach, tier: tier));
            while (_now.isTierTransition) {
              svc.transitionFinished(_now);
            }
            final rhythm = _now;
            expect(rhythm.tagsByCategory[BackgroundTagCategory.position],
                contains('mid'));
            svc.pickForContext(
                _ctx('hold', position: 'throat', coach: coach, tier: tier));
            expect(_now, rhythm, reason: 'graine $seed : ${_now.id}');
          }
        });
      }
    }
  });

  group('scènes de joueuse', () {
    test("s'intercalent environ une fois sur trois, jamais deux d'affilée", () {
      svc.debugRandom = Random(7);
      _load([
        'a_rhythm_full_lina',
        'b_rhythm_full_lina',
        ..._povs,
      ]);
      final ctx = _ctx('rhythm', position: 'full');
      svc.pickForContext(ctx);
      var scenes = 0;
      for (var i = 0; i < 600; i++) {
        expect(_now.isPov, isFalse);
        svc.pickForContext(ctx, playerScene: true);
        if (!_now.isPov) continue;
        scenes++;
        expect(_now.id, 'pov-E-rhythm-full');
        svc.transitionFinished(_now);
      }
      expect(scenes, inInclusiveRange(180, 240));
    });

    test('jouée une fois, puis la coach ; un nouveau step la coupe', () {
      svc.debugRandom = _Zero();
      _load(['a_rhythm_full_lina', 'b_lick_lina', ..._povs]);
      svc.pickForContext(_ctx('rhythm', position: 'full'));
      svc.pickForContext(_ctx('rhythm', position: 'full'), playerScene: true);
      expect(_now.id, 'pov-E-rhythm-full');
      svc.transitionFinished(_now);
      expect(_now.id, 'a');

      svc.pickForContext(_ctx('rhythm', position: 'full'), playerScene: true);
      expect(_now.isPov, isTrue);
      svc.pickForContext(_ctx('rhythm', position: 'full'), playerScene: true);
      expect(_now.id, 'a', reason: "pas deux scènes d'affilée");
      svc.pickForContext(_ctx('rhythm', position: 'full'), playerScene: true);
      svc.pickForContext(_ctx('lick'), playerScene: true);
      expect(_now.id, 'b', reason: 'le step suivant coupe la scène');
    });

    test('suivent le mode et la position, communes à toutes les coachs', () {
      svc.debugRandom = _Zero();
      _load([
        'a_rhythm_lina',
        'b_hold_lina',
        'c_suckle_lina',
        'd_lick_lina',
        'e_hold_helene_nu2',
        ..._povs,
      ]);
      String? sceneFor(BackgroundContext ctx) {
        svc.pickForContext(ctx);
        svc.pickForContext(ctx, playerScene: true);
        final id = _now.isPov ? _now.id : null;
        if (_now.isPov) svc.transitionFinished(_now);
        return id;
      }

      expect(sceneFor(_ctx('rhythm', position: 'full')), 'pov-E-rhythm-full');
      expect(sceneFor(_ctx('rhythm', position: 'tip')), isNull);
      expect(sceneFor(_ctx('hold', position: 'full')), 'pov-E-gag');
      expect(sceneFor(_ctx('hold', position: 'mid')), isNull);
      expect(sceneFor(_ctx('suckle', position: 'head')), 'pov-E-suckle');
      expect(sceneFor(_ctx('lick', position: 'full')), isNull);
      expect(
          sceneFor(
              _ctx('hold', position: 'full', coach: 'helene', tier: 'nu2')),
          'pov-E-gag');
    });

    test('la scène « suckle » est réservée au gland', () {
      svc.debugRandom = _Zero();
      _load(['a_suckle_lina', ..._povs]);
      for (final position in ['tip', 'mid', 'throat', 'full', 'balls']) {
        final ctx = _ctx('suckle', position: position);
        svc.pickForContext(ctx);
        svc.pickForContext(ctx, playerScene: true);
        expect(_now.isPov, isFalse, reason: position);
      }
      final head = _ctx('suckle', position: 'head');
      svc.pickForContext(head);
      svc.pickForContext(head, playerScene: true);
      expect(_now.id, 'pov-E-suckle');
    });

    test('aucune hors du créneau : intro, finale, sans geste à l\'écran', () {
      svc.debugRandom = _Zero();
      _load([
        'a_rhythm_lina',
        'f_final_lina',
        'lina-pack-intro-1_lina',
        ..._povs,
      ]);
      final ctx = _ctx('rhythm', position: 'full');
      svc.pickForContext(ctx, playerScene: true);
      expect(_now.id, 'a', reason: 'aucun fond avant');
      svc.pickIntro('lina');
      svc.pickForContext(ctx, playerScene: true);
      expect(_now.id, 'a', reason: "l'intro n'est pas un geste de la coach");
      svc.pickForContext(ctx);
      svc.pickForContext(_ctx('hold', position: 'full', phase: 'final'),
          playerScene: true);
      expect(_now.id, 'f', reason: 'finale');
      svc.pickForContext(ctx);
      svc.pickForContext(ctx);
      expect(_now.isPov, isFalse, reason: 'sans demande du contrôleur');
    });

    test('aucune sur une bande de palier ni sur un fond de phase', () {
      svc.debugRandom = _Zero();
      _load([
        'a_rhythm_full_lina',
        'lina-pack-strip1-25001-anim_lina_nu1',
        'f_fail_lina',
        ..._povs,
      ]);
      final ctx = _ctx('rhythm', position: 'full');
      svc.pickForContext(ctx);
      svc.setById('lina-pack-strip1-25001-anim');
      svc.pickForContext(ctx, playerScene: true);
      expect(_now.id, 'a', reason: 'bande de palier');
      svc.pickFail('lina');
      svc.pickForContext(ctx, playerScene: true);
      expect(_now.id, 'a', reason: "fond d'échec");
    });

    test('un fond imposé par le step la remplace sans geler la suite', () {
      svc.debugRandom = _Zero();
      _load([
        'a_rhythm_full_lina',
        'b_lick_lina',
        'x_rhythm_full_lina',
        ..._povs,
      ]);
      svc.pickForContext(_ctx('rhythm', position: 'full'));
      svc.pickForContext(_ctx('rhythm', position: 'full'), playerScene: true);
      expect(_now.isPov, isTrue);
      svc.setById('x');
      svc.pickForContext(_ctx('lick'));
      expect(_now.id, 'b');
    });

    test('jamais tirées comme fond ordinaire', () {
      _load(['a_rhythm_lina', ..._povs]);
      for (var i = 0; i < 100; i++) {
        svc.pickForContext(_ctx('hold', position: 'full'));
        expect(_now.isPov, isFalse);
      }
    });

    testWidgets("l'écran la joue une fois puis revient à la coach",
        (tester) async {
      svc.debugRandom = _Zero();
      _load(['a_rhythm_full_lina', ..._povs]);
      svc.pickForContext(_ctx('rhythm', position: 'full'));
      svc.pickForContext(_ctx('rhythm', position: 'full'), playerScene: true);
      expect(_now.isPov, isTrue);
      await tester.runAsync(() async {
        await tester.pumpWidget(DefaultAssetBundle(
          bundle: _FakeBundle(_twoFrameGif()),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SessionBackground(),
          ),
        ));
        expect(find.byType(PlayOnceImage), findsOneWidget);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      expect(_now.id, 'a');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('câblage SessionController', () {
    const audio = [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ];
    const wakelock = [
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async => call.method == 'getVoices' ? <dynamic>[] : 1);
      for (final c in audio) {
        messenger.setMockMethodCallHandler(c, (_) async => null);
      }
      for (final name in wakelock) {
        messenger.setMockMessageHandler(
            name,
            (_) async =>
                const StandardMessageCodec().encodeMessage(<Object?>[null]));
      }
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'), null);
      for (final c in audio) {
        messenger.setMockMethodCallHandler(c, null);
      }
      for (final name in wakelock) {
        messenger.setMockMessageHandler(name, null);
      }
    });

    Future<bool> sceneSeen({
      SessionMode second = SessionMode.rhythm,
      int? milestoneStart,
    }) async {
      svc.debugRandom = _Zero();
      _load([
        'a_rhythm_tip_lina',
        'b_rhythm_full_lina',
        'c_beg_lina',
        'pov-E-rhythm-full_pov_rhythm_full',
        'pov-X-beg_pov_beg',
      ]);
      var seen = false;
      void watch() => seen |= svc.current.value?.isPov ?? false;
      svc.current.addListener(watch);
      final ctrl = SessionController(
        session: Session(
          id: 'pov',
          name: 'pov',
          description: '',
          durationSeconds: 30,
          defaultMode: SessionMode.rhythm,
          milestoneId: milestoneStart == null ? null : 'intro_pov',
          milestoneStartTime: milestoneStart,
          milestoneDurationSeconds: milestoneStart == null ? null : 20,
          steps: [
            const SessionStep(
                time: 0,
                mode: SessionMode.rhythm,
                from: Position.tip,
                to: Position.tip,
                bpm: 40,
                duration: 2),
            SessionStep(
                time: 2,
                mode: second,
                from: Position.tip,
                to: Position.full,
                bpm: 40,
                duration: 10),
          ],
        ),
        tts: TtsService(),
        beep: _QuietBeep(),
        ambience: _QuietAmbience(),
        coachTag: 'lina',
        punishmentBundle:
            const PunishmentBundle(failPhrases: [], punishments: []),
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );
      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      await ctrl.stop();
      svc.current.removeListener(watch);
      return seen;
    }

    test('la scène vient au changement de geste de la séance', () async {
      expect(await sceneSeen(), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test("jamais pendant une étape franchie", () async {
      expect(await sceneSeen(milestoneStart: 0), isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('jamais pendant une supplique', () async {
      expect(await sceneSeen(second: SessionMode.beg), isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

class _Zero implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.data);
  final Uint8List data;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(data);
}

Uint8List _twoFrameGif() {
  const frame = [
    0x21, 0xF9, 0x04, 0x04, 0x05, 0x00, 0x00, 0x00, //
    0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, //
    0x02, 0x02, 0x44, 0x01, 0x00,
  ];
  return Uint8List.fromList([
    ...'GIF89a'.codeUnits, 1, 0, 1, 0, 0x80, 0, 0, //
    0xFF, 0xFF, 0xFF, 0, 0, 0,
    0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0,
    ...frame, ...frame, 0x3B,
  ]);
}

class _QuietBeep extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _QuietAmbience extends AmbienceEngine {
  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> playForMode(SessionMode mode, {Position? depth}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
