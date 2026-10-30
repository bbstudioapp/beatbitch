import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
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
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackgroundEntry _e(String basename) =>
    BackgroundsLoader.parseEntry('assets/backgrounds/$basename')!;

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
  String coach = 'lina',
}) =>
    BackgroundContext(
        mode: mode, position: position, coach: coach, phase: phase, tier: tier);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = BackgroundsService.instance;
  setUp(svc.debugResetForTest);

  group('vocabulaire', () {
    test('nu1/nu2 forment la catégorie palier, fail une phase', () {
      expect(_e('a_hold_lina_nu1.webp').tagsByCategory, {
        BackgroundTagCategory.mode: {'hold'},
        BackgroundTagCategory.coach: {'lina'},
        BackgroundTagCategory.tier: {'nu1'},
      });
      expect(_e('a_fail_lina.webp').tagsByCategory[BackgroundTagCategory.phase],
          {'fail'});
    });

    test('la transition du pack (palier + coach, sans mode) est reconnue', () {
      expect(_e(_strips[0]).isTierTransition, isTrue);
      expect(_e(_strips[1]).isTierTransition, isTrue);
      expect(_e('lina-pack-intro-1-x_lina.webp').isTierTransition, isFalse);
      expect(_e(_tier('nu1')[0]).isTierTransition, isFalse);
    });
  });

  group('palier selon l\'avancée', () {
    const s = Session(
      id: 't',
      name: 't',
      description: '',
      durationSeconds: 900,
      defaultMode: SessionMode.rhythm,
      steps: [],
      silentFinishStartTime: 780,
      finalStepTime: 840,
    );
    String? at(int sec, [Session session = s]) =>
        SessionController.backgroundTierFor(sec, session);

    test('lingerie, puis nu1 au premier tiers, nu2 au deuxième', () {
      expect(at(0), isNull);
      expect(at(299), isNull);
      expect(at(300), 'nu1');
      expect(at(599), 'nu1');
      expect(at(600), 'nu2');
    });

    test('la montée et le final sont toujours en nu2', () {
      const early = Session(
        id: 't',
        name: 't',
        description: '',
        durationSeconds: 900,
        defaultMode: SessionMode.rhythm,
        steps: [],
        silentFinishStartTime: 200,
        finalStepTime: 250,
      );
      expect(at(199, early), isNull);
      expect(at(200, early), 'nu2');
      expect(at(250, early), 'nu2');
      expect(at(890, early), 'nu2');
    });
  });

  group('choix du fond par tags', () {
    setUp(() => _load([..._lingerie, ..._tier('nu1'), ..._tier('nu2')]));

    test('palier 1 : lingerie, jamais un fond de palier', () {
      svc.pickForContext(_ctx());
      expect(_now.id, 'lina-pack-hold-1-x');
      expect(_now.tagsByCategory[BackgroundTagCategory.tier], isNull);
    });

    test('palier 2 : le fond du mode au palier nu1', () {
      _load([..._lingerie, ..._tier('nu1')]);
      svc.pickForContext(_ctx(tier: 'nu1'));
      expect(_now.tags, {'hold', 'lina', 'nu1'});
    });

    test('palier nu sans fond du mode : jamais la lingerie du même mode', () {
      _load([_lingerie[1], _tier('nu1')[1], 'plain.webp']);
      svc.pickForContext(_ctx(tier: 'nu1'));
      expect(_now.path, endsWith('plain.webp'));
    });

    test('la position départage les rhythm', () {
      svc.pickForContext(_ctx(mode: 'rhythm', position: 'tip', tier: 'nu2'));
      expect(_now.tags, {'rhythm', 'tip', 'lina', 'nu2'});
    });

    test('le final l\'emporte sur le fond du mode (le final est une tenue)',
        () {
      for (var i = 0; i < 20; i++) {
        svc.pickForContext(_ctx(phase: 'final', position: 'full', tier: 'nu2'));
        expect(_now.tags, contains('final'));
      }
      svc.pickForContext(_ctx(phase: 'post-final', tier: 'nu2'));
      expect(_now.tags, contains('post-final'));
    });

    test('final : jamais de fond lingerie, et rien de final au palier 1', () {
      svc.pickForContext(_ctx(phase: 'final', tier: 'nu2'));
      expect(_now.tags, contains('nu2'));
      svc.clear();
      svc.pickForContext(_ctx(phase: 'final'));
      expect(_now.tags, isNot(contains('final')));
    });

    test('un fond final ne sort pas hors phase finale', () {
      for (var i = 0; i < 20; i++) {
        svc.pickForContext(_ctx(tier: 'nu2'));
        expect(_now.tags, isNot(contains('final')));
        expect(_now.tags, isNot(contains('post-final')));
      }
    });

    test('la phase d\'échec : fond fail au palier atteint', () {
      svc.pickForContext(_ctx());
      expect(svc.pickFail('lina'), isTrue);
      expect(_now.tags, {'fail', 'lina'});
      svc.pickForContext(_ctx(tier: 'nu1'));
      svc.transitionFinished(_now);
      expect(svc.pickFail('lina'), isTrue);
      expect(_now.tags, {'fail', 'lina', 'nu1'});
    });
  });

  group('transition de palier', () {
    setUp(() => _load([
          ..._lingerie,
          ..._tier('nu1'),
          ..._tier('nu2'),
          ..._strips,
        ]));

    test('jouée une seule fois, puis le fond du mode au nouveau palier', () {
      svc.pickForContext(_ctx());
      expect(_now.isTierTransition, isFalse);

      svc.pickForContext(_ctx(tier: 'nu1'));
      final strip = _now;
      expect(strip.id, 'lina-pack-strip1-1-x');

      svc.pickForContext(_ctx(mode: 'rhythm', position: 'tip', tier: 'nu1'));
      expect(_now, strip);

      svc.transitionFinished(strip);
      expect(_now.tags, {'rhythm', 'tip', 'lina', 'nu1'},
          reason: 'le dernier contexte demandé, pas celui du déclenchement');

      for (var i = 0; i < 10; i++) {
        svc.pickForContext(_ctx(tier: 'nu1'));
        expect(_now.isTierTransition, isFalse);
      }
    });

    test('nu2 : strip2 une fois ; un palier ne redescend pas', () {
      svc.pickForContext(_ctx(tier: 'nu1'));
      svc.transitionFinished(_now);
      svc.pickForContext(_ctx(tier: 'nu2'));
      expect(_now.id, 'lina-pack-strip2-1-x');
      svc.transitionFinished(_now);
      svc.pickForContext(_ctx());
      expect(_now.tags, contains('nu2'));
      expect(_now.isTierTransition, isFalse);
    });

    test('saut lingerie → nu2 : strip1 puis strip2', () {
      svc.pickForContext(_ctx());
      svc.pickForContext(_ctx(tier: 'nu2'));
      expect(_now.id, 'lina-pack-strip1-1-x');
      svc.transitionFinished(_now);
      expect(_now.id, 'lina-pack-strip2-1-x');
      svc.transitionFinished(_now);
      expect(_now.tags, {'hold', 'lina', 'nu2'});
    });

    test("un fond imposé coupe la montée : la bande n'est pas rejouée", () {
      svc.pickForContext(_ctx());
      svc.pickForContext(_ctx(tier: 'nu1'));
      final strip = _now;
      expect(strip.isTierTransition, isTrue);

      svc.setById('lina-pack-intro-1-x');
      svc.transitionFinished(strip);
      expect(_now.id, 'lina-pack-intro-1-x');

      svc.pickForContext(_ctx(tier: 'nu1'));
      expect(_now.tags, {'hold', 'lina', 'nu1'},
          reason: 'le palier est acquis sans transition');
    });

    test('une fin de transition d\'un autre fond est ignorée', () {
      svc.pickForContext(_ctx(tier: 'nu1'));
      final strip = _now;
      svc.transitionFinished(_e(_tier('nu1')[0]));
      expect(_now, strip);
    });

    test('clear() rend la séance suivante à la lingerie', () {
      svc.pickForContext(_ctx(tier: 'nu1'));
      svc.transitionFinished(_now);
      svc.clear();
      svc.pickForContext(_ctx());
      expect(_now.tags, {'hold', 'lina'});
      svc.pickForContext(_ctx(tier: 'nu1'));
      expect(_now.isTierTransition, isTrue,
          reason: 'nouvelle séance, nouveau strip');
    });
  });

  group('autres coachs inchangés', () {
    setUp(() => _load([
          ..._lingerie,
          ..._tier('nu1'),
          ..._strips,
          'clip_helene_hold.webp',
          'plain.webp',
        ]));

    test('aucun fond de palier, aucune transition, même avec tier demandé', () {
      final helene = _e('clip_helene_hold.webp');
      for (final tier in [null, 'nu1', 'nu2']) {
        svc.pickForContext(_ctx(coach: 'helene', tier: tier));
        expect(_now.path, helene.path);
      }
    });

    test('pas de fond fail : le fond courant est gardé', () {
      svc.pickForContext(_ctx(coach: 'helene'));
      final before = _now;
      expect(svc.pickFail('helene'), isFalse);
      expect(_now, before);
    });

    test('le repli sur la coach ne tire jamais une transition', () {
      _load([_strips[0], _strips[1], 'lina-pack-a_lick_lina.webp']);
      for (var i = 0; i < 30; i++) {
        svc.pickForContext(const BackgroundContext(mode: 'beg', coach: 'lina'));
        expect(_now.isTierTransition, isFalse);
      }
    });
  });

  group('PlayOnceImage', () {
    testWidgets('joue les images une fois puis prévient, sans boucler',
        (tester) async {
      var done = 0;
      await tester.runAsync(() async {
        await tester.pumpWidget(DefaultAssetBundle(
          bundle: _FakeBundle(_twoFrameGif()),
          child: PlayOnceImage(path: 'x.gif', onDone: () => done++),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(done, 1);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(done, 1, reason: 'pas de seconde lecture');
      });
    });
  });

  group('câblage SessionController', () {
    const ttsChannel = MethodChannel('flutter_tts');
    const audio = [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ];
    const wakelock = [
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
          '.isEnabled',
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      messenger.setMockMethodCallHandler(ttsChannel, (call) async {
        if (call.method == 'getVoices') return <dynamic>[];
        return 1;
      });
      for (final c in audio) {
        messenger.setMockMethodCallHandler(c, (call) async => null);
      }
      for (final n in wakelock) {
        messenger.setMockMessageHandler(
            n,
            (_) async =>
                const StandardMessageCodec().encodeMessage(<Object?>[null]));
      }
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(ttsChannel, null);
      for (final c in audio) {
        messenger.setMockMethodCallHandler(c, null);
      }
    });

    SessionController build(String coach) => SessionController(
          staminaProfile: List<double>.filled(120, 100),
          session: const Session(
            id: 'tiers',
            name: 'tiers',
            description: '',
            durationSeconds: 6,
            defaultMode: SessionMode.hold,
            steps: [SessionStep(time: 0, mode: SessionMode.hold, duration: 6)],
          ),
          tts: TtsService(),
          beep: _QuietBeep(),
          ambience: _QuietAmbience(),
          coachTag: coach,
          punishmentBundle: const PunishmentBundle(
            failPhrases: ['x'],
            punishments: [
              Punishment(
                id: 'p',
                name: 'p',
                durationSeconds: 1,
                steps: [
                  SessionStep(time: 0, mode: SessionMode.breath, duration: 1)
                ],
              ),
            ],
          ),
          randomComments: const RandomCommentsBundle(
            comments: [],
            minIntervalSeconds: 999,
            maxIntervalSeconds: 999,
            scriptedCooldownSeconds: 4,
          ),
        );

    test('Lina : lingerie, strip1 au tiers, strip2 aux deux tiers, fail',
        () async {
      _load([..._lingerie, ..._tier('nu1'), ..._tier('nu2'), ..._strips]);
      final ctrl = build('lina');
      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(_now.tags, {'hold', 'lina'});

      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(_now.id, 'lina-pack-strip1-1-x');
      svc.transitionFinished(_now);

      await Future<void>.delayed(const Duration(milliseconds: 2000));
      expect(_now.id, 'lina-pack-strip2-1-x');
      svc.transitionFinished(_now);
      expect(_now.tags, {'hold', 'lina', 'nu2'});

      unawaited(ctrl.triggerFail());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(ctrl.isFailing, isTrue);
      expect(_now.tags, {'fail', 'lina', 'nu2'});
      await ctrl.stop();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('autre coach : le bundle Lina ne change rien à son fond', () async {
      _load(
          [..._lingerie, ..._tier('nu1'), ..._strips, 'clip_helene_hold.webp']);
      final ctrl = build('helene');
      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      expect(_now.id, 'clip');
      await ctrl.stop();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
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
