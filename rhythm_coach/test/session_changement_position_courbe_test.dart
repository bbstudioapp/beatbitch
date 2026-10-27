import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/main.dart' show milestoneService;
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `Stopwatch` et `DateTime.now()` ne sont pas simulés par `flutter_test` :
/// la séance se joue à l'horloge du mur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const audioEventChannels = [
    EventChannel('xyz.luan/audioplayers.global/events'),
    EventChannel('xyz.luan/audioplayers/events/ambience_loop'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async => call.method == 'getVoices' ? <dynamic>[] : 1);
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, (call) async => null);
    }
    for (final name in wakelockChannels) {
      messenger.setMockMessageHandler(
        name,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    }
    for (final channel in audioEventChannels) {
      messenger.setMockStreamHandler(
          channel, MockStreamHandler.inline(onListen: (_, __) {}));
    }
    milestoneService.setSessionUnlocks({UnlockKey.begLibre});
  });

  tearDown(() {
    milestoneService.setSessionUnlocks(<UnlockKey>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, null);
    }
    for (final name in wakelockChannels) {
      messenger.setMockMessageHandler(name, null);
    }
    for (final channel in audioEventChannels) {
      messenger.setMockStreamHandler(channel, null);
    }
  });

  final failButton = find.byKey(const Key('session-fail-button'));
  final useMeButton = find.byKey(const Key('session-useme-button'));

  testWidgets(
      "changement de position : pas de courbe tant que la joueuse n'est pas "
      'en place, elle revient ensuite', (tester) async {
    final beep = _StateBeepEngine();
    final run = await _mount(tester, _changeSession, beep);
    var bipsSousGel = 0;
    var bipsHorsGel = 0;
    var gel = false;
    final relay = beep.onBeat;
    beep.onBeat = (e) {
      gel ? bipsSousGel++ : bipsHorsGel++;
      relay?.call(e);
    };

    var avantGel = 0;
    var imagesGel = 0;
    var apres = 0;
    var courbeSousGel = 0;
    final curseurSousGel = <(int, double)>[];
    await run.play((ctrl, sinceGel) {
      gel = ctrl.awaitingPostureReady;
      final courbe = find.byType(MovementAnimation).evaluate().isNotEmpty;
      if (sinceGel == null) {
        if (courbe) avantGel++;
        return false;
      }
      if (!gel) {
        if (courbe) apres++;
        return apres >= 10;
      }
      expect(ctrl.breakActive, isFalse);
      imagesGel++;
      if (courbe) courbeSousGel++;
      final c = _curve(tester);
      if (courbe && c.isNotEmpty) {
        curseurSousGel.add((sinceGel.inMilliseconds, c.first.$2));
      }
      if (sinceGel >= const Duration(seconds: 4)) ctrl.confirmPostureReady();
      return false;
    });

    expect(avantGel, greaterThanOrEqualTo(5),
        reason: 'la courbe doit être affichée avant le changement de position :'
            ' sans elle, son absence sous gel ne prouverait rien');
    expect(imagesGel, greaterThanOrEqualTo(15),
        reason: "le scénario n'est jamais entré en attente de position");
    expect(bipsHorsGel, greaterThanOrEqualTo(2),
        reason: 'le moteur doit battre hors changement de position : sans'
            ' cela, son silence sous gel ne prouverait rien');
    expect(bipsSousGel, 0,
        reason: 'le moteur de bips doit se taire pendant le changement de'
            ' position');
    expect(apres, greaterThanOrEqualTo(10),
        reason: 'la courbe doit revenir une fois la joueuse en place');
    expect(courbeSousGel, 0,
        reason: 'courbe montée sur $courbeSousGel des $imagesGel images de'
            ' changement de position, sur $bipsSousGel bip : '
            '${_describeCursor(curseurSousGel)}');
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets(
      'changement de position : ni « UTILISE-MOI » ni « JE PEUX PAS » tant que '
      "la joueuse n'est pas en place, ils reviennent ensuite", (tester) async {
    final run = await _mount(tester, _changeSession, _StateBeepEngine());
    run.ctrl.debugAddPlayed(SessionController.useMeUnlockAfter);

    var avantGel = 0;
    var imagesGel = 0;
    var apres = 0;
    final visiblesSousGel = <String>[];
    await run.play((ctrl, sinceGel) {
      final boutons =
          failButton.evaluate().isNotEmpty && useMeButton.evaluate().isNotEmpty;
      if (sinceGel == null) {
        if (boutons) avantGel++;
        return false;
      }
      if (!ctrl.awaitingPostureReady) {
        if (boutons) apres++;
        return apres >= 5;
      }
      imagesGel++;
      final enPlace = find.text(
          AppLocalizations.of(tester.element(find.byType(SessionScreen)))
              .sessionPostureReadyButton);
      expect(enPlace, findsOneWidget);
      for (final (nom, f) in [
        ('JE PEUX PAS', failButton),
        ('UTILISE-MOI', useMeButton),
      ]) {
        if (f.evaluate().isNotEmpty) {
          visiblesSousGel.add('$nom à ${sinceGel.inMilliseconds} ms');
        }
      }
      if (sinceGel >= const Duration(seconds: 3)) ctrl.confirmPostureReady();
      return false;
    });

    expect(avantGel, greaterThanOrEqualTo(3),
        reason: 'les deux boutons doivent être affichés avant le changement :'
            ' sans eux, leur absence sous gel ne prouverait rien');
    expect(imagesGel, greaterThanOrEqualTo(10),
        reason: "le scénario n'est jamais entré en attente de position");
    expect(apres, greaterThanOrEqualTo(5),
        reason:
            'les deux boutons doivent revenir une fois la joueuse en place');
    expect(visiblesSousGel, isEmpty,
        reason: '${visiblesSousGel.length} boutons affichés sur $imagesGel'
            ' images de changement de position : '
            '${visiblesSousGel.take(4).join(', ')}');
  }, timeout: const Timeout(Duration(seconds: 90)));

  for (final (titre, session) in [
    ('pause qui change la position', _breakSession),
    ('pause sans changement de position', _plainBreakSession),
  ]) {
    testWidgets(
        '$titre : ni « UTILISE-MOI » ni « JE PEUX PAS » pendant la pause, ils '
        'reviennent ensuite', (tester) async {
      final run = await _mount(tester, session, _StateBeepEngine());
      run.ctrl.debugAddPlayed(SessionController.useMeUnlockAfter);

      var avant = 0;
      var imagesPause = 0;
      var apres = 0;
      var pauseVue = false;
      final visiblesEnPause = <String>[];
      await run.play((ctrl, _) {
        final boutons = failButton.evaluate().isNotEmpty &&
            useMeButton.evaluate().isNotEmpty;
        if (ctrl.breakActive) {
          pauseVue = true;
          imagesPause++;
          for (final (nom, f) in [
            ('JE PEUX PAS', failButton),
            ('UTILISE-MOI', useMeButton),
          ]) {
            if (f.evaluate().isNotEmpty) {
              visiblesEnPause.add('$nom image n° $imagesPause');
            }
          }
          if (ctrl.awaitingPostureReady && imagesPause >= 20) {
            ctrl.confirmPostureReady();
          }
          return false;
        }
        if (!pauseVue) {
          if (boutons) avant++;
          return false;
        }
        if (ctrl.awaitingPostureReady) {
          ctrl.confirmPostureReady();
          return false;
        }
        if (boutons) apres++;
        return apres >= 5;
      });

      expect(avant, greaterThanOrEqualTo(3),
          reason: 'les deux boutons doivent être affichés avant la pause :'
              ' sans eux, leur absence en pause ne prouverait rien');
      expect(imagesPause, greaterThanOrEqualTo(15),
          reason: "le scénario n'est jamais entré en pause");
      expect(apres, greaterThanOrEqualTo(5),
          reason: 'les deux boutons doivent revenir après la pause');
      expect(visiblesEnPause, isEmpty,
          reason: '${visiblesEnPause.length} boutons affichés sur'
              ' $imagesPause images de pause : '
              '${visiblesEnPause.take(4).join(', ')}');
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
}

String _describeCursor(List<(int, double)> samples) {
  if (samples.isEmpty) return 'aucune';
  final idx = [for (final s in samples) s.$2];
  final changes = <int>[];
  for (var i = 1; i < samples.length; i++) {
    if (samples[i].$2 != samples[i - 1].$2) changes.add(samples[i].$1);
  }
  final gaps = [
    for (var i = 1; i < changes.length; i++) changes[i] - changes[i - 1],
  ]..sort();
  final min = idx.reduce((a, b) => a < b ? a : b);
  final max = idx.reduce((a, b) => a > b ? a : b);
  return 'le curseur parcourt ${min.toStringAsFixed(2)}–'
      '${max.toStringAsFixed(2)}, il change ${changes.length} fois, intervalle'
      ' médian ${gaps.isEmpty ? '-' : gaps[gaps.length ~/ 2]} ms entre deux'
      ' valeurs';
}

/// Points de la courbe peinte : (t ∈ [0,1] de la fenêtre de 3 s, idx).
List<(double, double)> _curve(WidgetTester tester) {
  for (final cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final p = cp.painter;
    if (p != null && p.runtimeType.toString() == '_TrajectoryPainter') {
      return [
        for (final b in (p as dynamic).beats as List)
          ((b as dynamic).t as double, b.idx as double),
      ];
    }
  }
  return const [];
}

class _Run {
  final SessionController ctrl;

  /// `sinceGel` est nul tant que la séance n'a pas attendu une mise en place ;
  /// `true` arrête la boucle.
  final Future<void> Function(
      bool Function(SessionController ctrl, Duration? sinceGel) onFrame) play;
  const _Run(this.ctrl, this.play);
}

Future<_Run> _mount(
    WidgetTester tester, Session session, BeepEngine beep) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SessionScreen(
      session: session,
      tts: TtsService(),
      beep: beep,
      ambience: _SilentAmbienceEngine(),
      punishmentBundle:
          const PunishmentBundle(failPhrases: [], punishments: []),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
      isCareer: true,
      onRequestUpgrade: (_) async {},
      autoStart: true,
    ),
  ));
  await tester.pump();
  final ctrl = Provider.of<SessionController>(
      tester.element(find.byType(MovementAnimation)),
      listen: false);

  Future<void> play(
      bool Function(SessionController ctrl, Duration? sinceGel) onFrame) async {
    // Le ticker du contrôleur est une minuterie simulée et son horloge un
    // `Stopwatch` réel : chaque tranche avance l'une du temps réel de l'autre.
    var sliceEnd = DateTime.now();
    DateTime? gelAt;
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      final now = DateTime.now();
      await tester.pump(now.difference(sliceEnd));
      sliceEnd = now;
      if (ctrl.awaitingPostureReady) gelAt ??= now;
      if (onFrame(ctrl, gelAt == null ? null : now.difference(gelAt))) break;
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
  }

  return _Run(ctrl, play);
}

const _rhythm = SessionStep(
  time: 0,
  mode: SessionMode.rhythm,
  bpm: 60,
  from: Position.head,
  to: Position.throat,
);

const _changeSession = Session(
  id: 'changement-position',
  name: 'changement-position',
  description: '',
  durationSeconds: 60,
  defaultMode: SessionMode.rhythm,
  postureChanges: [PostureChange(time: 2, pose: Posture.kneeling)],
  steps: [
    _rhythm,
    SessionStep(
      time: 2,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
      duration: 58,
    ),
  ],
);

const _breakSession = Session(
  id: 'pause-position',
  name: 'pause-position',
  description: '',
  durationSeconds: 60,
  defaultMode: SessionMode.rhythm,
  breaks: [
    ScriptedBreak(time: 2, durationSeconds: 10, newPose: Posture.kneeling),
  ],
  steps: [
    _rhythm,
    SessionStep(
      time: 12,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
      duration: 48,
    ),
  ],
);

const _plainBreakSession = Session(
  id: 'pause-sans-position',
  name: 'pause-sans-position',
  description: '',
  durationSeconds: 60,
  defaultMode: SessionMode.rhythm,
  breaks: [ScriptedBreak(time: 2, durationSeconds: 4)],
  steps: [
    _rhythm,
    SessionStep(
      time: 6,
      mode: SessionMode.rhythm,
      bpm: 60,
      from: Position.head,
      to: Position.throat,
      duration: 54,
    ),
  ],
);

/// Muet (aucun lecteur chargé) mais fidèle : ses minuteries émettent les
/// battements que la courbe suit.
class _StateBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
}

class _SilentAmbienceEngine extends AmbienceEngine {
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
