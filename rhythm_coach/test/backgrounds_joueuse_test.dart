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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = BackgroundsService.instance;
  tearDown(svc.debugResetForTest);

  group('tenues où la coach lève la main', () {
    test('ne sont jamais tirées', () {
      _load([..._handRaised, 'lina-pack-hold-25002-ltx-pp-s25002_hold_lina']);
      for (var i = 0; i < 50; i++) {
        svc.pickForContext(_ctx('hold'));
        expect(_now.id, 'lina-pack-hold-25002-ltx-pp-s25002');
        svc.pickRandom();
        expect(_now.id, 'lina-pack-hold-25002-ltx-pp-s25002');
      }
    });

    test('sans tenue permise, la coach garde son geste au palier atteint', () {
      _load([
        ..._handRaised,
        'helene-pack-rhythm-full-26002-ltx-pp-s26002_rhythm_full_helene',
        'helene-pack-nu1-rhythm-full-26002-ltx-pp-s26002_rhythm_full_helene_nu1',
        'helene-pack-strip1-26002-anim_helene_nu1',
        'lina-pack-rhythm-full-25001-ltx-pp-s25001_rhythm_full_lina',
      ]);
      svc.pickForContext(_ctx('rhythm', position: 'full', coach: 'helene'));
      svc.pickForContext(_ctx('hold', position: 'full', coach: 'helene'));
      expect(_now.id, 'helene-pack-rhythm-full-26002-ltx-pp-s26002');

      svc.pickForContext(
          _ctx('hold', position: 'full', coach: 'helene', tier: 'nu1'));
      expect(_now.isTierTransition, isTrue);
      svc.transitionFinished(_now);
      expect(_now.id, 'helene-pack-nu1-rhythm-full-26002-ltx-pp-s26002',
          reason: 'après la transition, le geste précédent au nouveau palier');
    });
  });

  group('scènes de joueuse', () {
    test("s'intercalent environ une fois sur trois, jamais deux d'affilée", () {
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
      expect(scenes, inInclusiveRange(120, 280));
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

    test('jamais tirées comme fond ordinaire', () {
      _load(['a_rhythm_lina', ..._povs]);
      for (var i = 0; i < 100; i++) {
        svc.pickForContext(_ctx('hold', position: 'full', coach: 'jade'));
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
