import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sur Android, un player qui tient le focus audio est mis en pause par
/// `audioplayers` dès qu'un autre player de l'app le réclame : le premier bip
/// coupait l'ambiance pour le reste du mode.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];

  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async {
        calls.add(call);
        return null;
      });
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  test("l'ambiance ne réclame pas le focus audio avant de jouer", () async {
    final engine = AmbienceEngine();

    await engine.play('audio/tip_beep.mp3');

    final ambienceCalls = calls
        .where((c) => (c.arguments as Map?)?['playerId'] == 'ambience_loop')
        .map((c) => c.method)
        .toList();
    expect(ambienceCalls, contains('setSourceUrl'));
    final contextCall = calls.firstWhere(
      (c) =>
          c.method == 'setAudioContext' &&
          (c.arguments as Map)['playerId'] == 'ambience_loop',
    );
    expect(
      (contextCall.arguments as Map)['audioFocus'],
      AndroidAudioFocus.none.value,
    );
    expect(
      ambienceCalls.indexOf('setAudioContext'),
      lessThan(ambienceCalls.indexOf('setSourceUrl')),
    );
  });
}
