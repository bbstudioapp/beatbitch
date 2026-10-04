import 'package:beat_bitch/models/hold_move.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _hold = SessionStep(
  time: 0,
  mode: SessionMode.hold,
  to: Position.throat,
  duration: 10,
  moves: [HoldMove(kind: HoldMoveKind.excursion, at: 0.5, to: Position.tip)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    for (final c in const [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
  });

  Future<(BeepEngine, List<(String, int)>, Stopwatch)> start() async {
    final beep = BeepEngine();
    await beep.init();
    final clock = Stopwatch();
    final played = <(String, int)>[];
    beep.debugOnTrigger = (asset, _) {
      if (!clock.isRunning) clock.start();
      played.add((asset, clock.elapsedMilliseconds));
    };
    beep.applyStep(_hold, SessionMode.rhythm).ignore();
    return (beep, played, clock);
  }

  test('l\'aller-retour sonne à l\'arrivée sur la cible puis au retour',
      () async {
    final (beep, played, _) = await start();
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    await beep.stop();

    final leg = excursionLeg(Position.throat, Position.tip).inMilliseconds;
    // Le départ de la tenue joue sa position et la nappe de tenue ensemble.
    expect(played.map((p) => p.$1).toList(),
        ['throat_beep', 'hold_beep', 'tip_beep', 'throat_beep']);
    expect(played[2].$2, closeTo(500 + leg, 40));
    expect(played[3].$2, closeTo(500 + 2 * leg, 40));
  });

  test('une pause décale les mouvements restants de sa durée', () async {
    final (beep, played, _) = await start();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await beep.pause();
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    await beep.resume();
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    await beep.stop();

    final leg = excursionLeg(Position.throat, Position.tip).inMilliseconds;
    final tip = played.firstWhere((p) => p.$1 == 'tip_beep').$2;
    expect(tip, closeTo(500 + leg + 1000, 60),
        reason: 'le bip d\'arrivée tombe après la pause, pas pendant');
  });

  test('une rafale de micro-mouvements sonne des tics légers', () async {
    final beep = BeepEngine();
    await beep.init();
    final ticks = <(String, double)>[];
    var started = false;
    beep.debugOnTrigger = (asset, volume) {
      if (started) ticks.add((asset, volume));
      if (asset == 'hold_beep') started = true;
    };
    beep
        .applyStep(
            const SessionStep(
              time: 0,
              mode: SessionMode.hold,
              to: Position.throat,
              duration: 10,
              moves: [
                HoldMove(kind: HoldMoveKind.micro, at: 0.2, duration: 1.5),
              ],
            ),
            SessionMode.rhythm)
        .ignore();
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    await beep.stop();
    expect(ticks.length, closeTo(1500 / 340, 1.5));
    expect(ticks.map((t) => t.$1).toSet(), {'throat_beep'});
    final full = ticks.first.$2 / microTickVolume;
    for (final t in ticks) {
      expect(t.$2, closeTo(full * microTickVolume, 1e-9));
    }
    expect(full, greaterThan(ticks.first.$2), reason: 'tic plus doux');
  });
}
