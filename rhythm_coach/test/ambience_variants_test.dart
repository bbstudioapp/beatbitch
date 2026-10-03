import 'dart:math';

import 'package:beat_bitch/models/ambience_pack.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pack = AmbiencePack.fromJson({
    'id': 'p',
    'name': 'p',
    'tracks': {
      'rhythm': {
        'shallow': ['r_s1.mp3', 'r_s2.mp3'],
        'deep': ['r_d1.mp3', 'r_d2.mp3', 'r_d3.mp3'],
      },
      'lick': ['l1.mp3', 'l2.mp3'],
      'biffle': 'b.mp3',
      'hold': {'deep': 'h_d.mp3'},
      'breath': null,
    },
  });

  group('AmbiencePack.fromJson', () {
    test('palier peu profond et profond séparés', () {
      expect(pack.candidatesFor(SessionMode.rhythm, deep: false),
          ['r_s1.mp3', 'r_s2.mp3']);
      expect(pack.candidatesFor(SessionMode.rhythm, deep: true),
          ['r_d1.mp3', 'r_d2.mp3', 'r_d3.mp3']);
    });

    test('une liste vaut pour les deux paliers', () {
      expect(pack.candidatesFor(SessionMode.lick, deep: false),
          ['l1.mp3', 'l2.mp3']);
      expect(pack.candidatesFor(SessionMode.lick, deep: true),
          ['l1.mp3', 'l2.mp3']);
    });

    test('un fichier seul reste lu tel quel', () {
      expect(pack.candidatesFor(SessionMode.biffle, deep: true), ['b.mp3']);
      expect(pack.assetFor(SessionMode.biffle), 'b.mp3');
    });

    test('un palier absent se rabat sur l\'autre', () {
      expect(pack.candidatesFor(SessionMode.hold, deep: false), ['h_d.mp3']);
    });

    test('null coupe le mode', () {
      expect(pack.candidatesFor(SessionMode.breath, deep: false), isEmpty);
    });

    test('assetFor garde la première variante pour le test d\'écoute', () {
      expect(pack.assetFor(SessionMode.rhythm), 'r_s1.mp3');
    });
  });

  group('AmbienceEngine.playForMode', () {
    late _RecordingAmbienceEngine engine;

    setUp(() {
      for (final c in const [
        MethodChannel('xyz.luan/audioplayers.global'),
        MethodChannel('xyz.luan/audioplayers'),
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(c, (call) async => null);
      }
      engine = _RecordingAmbienceEngine(Random(1))..setPack(pack);
    });

    test('tire dans le palier de la profondeur', () async {
      await engine.playForMode(SessionMode.rhythm, depth: Position.head);
      expect(['r_s1.mp3', 'r_s2.mp3'], contains(engine.played.last));

      await engine.playForMode(SessionMode.rhythm, depth: Position.throat);
      expect(
          ['r_d1.mp3', 'r_d2.mp3', 'r_d3.mp3'], contains(engine.played.last));
    });

    test('même mode et même palier : la variante continue', () async {
      await engine.playForMode(SessionMode.rhythm, depth: Position.full);
      final first = engine.played.last;
      for (var i = 0; i < 10; i++) {
        await engine.playForMode(SessionMode.rhythm, depth: Position.balls);
      }
      expect(engine.played.toSet(), {first});
    });

    test('retour sur un palier : une autre variante que la précédente',
        () async {
      for (var i = 0; i < 20; i++) {
        await engine.playForMode(SessionMode.lick, depth: Position.tip);
        final before = engine.played.last;
        await engine.playForMode(SessionMode.lick, depth: Position.full);
        expect(engine.played.last, isNot(before));
      }
    });

    test('toutes les variantes finissent par sortir', () async {
      for (var i = 0; i < 60; i++) {
        await engine.playForMode(SessionMode.rhythm, depth: Position.tip);
        await engine.playForMode(SessionMode.rhythm, depth: Position.throat);
      }
      expect(engine.played.toSet(),
          {'r_s1.mp3', 'r_s2.mp3', 'r_d1.mp3', 'r_d2.mp3', 'r_d3.mp3'});
    });
  });
}

class _RecordingAmbienceEngine extends AmbienceEngine {
  _RecordingAmbienceEngine(Random random) : super(random: random);

  final List<String> played = [];

  @override
  Future<void> startPlayback(String assetPath) async {
    played.add(assetPath);
  }
}
