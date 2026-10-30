import 'package:beat_bitch/models/ambience_pack.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pluie = AmbiencePack(
  id: 'pluie',
  name: 'Pluie',
  tracksByMode: {SessionMode.rhythm: 'audio/ambience/pluie.mp3'},
);
const _voix = AmbiencePack(
  id: 'voix_femme',
  name: 'Voix',
  tracksByMode: {SessionMode.rhythm: 'audio/ambience/femme.mp3'},
);
const _packs = [AmbiencePack.none, _pluie, _voix];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> ttsCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    ttsCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      ttsCalls.add(call);
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    for (final c in const [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('le volume de la voix choisi revient au lancement suivant', () async {
    final avant = TtsService();
    await avant.init();
    await avant.setVolume(0.4);

    ttsCalls.clear();
    final apres = TtsService();
    await apres.init();

    final volumes = ttsCalls
        .where((c) => c.method == 'setVolume')
        .map((c) => (c.arguments as num).toDouble());
    expect(volumes.last, closeTo(0.4, 1e-9),
        reason: 'le moteur vocal repart au volume choisi, pas au maximum');
    expect(apres.volume, closeTo(0.4, 1e-9),
        reason: 'l\'écran lit ce volume pour placer son curseur');
  });

  test('le pack d\'ambiance et son volume reviennent au lancement suivant',
      () async {
    final avant = AmbienceEngine();
    avant.setPack(_voix);
    await avant.setVolume(0.3);

    final apres = AmbienceEngine();
    await apres.restore(_packs);

    expect(apres.currentPack.id, 'voix_femme');
    expect(apres.volume, closeTo(0.3, 1e-9));
  });

  test('un pack disparu du catalogue retombe sur aucune ambiance', () async {
    SharedPreferences.setMockInitialValues({'ambience.pack': 'disparu'});
    final engine = AmbienceEngine();
    await engine.restore(_packs);
    expect(engine.currentPack.id, AmbiencePack.none.id);
  });
}
