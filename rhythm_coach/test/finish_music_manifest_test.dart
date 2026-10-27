import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// Fichier à part : le manifeste lu est mis en cache pour tout l'isolat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'un manifeste illisible fait jouer le commun à une coach qui a un morceau',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));

    final engine = AmbienceEngine(finishTracksByCoach: {
      'lina': (
        asset: 'audio/music/finish_coach_01_lina.mp3',
        peak: const Duration(seconds: 61)
      ),
    });

    expect(
        await engine.finishTrackFor('lina'), AmbienceEngine.commonFinishTrack);
  });
}
