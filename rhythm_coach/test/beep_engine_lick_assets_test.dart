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

  Future<List<String>> play(SessionMode mode) async {
    final beep = BeepEngine();
    await beep.init();
    final assets = <String>[];
    beep.debugOnTrigger = (asset, _) => assets.add(asset);
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
    return assets;
  }

  test('le lick joue ses propres sons, un par position', () async {
    final assets = await play(SessionMode.lick);
    expect(assets, isNotEmpty);
    expect(assets.toSet(), {'lick_tip_beep', 'lick_full_beep'});
  });

  test('le rythme garde les bips de position', () async {
    final assets = await play(SessionMode.rhythm);
    expect(assets.toSet(), {'tip_beep', 'full_beep'});
  });

  test('le lick joué seul passe par son propre son', () async {
    final beep = BeepEngine();
    await beep.init();
    final assets = <String>[];
    beep.debugOnTrigger = (asset, _) => assets.add(asset);
    beep.playLickPositionOnce(Position.balls);
    expect(assets, ['lick_balls_beep']);
  });
}
