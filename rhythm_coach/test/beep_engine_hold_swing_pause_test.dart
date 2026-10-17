import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une tenue ancrée sur `to` joue ses allers-retours ; une pause au milieu ne
/// les éteint pas : la suite reprend là où elle s'était arrêtée, décalée de la
/// durée de la pause.
const _swing = SessionStep(
  time: 0,
  mode: SessionMode.hold,
  from: Position.throat,
  to: Position.throat,
  bpm: 60,
  ratio: 3,
  anchor: BeatAnchor.to,
  duration: 30,
);

const _pauseAfter = Duration(milliseconds: 2500);
const _pauseFor = Duration(milliseconds: 1000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in const [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ]) {
      messenger.setMockMethodCallHandler(c, (call) async => null);
    }
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
      '.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  test('moteur : les allers-retours reprennent après la pause', () async {
    final played = await _playAroundPause(
      start: (beep) => beep.applyStep(_swing, SessionMode.rhythm),
      pause: (beep) => beep.pause(),
      resume: (beep) => beep.resume(),
    );
    _expectSwingContinues(played);
  });

  test('séance : les allers-retours reprennent après pause() / resume()',
      () async {
    late SessionController ctrl;
    final played = await _playAroundPause(
      start: (beep) {
        ctrl = SessionController(
          session: const Session(
            id: 'tenue-ancree',
            name: 'tenue-ancree',
            description: '',
            durationSeconds: 60,
            defaultMode: SessionMode.rhythm,
            steps: [_swing],
          ),
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
        );
        return ctrl.start();
      },
      pause: (_) => ctrl.pause(),
      resume: (_) => ctrl.resume(),
    );
    await ctrl.stop();
    ctrl.dispose();
    _expectSwingContinues(played);
  });
}

class _Played {
  /// Instants des bips, en ms depuis le premier bip de la tenue.
  final List<(String, int)> beeps;
  final int pausedAtMs;
  final int pauseMs;
  const _Played(this.beeps, this.pausedAtMs, this.pauseMs);
}

Future<_Played> _playAroundPause({
  required Future<void> Function(BeepEngine beep) start,
  required Future<void> Function(BeepEngine beep) pause,
  required Future<void> Function(BeepEngine beep) resume,
}) async {
  final beep = BeepEngine();
  await beep.init();
  final clock = Stopwatch();
  final played = <(String, int)>[];
  beep.debugOnTrigger = (asset, _) {
    if (!clock.isRunning) clock.start();
    played.add((asset, clock.elapsedMilliseconds));
  };
  start(beep).ignore();
  for (var i = 0; i < 40 && !clock.isRunning; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(clock.isRunning, isTrue, reason: 'la tenue ne sonne pas');
  await Future<void>.delayed(_pauseAfter);
  final pausedAtMs = clock.elapsedMilliseconds;
  await pause(beep);
  await Future<void>.delayed(_pauseFor);
  final pauseMs = clock.elapsedMilliseconds - pausedAtMs;
  await resume(beep);
  await Future<void>.delayed(const Duration(milliseconds: 2500));
  await beep.stop();
  return _Played(played, pausedAtMs, pauseMs);
}

/// Les bips du balancement (instants depuis le premier bip), sans
/// interruption.
List<int> _swingOffsets() {
  var at = 0;
  return [
    for (final (_, ms) in BeepEngine().holdSwingSequenceForTest(
        anchorPos: _swing.to!,
        bpm: _swing.bpm!.toDouble(),
        ratio: _swing.ratio))
      at += ms,
  ];
}

void _expectSwingContinues(_Played run) {
  final next = _swingOffsets().firstWhere((ms) => ms > run.pausedAtMs);
  final after = run.beeps.where((b) => b.$2 > run.pausedAtMs).toList();
  expect(after, isNotEmpty,
      reason: 'aucun bip après la pause (pause à ${run.pausedAtMs} ms, '
          'bips : ${run.beeps})');
  expect(after.first.$2, closeTo(next + run.pauseMs, 120),
      reason: 'le 1er bip après la pause est l\'aller-retour suivant, décalé '
          'de la pause (${run.pauseMs} ms). Bips : ${run.beeps}');
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
