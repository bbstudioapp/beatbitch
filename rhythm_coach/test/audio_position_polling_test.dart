import 'dart:io';

import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> frame(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  late Map<String, int> calls;

  setUp(() {
    calls = {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in const [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ]) {
      messenger.setMockMethodCallHandler(c, (call) async {
        calls.update(call.method, (n) => n + 1, ifAbsent: () => 1);
        final id = (call.arguments as Map?)?['playerId'] as String?;
        if (id != null) {
          final events = 'xyz.luan/audioplayers/events/$id';
          void emit(String event, [Object? value]) =>
              Future.microtask(() => messenger.handlePlatformMessage(
                  events,
                  const StandardMethodCodec()
                      .encodeSuccessEnvelope({'event': event, 'value': value}),
                  (_) {}));
          switch (call.method) {
            case 'create':
              messenger.setMockMethodCallHandler(
                  MethodChannel(events), (_) async => null);
            case 'setSourceUrl':
              emit('audio.onPrepared', true);
            case 'seek':
              emit('audio.onSeekComplete');
          }
        }
        return call.method == 'getCurrentPosition' ? 0 : null;
      });
    }
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global/events'),
        (_) async => null);
    final tmp = Directory.systemTemp.createTempSync('audio_cache');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path);
  });

  testWidgets('les bips ne font pas interroger leur position à chaque image',
      (tester) async {
    final beep = BeepEngine();
    await tester.runAsync(beep.init);
    for (var i = 0; i < 40; i++) {
      if (i < 8) {
        await tester.runAsync(() async {
          beep.playPositionOnce(Position.values[i % 5]);
        });
      }
      await frame(tester);
    }
    expect(calls['resume'] ?? 0, greaterThanOrEqualTo(8),
        reason: 'les bips sont bien joués');
    expect(calls['getCurrentPosition'] ?? 0, 0);
  });

  testWidgets('la boucle d\'ambiance ne fait pas interroger sa position',
      (tester) async {
    final ambience = AmbienceEngine();
    await tester.runAsync(() => ambience.play('audio/tip_beep.mp3'));
    for (var i = 0; i < 30; i++) {
      await frame(tester);
    }
    expect(ambience.isPlaying, isTrue, reason: 'l\'ambiance tourne');
    expect(calls['getCurrentPosition'] ?? 0, 0);
  });
}
