import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<List<(String, double)>> playWithVolumes(SessionMode mode) async {
    final beep = BeepEngine();
    await beep.init();
    final triggers = <(String, double)>[];
    beep.debugOnTrigger = (asset, volume) => triggers.add((asset, volume));
    beep
        .applyStep(
            SessionStep(
              time: 0,
              mode: mode,
              bpm: 120,
              from: Position.tip,
              to: Position.full,
              duration: 10,
            ),
            mode)
        .ignore();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await beep.stop();
    return triggers;
  }

  Future<List<String>> play(SessionMode mode) async =>
      [for (final t in await playWithVolumes(mode)) t.$1];

  test('le lick joue ses propres sons, un par position', () async {
    final assets = await play(SessionMode.lick);
    expect(assets, isNotEmpty);
    expect(assets.toSet(), {'lick_tip_beep', 'lick_full_beep'});
  });

  test('le lick joue ses sons à mi-volume', () async {
    final triggers = await playWithVolumes(SessionMode.lick);
    expect(triggers, isNotEmpty);
    expect(triggers.map((t) => t.$2).toSet(), {0.5});
  });

  test('le rythme garde les bips de position', () async {
    final assets = await play(SessionMode.rhythm);
    expect(assets.toSet(), {'tip_beep', 'full_beep'});
  });

  test('le lick joué seul passe par son propre son', () async {
    final beep = BeepEngine();
    await beep.init();
    final triggers = <(String, double)>[];
    beep.debugOnTrigger = (asset, volume) => triggers.add((asset, volume));
    beep.playLickPositionOnce(Position.balls);
    expect(triggers, [('lick_balls_beep', 0.5)]);
  });
}
